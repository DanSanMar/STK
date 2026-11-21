#!/usr/bin/env bash
# ==============================================================================
#  STK - BIBLIOTECA COMPARTIDA DEL MODO AUTOMÁTICO
# ==============================================================================
#  Una sola implementación de: lock, preflight, snapshot, actualización,
#  limpieza, auditoría y servicios. La usan stk2.sh (modo interactivo / --auto)
#  y el wrapper programado generado por stk_cron.sh.
#
#  Convención: las funciones rellenan variables globales con prefijo
#  PRE_, SNAPSHOT_, ACT_, PKGS_, FLATPAKS_, SNAPS_, RES_, SEC_, SVC_,
#  REBOOT_, KERNEL_, NEEDRESTART y SUPER_LIMPIEZA_LIBERADO para que el
#  llamador construya su resumen. Ninguna función termina el programa.
# ==============================================================================

# --- Valores por defecto (el script padre puede sobreescribirlos) ---
: "${LOG_FILE:=/var/log/stk_mantenimiento.log}"
: "${LOG_INFO:=INFO}"
: "${LOG_WARN:=WARN}"
: "${LOG_ERR:=ERROR}"
: "${RESET:=\e[0m}"

# Días de retención de logs del journal en la limpieza automática.
: "${AUTO_LIMPIEZA_LOG_DIAS:=7}"
: "${AUTO_TIMEOUT_ACTUALIZACION:=1800}"
: "${AUTO_TIMEOUT_LIMPIEZA:=600}"
: "${AUTO_MIN_ESPACIO_MB:=1024}"
: "${AUTO_LIMITE_SUID:=60}"
: "${STK_ESTADO_DIR:=/var/lib/stk}"

# --- registrar_log: se usa la del script padre si ya existe ---
if ! declare -F registrar_log >/dev/null 2>&1; then
    registrar_log() {
        local nivel="${1:-INFO}" mensaje="${2}" fecha
        fecha=$(date '+%Y-%m-%d %H:%M:%S')
        echo "[$fecha] [$nivel] [${SUDO_USER:-$USER}] - $mensaje" >> "$LOG_FILE" 2>/dev/null
    }
fi

# --- pintar: se usa la del script padre si ya existe ---
if ! declare -F pintar >/dev/null 2>&1; then
    pintar() { echo -e "${1}${2}${RESET}"; }
fi

# ==============================================================================
#  DETECCIÓN DE GESTOR (para cuando la librería se usa desde el cron)
# ==============================================================================
stk_detectar_gestor() {
    [ -n "${Package:-}" ] && return 0
    Package=""
    IMMUTABLE=false

    if [ -f /etc/os-release ]; then
        . /etc/os-release 2>/dev/null
        case "${ID:-}-${ID_LIKE:-}" in
            *debian*|*ubuntu*)          Package="apt" ;;
            *fedora*|*rhel*|*centos*)   Package="dnf" ;;
            *arch*|*manjaro*)           Package="pacman" ;;
            *suse*)                     Package="zypper" ;;
        esac
    fi

    if [ -z "$Package" ]; then
        if command -v rpm-ostree >/dev/null 2>&1 && [ -d /ostree/deploy ]; then
            Package="dnf"; IMMUTABLE=true
        elif command -v apt-get >/dev/null 2>&1;    then Package="apt"
        elif command -v dnf >/dev/null 2>&1;        then Package="dnf"
        elif command -v pacman >/dev/null 2>&1;     then Package="pacman"
        elif command -v zypper >/dev/null 2>&1;     then Package="zypper"
        elif command -v apk >/dev/null 2>&1;        then Package="apk"
        else Package="unknown"
        fi
    fi

    if [ "${IMMUTABLE:-false}" = false ] && command -v rpm-ostree >/dev/null 2>&1 \
       && [ -d /ostree/deploy ]; then
        IMMUTABLE=true
    fi
    return 0
}

# Prefijo de timeout opcional. Uso: local -a TMO=(); stk_timeout TMO 600
stk_timeout() {
    local -n _stk_tmo_ref="$1" 2>/dev/null || return 0
    local segs="$2"
    _stk_tmo_ref=()
    if [ -n "$segs" ] && command -v timeout >/dev/null 2>&1; then
        _stk_tmo_ref=(timeout "$segs")
    fi
}

# ==============================================================================
#  LOCK EXCLUSIVO (compartido por la sesión interactiva y el cron)
# ==============================================================================
STK_LOCK_FD=""
stk_lock_adquirir() {
    command -v flock >/dev/null 2>&1 || return 0

    local lock_dir="/run/lock"
    [ -d "$lock_dir" ] || lock_dir="/var/lock"
    [ -d "$lock_dir" ] || return 0

    STK_LOCK_FILE="$lock_dir/stk_auto.lock"
    if ! { exec 9>"$STK_LOCK_FILE"; } 2>/dev/null; then
        STK_LOCK_FILE=""
        return 0
    fi
    if ! flock -n 9; then
        exec 9>&-
        STK_LOCK_FILE=""
        return 1
    fi
    STK_LOCK_FD=9
    return 0
}

