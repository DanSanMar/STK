#!/bin/bash

# ==============================================================================
# JOBS4ME - Dashboard de análisis e interpretación de servicios y jobs
# ==============================================================================
# Módulo de solo lectura para Linux. No instala nada y NO exige root.
# Si se lanza desde STK tendrá más datos; si se lanza solo, degrada con N/D.
# Pensado para ejecutarse solo (bash jobs4me.sh) o integrarse en STK.
# ==============================================================================

DESCRIPCION="Dashboard de análisis de servicios, procesos y tareas programadas"
AUTOR="DanSanMar"

# --- CAPA DE COMPATIBILIDAD STK (TERM / fzf / TTY / rutas) ---
STK_COMPAT_HEADER="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)/stk_header.sh"
if [ -r "$STK_COMPAT_HEADER" ]; then
    # shellcheck source=stk_header.sh
    source "$STK_COMPAT_HEADER"
fi

STK_UI_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)/stk_ui_lib.sh"
[ -r "$STK_UI_LIB" ] && source "$STK_UI_LIB"

V="${STK_VERSION:-7.0.0}"
ver="v ${STK_VERSION:-7.0.0} · JOBS4ME"
STK_MODULO="JOBS4ME"

# --- CONFIGURACIÓN DE COLORES (Estilo STK / dash4me) ---
RESET='\e[0m'
NEGRITA='\e[1m'
VERDE_BRILLANTE='\e[92m'
VERDE='\e[32m'
AMARILLO='\e[33m'
AMARILLO_BRILLANTE='\e[93m'
AZUL='\e[34m'
AZUL_BRILLANTE='\e[94m'
AZUL_OSCURO='\e[0;34m'
AZUL_CLARO='\e[38;5;117m'
CIAN='\e[36m'
CIAN_BRILLANTE='\e[96m'
MAGENTA='\e[35m'
ROJO='\e[31m'
ROJO_BRILLANTE='\e[91m'
BLANCO='\e[97m'
GRIS_CLARO='\e[0;90m'

# --- LOGS E INFORMES ---
LOG_FILE="/var/log/stk_mantenimiento.log"
LOG_INFO="INFO"
LOG_WARN="WARN"
LOG_ERR="ERROR"
INFORME_DIR="/var/log/jobs4me"

# --- RUTA ABSOLUTA (para el preview de FZF y la cabecera viva) ---
SELF_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)/$(basename "${BASH_SOURCE[0]}")"

# Se ejecuta de forma independiente o se invoca desde STK
JOBS4ME_SOLO=false
[ "${BASH_SOURCE[0]}" = "$0" ] && JOBS4ME_SOLO=true

# --- DETECCIÓN DE ENTORNO ---
OS_ID="Linux"
KERNEL_STK=""
HOST_STK=""
HAS_SYSTEMD=false
HAS_JOURNAL=false
HAS_SS=false
HAS_CRONTAB=false
HAS_ATQ=false

registrar_log() {
    local NIVEL="${1:-INFO}"
    local MENSAJE="${2}"
    local FECHA
    FECHA=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$FECHA] [$NIVEL] [${USER:-$(id -un 2>/dev/null)}] - [JOBS4ME] $MENSAJE" >> "$LOG_FILE" 2>/dev/null
}

pintar() {
    local COLOR="$1"
    local MENSAJE="$2"
    echo -e "${COLOR}${MENSAJE}${RESET}"
}

ok()      { pintar "$VERDE_BRILLANTE" "✔ $1"; }
alerta()  { pintar "$ROJO_BRILLANTE" "⚠️ $1"; }
info()    { pintar "$AZUL" "ℹ️ $1"; }
seccion() { echo ""; pintar "$MAGENTA" "--- $1 ---"; }
pausa()   { echo ""; read -r -p "Presione Enter para continuar..." _; }

es_numero()  { [[ "$1" =~ ^[0-9]+$ ]]; }
es_decimal() { [[ "$1" =~ ^[0-9]+(\.[0-9]+)?$ ]]; }

recortar() {
    local texto="$1" max="${2:-60}"
    [ ${#texto} -gt "$max" ] && printf '%s…' "${texto:0:$((max - 1))}" || printf '%s' "$texto"
}

detectar_sistema() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release 2>/dev/null
        OS_ID="${PRETTY_NAME:-${ID:-Linux}}"
    fi
    KERNEL_STK=$(uname -r 2>/dev/null || echo "N/D")
    HOST_STK=$(hostname 2>/dev/null || cat /etc/hostname 2>/dev/null || echo "Desconocido")

    [ -d /run/systemd/system ] && command -v systemctl &>/dev/null && HAS_SYSTEMD=true
    command -v journalctl &>/dev/null && HAS_JOURNAL=true
    command -v ss &>/dev/null && HAS_SS=true
    command -v crontab &>/dev/null && HAS_CRONTAB=true
    command -v atq &>/dev/null && HAS_ATQ=true
}

# --- LOGO ANIMADO (estilo PROC4ME / STK) ---
PALETA_LOGO=(
    "$ROJO" "$AZUL_BRILLANTE" "$VERDE_BRILLANTE" "$AMARILLO_BRILLANTE"
    "$CIAN_BRILLANTE" "$ROJO_BRILLANTE" "$AZUL_CLARO" "$VERDE" "$AMARILLO" "$CIAN"
)

actualizar_colores_logo() {
    local epoch total=${#PALETA_LOGO[@]}
    epoch=$(date +%s 2>/dev/null)
    [[ "$epoch" =~ ^[0-9]+$ ]] || epoch=0
    local base=$(( (epoch / 3) % total ))
    COLOR_LOGO="${PALETA_LOGO[$base]}"
    COLOR_DASH="${PALETA_LOGO[$(( (base + 3) % total ))]}"
    COLOR_VER="${PALETA_LOGO[$(( (base + 6) % total ))]}"
}

logo_texto() {
    actualizar_colores_logo
    local hora
    hora=$(date '+%H:%M:%S')
    echo -e " ${AZUL_BRILLANTE}--- ⚡ ${NEGRITA}${COLOR_LOGO}JOBS4ME${RESET} ${AZUL_OSCURO}| ${COLOR_DASH}SERVICES & JOBS ANALYZER${RESET} ${AZUL_OSCURO}| ${COLOR_VER}v${V}${RESET} ${BLANCO}:${hora}: ${AZUL_BRILLANTE}⚡---${RESET}"
    echo -e " ${CIAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e " ${AMARILLO}➤ Sistema:${RESET} ${AZUL}${OS_ID}${RESET}  ${AMARILLO}Kernel:${RESET} ${AZUL}${KERNEL_STK}${RESET}"
    echo -e " ${AMARILLO}➤ Host:${RESET} ${AZUL}${HOST_STK}${RESET}  ${AMARILLO}Usuario:${RESET} ${AZUL}${USER:-root}${RESET}  ${AMARILLO}By:${RESET} ${AZUL}${AUTOR}${RESET}"
    echo -e " ${CIAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
}

mostrar_logo_jobs4me() {
    echo ""
    logo_texto
}

jobs4me_fzf_menu() {
    local prompt_text="$1"
    local titulo="$2"
    local altura="${3:-~90%}"
    local logo logo_cmd
    logo=$(logo_texto)
    printf -v logo_cmd 'bash %q --logo-header' "$SELF_PATH"
    stk_fzf_ejecutar "$prompt_text" "$logo" "$titulo" \
        --ansi \
        --height="$altura" \
        --layout=reverse \
        --no-sort \
        --header-first \
        --border=rounded \
        --border-label=" $titulo " \
        --prompt="➤ $prompt_text: " \
        --header="$logo" \
        --bind "every(5):bg-transform-header:$logo_cmd" \
        --color="border:#ff5555,pointer:#92ff92,header:#5fb2ff,label:#5fb2ff,marker:#92ff92"
}

salir_jobs4me() {
    echo -e "\n${AZUL}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    pintar "$AZUL" "Saliendo de JOBS4ME..."
    pintar "$VERDE" "Análisis completado. No se ha modificado ningún servicio."
    echo -e "${AZUL}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"
    if [ "$JOBS4ME_SOLO" = true ]; then
        exit 0
    fi
}

# ==============================================================================
# --- RECOLECCIÓN DE DATOS ---
# ==============================================================================

declare -A SVC_ACTIVE SVC_SUB SVC_DESC SVC_MEM SVC_CPU SVC_RSS SVC_REST
declare -A SVC_PID SVC_SINCE SVC_UFS SVC_EXEC SVC_VERD SVC_THREAD SVC_ETIME SVC_ARGS
declare -a SVC_UNITS=() FAILED_UNITS=() TOP_UNITS=() TIMERS=()
CONT_CRONTAB=0
CONT_ATQ=0
CONT_JOBS=0

formato_mb() {
    local b="${1:-0}"
    es_numero "$b" || { printf '—'; return; }
    awk -v b="$b" 'BEGIN {
        if (b >= 1073741824) printf "%.1f GB", b / 1073741824;
        else if (b >= 1048576) printf "%.0f MB", b / 1048576;
        else printf "%d KB", b / 1024;
    }'
}

funcion_probable() {
    local unidad="$1" desc="$2"
    case "$unidad" in
        *ssh*)                              echo "Acceso remoto (SSH)" ;;
        *nginx*|*apache*|*httpd*)           echo "Servidor web" ;;
        *cron*|*crond*)                     echo "Programador de tareas" ;;
        *dbus*)                             echo "Bus de mensajes del sistema" ;;
        *systemd*|*journal*)                echo "Gestión del sistema y logs" ;;
        *network*|*NetworkManager*)         echo "Gestión de red" ;;
        *firewalld*|*ufw*|*iptables*)       echo "Cortafuegos / filtrado" ;;
        *docker*|*containerd*|*podman*)     echo "Motor de contenedores" ;;
        *mysql*|*mariadb*|*postgres*|*redis*|*mongod*) echo "Base de datos" ;;
        *cups*)                             echo "Servicio de impresión" ;;
        *bluetooth*)                        echo "Bluetooth" ;;
        *)
            [ -n "$desc" ] && printf '%s' "$desc" || printf 'Sin descripción disponible'
            ;;
    esac
}