stk_lock_liberar() {
    [ -n "$STK_LOCK_FD" ] || return 0
    flock -u 9 2>/dev/null
    exec 9>&-
    STK_LOCK_FD=""
}

stk_gestor_ocupado() {
    local p
    for p in apt-get apt dpkg dnf zypper pacman rpm-ostree; do
        pgrep -x "$p" >/dev/null 2>&1 && return 0
    done
    return 1
}

# ==============================================================================
#  PREFLIGHT
#  Rellena: PRE_RED, PRE_ESPACIO_MB, PRE_ESPACIO_OK, PRE_GESTOR_LIBRE,
#           PRE_BATERIA, PRE_AVISOS
# ==============================================================================
stk_preflight() {
    PRE_RED="ok"
    PRE_ESPACIO_MB=0
    PRE_ESPACIO_OK=true
    PRE_GESTOR_LIBRE=true
    PRE_BATERIA="N/D"
    PRE_AVISOS=()

    local -a urls_red=()
    if [ "${IMMUTABLE:-false}" = true ]; then
        urls_red=(https://fedoraproject.org)
    else
        case "${Package:-unknown}" in
            apt)    urls_red=(https://deb.debian.org https://archive.ubuntu.com) ;;
            pacman) urls_red=(https://archlinux.org https://mirror.rackspace.com) ;;
            dnf)    urls_red=(https://fedoraproject.org) ;;
            zypper) urls_red=(https://www.opensuse.org) ;;
            *)      urls_red=(https://deb.debian.org https://archlinux.org) ;;
        esac
    fi

    local url red_ok=false
    for url in "${urls_red[@]}"; do
        if curl -sI --max-time 5 "$url" >/dev/null 2>&1; then
            red_ok=true
            break
        fi
    done
    if [ "$red_ok" = false ]; then
        PRE_RED="sin conexión"
        PRE_AVISOS+=("Sin conexión a Internet: se omite la actualización")
    fi

    PRE_ESPACIO_MB=$(df -Pm / 2>/dev/null | awk 'NR==2 {print $4}')
    [[ "$PRE_ESPACIO_MB" =~ ^[0-9]+$ ]] || PRE_ESPACIO_MB=0
    if [ "$PRE_ESPACIO_MB" -lt "$AUTO_MIN_ESPACIO_MB" ]; then
        PRE_ESPACIO_OK=false
        PRE_AVISOS+=("Espacio libre bajo (${PRE_ESPACIO_MB} MB < ${AUTO_MIN_ESPACIO_MB} MB): se omite la actualización")
    fi

    if stk_gestor_ocupado; then
        PRE_GESTOR_LIBRE=false
        echo "   ⏳ Gestor de paquetes ocupado; esperando hasta 60 s..."
        local i
        for i in $(seq 1 12); do
            sleep 5
            if ! stk_gestor_ocupado; then
                PRE_GESTOR_LIBRE=true
                break
            fi
        done
        [ "$PRE_GESTOR_LIBRE" = false ] && \
            PRE_AVISOS+=("Gestor de paquetes bloqueado: se omite la actualización")
    fi

    local bat cap estado
    for bat in /sys/class/power_supply/BAT*; do
        [ -r "$bat/capacity" ] || continue
        cap=$(cat "$bat/capacity" 2>/dev/null)
        estado=$(cat "$bat/status" 2>/dev/null)
        PRE_BATERIA="${cap}% (${estado})"
        if [ "$estado" = "Discharging" ] && [ "${cap:-100}" -lt 20 ]; then
            PRE_AVISOS+=("Batería baja (${cap}%) y sin cargador")
        fi
        break
    done

    echo "   Red: ${PRE_RED}   Espacio: ${PRE_ESPACIO_MB} MB   Batería: ${PRE_BATERIA}"
    local aviso
    for aviso in "${PRE_AVISOS[@]}"; do
        echo "   ⚠ $aviso"
        # Los avisos del preflight antes solo se veían en pantalla: ahora
        # quedan también en la bitácora para que no se pierdan.
        registrar_log "$LOG_WARN" "PREFLIGHT: $aviso"
    done
}

# ==============================================================================
#  SNAPSHOT PREVIO
#  Rellena: SNAPSHOT_METODO, SNAPSHOT_OK
# ==============================================================================
stk_snapshot() {
    SNAPSHOT_METODO="ninguno"
    SNAPSHOT_OK=false

    if command -v snapper >/dev/null 2>&1 && snapper list-configs >/dev/null 2>&1; then
        local cfg
        cfg=$(snapper list-configs 2>/dev/null | awk -F'|' 'NF > 1 && $1 !~ /Config|^-/ {gsub(/ /, "", $1); print $1; exit}')
        if [ -n "$cfg" ] && snapper -c "$cfg" create -d "STK auto pre-update $(date '+%F %T')" >/dev/null 2>&1; then
            SNAPSHOT_METODO="snapper ($cfg)"
            SNAPSHOT_OK=true
            registrar_log "$LOG_INFO" "SNAPSHOT: snapper ($cfg)"
            return 0
        fi
    fi

    if command -v timeshift >/dev/null 2>&1 \
       && { [ -f /etc/timeshift/timeshift.json ] || [ -f /etc/timeshift.json ]; }; then
        local -a TMO_TS=()
        stk_timeout TMO_TS 300
        if "${TMO_TS[@]}" timeshift --create --scripted --comments "STK auto pre-update" >/dev/null 2>&1; then
            SNAPSHOT_METODO="timeshift"
            SNAPSHOT_OK=true
            registrar_log "$LOG_INFO" "SNAPSHOT: timeshift"
            return 0
        fi
    fi

    local dir="$STK_ESTADO_DIR/snapshots/$(date '+%Y%m%d_%H%M%S')"
    if mkdir -p "$dir" 2>/dev/null; then
        case "${Package:-unknown}" in
            apt)    dpkg --get-selections > "$dir/dpkg-selections.txt" 2>/dev/null ;;
            pacman) pacman -Qqe > "$dir/pacman-explicit.txt" 2>/dev/null ;;
            dnf|zypper) rpm -qa > "$dir/rpm-packages.txt" 2>/dev/null ;;
        esac
        [ "${IMMUTABLE:-false}" = true ] && rpm-ostree status > "$dir/rpm-ostree-status.txt" 2>/dev/null
        SNAPSHOT_METODO="lista de paquetes ($dir)"
        SNAPSHOT_OK=true
        registrar_log "$LOG_INFO" "SNAPSHOT: lista de paquetes en $dir"
        return 0
    fi

    SNAPSHOT_METODO="ninguno"
    registrar_log "$LOG_WARN" "SNAPSHOT: no se pudo crear ningún punto de recuperación"
    return 1
}

# ==============================================================================
#  INCIDENCIAS DE ACTUALIZACIÓN
#  Extrae líneas de error/aviso del log volátil y las deja en bitácora y en
#  ACT_INCIDENCIAS para que el resumen final las muestre.
# ==============================================================================
stk_extraer_incidencias() {
    local logfile="$1" nivel="${2:-$LOG_WARN}"
    [ -s "$logfile" ] || return 0
    declare -p ACT_INCIDENCIAS >/dev/null 2>&1 || ACT_INCIDENCIAS=()

    local linea limpia existente duplicado
    while IFS= read -r linea; do
        limpia=$(printf '%s' "$linea" | sed 's/\x1B\[[0-9;]*[mK]//g' | cut -c1-200)
        [ -n "$limpia" ] || continue

        duplicado=false
        for existente in "${ACT_INCIDENCIAS[@]}"; do
            [ "$existente" = "$limpia" ] && { duplicado=true; break; }
        done
        [ "$duplicado" = true ] && continue

        ACT_INCIDENCIAS+=("$limpia")
        registrar_log "$nivel" "ACTUALIZACIÓN: $limpia"
    done < <(grep -iE '(error|failed|failure|warning|warn|E:|W:|cannot|unable|no se pudo|no se ha podido|falló|fallido|lock|bloquead)' "$logfile" 2>/dev/null | tail -n 12)
}