icono_estado() {
    case "${SVC_ACTIVE[$1]:-unknown}" in
        active)   printf "${VERDE_BRILLANTE}✔${RESET}" ;;
        failed)   printf "${ROJO_BRILLANTE}✖${RESET}" ;;
        inactive) printf "${AMARILLO}■${RESET}" ;;
        *)        printf "${AZUL}?${RESET}" ;;
    esac
}

interpretar_servicio() {
    local u="$1" v="" act="${SVC_ACTIVE[$1]:-unknown}"
    local mem="${SVC_MEM[$1]:-0}" rest="${SVC_REST[$1]:-0}" pid="${SVC_PID[$1]:-0}"
    local cpu="${SVC_CPU[$1]:-0}"

    [ "$act" = "failed" ] && v+="Fallido · "
    es_numero "$rest" && [ "$rest" -ge 3 ] && v+="Reiniciado ${rest} veces · "
    es_numero "$mem" && [ "$mem" -gt 524288000 ] && v+="Alto consumo de memoria · "
    if awk -v c="$cpu" 'BEGIN { exit !(c > 70) }' 2>/dev/null; then
        v+="Alto consumo de CPU · "
    fi
    [ "$act" = "inactive" ] && [ "${SVC_UFS[$u]:-}" = "enabled" ] && v+="Activado pero inactivo · "
    if [ "$pid" = "0" ] || [ -z "$pid" ]; then
        v+="Sin proceso principal · "
    fi
    [ -z "$v" ] && v="Estable"
    SVC_VERD[$u]="${v% · }"
}

# El veredicto se guarda en texto plano y se colorea solo al mostrarlo
# (las variables de color del proyecto contienen '\e' literal, no ESC real).
verdict_coloreado() {
    local texto="$1" color="$VERDE_BRILLANTE"
    case "$texto" in
        *Fallido*)                       color="$ROJO_BRILLANTE" ;;
        *Reiniciado*|*Alto*|*inactivo*)  color="$AMARILLO_BRILLANTE" ;;
    esac
    printf '%b%s%b' "$color" "$(recortar "$texto" 30)" "$RESET"
}