# ==============================================================================
#  ACTUALIZACIÓN UNIFICADA
#  Rellena: ESTADO_ACT, PKGS_ACTUALIZADOS, FLATPAKS_ACT, SNAPS_ACT,
#           RES_FLATPAK, RES_SNAP, ACT_INCIDENCIAS, RES_ACTUALIZACION
#  Devuelve: 0 ok | 124 timeout | otro código de error
# ==============================================================================
stk_actualizar() {
    stk_detectar_gestor
    ESTADO_ACT=1
    PKGS_ACTUALIZADOS=()
    FLATPAKS_ACT=()
    SNAPS_ACT=()
    RES_FLATPAK=""
    RES_SNAP=""
    ACT_INCIDENCIAS=()
    RES_ACTUALIZACION="Sin procesar"

    local ETIQUETA_GESTOR="${Package}"
    [ "${IMMUTABLE:-false}" = true ] && ETIQUETA_GESTOR="rpm-ostree"

    local LOG_TEMP_ACT
    LOG_TEMP_ACT=$(mktemp "${TMPDIR:-/tmp}/stk-act.XXXXXX" 2>/dev/null) || LOG_TEMP_ACT="${TMPDIR:-/tmp}/stk-act.$$"
    local -a TMO_ACT=()
    stk_timeout TMO_ACT "$AUTO_TIMEOUT_ACTUALIZACION"

    local DEBIAN_FRONTEND_SAVE="${DEBIAN_FRONTEND:-}"
    export DEBIAN_FRONTEND=noninteractive

    if [ "${IMMUTABLE:-false}" = true ]; then
        "${TMO_ACT[@]}" rpm-ostree upgrade 2>&1 | tee "$LOG_TEMP_ACT"
        ESTADO_ACT=${PIPESTATUS[0]}
    else
        case "${Package:-unknown}" in
            apt)
                mapfile -t PKGS_ACTUALIZADOS < <(apt list --upgradable 2>/dev/null | grep -v "Listing..." | cut -d/ -f1)
                "${TMO_ACT[@]}" bash -c 'apt-get update -y && apt-get full-upgrade -y \
                    -o Dpkg::Options::="--force-confdef" \
                    -o Dpkg::Options::="--force-confold"' 2>&1 | tee "$LOG_TEMP_ACT"
                ESTADO_ACT=${PIPESTATUS[0]}
                ;;
            pacman)
                "${TMO_ACT[@]}" pacman -Syu --noconfirm --color never 2>&1 | tee "$LOG_TEMP_ACT"
                ESTADO_ACT=${PIPESTATUS[0]}
                if [ "$ESTADO_ACT" -eq 0 ]; then
                    if grep -qiE "there is nothing to do|ya está actualizado|nada que hacer" "$LOG_TEMP_ACT"; then
                        PKGS_ACTUALIZADOS=()
                    else
                        mapfile -t PKGS_ACTUALIZADOS < <(grep -E ' -> ' "$LOG_TEMP_ACT" | awk '{print $1}')
                    fi
                fi
                ;;
            dnf)
                "${TMO_ACT[@]}" bash -c 'dnf upgrade --refresh -y --color=never' 2>&1 | tee "$LOG_TEMP_ACT"
                ESTADO_ACT=${PIPESTATUS[0]}
                [ "$ESTADO_ACT" -eq 0 ] && \
                    mapfile -t PKGS_ACTUALIZADOS < <(awk '/^Upgraded:/{f=1; next} /^$/{f=0} f{print $1}' "$LOG_TEMP_ACT")
                ;;
            zypper)
                "${TMO_ACT[@]}" bash -c 'zypper refresh && zypper --non-interactive update' 2>&1 | tee "$LOG_TEMP_ACT"
                ESTADO_ACT=${PIPESTATUS[0]}
                ;;
            apk)
                "${TMO_ACT[@]}" bash -c 'apk update && apk upgrade' 2>&1 | tee "$LOG_TEMP_ACT"
                ESTADO_ACT=${PIPESTATUS[0]}
                ;;
            *)
                echo "❌ Actualización no soportada para ${Package:-desconocido}"
                registrar_log "$LOG_ERR" "ACTUALIZACIÓN: gestor no soportado (${Package:-desconocido})"
                rm -f "$LOG_TEMP_ACT"
                return 1
                ;;
        esac
    fi

    # Flatpak y Snap usan el mismo timeout que el gestor principal.
    if command -v flatpak >/dev/null 2>&1; then
        echo ""
        echo "📦 Comprobando y actualizando Flatpak..."
        local LOG_FLATPAK
        LOG_FLATPAK=$(mktemp "${TMPDIR:-/tmp}/stk-flatpak.XXXXXX" 2>/dev/null) || LOG_FLATPAK="${TMPDIR:-/tmp}/stk-flatpak.$$"
        "${TMO_ACT[@]}" flatpak update -y 2>&1 | tee "$LOG_FLATPAK"
        if grep -qi -E "nothing to do|nothing updated|nada que hacer" "$LOG_FLATPAK"; then
            RES_FLATPAK="Flatpak: Sin cambios."
        else
            mapfile -t FLATPAKS_ACT < <(grep -E "Updating|Installing|Actualizando" "$LOG_FLATPAK" | awk -F"'" '{print $2}')
            RES_FLATPAK="Flatpak: ${#FLATPAKS_ACT[@]} aplicación(es) actualizada(s)."
        fi
        stk_extraer_incidencias "$LOG_FLATPAK"
        rm -f "$LOG_FLATPAK"
    fi

    if command -v snap >/dev/null 2>&1; then
        echo ""
        echo "📦 Comprobando y actualizando Snap..."
        local LOG_SNAP
        LOG_SNAP=$(mktemp "${TMPDIR:-/tmp}/stk-snap.XXXXXX" 2>/dev/null) || LOG_SNAP="${TMPDIR:-/tmp}/stk-snap.$$"
        "${TMO_ACT[@]}" snap refresh 2>&1 | tee "$LOG_SNAP"
        if grep -qi -E "all snaps are up to date|todos los snaps están actualizados" "$LOG_SNAP"; then
            RES_SNAP="Snap: Sin cambios."
        else
            mapfile -t SNAPS_ACT < <(grep -v "All snaps" "$LOG_SNAP" | awk 'NR>1 {print $1}')
            RES_SNAP="Snap: ${#SNAPS_ACT[@]} paquete(s) actualizado(s)."
        fi
        stk_extraer_incidencias "$LOG_SNAP"
        rm -f "$LOG_SNAP"
    fi

    [ -n "$DEBIAN_FRONTEND_SAVE" ] && export DEBIAN_FRONTEND="$DEBIAN_FRONTEND_SAVE" || unset DEBIAN_FRONTEND

    # Antes de borrar el log volátil, rescatamos errores y avisos.
    stk_extraer_incidencias "$LOG_TEMP_ACT" "$LOG_ERR"

    if [ "$ESTADO_ACT" -eq 0 ]; then
        if [ "${IMMUTABLE:-false}" = true ]; then
            RES_ACTUALIZACION="✔ Imagen del sistema preparada (rpm-ostree). Reinicia para aplicar."
        else
            RES_ACTUALIZACION="✔ Sistema al día ($ETIQUETA_GESTOR: ${#PKGS_ACTUALIZADOS[@]} actualizados | $RES_FLATPAK"
            [ -n "$RES_SNAP" ] && RES_ACTUALIZACION="$RES_ACTUALIZACION | $RES_SNAP"
            RES_ACTUALIZACION="$RES_ACTUALIZACION)"
        fi
        registrar_log "$LOG_INFO" "ACTUALIZACIÓN: $RES_ACTUALIZACION"
    elif [ "$ESTADO_ACT" -eq 124 ]; then
        RES_ACTUALIZACION="⏱ Tiempo agotado en la actualización (${AUTO_TIMEOUT_ACTUALIZACION}s)."
        registrar_log "$LOG_ERR" "ACTUALIZACIÓN: $RES_ACTUALIZACION"
    else
        RES_ACTUALIZACION="❌ Error en la actualización del gestor principal ($ETIQUETA_GESTOR)."
        registrar_log "$LOG_ERR" "ACTUALIZACIÓN: $RES_ACTUALIZACION (código $ESTADO_ACT)"
    fi

    rm -f "$LOG_TEMP_ACT"
    return "$ESTADO_ACT"
}

# ==============================================================================
#  LIMPIEZA UNIFICADA
#  Modo "auto"   : SOLO cachés y logs. Sin desinstalar paquetes, sin papeleras.
#  Modo "completa": además, autoremove / huérfanos y papelera, con confirmación.
#  Rellena: SUPER_LIMPIEZA_LIBERADO
# ==============================================================================
stk_limpieza() {
    stk_detectar_gestor
    local MODO="${1:-auto}"
    local -a TMO=()
    stk_timeout TMO "$AUTO_TIMEOUT_LIMPIEZA"

    local SPINNER_PID_LIMPIEZA=""

    if [ "$MODO" = "auto" ]; then
        echo ""
        echo "🧹 Limpieza automática (modo seguro):"
        echo "   • Logs del sistema con más de ${AUTO_LIMPIEZA_LOG_DIAS} días"
        echo "   • Caché del gestor de paquetes"
        echo "   • Miniaturas de imágenes sin uso en más de 7 días"
        echo "   • NO se desinstalan paquetes, NO se tocan papeleras ni archivos personales"
        echo ""
    else
        echo ""
        echo "🧹 Limpieza completa:"
        echo "   • Lo anterior + paquetes obsoletos/huérfanos y vaciado de papeleras"
        echo ""
    fi

    # Spinner solo si hay terminal; en cron/wrapper no tiene sentido.
    if [ -t 1 ] && declare -F mostrar_spinner >/dev/null 2>&1; then
        mostrar_spinner & SPINNER_PID_LIMPIEZA=$!
    fi

    local ANTES_RAIZ ANTES_HOME DESPUES_RAIZ DESPUES_HOME
    ANTES_RAIZ=$(df --output=avail / 2>/dev/null | tail -n 1)
    ANTES_HOME=$(df --output=avail /home 2>/dev/null | tail -n 1)

    # 1. Logs del journal
    if command -v journalctl >/dev/null 2>&1; then
        "${TMO[@]}" journalctl --vacuum-time="${AUTO_LIMPIEZA_LOG_DIAS}d" >/dev/null 2>&1
        registrar_log "$LOG_INFO" "LIMPIEZA[$MODO]: journalctl --vacuum-time=${AUTO_LIMPIEZA_LOG_DIAS}d"
    fi

    # 2. Caché del gestor (nunca desinstala paquetes en modo auto)
    case "${Package:-unknown}" in
        apt)
            "${TMO[@]}" apt-get autoclean -y >/dev/null 2>&1
            "${TMO[@]}" apt-get clean >/dev/null 2>&1
            registrar_log "$LOG_INFO" "LIMPIEZA[$MODO]: caché APT (autoclean + clean)"
            ;;
        dnf)
            "${TMO[@]}" dnf clean all >/dev/null 2>&1
            registrar_log "$LOG_INFO" "LIMPIEZA[$MODO]: caché DNF"
            ;;
        pacman)
            "${TMO[@]}" pacman -Sc --noconfirm >/dev/null 2>&1
            registrar_log "$LOG_INFO" "LIMPIEZA[$MODO]: caché PACMAN (-Sc)"
            ;;
        zypper)
            "${TMO[@]}" zypper clean --all >/dev/null 2>&1
            registrar_log "$LOG_INFO" "LIMPIEZA[$MODO]: caché ZYPPER"
            ;;
        apk)
            "${TMO[@]}" apk cache clean >/dev/null 2>&1
            registrar_log "$LOG_INFO" "LIMPIEZA[$MODO]: caché APK"
            ;;
        *)
            [ -n "$SPINNER_PID_LIMPIEZA" ] && { kill "$SPINNER_PID_LIMPIEZA" 2>/dev/null; wait "$SPINNER_PID_LIMPIEZA" 2>/dev/null; }
            [ -t 1 ] && printf "\r\e[K"
            echo "❌ Limpieza automática no soportada para ${Package:-desconocido}"
            registrar_log "$LOG_WARN" "LIMPIEZA: gestor no soportado (${Package:-desconocido})"
            return 1
            ;;
    esac
    [ "${IMMUTABLE:-false}" = true ] && "${TMO[@]}" rpm-ostree cleanup -m >/dev/null 2>&1

    # 3. Miniaturas (solo caché, nunca archivos del usuario)
    find /home/*/.cache/thumbnails /root/.cache/thumbnails -type f -atime +7 -delete 2>/dev/null
    registrar_log "$LOG_INFO" "LIMPIEZA[$MODO]: miniaturas con más de 7 días sin uso"

    # 4. Solo en la limpieza COMPLETA: desinstalación y papeleras, con confirmación.
    if [ "$MODO" != "auto" ]; then
        local huerfanos=()
        case "${Package:-unknown}" in
            apt)
                "${TMO[@]}" apt-get autoremove -y >/dev/null 2>&1
                registrar_log "$LOG_INFO" "LIMPIEZA[completa]: apt-get autoremove (sin --purge)"
                ;;
            dnf)
                "${TMO[@]}" dnf autoremove -y >/dev/null 2>&1
                registrar_log "$LOG_INFO" "LIMPIEZA[completa]: dnf autoremove"
                ;;
            pacman)
                mapfile -t huerfanos < <(pacman -Qtdq 2>/dev/null)
                if [ ${#huerfanos[@]} -gt 0 ]; then
                    "${TMO[@]}" pacman -R "${huerfanos[@]}" --noconfirm >/dev/null 2>&1
                    registrar_log "$LOG_INFO" "LIMPIEZA[completa]: huérfanos (${#huerfanos[@]}): ${huerfanos[*]}"
                fi
                ;;
        esac

        local n_trash
        n_trash=$(find /home/*/.local/share/Trash/files /home/*/.local/share/Trash/info /root/.local/share/Trash/files /root/.local/share/Trash/info -mindepth 1 2>/dev/null | wc -l)
        if [ "$n_trash" -gt 0 ] && [ -t 0 ]; then
            echo "🗑️  Hay ${n_trash} elemento(s) en las papeleras de los usuarios."
            local respuesta="n"
            read -r -p "¿Vaciar TODAS las papeleras? Esto es irreversible (s/N): " respuesta
            case "$respuesta" in
                s|S|si|SI|Si)
                    find /home/*/.local/share/Trash/files /home/*/.local/share/Trash/info -mindepth 1 -delete 2>/dev/null
                    find /root/.local/share/Trash/files /root/.local/share/Trash/info -mindepth 1 -delete 2>/dev/null
                    registrar_log "$LOG_WARN" "LIMPIEZA[completa]: papeleras vaciadas (${n_trash} elementos)"
                    ;;
                *) registrar_log "$LOG_INFO" "LIMPIEZA[completa]: papeleras conservadas" ;;
            esac
        elif [ "$n_trash" -gt 0 ]; then
            registrar_log "$LOG_INFO" "LIMPIEZA[completa]: ${n_trash} elemento(s) en papeleras; sin TTY no se vacían"
        fi
    fi

    [ -n "$SPINNER_PID_LIMPIEZA" ] && { kill "$SPINNER_PID_LIMPIEZA" 2>/dev/null; wait "$SPINNER_PID_LIMPIEZA" 2>/dev/null; }
    [ -t 1 ] && printf "\r\e[K"

    DESPUES_RAIZ=$(df --output=avail / 2>/dev/null | tail -n 1)
    DESPUES_HOME=$(df --output=avail /home 2>/dev/null | tail -n 1)

    local DIF_RAIZ=0 DIF_HOME=0
    [[ "$ANTES_RAIZ" =~ ^[0-9]+$ && "$DESPUES_RAIZ" =~ ^[0-9]+$ ]] && DIF_RAIZ=$(( (DESPUES_RAIZ - ANTES_RAIZ) / 1024 ))
    if [[ "$ANTES_HOME" =~ ^[0-9]+$ && "$DESPUES_HOME" =~ ^[0-9]+$ ]]; then
        DIF_HOME=$(( (DESPUES_HOME - ANTES_HOME) / 1024 ))
    fi
    SUPER_LIMPIEZA_LIBERADO=$(( DIF_RAIZ + DIF_HOME ))

    registrar_log "$LOG_INFO" "LIMPIEZA[$MODO]: espacio liberado aprox. ${SUPER_LIMPIEZA_LIBERADO} MB"
    if [ "$SUPER_LIMPIEZA_LIBERADO" -gt 0 ]; then
        echo "✨ Se han liberado aprox. ${SUPER_LIMPIEZA_LIBERADO} MB."
    else
        echo "Limpieza completada (el sistema ya estaba optimizado)."
    fi
    return 0
}

# ==============================================================================
#  AUDITORÍA DE SEGURIDAD UNIFICADA
#  Rellena: SEC_ALERTAS, SEC_CHECKS, SEC_PASSED, SCORE_SEGURIDAD, RES_SEGURIDAD
# ==============================================================================
stk_auditoria() {
    stk_detectar_gestor
    local sec_checks=0 sec_passed=0
    SEC_ALERTAS=()

    local alerta
    stk_add_alerta() {
        alerta="$1"
        SEC_ALERTAS+=("$alerta")
        registrar_log "$LOG_WARN" "SEG-ALERTA: $alerta"
    }

    ((sec_checks++))
    if [ "$(awk -F: '$3 == 0 {print $1}' /etc/passwd 2>/dev/null | wc -l)" -gt 1 ]; then
        stk_add_alerta "Múltiples usuarios con UID 0 detectados"
    else
        ((sec_passed++))
    fi

    ((sec_checks++))
    if [ -n "$(awk -F: '($2 == "" || $2 == "!!") {print $1}' /etc/shadow 2>/dev/null)" ]; then
        stk_add_alerta "Cuentas inactivas o sin contraseña configurada"
    else
        ((sec_passed++))
    fi

    ((sec_checks++))
    local firewall_ok=false
    if command -v ufw >/dev/null 2>&1 && ufw status 2>/dev/null | grep -qi "active"; then
        firewall_ok=true
    elif command -v firewall-cmd >/dev/null 2>&1 && firewall-cmd --state 2>/dev/null | grep -qi "running"; then
        firewall_ok=true
    elif command -v nft >/dev/null 2>&1 && nft list ruleset 2>/dev/null | grep -q "table"; then
        firewall_ok=true
    elif command -v iptables >/dev/null 2>&1 && iptables -S 2>/dev/null | grep -qv '^-P .* ACCEPT'; then
        firewall_ok=true
    fi
    if [ "$firewall_ok" = true ]; then ((sec_passed++)); else stk_add_alerta "Firewall inactivo o sin reglas configuradas"; fi

    ((sec_checks++))
    if command -v ss >/dev/null 2>&1; then
        if ss -tulpn 2>/dev/null | grep LISTEN | grep -E "0\.0\.0\.0:22|:::22|\*:22" >/dev/null 2>&1; then
            stk_add_alerta "Puerto SSH (22) expuesto públicamente"
        else
            ((sec_passed++))
        fi
    else
        ((sec_passed++))
    fi

    ((sec_checks++))
    if command -v getenforce >/dev/null 2>&1 && [ "$(getenforce 2>/dev/null)" = "Enforcing" ]; then
        ((sec_passed++))
    elif command -v aa-status >/dev/null 2>&1 && aa-status --enabled 2>/dev/null; then
        ((sec_passed++))
    else
        stk_add_alerta "Sin módulo MAC activo (AppArmor/SELinux)"
    fi

    if [ "${Package:-unknown}" = "apt" ]; then
        ((sec_checks++))
        if dpkg -s unattended-upgrades >/dev/null 2>&1 \
           && grep -Rqs 'Unattended-Upgrade[[:space:]]*"1"' /etc/apt/apt.conf.d/ 2>/dev/null; then
            ((sec_passed++))
        else
            stk_add_alerta "Actualizaciones de seguridad automáticas (unattended-upgrades) no activas"
        fi
    fi

    local ssh_activo=false
    if systemctl is-active --quiet ssh 2>/dev/null || systemctl is-active --quiet sshd 2>/dev/null; then
        ssh_activo=true
    fi
    if [ "$ssh_activo" = true ]; then
        ((sec_checks++))
        if systemctl is-active --quiet fail2ban 2>/dev/null || pgrep -x fail2ban-server >/dev/null 2>&1; then
            ((sec_passed++))
        else
            stk_add_alerta "SSH activo sin fail2ban"
        fi

        if [ -f /etc/ssh/sshd_config ]; then
            ((sec_checks++))
            local ssh_root_login="" ssh_pass_auth=""
            if command -v sshd >/dev/null 2>&1 && sshd -T >/dev/null 2>&1; then
                ssh_root_login=$(sshd -T 2>/dev/null | awk '$1 == "permitrootlogin" {print $2}')
                ssh_pass_auth=$(sshd -T 2>/dev/null | awk '$1 == "passwordauthentication" {print $2}')
            else
                ssh_root_login=$(grep -Ei '^[[:space:]]*PermitRootLogin[[:space:]]+' /etc/ssh/sshd_config 2>/dev/null | awk '{print tolower($2)}' | tail -n1)
                ssh_pass_auth=$(grep -Ei '^[[:space:]]*PasswordAuthentication[[:space:]]+' /etc/ssh/sshd_config 2>/dev/null | awk '{print tolower($2)}' | tail -n1)
            fi
            if [ "$ssh_root_login" = "yes" ] || [ "$ssh_pass_auth" = "yes" ]; then
                stk_add_alerta "SSH poco endurecido (PermitRootLogin/PasswordAuthentication en 'yes')"
            else
                ((sec_passed++))
            fi
        fi
    fi

    ((sec_checks++))
    if grep -rEsq '^[[:space:]]*[^#[:space:]].*NOPASSWD' /etc/sudoers /etc/sudoers.d 2>/dev/null; then
        stk_add_alerta "Reglas NOPASSWD en sudoers"
    else
        ((sec_passed++))
    fi

    ((sec_checks++))
    local ww
    ww=$(find /etc /usr/local /var/www -xdev -type f -perm -0002 2>/dev/null | head -n 3 | tr '\n' ' ')
    if [ -n "$ww" ]; then
        stk_add_alerta "Archivos world-writable en rutas críticas: $ww"
    else
        ((sec_passed++))
    fi

    ((sec_checks++))
    if command -v ss >/dev/null 2>&1 \
       && ss -tulpn 2>/dev/null | awk 'NR > 1 {print $5}' \
          | grep -qE '^(0\.0\.0\.0|\[::\]|\*):(21|23|3306|5432|6379|27017|11211)$'; then
        stk_add_alerta "Puertos sensibles expuestos (21/23/3306/5432/6379/27017/11211)"
    else
        ((sec_passed++))
    fi

    SEC_CHECKS=$sec_checks
    SEC_PASSED=$sec_passed
    [ "$sec_checks" -gt 0 ] && SCORE_SEGURIDAD=$(( (sec_passed * 100) / sec_checks )) || SCORE_SEGURIDAD=0
    RES_SEGURIDAD="Puntuación: ${SCORE_SEGURIDAD}% (${sec_passed}/${sec_checks} pruebas). Alertas: ${#SEC_ALERTAS[@]}."
    registrar_log "$LOG_INFO" "SEGURIDAD: $RES_SEGURIDAD"
}

# ==============================================================================
#  SERVICIOS Y REINICIO UNIFICADOS
#  Rellena: SVC_FAILED_ARR, RES_SERVICIOS, REBOOT_REQUIRED, REBOOT_PKGS,
#           KERNEL_PENDIENTE, NEEDRESTART
# ==============================================================================
stk_servicios() {
    SVC_FAILED_ARR=()
    NEEDRESTART=""
    if command -v systemctl >/dev/null 2>&1; then
        local svcs_failed
        svcs_failed=$(systemctl list-units --state=failed --no-legend --plain 2>/dev/null | awk '{print $1}')
        if [ -n "$svcs_failed" ]; then
            mapfile -t SVC_FAILED_ARR < <(printf '%s\n' "$svcs_failed")
            RES_SERVICIOS="⚠️ Detectados ${#SVC_FAILED_ARR[@]} servicio(s) fallido(s): $(printf '%s ' "${SVC_FAILED_ARR[@]}")"
            registrar_log "$LOG_WARN" "SERVICIOS: $RES_SERVICIOS"
        else
            RES_SERVICIOS="✔ Todos los servicios operan correctamente (0 fallidos)."
        fi
    else
        RES_SERVICIOS="N/D (systemd no disponible)."
    fi

    REBOOT_REQUIRED=false
    REBOOT_PKGS=""
    if [ -f /var/run/reboot-required ] || [ -f /run/reboot-required ]; then
        REBOOT_REQUIRED=true
        local f="/var/run/reboot-required.pkgs"
        [ -f "$f" ] || f="/run/reboot-required.pkgs"
        [ -f "$f" ] && REBOOT_PKGS=$(sort -u "$f" 2>/dev/null | tr '\n' ' ')
        registrar_log "$LOG_WARN" "REINICIO RECOMENDADO${REBOOT_PKGS:+: $REBOOT_PKGS}"
    fi

    KERNEL_PENDIENTE=false
    local run_kernel latest_kernel
    run_kernel=$(uname -r 2>/dev/null)
    latest_kernel=$(ls -1 /boot/vmlinuz-* 2>/dev/null | sed 's#.*/vmlinuz-##' | grep -E '[0-9]' | sort -V | tail -n1)
    if [ -n "$latest_kernel" ] && [ "$latest_kernel" != "$run_kernel" ]; then
        KERNEL_PENDIENTE=true
        registrar_log "$LOG_WARN" "KERNEL: nuevo kernel instalado ($latest_kernel); se aplicará al reiniciar"
    fi

    if command -v needrestart >/dev/null 2>&1; then
        NEEDRESTART=$(needrestart -b 2>/dev/null | awk -F': ' '/NEEDRESTART-SVC/ {print $2}' | tr '\n' ' ')
        [ -n "$NEEDRESTART" ] && registrar_log "$LOG_WARN" "NEEDRESTART: $NEEDRESTART"
    fi
}