cargar_servicios() {
    SVC_UNITS=(); FAILED_UNITS=(); TOP_UNITS=()
    SVC_ACTIVE=(); SVC_SUB=(); SVC_DESC=(); SVC_MEM=(); SVC_CPU=(); SVC_RSS=()
    SVC_REST=(); SVC_PID=(); SVC_SINCE=(); SVC_UFS=(); SVC_EXEC=(); SVC_VERD=()
    SVC_THREAD=(); SVC_ETIME=(); SVC_ARGS=()

    if [ "$HAS_SYSTEMD" = true ]; then
        local unit act sub desc
        while IFS=$'\t' read -r unit act sub desc; do
            [ -n "$unit" ] || continue
            SVC_UNITS+=("$unit")
            SVC_ACTIVE[$unit]="$act"
            SVC_SUB[$unit]="$sub"
            SVC_DESC[$unit]="$desc"
            [ "$act" = "failed" ] && FAILED_UNITS+=("$unit")
        done < <(systemctl list-units --type=service --all --no-pager --no-legend --plain 2>/dev/null \
            | awk '{ d=""; for (i=5; i<=NF; i++) d = d (i>5 ? " " : "") $i; print $1 "\t" $3 "\t" $4 "\t" d }')

        # Propiedades de todos los servicios en una sola llamada
        local id="" mem="" cpu="" rest="" pid="" since="" descripcion="" ufs="" exec_cmd=""
        guardar_prop() {
            [ -n "$id" ] || return 0
            SVC_MEM[$id]="$mem"; SVC_CPU[$id]="$cpu"; SVC_REST[$id]="$rest"
            SVC_PID[$id]="$pid"; SVC_SINCE[$id]="$since"; SVC_UFS[$id]="$ufs"
            [ -n "$descripcion" ] && SVC_DESC[$id]="$descripcion"
            [ -n "$exec_cmd" ] && SVC_EXEC[$id]="$exec_cmd"
        }
        while IFS= read -r linea; do
            case "$linea" in
                Id=*)                 if [ -n "$id" ]; then guardar_prop; fi; id="${linea#*=}"; mem=""; cpu=""; rest=""; pid=""; since=""; descripcion=""; ufs=""; exec_cmd="" ;;
                MemoryCurrent=*)      mem="${linea#*=}" ;;
                CPUUsageNSec=*)       cpu="${linea#*=}" ;;
                NRestarts=*)          rest="${linea#*=}" ;;
                ExecMainPID=*)        pid="${linea#*=}" ;;
                ActiveEnterTimestamp=*) since="${linea#*=}" ;;
                Description=*)        descripcion="${linea#*=}" ;;
                UnitFileState=*)      ufs="${linea#*=}" ;;
                ExecStart=*)          exec_cmd="${linea#*=}" ;;
            esac
        done < <(systemctl show \
            -p Id -p MemoryCurrent -p CPUUsageNSec -p NRestarts -p ExecMainPID \
            -p ActiveEnterTimestamp -p Description -p UnitFileState -p ExecStart \
            "${SVC_UNITS[@]}" 2>/dev/null)
        guardar_prop
        unset -f guardar_prop

        # Top por memoria + servicios fallidos (siempre visibles)
        mapfile -t TOP_UNITS < <(
            for u in "${SVC_UNITS[@]}"; do
                printf '%s\t%s\n' "${SVC_MEM[$u]:-0}" "$u"
            done | sort -rn | head -n 8 | cut -f2
        )
        local u ya
        for u in "${FAILED_UNITS[@]}"; do
            ya=false
            for t in "${TOP_UNITS[@]}"; do [ "$t" = "$u" ] && ya=true; done
            if [ "$ya" = false ] && [ ${#TOP_UNITS[@]} -lt 10 ]; then TOP_UNITS+=("$u"); fi
        done

        # Percentiles reales de CPU/RAM del proceso principal (solo del top)
        local pcpu rss thrs etiempo args proceso
        for u in "${TOP_UNITS[@]}"; do
            proceso="${SVC_PID[$u]:-0}"
            if es_numero "$proceso" && [ "$proceso" -gt 0 ]; then
                read -r pcpu rss thrs etiempo args < <(
                    ps -p "$proceso" -o %cpu=,rss=,nlwp=,etime=,args= 2>/dev/null | head -n 1
                )
                SVC_CPU[$u]="${pcpu:-0}"
                SVC_THREAD[$u]="${thrs:-0}"
                SVC_ETIME[$u]="${etiempo:-N/D}"
                es_numero "${rss:-}" && SVC_RSS[$u]=$(( rss * 1024 ))
                SVC_ARGS[$u]="${args:-N/D}"
            fi
        done
    else
        # Sin systemd: análisis basado en ps (mismo espíritu que el fallback de proc4me)
        local pid pcpu rss etiempo comm args
        while IFS=$'\t' read -r pid pcpu rss etiempo comm args; do
            [ -n "$pid" ] || continue
            SVC_UNITS+=("$comm")
            SVC_ACTIVE[$comm]="running"
            SVC_PID[$comm]="$pid"
            SVC_CPU[$comm]="$pcpu"
            SVC_RSS[$comm]=$(( ${rss:-0} * 1024 ))
            SVC_ETIME[$comm]="$etiempo"
            SVC_ARGS[$comm]="$args"
            SVC_DESC[$comm]="(proceso) $args"
            TOP_UNITS+=("$comm")
        done < <(ps -eo pid=,pcpu=,rss=,etime=,comm=,args= 2>/dev/null \
            | awk '{ p=$1; c=$2; m=$3; e=$4; n=$5; a=""; for (i=6; i<=NF; i++) a=a (i>6 ? " " : "") $i; print p "\t" c "\t" m "\t" e "\t" n "\t" a }' \
            | sort -k3,3rn | head -n 8)
    fi

    local u
    for u in "${SVC_UNITS[@]}"; do interpretar_servicio "$u"; done
}

cargar_tareas() {
    TIMERS=()
    CONT_CRONTAB=0; CONT_ATQ=0; CONT_JOBS=0

    if [ "$HAS_SYSTEMD" = true ]; then
        local unit izq
        while IFS=$'\t' read -r unit izq; do
            [ -n "$unit" ] || continue
            TIMERS+=("$unit|$izq restantes")
        done < <(systemctl list-timers --all --no-pager --no-legend 2>/dev/null \
            | awk '{
                u = $NF;
                if ($(NF-1) ~ /\.timer$/) u = $(NF-1);
                izq = "";
                # Desde el campo 5 hasta la fecha de la última ejecución (YYYY-MM-DD),
                # que marca el inicio de la.columna PASSED. Funciona en cualquier idioma.
                for (i = 5; i <= NF; i++) {
                    if ($(i + 1) ~ /^[0-9]{4}-[0-9]{2}-[0-9]{2}$/) break;
                    if ($i == "left" || $i == "ago") continue;
                    izq = izq (izq == "" ? "" : " ") $i;
                }
                if (izq == "") izq = "—";
                print u "\t" izq;
            }')

        CONT_JOBS=$(systemctl list-jobs --no-legend --no-pager 2>/dev/null | wc -l)
    fi

    if [ "$HAS_CRONTAB" = true ]; then
        CONT_CRONTAB=$(crontab -l 2>/dev/null | grep -vcE '^[[:space:]]*(#|$)' || true)
    fi
    local f n
    for f in /etc/crontab /etc/cron.d/*; do
        [ -f "$f" ] || continue
        n=$(grep -vcE '^[[:space:]]*(#|$)' "$f" 2>/dev/null || true)
        es_numero "$n" && CONT_CRONTAB=$((CONT_CRONTAB + n))
    done

    if [ "$HAS_ATQ" = true ]; then
        CONT_ATQ=$(atq 2>/dev/null | wc -l)
    fi
}

# ==============================================================================
# --- RENDERIZADO DEL DASHBOARD ---
# ==============================================================================

# Construye el contenido del dashboard en STDOUT (sin códigos de control de pantalla).
construir_pantalla() {
    logo_texto

    local total=${#SVC_UNITS[@]}
    local fallidos=${#FAILED_UNITS[@]}
    local activos=0 inactivos=0 u
    for u in "${SVC_UNITS[@]}"; do
        case "${SVC_ACTIVE[$u]:-}" in
            active)   activos=$((activos + 1)) ;;
            inactive) inactivos=$((inactivos + 1)) ;;
        esac
    done

    echo -e " ${AMARILLO}➤ Servicios:${RESET} ${BLANCO}${total}${RESET}  ${VERDE}activos: ${activos}${RESET}  ${AMARILLO}inactivos: ${inactivos}${RESET}  ${ROJO}fallidos: ${fallidos}${RESET}"
    echo -e " ${AMARILLO}➤ Programación:${RESET} ${BLANCO}${CONT_CRONTAB}${RESET} entradas cron · ${BLANCO}${#TIMERS[@]}${RESET} timers · ${BLANCO}${CONT_ATQ}${RESET} en cola (atq) · ${BLANCO}${CONT_JOBS}${RESET} jobs systemd"

    # Interpretación resumida (máximo 2 hallazgos)
    local avisos=() aviso
    for u in "${FAILED_UNITS[@]}"; do
        avisos+=("🔴 $u: ${SVC_VERD[$u]}")
    done
    for u in "${TOP_UNITS[@]}"; do
        case "${SVC_VERD[$u]}" in
            *Reiniciado*|*"consumo"*) avisos+=("⚠ $u: ${SVC_VERD[$u]}") ;;
        esac
    done
    if [ ${#avisos[@]} -gt 0 ]; then
        echo -e " ${MAGENTA}➤ Interpretación:${RESET} $(recortar "${avisos[0]}" 80)"
        [ ${#avisos[@]} -gt 1 ] && echo -e "   $(recortar "${avisos[1]}" 80)"
    else
        echo -e " ${VERDE_BRILLANTE}➤ Interpretación: sin incidencias destacables${RESET}"
    fi

    echo -e " ${CIAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e " ${NEGRITA}${CIAN}📊 ANÁLISIS DE SERVICIOS (top por consumo + fallidos)${RESET}"
    printf '  %-27s %9s %7s %-4s %s\n' "SERVICIO" "MEMORIA" "CPU" "EST" "QUÉ HACE / INTERPRETACIÓN"
    local mem cpu desc verd
    for u in "${TOP_UNITS[@]}"; do
        # Memoria del cgroup del servicio (más representativa que el RSS de un solo PID)
        mem="${SVC_MEM[$u]:-${SVC_RSS[$u]:-0}}"
        cpu="${SVC_CPU[$u]:-—}"
        es_decimal "$cpu" && cpu="${cpu}%"
        desc=$(recortar "$(funcion_probable "$u" "${SVC_DESC[$u]:-}")" 30)
        verd=$(verdict_coloreado "${SVC_VERD[$u]:-}")
        printf '  %-27s %9s %7s %b  %s · %s\n' \
            "$(recortar "$u" 26)" "$(formato_mb "$mem")" "$cpu" "$(icono_estado "$u")" "$desc" "$verd"
    done
    [ ${#TOP_UNITS[@]} -eq 0 ] && echo -e "  ${AZUL}Sin servicios analizables (systemctl/ps no disponibles)${RESET}"

    echo -e " ${CIAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e " ${NEGRITA}${CIAN}⏱ TAREAS PROGRAMADAS (timers)${RESET}"
    local t datos
    for t in "${TIMERS[@]:0:5}"; do
        IFS='|' read -r u datos <<< "$t"
        printf '  %b %-32s %s\n' "${VERDE_BRILLANTE}▸${RESET}" "$(recortar "$u" 31)" "$datos"
    done
    [ ${#TIMERS[@]} -eq 0 ] && echo -e "  ${AZUL}Sin timers visibles (systemd no disponible o sin permisos)${RESET}"

    echo -e " ${CIAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e " ${AMARILLO}➤ Colas:${RESET} systemd jobs: ${BLANCO}${CONT_JOBS}${RESET} | tareas at: ${BLANCO}${CONT_ATQ}${RESET}"
    echo -e " ${CIAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e " ${VERDE_BRILLANTE}[f]${RESET} explorar servicio (FZF + detalle en árbol)   ${VERDE_BRILLANTE}[r]${RESET} refrescar   ${VERDE_BRILLANTE}[i]${RESET} informe   ${ROJO_BRILLANTE}[q]${RESET} salir"
}

# Redibujo sin parpadeo, igual que dash4me:
#   1) \e[H  -> llevar el cursor arriba SIN borrar la pantalla
#   2) \e[K  -> borrar cada línea antes de escribirla (evita restos de líneas más largas)
#   3) \e[J  -> borrar desde el cursor hasta el final (por si hay menos líneas que antes)
# El contenido se genera antes de mover el cursor, para que nunca se vea una pantalla vacía.
renderizar_pantalla() {
    local contenido linea
    contenido=$(construir_pantalla)
    printf '\033[H'
    while IFS= read -r linea; do
        printf '\033[K%s\n' "$linea"
    done <<< "$contenido"
    printf '\033[J'
}

# ==============================================================================
# --- LUPA OPCIONAL: FZF CON PREVIEW EN ÁRBOL ---
# ==============================================================================

# Carga únicamente la unidad solicitada (rápido: lo usa el preview de FZF)
cargar_unidad() {
    local u="${1:-}"
    [ -n "$u" ] || return 1
    [ "$HAS_SYSTEMD" = true ] || return 0

    local linea id="" act="" sub="" mem="" cpu="" rest="" pid=""
    local since="" desc="" ufs="" exec_cmd=""
    while IFS= read -r linea; do
        case "$linea" in
            Id=*)                   id="${linea#*=}" ;;
            ActiveState=*)          act="${linea#*=}" ;;
            SubState=*)             sub="${linea#*=}" ;;
            MemoryCurrent=*)        mem="${linea#*=}" ;;
            CPUUsageNSec=*)         cpu="${linea#*=}" ;;
            NRestarts=*)            rest="${linea#*=}" ;;
            ExecMainPID=*)          pid="${linea#*=}" ;;
            ActiveEnterTimestamp=*) since="${linea#*=}" ;;
            Description=*)          desc="${linea#*=}" ;;
            UnitFileState=*)        ufs="${linea#*=}" ;;
            ExecStart=*)            exec_cmd="${linea#*=}" ;;
        esac
    done < <(systemctl show \
        -p Id -p ActiveState -p SubState -p MemoryCurrent -p CPUUsageNSec \
        -p NRestarts -p ExecMainPID -p ActiveEnterTimestamp \
        -p Description -p UnitFileState -p ExecStart "$u" 2>/dev/null)

    [ -z "$id" ] && return 1
    SVC_ACTIVE[$u]="$act"; SVC_SUB[$u]="$sub"; SVC_MEM[$u]="$mem"
    SVC_CPU[$u]="$cpu"; SVC_REST[$u]="$rest"; SVC_PID[$u]="$pid"
    SVC_SINCE[$u]="$since"; SVC_UFS[$u]="$ufs"
    SVC_DESC[$u]="$desc"; SVC_EXEC[$u]="$exec_cmd"

    local pcpu rss thrs etiempo args
    if es_numero "$pid" && [ "$pid" -gt 0 ]; then
        read -r pcpu rss thrs etiempo args < <(
            ps -p "$pid" -o %cpu=,rss=,nlwp=,etime=,args= 2>/dev/null | head -n 1
        )
        SVC_CPU[$u]="${pcpu:-0}"
        SVC_THREAD[$u]="${thrs:-0}"
        SVC_RSS[$u]=$(( ${rss:-0} * 1024 ))
        SVC_ETIME[$u]="${etiempo:-N/D}"
        SVC_ARGS[$u]="${args:-N/D}"
    fi
    interpretar_servicio "$u"
}

detalle_arbol() {
    local u="${1:-}"
    [ -n "$u" ] || return 1

    if es_numero "$u"; then
        echo -e "${AZUL_BRILLANTE}PROCESO PID $u${RESET}"
        ps -p "$u" -o pid=,user=,pcpu=,pmem=,rss=,etime=,stat=,args= 2>/dev/null || echo "  Proceso no encontrado"
        return 0
    fi

    local desc="${SVC_DESC[$u]:-}" act="${SVC_ACTIVE[$u]:-N/D}" sub="${SVC_SUB[$u]:-N/D}"
    local pid="${SVC_PID[$u]:-0}" cpu="${SVC_CPU[$u]:-—}" rss="${SVC_RSS[$u]:-${SVC_MEM[$u]:-0}}"
    local depuis="${SVC_SINCE[$u]:-N/D}" ufs="${SVC_UFS[$u]:-N/D}" exec_cmd="${SVC_EXEC[$u]:-${SVC_ARGS[$u]:-N/D}}"
    local req="" wants="" puertos="" logs="N/D (journalctl no disponible)"

    if [ "$HAS_SYSTEMD" = true ]; then
        local linea
        while IFS= read -r linea; do
            case "$linea" in
                Requires=*) req="${linea#*=}" ;;
                Wants=*)    wants="${linea#*=}" ;;
            esac
        done < <(systemctl show -p Requires -p Wants "$u" 2>/dev/null)
    fi

    if [ "$HAS_SS" = true ] && es_numero "$pid" && [ "$pid" -gt 0 ]; then
        puertos=$(ss -tulpn 2>/dev/null | grep "pid=$pid" | awk '{print $5}' | sort -u | paste -sd, -)
        [ -z "$puertos" ] && puertos="ninguno visible"
    else
        puertos="N/D"
    fi

    if [ "$HAS_JOURNAL" = true ]; then
        logs=$(journalctl -u "$u" -n 100 --no-pager 2>/dev/null | grep -ciE 'error|fail|warn' 2>/dev/null)
        logs="${logs:-0} avisos/errores en las últimas 100 líneas"
    fi

    echo -e "${AZUL_BRILLANTE}$u${RESET}"
    printf '├── %-14s %s\n' "Descripción" "$(recortar "$(funcion_probable "$u" "$desc")" 62)"
    printf '├── %-14s %s (%s)\n' "Estado" "$act" "$sub"
    printf '├── %-14s %s\n' "Activo desde" "$depuis"
    printf '├── %-14s PID %s · %s CPU · %s hilos · %s\n' \
        "Proceso" "$pid" "$cpu" "${SVC_THREAD[$u]:-N/D}" "${SVC_ETIME[$u]:-N/D}"
    printf '├── %-14s %s (cgroup) · %s (proceso principal)\n' \
        "Memoria" "$(formato_mb "${SVC_MEM[$u]:-0}")" "$(formato_mb "${SVC_RSS[$u]:-0}")"
    printf '├── %-14s %s\n' "Comando" "$(recortar "$exec_cmd" 55)"
    printf '├── %-14s %s\n' "Arranque" "$ufs"
    printf '├── %-14s %s\n' "Dependencias" "$(recortar "${req:-—} | ${wants:-—}" 55)"
    printf '├── %-14s %s\n' "Puertos" "$puertos"
    printf '├── %-14s %s\n' "Registro" "$logs"
    printf '└── %-14s %b\n' "Veredicto" "${SVC_VERD[$u]:-Sin datos}"
}

explorar_servicios() {
    if ! command -v fzf &>/dev/null; then
        alerta "fzf no está instalado; se muestra el detalle del primer servicio."
        [ ${#SVC_UNITS[@]} -gt 0 ] && detalle_arbol "${SVC_UNITS[0]}"
        pausa
        return 0
    fi

    local lista="" u
    for u in "${SVC_UNITS[@]}"; do
        # La unidad va PRIMERO: FZF usa {1} como argumento del preview
        lista+="$u  $(icono_estado "$u")  $(recortar "${SVC_DESC[$u]:-}" 55)\n"
    done

    local preview_cmd header_cmd
    printf -v preview_cmd 'bash %q --detalle {1}' "$SELF_PATH"
    printf -v header_cmd 'bash %q --logo-header' "$SELF_PATH"

    printf '%b' "$lista" | stk_fzf_ejecutar "Seleccione servicio" "ANÁLISIS DE SERVICIOS" "ANÁLISIS DE SERVICIOS" \
        --ansi \
        --height=~90% \
        --layout=reverse \
        --no-sort \
        --header-first \
        --border=rounded \
        --border-label=" ANÁLISIS DE SERVICIOS " \
        --prompt="➤ Servicio: " \
        --preview="$preview_cmd" \
        --preview-window="right:62%:wrap" \
        --bind="every(5):bg-transform-header:$header_cmd" \
        --color="border:#ff5555,pointer:#92ff92,header:#5fb2ff,label:#5fb2ff,marker:#92ff92"
}

generar_informe() {
    local dir="$INFORME_DIR"
    mkdir -p "$dir" 2>/dev/null || dir="${TMPDIR:-/tmp}"
    local archivo="$dir/jobs4me_$(date +%Y%m%d_%H%M%S).txt"
    local u

    {
        echo "JOBS4ME v$V - Informe de análisis $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Sistema: $OS_ID | Kernel: $KERNEL_STK | Host: $HOST_STK"
        echo "============================================================"
        echo "SERVICIOS (${#SVC_UNITS[@]}): activos/fallidos/se desconocen según systemctl"
        for u in "${SVC_UNITS[@]}"; do
            printf '%-38s %-10s %9s %s\n' \
                "$u" "${SVC_ACTIVE[$u]:-?}" "$(formato_mb "${SVC_RSS[$u]:-${SVC_MEM[$u]:-0}}")" \
                "$(funcion_probable "$u" "${SVC_DESC[$u]:-}") :: ${SVC_VERD[$u]:-}"
        done
        echo "============================================================"
        echo "TAREAS PROGRAMADAS"
        printf 'cron: %s entradas | atq: %s | timers: %s | systemd jobs: %s\n' \
            "$CONT_CRONTAB" "$CONT_ATQ" "${#TIMERS[@]}" "$CONT_JOBS"
        for u in "${TIMERS[@]}"; do echo "  $u"; done
    } > "$archivo" 2>/dev/null

    if [ -f "$archivo" ]; then
        chmod 640 "$archivo" 2>/dev/null
        if [ "$(id -u)" -eq 0 ] && [ -n "${SUDO_USER:-}" ]; then
            chown "${SUDO_USER}:$(id -gn "$SUDO_USER" 2>/dev/null || echo "$SUDO_USER")" "$archivo" 2>/dev/null
        fi
        registrar_log "$LOG_INFO" "Informe generado: $archivo"
        ok "Informe guardado en: $archivo"
    else
        alerta "No se pudo escribir el informe."
    fi
    pausa
}

mostrar_ayuda() {
    echo -e "${CIAN}JOBS4ME v${V} - ${DESCRIPCION}${RESET}"
    echo -e "${BLANCO}Autor:${RESET} ${AUTOR}"
    echo ""
    echo -e "${AMARILLO}Uso:${RESET} bash $0 [OPCIÓN]"
    echo ""
    echo -e "  ${VERDE}--detalle UNIDAD${RESET}  Muestra el análisis en árbol de un servicio/PID."
    echo -e "  ${VERDE}--logo-header${RESET}     Uso interno para la cabecera viva de FZF."
    echo -e "  ${VERDE}--help${RESET}            Muestra esta ayuda."
    echo ""
    echo -e "${AZUL}Dentro del dashboard:${RESET} [f] explorar · [r] refrescar · [i] informe · [q] salir"
    echo -e "${ROJO_BRILLANTE}No exige root y no modifica ningún servicio.${RESET}"
}

# ==============================================================================
# --- PUNTO DE ENTRADA ---
# ==============================================================================

main() {
    detectar_sistema

    if [ "$JOBS4ME_SOLO" = true ]; then
        case "$1" in
            --logo-header) logo_texto; exit 0 ;;
            --detalle)
                if [ -n "${2:-}" ]; then
                    if es_numero "$2"; then
                        detalle_arbol "$2"
                    else
                        cargar_unidad "$2"
                        detalle_arbol "$2"
                    fi
                fi
                exit 0
                ;;
            --help|-h)     mostrar_ayuda; exit 0 ;;
        esac
    fi

    # Sin TTY (redirección, cron, preview): una sola captura y salir
    if [ ! -t 0 ] || [ ! -t 1 ] || [ -z "${TERM:-}" ] || [ "$TERM" = "dumb" ]; then
        cargar_servicios
        cargar_tareas
        renderizar_pantalla
        exit 0
    fi

    # Pantalla alternativa sin terminfo (secuencias ANSI de stk_header.sh).
    stk_alt_screen_on
    stk_cursor_off
    trap 'stk_alt_screen_off; stk_cursor_on; exit 0' SIGINT SIGTERM

    local tecla=""
    while true; do
        cargar_servicios
        cargar_tareas
        renderizar_pantalla

        tecla=""
        read -r -n 1 -s -t 3 tecla || tecla=""
        case "$tecla" in
            f|F)
                stk_alt_screen_off; stk_cursor_on
                explorar_servicios
                stk_alt_screen_on; stk_cursor_off
                ;;
            i|I)
                stk_alt_screen_off; stk_cursor_on
                generar_informe
                stk_alt_screen_on; stk_cursor_off
                ;;
            q|Q|$'\e')
                break
                ;;
            *)
                ;;
        esac
    done

    stk_alt_screen_off; stk_cursor_on
    salir_jobs4me
}

main "$@"
