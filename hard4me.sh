#!/bin/bash

# ==============================================================================
# HARD4ME - Dashboard de análisis, monitorización e interpretación del disco
# ==============================================================================
# Módulo de SOLO LECTURA para Linux. No instala nada sin preguntar y NO exige
# root: lo que requiera permisos se muestra como N/D con una nota.
# No lanza auto-tests SMART, scrubs ni reparaciones: solo consulta y alerta.
# Pensado para ejecutarse solo (bash hard4me.sh) o integrarse en STK.
# ==============================================================================

DESCRIPCION="Dashboard de análisis y monitorización del disco duro"
AUTOR="DanSanMar"

# --- BIBLIOTECA DE CABECERAS STK (paleta, menús FZF y cabecera responsive) ---
# Misma cabecera que install4me.sh: modos completo/normal/compacto según
# ancho y alto reales de terminal, con colores rotativos y `wc -L` para medir.
STK_HEADER="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)/stk_header.sh"
if [ ! -f "$STK_HEADER" ]; then
    STK_HEADER=$(find /home /root /usr/local -maxdepth 5 -name "stk_header.sh" 2>/dev/null | head -n 1)
fi
if [ -f "$STK_HEADER" ]; then
    # shellcheck source=stk_header.sh
    source "$STK_HEADER"
else
    echo "❌ No se encuentra $STK_HEADER. HARD4ME no puede iniciarse." >&2
    exit 1
fi

STK_UI_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)/stk_ui_lib.sh"
[ -r "$STK_UI_LIB" ] && source "$STK_UI_LIB"

V="${STK_VERSION:-7.0.0}"
ver="v ${STK_VERSION:-7.0.0} · HARD4ME"
STK_MODULO="HARD4ME"
stk_init "HARD4ME" "$V" "DISK HEALTH MONITOR"

# --- LOGS E INFORMES ---
LOG_FILE="/var/log/stk_mantenimiento.log"
LOG_INFO="INFO"
LOG_WARN="WARN"
LOG_ERR="ERROR"
INFORME_DIR="/var/log/hard4me"

# --- RUTA ABSOLUTA (para el preview de FZF y la cabecera viva) ---
SELF_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)/$(basename "${BASH_SOURCE[0]}")"

# Se ejecuta de forma independiente o se invoca desde STK
HARD4ME_SOLO=false
[ "${BASH_SOURCE[0]}" = "$0" ] && HARD4ME_SOLO=true

# --- DETECCIÓN DE ENTORNO ---
OS_ID="Linux"
KERNEL_STK=""
HOST_STK=""
Package=""
HAS_SMART=false
HAS_NVME=false
HAS_LSBLK=false
HAS_IOSTAT=false
HAS_FSTRIM=false
HAS_FZF=false
HAS_LVM=false
HAS_MDADM=false
HAS_BTRFS=false
HAS_ZFS=false
HAS_CRYPTSETUP=false
ES_ROOT=false
[ "$(id -u)" -eq 0 ] && ES_ROOT=true

registrar_log() {
    local NIVEL="${1:-INFO}"
    local MENSAJE="${2}"
    local FECHA
    FECHA=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$FECHA] [$NIVEL] [${SUDO_USER:-${USER:-$(id -un 2>/dev/null)}}] - [HARD4ME] $MENSAJE" >> "$LOG_FILE" 2>/dev/null
}

ok()      { pintar "$VERDE_BRILLANTE" "✔ $1"; }
alerta()  { pintar "$ROJO_BRILLANTE" "⚠️ $1"; }
info()    { pintar "$AZUL" "ℹ️ $1"; }
seccion() { echo ""; pintar "$MAGENTA" "--- $1 ---"; }
pausa()   { echo ""; read -r -p "Presione Enter para continuar..." _; }

es_numero()  { [[ "$1" =~ ^[0-9]+$ ]]; }
es_decimal() { [[ "$1" =~ ^[0-9]+(\.[0-9]+)?$ ]]; }

# --- Layout compartido con stk_header.sh (ancho/alto reales de terminal) ---
ANCHO=80
COMPACTO=false

actualizar_layout() {
    local cols lineas
    cols=$(stk_detectar_columnas)
    lineas=$(stk_detectar_filas)
    es_numero "$cols" || cols=80
    es_numero "$lineas" || lineas=24
    ANCHO=$cols
    if [ "$ANCHO" -lt 90 ] || [ "$lineas" -lt 20 ]; then
        COMPACTO=true
    else
        COMPACTO=false
    fi
}

recortar() {
    local texto="$1" max="${2:-60}" limite recortado
    limite=$(( ANCHO - 4 ))
    [ "$limite" -lt 12 ] && limite=12
    [ "$max" -gt "$limite" ] && max="$limite"
    recortado=$(stk_recortar "$texto" "$max")
    [ "$recortado" != "$texto" ] && printf '%s…' "$recortado" || printf '%s' "$recortado"
}

separador() {
    local n=$(( ANCHO - 1 ))
    [ "$n" -lt 20 ] && n=20
    stk_repetir '━' "$n"
}

cmd_timeout() {
    # timeout portable: si no existe, se ejecuta sin límite.
    if command -v timeout >/dev/null 2>&1; then
        timeout "$@"
    else
        shift  # descarta los segundos
        "$@"
    fi
}

detectar_sistema() {
    if [ -f /etc/os-release ]; then
        . /etc/os-release 2>/dev/null
        OS_ID="${PRETTY_NAME:-${ID:-Linux}}"
    fi
    KERNEL_STK=$(uname -r 2>/dev/null || echo "N/D")
    HOST_STK=$(hostname 2>/dev/null || cat /etc/hostname 2>/dev/null || echo "Desconocido")

    command -v smartctl >/dev/null 2>&1 && HAS_SMART=true
    command -v nvme >/dev/null 2>&1 && HAS_NVME=true
    command -v lsblk >/dev/null 2>&1 && HAS_LSBLK=true
    command -v iostat >/dev/null 2>&1 && HAS_IOSTAT=true
    command -v fstrim >/dev/null 2>&1 && HAS_FSTRIM=true
    command -v fzf >/dev/null 2>&1 && HAS_FZF=true
    command -v pvs >/dev/null 2>&1 && HAS_LVM=true
    command -v mdadm >/dev/null 2>&1 && HAS_MDADM=true
    command -v btrfs >/dev/null 2>&1 && HAS_BTRFS=true
    command -v zpool >/dev/null 2>&1 && HAS_ZFS=true
    command -v cryptsetup >/dev/null 2>&1 && HAS_CRYPTSETUP=true

    if [ -z "$Package" ]; then
        case "${ID:-}-${ID_LIKE:-}" in
            *debian*|*ubuntu*)        Package="apt" ;;
            *fedora*|*rhel*|*centos*) Package="dnf" ;;
            *arch*|*manjaro*)         Package="pacman" ;;
            *suse*)                   Package="zypper" ;;
            *)
                if command -v apt-get >/dev/null 2>&1; then Package="apt"
                elif command -v dnf >/dev/null 2>&1; then Package="dnf"
                elif command -v pacman >/dev/null 2>&1; then Package="pacman"
                elif command -v zypper >/dev/null 2>&1; then Package="zypper"
                elif command -v apk >/dev/null 2>&1; then Package="apk"
                else Package="unknown"
                fi
                ;;
        esac
    fi
}

# --- CABECERA Y MENÚS: delegados a stk_header.sh ---
# stk_init ya se llamó al sourcear la librería. stk_header dibuja la cabecera
# responsive (completo/normal/compacto) y stk_fzf_menu da el menú estándar.

# ==============================================================================
# --- INSTALACIÓN DE DEPENDENCIAS BAJO DEMANDA ---
# ==============================================================================
ofrecer_instalar() {
    local cmd="$1" paquete="$2" descripcion="$3"
    command -v "$cmd" >/dev/null 2>&1 && return 0

    echo -e " ${AMARILLO}⚠ No se encontró ${BLANCO}${cmd}${AMARILLO} (${descripcion}).${RESET}"
    # Desde el preview de FZF o sin TTY nunca se instala nada.
    if [ ! -t 0 ] || [ ! -t 1 ]; then
        echo -e "   ${AZUL}Instálalo con:${RESET} sudo ${Package} install ${paquete}  (o desde el menú Software → Instalador)"
        return 1
    fi

    local respuesta="n"
    read -r -p "   ¿Instalar '$paquete' ahora? (s/N): " respuesta
    case "$respuesta" in
        s|S|si|SI|Si) ;;
        *)
            echo -e "   ${AZUL}Omitido. Puedes instalarlo desde el menú Software → Instalador por categorías.${RESET}"
            registrar_log "$LOG_INFO" "Dependencia $paquete omitida por el usuario"
            return 1
            ;;
    esac

    if [ "$ES_ROOT" = false ] && ! command -v sudo >/dev/null 2>&1; then
        alerta "Se necesita root o sudo para instalar $paquete."
        return 1
    fi
    local SUDO=""
    [ "$ES_ROOT" = false ] && SUDO="sudo"

    local estado=1
    echo -e "   ${AZUL}Instalando $paquete ($Package)...${RESET}"
    case "$Package" in
        apt)    $SUDO apt-get update -qq >/dev/null 2>&1 && $SUDO apt-get install -y "$paquete" >/dev/null 2>&1 && estado=0 ;;
        dnf)    $SUDO dnf install -y "$paquete" >/dev/null 2>&1 && estado=0 ;;
        pacman) $SUDO pacman -S --noconfirm "$paquete" >/dev/null 2>&1 && estado=0 ;;
        zypper) $SUDO zypper install -y "$paquete" >/dev/null 2>&1 && estado=0 ;;
        apk)    $SUDO apk add "$paquete" >/dev/null 2>&1 && estado=0 ;;
        *)      alerta "Gestor desconocido: usa el menú Software." ;;
    esac

    if [ "$estado" -eq 0 ] && command -v "$cmd" >/dev/null 2>&1; then
        ok "$paquete instalado."
        registrar_log "$LOG_INFO" "Dependencia instalada a petición del usuario: $paquete"
        case "$cmd" in
            smartctl) HAS_SMART=true ;;
            nvme)     HAS_NVME=true ;;
        esac
        return 0
    fi
    alerta "No se pudo instalar $paquete. Se mostrarán datos parciales."
    registrar_log "$LOG_WARN" "No se pudo instalar la dependencia: $paquete"
    return 1
}

# ==============================================================================
# --- RECOLECCIÓN DE DATOS ---
# ==============================================================================
declare -A DK_MODEL DK_SIZE DK_KIND DK_BUS DK_SERIAL DK_ROTA DK_FSTYPE DK_MOUNT
declare -A DK_HEALTH DK_LEVEL DK_VERD DK_TEMP DK_HOURS DK_REALLOC DK_PENDING
declare -A DK_UNCORR DK_LIFE DK_ERRLOG DK_SELFTEST DK_FIRMWARE DK_DETAIL
declare -a DISCOS=() FS_FILAS=() PERF_FILAS=() LAYER_FILAS=() TEMP_FILAS=()
declare -A FS_DEV FS_TYPE FS_SIZE FS_USED FS_AVAIL FS_PCT FS_IPCT FS_MOUNT
NIVEL_GLOBAL=0
CONT_DISCOS=0
CONT_NVME=0
CONT_SSD=0
CONT_HDD=0
CONT_CRITICOS=0
CONT_AVISOS=0

formato_mb() {
    local b="${1:-0}"
    es_numero "$b" || { printf '—'; return; }
    awk -v b="$b" 'BEGIN {
        if (b >= 1099511627776) printf "%.1f TB", b / 1099511627776;
        else if (b >= 1073741824) printf "%.1f GB", b / 1073741824;
        else if (b >= 1048576) printf "%.0f MB", b / 1048576;
        else printf "%d KB", b / 1024;
    }'
}

porcentaje_barra() {
    local pct="${1:-0}"
    pct="${pct%\%}"
    es_numero "$pct" || { printf '—'; return; }
    local llenos=$(( pct / 10 ))
    [ "$llenos" -gt 10 ] && llenos=10
    local barra=""
    local i
    for (( i=0; i<llenos; i++ )); do barra+="█"; done
    for (( i=llenos; i<10; i++ )); do barra+="░"; done
    printf '%s %s%%' "$barra" "$pct"
}

porcentaje_barra_corta() {
    local pct="${1:-0}"
    pct="${pct%\%}"
    es_numero "$pct" || { printf '—'; return; }
    local llenos=$(( pct / 20 )) barra="" i
    [ "$llenos" -gt 5 ] && llenos=5
    for (( i=0; i<llenos; i++ )); do barra+="█"; done
    for (( i=llenos; i<5; i++ )); do barra+="░"; done
    printf '%s %s%%' "$barra" "$pct"
}

color_por_nivel() {
    case "${1:-0}" in
        2) printf '%b' "$ROJO_BRILLANTE" ;;
        1) printf '%b' "$AMARILLO_BRILLANTE" ;;
        *) printf '%b' "$VERDE_BRILLANTE" ;;
    esac
}

icono_nivel() {
    case "${1:-0}" in
        2) printf "${ROJO_BRILLANTE}🔴${RESET}" ;;
        1) printf "${AMARILLO_BRILLANTE}⚠${RESET}" ;;
        *) printf "${VERDE_BRILLANTE}✔${RESET}" ;;
    esac
}

# --- Descubrimiento de dispositivos de bloque ---
cargar_dispositivos() {
    DISCOS=()
    DK_MODEL=(); DK_SIZE=(); DK_KIND=(); DK_BUS=(); DK_SERIAL=(); DK_ROTA=()
    DK_FSTYPE=(); DK_MOUNT=(); DK_HEALTH=(); DK_LEVEL=(); DK_VERD=(); DK_TEMP=()
    DK_HOURS=(); DK_REALLOC=(); DK_PENDING=(); DK_UNCORR=(); DK_LIFE=()
    DK_ERRLOG=(); DK_SELFTEST=(); DK_FIRMWARE=(); DK_DETAIL=()
    CONT_DISCOS=0; CONT_NVME=0; CONT_SSD=0; CONT_HDD=0
    CONT_CRITICOS=0; CONT_AVISOS=0
    NIVEL_GLOBAL=0

    local nombre tipo size rota modelo serial
    while IFS='|' read -r nombre tipo size rota modelo serial; do
        [ -n "$nombre" ] || continue
        case "$nombre" in
            loop*|ram*|dm-*|md*|zd*|nbd*) continue ;;
        esac
        [ "$tipo" = "disk" ] || continue

        local dev="/dev/$nombre"
        DISCOS+=("$nombre")
        CONT_DISCOS=$(( CONT_DISCOS + 1 ))

        DK_SIZE[$nombre]="${size:-N/D}"
        DK_MODEL[$nombre]="${modelo:-Desconocido}"
        DK_SERIAL[$nombre]="${serial:-N/D}"
        DK_ROTA[$nombre]="${rota:-N/D}"

        local bus="N/D"
        case "$nombre" in
            nvme*) bus="NVMe"; CONT_NVME=$(( CONT_NVME + 1 )) ;;
            sd*)
                if [ -r "/sys/block/$nombre/device/virtio" ] || grep -q 'virtio' "/sys/block/$nombre/device/modalias" 2>/dev/null; then
                    bus="VirtIO"
                elif [ -r "/sys/block/$nombre/device/subsystem" ]; then
                    bus=$(basename "$(readlink -f "/sys/block/$nombre/device/subsystem" 2>/dev/null)" 2>/dev/null || echo "SCSI")
                    [ -z "$bus" ] && bus="SCSI"
                else
                    bus="SCSI"
                fi
                ;;
            vd*) bus="VirtIO" ;;
            xvd*) bus="Xen" ;;
            mmcblk*) bus="MMC/SD" ;;
        esac
        DK_BUS[$nombre]="$bus"

        if [ "$bus" = "NVMe" ]; then
            DK_KIND[$nombre]="SSD (NVMe)"; CONT_SSD=$(( CONT_SSD + 1 ))
        elif [ "${rota:-1}" = "0" ]; then
            DK_KIND[$nombre]="SSD"; CONT_SSD=$(( CONT_SSD + 1 ))
        else
            DK_KIND[$nombre]="HDD"; CONT_HDD=$(( CONT_HDD + 1 ))
        fi

        DK_FSTYPE[$nombre]="—"
        DK_MOUNT[$nombre]="—"
        if [ "$HAS_LSBLK" = true ]; then
            local primer_mount primer_fs
            primer_fs=$(lsblk -n -o FSTYPE "$dev" 2>/dev/null | grep -v '^$' | head -n 1)
            primer_mount=$(lsblk -n -o MOUNTPOINT "$dev" 2>/dev/null | grep -v '^$' | head -n 1)
            [ -n "$primer_fs" ] && DK_FSTYPE[$nombre]="$primer_fs"
            [ -n "$primer_mount" ] && DK_MOUNT[$nombre]="$primer_mount"
        fi

        DK_HEALTH[$nombre]="N/D"
        DK_LEVEL[$nombre]=0
        DK_VERD[$nombre]="Sin datos de salud"
        DK_TEMP[$nombre]="N/D"
        DK_HOURS[$nombre]="N/D"
        DK_REALLOC[$nombre]="N/D"
        DK_PENDING[$nombre]="N/D"
        DK_UNCORR[$nombre]="N/D"
        DK_LIFE[$nombre]="N/D"
        DK_ERRLOG[$nombre]="N/D"
        DK_SELFTEST[$nombre]="N/D"
        DK_FIRMWARE[$nombre]="N/D"
        DK_DETAIL[$nombre]=""

        # --- SMART (ATA/SAS) ---
        if [ "$HAS_SMART" = true ] && [ "$bus" != "NVMe" ]; then
            local salida
            salida=$(cmd_timeout 6 smartctl -i -H -A -l selftest -l error "$dev" 2>/dev/null)
            if [ -n "$salida" ]; then
                DK_DETAIL[$nombre]="$salida"
                local linea valor
                while IFS= read -r linea; do
                    case "$linea" in
                        *"Firmware Version:"*)
                            DK_FIRMWARE[$nombre]=$(echo "${linea#*:}" | xargs) ;;
                        *"overall-health self-assessment test result:"*)
                            valor=$(echo "${linea##*:}" | xargs)
                            DK_HEALTH[$nombre]="${valor:-N/D}"
                            case "$valor" in
                                PASSED) DK_LEVEL[$nombre]=0 ;;
                                FAILED) DK_LEVEL[$nombre]=2; DK_HEALTH[$nombre]="FAILED" ;;
                            esac
                            ;;
                        *Reallocated_Sector_Ct*|*Reallocated_Event_Count*)
                            valor=$(echo "$linea" | awk '{print $NF}')
                            es_numero "$valor" && DK_REALLOC[$nombre]="$valor" ;;
                        *Current_Pending_Sector*)
                            valor=$(echo "$linea" | awk '{print $NF}')
                            es_numero "$valor" && DK_PENDING[$nombre]="$valor" ;;
                        *Offline_Uncorrectable*|*Uncorrectable_Sector_Ct*)
                            valor=$(echo "$linea" | awk '{print $NF}')
                            es_numero "$valor" && DK_UNCORR[$nombre]="$valor" ;;
                        *Power_On_Hours*)
                            valor=$(echo "$linea" | awk '{print $NF}')
                            es_numero "$valor" && DK_HOURS[$nombre]="$valor h" ;;
                        *Temperature_Celsius*|*Temperature_Case*|*Temperature_Internal*|*Airflow_Temperature*)
                            # El valor real va detrás del guion; delante están los
                            # valores normalizado/peor/umbral, que no son la temperatura.
                            valor=$(echo "$linea" | awk '{for(i=1;i<=NF;i++) if($i=="-"){print $(i+1); exit}}' 2>/dev/null | awk '{print $1}')
                            es_numero "$valor" && DK_TEMP[$nombre]="${valor} °C" ;;
                        *Media_Wearout_Indicator*|*SSD_Life_Left*|*Percent_Lifetime_Remain*|*Wear_Leveling_Count*)
                            valor=$(echo "$linea" | awk '{print $NF}')
                            es_numero "$valor" && DK_LIFE[$nombre]="${valor}%" ;;
                        *"No Errors Logged"*) DK_ERRLOG[$nombre]="0 errores" ;;
                        *"Error Count:"*)
                            valor=$(echo "${linea#*:}" | xargs | awk '{print $1}')
                            es_numero "$valor" && DK_ERRLOG[$nombre]="$valor errores" ;;
                        *"Completed without error"*) DK_SELFTEST[$nombre]="OK" ;;
                        *"Completed: failed"*|*"Self-test routine failed"*)
                            DK_SELFTEST[$nombre]="FALLIDO" ;;
                    esac
                done <<< "$salida"
            fi
        fi

        # --- NVMe ---
        if [ "$HAS_NVME" = true ] && [ "$bus" = "NVMe" ]; then
            local salida_nvme
            salida_nvme=$(cmd_timeout 6 nvme smart-log "$dev" 2>/dev/null)
            if [ -n "$salida_nvme" ]; then
                DK_DETAIL[$nombre]="$salida_nvme"
                local linea valor crit temp usado spare errores
                while IFS= read -r linea; do
                    valor=$(echo "${linea#*:}" | xargs 2>/dev/null)
                    case "$linea" in
                        critical_warning*)  crit="$valor" ;;
                        temperature*)       temp=$(echo "$valor" | awk '{print $1}') ;;
                        percentage_used*)   usado=$(echo "$valor" | tr -d '%') ;;
                        available_spare*|available_spare_threshold*) : ;;
                        media_errors*)      errores="$valor" ;;
                        num_err_log_entries*) [ -z "$errores" ] && errores="$valor" ;;
                    esac
                done <<< "$salida_nvme"
                es_numero "$crit" && [ "$crit" -ne 0 ] && DK_LEVEL[$nombre]=2
                es_numero "$temp" && DK_TEMP[$nombre]="${temp} °C"
                es_numero "$usado" && DK_LIFE[$nombre]="$(( 100 - usado ))%"
                es_numero "$errores" && DK_ERRLOG[$nombre]="$errores errores"
                DK_HEALTH[$nombre]="$( [ ${DK_LEVEL[$nombre]} -eq 2 ] && echo 'CRÍTICO' || echo 'OK' )"
                DK_SELFTEST[$nombre]="N/D (NVMe)"
                DK_HOURS[$nombre]="N/D (NVMe)"
            fi
        fi

        interpretar_disco "$nombre"
    done < <(if [ "$HAS_LSBLK" = true ]; then
        lsblk -dn -o NAME,TYPE,SIZE,ROTA,MODEL,SERIAL 2>/dev/null \
            | awk 'NR>0 { gsub(/^ +| +$/, "", $1); print $1 "|" $2 "|" $3 "|" $4 "|" $5 "|" $6 }'
    fi)
}

# --- Veredicto por disco ---
interpretar_disco() {
    local d="$1"
    local motivos="" nivel="${DK_LEVEL[$d]:-0}"
    local realloc="${DK_REALLOC[$d]:-N/D}" pending="${DK_PENDING[$d]:-N/D}"
    local uncorr="${DK_UNCORR[$d]:-N/D}" temp="${DK_TEMP[$d]:-N/D}"
    local life="${DK_LIFE[$d]:-N/D}" errlog="${DK_ERRLOG[$d]:-N/D}"
    local selftest="${DK_SELFTEST[$d]:-N/D}" health="${DK_HEALTH[$d]:-N/D}"

    [ "$health" = "FAILED" ] && { motivos+="SMART FAILED · "; nivel=2; }
    [ "$health" = "CRÍTICO" ] && { motivos+="critical_warning NVMe · "; nivel=2; }

    es_numero "$realloc" && [ "$realloc" -gt 0 ] && {
        motivos+="Sectores reasignados ($realloc) · "; [ "$nivel" -lt 2 ] && nivel=1; }
    es_numero "$pending" && [ "$pending" -gt 0 ] && {
        motivos+="Sectores pendientes ($pending) · "; nivel=2; }
    es_numero "$uncorr" && [ "$uncorr" -gt 0 ] && {
        motivos+="Errores inconrrectables ($uncorr) · "; nivel=2; }

    local temp_num="${temp%% *}"
    if es_numero "$temp_num" && [ "$temp_num" -ge 50 ]; then
        motivos+="Temperatura alta (${temp}) · "; [ "$nivel" -lt 2 ] && nivel=1
    elif es_numero "$temp_num" && [ "$temp_num" -ge 45 ]; then
        motivos+="Temperatura elevada (${temp}) · "; [ "$nivel" -lt 1 ] && nivel=1
    fi

    local vida="${life%%%}"
    if es_numero "$vida" && [ "$vida" -le 10 ]; then
        motivos+="Vida restante baja ($life) · "; [ "$nivel" -lt 2 ] && nivel=1
    elif es_numero "$vida" && [ "$vida" -le 25 ]; then
        motivos+="Vida restante reducida ($life) · "; [ "$nivel" -lt 1 ] && nivel=1
    fi

    case "$errlog" in
        *[1-9]*) motivos+="Errores en el log ($errlog) · "; [ "$nivel" -lt 1 ] && nivel=1 ;;
    esac
    [ "$selftest" = "FALLIDO" ] && { motivos+="Autotest fallido · "; nivel=2; }

    [ -z "$motivos" ] && motivos="Sin incidencias"

    DK_LEVEL[$d]=$nivel
    DK_VERD[$d]="${motivos% · }"
    [ "$nivel" -eq 2 ] && CONT_CRITICOS=$(( CONT_CRITICOS + 1 ))
    [ "$nivel" -eq 1 ] && CONT_AVISOS=$(( CONT_AVISOS + 1 ))
    [ "$nivel" -gt "$NIVEL_GLOBAL" ] && NIVEL_GLOBAL=$nivel
}

# --- Capacidad e inodos ---
cargar_capacidad() {
    FS_FILAS=()
    FS_DEV=(); FS_TYPE=(); FS_SIZE=(); FS_USED=(); FS_AVAIL=()
    FS_PCT=(); FS_IPCT=(); FS_MOUNT=()

    local sistema tipo tam usado libre pct montaje ipct id
    while IFS='|' read -r sistema tipo tam usado libre pct montaje; do
        [ -n "$sistema" ] || continue
        # Se ignoran sistemas virtuales y los squashfs de Snap (siempre al 100 %
        # por ser imágenes de solo lectura: generaban avisos falsos).
        case "$tipo" in
            tmpfs|devtmpfs|overlay|squashfs|proc|sysfs|devpts|cgroup*|securityfs|pstore|bpf|tracefs|debugfs|fusectl|mqueue|hugetlbfs|autofs|efivarfs|none) continue ;;
        esac
        case "$montaje" in
            /var/lib/snapd/*|/snap/*) continue ;;
        esac
        id="${sistema}::${montaje}"
        FS_FILAS+=("$id")
        FS_DEV[$id]="$sistema"; FS_TYPE[$id]="$tipo"
        FS_SIZE[$id]="$tam"; FS_USED[$id]="$usado"; FS_AVAIL[$id]="$libre"
        FS_PCT[$id]="$pct"; FS_MOUNT[$id]="$montaje"
        pct="${pct%\%}"; es_numero "$pct" || pct=0
        if [ "$pct" -ge 90 ]; then
            [ "$NIVEL_GLOBAL" -lt 1 ] && NIVEL_GLOBAL=1
        fi
    done < <(df -hT -P 2>/dev/null | awk 'NR>1 {print $1 "|" $2 "|" $3 "|" $4 "|" $5 "|" $6 "|" $7}')

    while IFS='|' read -r sistema ipct montaje; do
        [ -n "$sistema" ] || continue
        case "$montaje" in
            /var/lib/snapd/*|/snap/*) continue ;;
        esac
        local id="${sistema}::${montaje}"
        [ -n "${FS_PCT[$id]:-}" ] || continue
        FS_IPCT[$id]="$ipct"
        ipct="${ipct%\%}"; es_numero "$ipct" || ipct=0
        if [ "$ipct" -ge 90 ]; then
            [ "$NIVEL_GLOBAL" -lt 1 ] && NIVEL_GLOBAL=1
        fi
    done < <(df -i -P 2>/dev/null | awk 'NR>1 {print $1 "|" $5 "|" $6}')

}

# --- Rendimiento desde /proc/diskstats ---
cargar_rendimiento() {
    PERF_FILAS=()
    [ ! -r /proc/diskstats ] && return 0

    local -A LECT1=() ESCR1=() SECT1=() TIEMPO1=()
    local campo nombre
    while read -r _ _ nombre campo; do
        LECT1[$nombre]="${campo}" # se rellena correctamente abajo
    done < /dev/null

    # Lectura 1 (campos: 4=lecturas, 8=escrituras, 6=sectores leídos, 10=escritos, 13=ms E/S)
    local a b c d e f g h i j k l m n o p q r s t u v w x y z aa ab ac ad ae af
    while read -r a b c d e f g h i j k l m n o p q r s t u v w x y z aa ab ac ad ae af; do
        [ -n "$c" ] || continue
        case "$c" in loop*|ram*|dm-*|md*) continue ;; esac
        LECT1[$c]="$d"; ESCR1[$c]="$h"; SECT1[$c]=$(( ${f:-0} + ${j:-0} )); TIEMPO1[$c]="${ad:-0}"
    done < /proc/diskstats

    sleep 1

    local -A LECT2=() ESCR2=() SECT2=() TIEMPO2=()
    while read -r a b c d e f g h i j k l m n o p q r s t u v w x y z aa ab ac ad ae af; do
        [ -n "$c" ] || continue
        case "$c" in loop*|ram*|dm-*|md*) continue ;; esac
        LECT2[$c]="$d"; ESCR2[$c]="$h"; SECT2[$c]=$(( ${f:-0} + ${j:-0} )); TIEMPO2[$c]="${ad:-0}"
    done < /proc/diskstats

    local dev rl re rs ut
    for dev in "${DISCOS[@]}"; do
        rl=$(( ${LECT2[$dev]:-0} - ${LECT1[$dev]:-0} ))
        re=$(( ${ESCR2[$dev]:-0} - ${ESCR1[$dev]:-0} ))
        rs=$(( ${SECT2[$dev]:-0} - ${SECT1[$dev]:-0} ))
        ut=$(( ${TIEMPO2[$dev]:-0} - ${TIEMPO1[$dev]:-0} ))
        [ "$rl" -lt 0 ] && rl=0; [ "$re" -lt 0 ] && re=0
        [ "$rs" -lt 0 ] && rs=0; [ "$ut" -lt 0 ] && ut=0
        [ "$ut" -gt 100 ] && ut=100
        PERF_FILAS+=("$dev|$rl|$re|$(( rs / 2 ))|$ut")
    done
}

# --- Capas: LVM, mdadm, Btrfs, ZFS, LUKS, swap ---
cargar_capas() {
    LAYER_FILAS=()

    if [ "$HAS_LVM" = true ]; then
        local linea
        while IFS= read -r linea; do
            [ -n "$linea" ] || continue
            LAYER_FILAS+=("LVM|$linea")
        done < <(pvs --noheadings -o pv_name,vg_name,pv_size,pv_free 2>/dev/null | head -n 6)
    fi

    if [ -r /proc/mdstat ]; then
        local md
        while IFS= read -r md; do
            case "$md" in
                md*|*recovery*|*resync*|*degraded*)
                    LAYER_FILAS+=("RAID|$(echo "$md" | xargs)") ;;
            esac
        done < <(grep -E '^(md|Personalities|.*(recovery|resync|degraded))' /proc/mdstat 2>/dev/null | head -n 8)
        if grep -qiE 'degraded|fail' /proc/mdstat 2>/dev/null; then
            [ "$NIVEL_GLOBAL" -lt 2 ] && NIVEL_GLOBAL=2
        fi
    fi

    if [ "$HAS_BTRFS" = true ]; then
        local montaje estado
        while IFS= read -r montaje; do
            [ -n "$montaje" ] || continue
            estado=$(cmd_timeout 5 btrfs scrub status "$montaje" 2>/dev/null | grep -iE 'status:|finished|running|aborted' | head -n 1 | xargs)
            [ -n "$estado" ] && LAYER_FILAS+=("Btrfs|$montaje: $estado")
        done < <(findmnt -t btrfs -n -o TARGET 2>/dev/null | head -n 4)
    fi

    if [ "$HAS_ZFS" = true ]; then
        local zpool_estado
        zpool_estado=$(cmd_timeout 5 zpool status -x 2>/dev/null | head -n 3 | xargs)
        [ -n "$zpool_estado" ] && LAYER_FILAS+=("ZFS|$zpool_estado")
        echo "$zpool_estado" | grep -qiE 'degraded|faulted|unavailable' && [ "$NIVEL_GLOBAL" -lt 2 ] && NIVEL_GLOBAL=2
    fi

    if [ "$HAS_CRYPTSETUP" = true ]; then
        local mapper
        for mapper in /dev/mapper/*; do
            [ -e "$mapper" ] || continue
            case "$mapper" in *--*) continue ;; esac
            local nombre_map
            nombre_map=$(basename "$mapper")
            cmd_timeout 3 cryptsetup status "$nombre_map" 2>/dev/null | grep -qi 'is active' \
                && LAYER_FILAS+=("LUKS|$nombre_map: activo")
        done
    fi

    if command -v swapon >/dev/null 2>&1; then
        local swap
        swap=$(swapon --show=NAME,TYPE,SIZE,USED --noheadings 2>/dev/null | head -n 4 | tr '\n' ';')
        [ -n "$swap" ] && LAYER_FILAS+=("SWAP|${swap%;}")
    fi
}

# --- Temperatura adicional desde hwmon ---
cargar_temperatura() {
    TEMP_FILAS=()
    local d
    local -A VISTOS=()
    for d in "${DISCOS[@]}"; do
        [ "${DK_TEMP[$d]:-N/D}" = "N/D" ] || continue
        [ "${DK_BUS[$d]:-}" = "NVMe" ] && continue
        local sensor valor
        for sensor in /sys/class/hwmon/hwmon*/temp*_input; do
            [ -r "$sensor" ] || continue
            valor=$(cat "$sensor" 2>/dev/null)
            es_numero "$valor" || continue
            valor=$(( valor / 1000 ))
            [ "$valor" -lt 20 ] && continue
            local nombre_sensor
            nombre_sensor=$(cat "$(dirname "$sensor")/name" 2>/dev/null || echo "hwmon")
            [ -n "${VISTOS[$nombre_sensor]:-}" ] && continue
            VISTOS[$nombre_sensor]=1
            TEMP_FILAS+=("${DK_MODEL[$d]}|${nombre_sensor}: ${valor} °C (sensor del sistema, no específico de disco)")
            break
        done
    done
}

# ==============================================================================
# --- RENDERIZADO DEL DASHBOARD ---
# ==============================================================================
construir_pantalla() {
    actualizar_layout
    stk_header

    local sin_salud=false
    if [ "$HAS_SMART" = false ] && [ "$HAS_NVME" = false ]; then
        sin_salud=true
    fi

    local estado_txt
    case "$NIVEL_GLOBAL" in
        2) estado_txt="${ROJO_BRILLANTE}CRÍTICO${RESET}" ;;
        1) estado_txt="${AMARILLO_BRILLANTE}ATENCIÓN${RESET}" ;;
        *)
            if [ "$sin_salud" = true ]; then
                estado_txt="${AMARILLO_BRILLANTE}DATOS PARCIALES${RESET}"
            else
                estado_txt="${VERDE_BRILLANTE}ÓPTIMO${RESET}"
            fi
            ;;
    esac

    if [ "$COMPACTO" = true ]; then
        local resumen_discos="Discos: ${CONT_DISCOS} (SSD ${CONT_SSD} · HDD ${CONT_HDD} · NVMe ${CONT_NVME})"
        [ "$CONT_CRITICOS" -gt 0 ] && resumen_discos+=" · 🔴${CONT_CRITICOS}"
        [ "$CONT_AVISOS" -gt 0 ] && resumen_discos+=" · ⚠${CONT_AVISOS}"
        echo -e " ${AMARILLO}➤ ${resumen_discos}${RESET}"
    else
        echo -e " ${AMARILLO}➤ Discos:${RESET} ${BLANCO}${CONT_DISCOS}${RESET}  ${VERDE}SSD: ${CONT_SSD}${RESET}  ${AZUL}HDD: ${CONT_HDD}${RESET}  ${CIAN}NVMe: ${CONT_NVME}${RESET}  ${ROJO}críticos: ${CONT_CRITICOS}${RESET}  ${AMARILLO}avisos: ${CONT_AVISOS}${RESET}"
    fi
    echo -e " ${AMARILLO}➤ Estado:${RESET} $estado_txt"
    if [ "$COMPACTO" = false ]; then
        echo -e " ${AMARILLO}➤ Herramientas:${RESET} SMART: $([ "$HAS_SMART" = true ] && echo disponible || echo "${ROJO}no disponible${RESET}") · NVMe: $([ "$HAS_NVME" = true ] && echo disponible || echo "${ROJO}no disponible${RESET}")"
    fi
    if [ "$ES_ROOT" = false ]; then
        if [ "$COMPACTO" = true ]; then
            echo -e "   ${GRIS_CLARO}ℹ Sin root: usa sudo para datos completos.${RESET}"
        else
            echo -e "   ${GRIS_CLARO}ℹ Sin root algunos datos son N/D: usa sudo para el informe completo.${RESET}"
        fi
    fi

    # Interpretación resumida
    local -a avisos=()
    local d id pct ip
    for d in "${DISCOS[@]}"; do
        [ "${DK_LEVEL[$d]:-0}" -ge 1 ] && avisos+=("$(icono_nivel "${DK_LEVEL[$d]}") $d (${DK_KIND[$d]}): ${DK_VERD[$d]}")
    done
    for id in "${FS_FILAS[@]}"; do
        pct="${FS_PCT[$id]:-0}"; pct="${pct%\%}"; es_numero "$pct" || pct=0
        [ "$pct" -ge 90 ] && avisos+=("⚠ ${FS_MOUNT[$id]}: uso al ${pct}%")
        ip="${FS_IPCT[$id]:-0}"; ip="${ip%\%}"; es_numero "$ip" || ip=0
        [ "$ip" -ge 90 ] && avisos+=("⚠ ${FS_MOUNT[$id]}: inodos al ${ip}%")
    done
    local max_aviso=92
    [ "$COMPACTO" = true ] && max_aviso=$(( ANCHO - 22 ))
    [ "$max_aviso" -lt 12 ] && max_aviso=12
    if [ ${#avisos[@]} -gt 0 ]; then
        echo -e " ${MAGENTA}➤ Interpretación:${RESET} $(recortar "${avisos[0]}" "$max_aviso")"
        if [ "$COMPACTO" = false ] && [ ${#avisos[@]} -gt 1 ]; then
            echo -e "   $(recortar "${avisos[1]}" "$max_aviso")"
        fi
    else
        echo -e " ${VERDE_BRILLANTE}➤ Interpretación: sin incidencias destacables${RESET}"
    fi

    # --- Salud ---
    echo -e " ${CIAN}$(separador)${RESET}"
    echo -e " ${NEGRITA}${CIAN}💽 SALUD DE DISPOSITIVOS (solo lectura)${RESET}"
    if [ "$sin_salud" = false ]; then
        local nivel verd extra
        if [ "$COMPACTO" = false ]; then
            printf '  %-12s %-11s %-9s %-8s %-10s %s\n' "DISCO" "TIPO" "ESTADO" "TEMP" "VIDA" "VEREDICTO"
            for d in "${DISCOS[@]}"; do
                nivel=${DK_LEVEL[$d]:-0}
                printf '  %-12s %-11s %b%-9s%b %-8s %-10s %s\n' \
                    "$d" "$(recortar "${DK_KIND[$d]:-?}" 10)" \
                    "$(color_por_nivel "$nivel")" "$(recortar "${DK_HEALTH[$d]:-N/D}" 8)" "$RESET" \
                    "$(recortar "${DK_TEMP[$d]:-N/D}" 7)" "$(recortar "${DK_LIFE[$d]:-N/D}" 9)" \
                    "$(recortar "${DK_VERD[$d]:-}" 40)"
            done
        else
            printf '  %-10s %-9s %-8s %s\n' "DISCO" "TIPO" "ESTADO" "VEREDICTO"
            for d in "${DISCOS[@]}"; do
                nivel=${DK_LEVEL[$d]:-0}
                extra=""
                [ "${DK_TEMP[$d]:-N/D}" != "N/D" ] && extra=" ${DK_TEMP[$d]}"
                [ "${DK_LIFE[$d]:-N/D}" != "N/D" ] && extra+=" vida:${DK_LIFE[$d]}"
                verd="${DK_VERD[$d]:-}$extra"
                printf '  %-10s %-9s %b%-8s%b %s\n' \
                    "$d" "$(recortar "${DK_KIND[$d]:-?}" 8)" \
                    "$(color_por_nivel "$nivel")" "$(recortar "${DK_HEALTH[$d]:-N/D}" 7)" "$RESET" \
                    "$(recortar "$verd" $(( ANCHO - 34 )))"
            done
        fi
    else
        if [ "$COMPACTO" = true ]; then
            echo -e "   ${AMARILLO}ℹ Salud N/D: instala smartmontools/nvme-cli${RESET}"
        else
            echo -e "   ${AMARILLO}ℹ Salud N/D: instala smartmontools / nvme-cli desde Software o ejecuta con sudo.${RESET}"
        fi
        printf '  %-12s %-11s %s\n' "DISCO" "TIPO" "MONTAJE"
        for d in "${DISCOS[@]}"; do
            printf '  %-12s %-11s %s\n' "$d" "$(recortar "${DK_KIND[$d]:-?}" 10)" "${DK_MOUNT[$d]:-—}"
        done
    fi
    [ ${#DISCOS[@]} -eq 0 ] && echo -e "  ${AZUL}No se detectaron discos (lsblk no disponible).${RESET}"

    # --- Capacidad ---
    echo -e " ${CIAN}$(separador)${RESET}"
    echo -e " ${NEGRITA}${CIAN}📁 CAPACIDAD E INODOS${RESET}"
    local barra ip
    if [ "$COMPACTO" = false ]; then
        printf '  %-20s %-8s %9s %9s %9s %-11s %s\n' "MONTAJE" "TIPO" "TAM" "USADO" "LIBRE" "USO" "INODOS"
        for id in "${FS_FILAS[@]:0:10}"; do
            barra=$(porcentaje_barra "${FS_PCT[$id]:-0}")
            ip="${FS_IPCT[$id]:-N/D}"
            [ "$ip" = "-" ] && ip="N/D"
            printf '  %-20s %-8s %9s %9s %9s %-11s %s\n' \
                "$(recortar "${FS_MOUNT[$id]:-?}" 19)" "$(recortar "${FS_TYPE[$id]:-?}" 7)" \
                "${FS_SIZE[$id]:-—}" "${FS_USED[$id]:-—}" "${FS_AVAIL[$id]:-—}" "$barra" "$ip"
        done
    else
        printf '  %-16s %7s %-9s %s\n' "MONTAJE" "TAM" "USO" "INODOS"
        for id in "${FS_FILAS[@]:0:10}"; do
            barra=$(porcentaje_barra_corta "${FS_PCT[$id]:-0}")
            ip="${FS_IPCT[$id]:-N/D}"
            [ "$ip" = "-" ] && ip="N/D"
            printf '  %-16s %7s %-9s %s\n' \
                "$(recortar "${FS_MOUNT[$id]:-?}" 15)" "${FS_SIZE[$id]:-—}" "$barra" "$ip"
        done
    fi

    # --- Rendimiento (solo si hay datos) ---
    if [ ${#PERF_FILAS[@]} -gt 0 ]; then
        echo -e " ${CIAN}$(separador)${RESET}"
        echo -e " ${NEGRITA}${CIAN}⚡ RENDIMIENTO (muestra de 1 s)${RESET}"
        local fila d2 rl re kb ut
        if [ "$COMPACTO" = false ]; then
            printf '  %-12s %12s %12s %12s %10s\n' "DISCO" "LECT/s" "ESCR/s" "KB/s" "OCUPACIÓN"
            for fila in "${PERF_FILAS[@]}"; do
                IFS='|' read -r d2 rl re kb ut <<< "$fila"
                printf '  %-12s %12s %12s %12s %9s%%\n' "$d2" "$rl" "$re" "$kb" "$ut"
            done
        else
            printf '  %-10s %9s %9s %9s\n' "DISCO" "LECT/s" "ESCR/s" "OCUPACIÓN"
            for fila in "${PERF_FILAS[@]}"; do
                IFS='|' read -r d2 rl re kb ut <<< "$fila"
                printf '  %-10s %9s %9s %8s%%\n' "$d2" "$rl" "$re" "$ut"
            done
        fi
    fi

    # --- Capas (solo si hay datos) ---
    if [ ${#LAYER_FILAS[@]} -gt 0 ]; then
        echo -e " ${CIAN}$(separador)${RESET}"
        echo -e " ${NEGRITA}${CIAN}🧱 CAPAS Y SUBSISTEMAS${RESET}"
        local capa detalle
        if [ "$COMPACTO" = false ]; then
            for fila in "${LAYER_FILAS[@]:0:8}"; do
                IFS='|' read -r capa detalle <<< "$fila"
                printf '  %-10s %s\n' "$capa" "$(recortar "$detalle" 78)"
            done
        else
            local resumen=""
            for fila in "${LAYER_FILAS[@]:0:6}"; do
                IFS='|' read -r capa detalle <<< "$fila"
                resumen+="${resumen:+, }$capa: $(recortar "$detalle" 24)"
            done
            echo "  $(recortar "$resumen" $(( ANCHO - 4 )))"
        fi
    fi

    # --- Temperatura (solo si hay datos) ---
    if [ ${#TEMP_FILAS[@]} -gt 0 ]; then
        echo -e " ${CIAN}$(separador)${RESET}"
        echo -e " ${NEGRITA}${CIAN}🌡 TEMPERATURA ADICIONAL${RESET}"
        for fila in "${TEMP_FILAS[@]:0:4}"; do
            echo "  $(recortar "$fila" $(( ANCHO - 4 )))"
        done
    fi

    echo -e " ${CIAN}$(separador)${RESET}"
    if [ "$ANCHO" -lt 70 ]; then
        echo -e " ${VERDE_BRILLANTE}[f]${RESET} explorar  ${VERDE_BRILLANTE}[d]${RESET} espacio  ${VERDE_BRILLANTE}[r]${RESET} refrescar"
        echo -e " ${VERDE_BRILLANTE}[i]${RESET} informe  ${ROJO_BRILLANTE}[q]${RESET} salir"
    elif [ "$COMPACTO" = true ]; then
        echo -e " ${VERDE_BRILLANTE}[f]${RESET} explorar  ${VERDE_BRILLANTE}[d]${RESET} espacio  ${VERDE_BRILLANTE}[r]${RESET} refrescar  ${VERDE_BRILLANTE}[i]${RESET} informe  ${ROJO_BRILLANTE}[q]${RESET} salir"
    else
        echo -e " ${VERDE_BRILLANTE}[f]${RESET} explorar disco   ${VERDE_BRILLANTE}[d]${RESET} espacio por directorios   ${VERDE_BRILLANTE}[r]${RESET} refrescar   ${VERDE_BRILLANTE}[i]${RESET} informe   ${ROJO_BRILLANTE}[q]${RESET} salir"
    fi
}

# Redibujo sin parpadeo (misma técnica que dash4me / jobs4me)
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
detalle_dispositivo() {
    local d="${1:-}"
    [ -n "$d" ] || return 1
    local dev="/dev/$d"
    local nivel=${DK_LEVEL[$d]:-0}

    echo -e "${AZUL_BRILLANTE}$d${RESET}  $(icono_nivel "$nivel")  ${DK_KIND[$d]:-N/D}"
    printf '├── %-15s %s\n' "Modelo" "${DK_MODEL[$d]:-N/D}"
    printf '├── %-15s %s\n' "Serial" "${DK_SERIAL[$d]:-N/D}"
    printf '├── %-15s %s\n' "Firmware" "${DK_FIRMWARE[$d]:-N/D}"
    printf '├── %-15s %s · %s · rotación=%s\n' "Bus / tamaño" "${DK_BUS[$d]:-N/D}" "${DK_SIZE[$d]:-N/D}" "${DK_ROTA[$d]:-N/D}"
    printf '├── %-15s %s (%s)\n' "Montaje" "${DK_MOUNT[$d]:-—}" "${DK_FSTYPE[$d]:-—}"
    printf '├── %-15s %s\n' "Salud" "${DK_HEALTH[$d]:-N/D}"
    printf '├── %-15s %s\n' "Temperatura" "${DK_TEMP[$d]:-N/D}"
    printf '├── %-15s %s\n' "Horas de uso" "${DK_HOURS[$d]:-N/D}"
    printf '├── %-15s %s\n' "Reasignados" "${DK_REALLOC[$d]:-N/D}"
    printf '├── %-15s %s\n' "Pendientes" "${DK_PENDING[$d]:-N/D}"
    printf '├── %-15s %s\n' "Incorrrectables" "${DK_UNCORR[$d]:-N/D}"
    printf '├── %-15s %s\n' "Vida restante" "${DK_LIFE[$d]:-N/D}"
    printf '├── %-15s %s\n' "Log de errores" "${DK_ERRLOG[$d]:-N/D}"
    printf '├── %-15s %s\n' "Autotest" "${DK_SELFTEST[$d]:-N/D}"
    printf '└── %-15s %b%s%b · %s\n' "Veredicto" "$(color_por_nivel "$nivel")" "${DK_VERD[$d]:-Sin datos}" "$RESET" "$dev"

    if [ "${DK_DETAIL[$d]:-}" = "" ] && [ "$HAS_SMART" = true ]; then
        echo ""
        echo -e "  ${GRIS_CLARO}Detalle SMART (consulta directa, solo lectura):${RESET}"
        cmd_timeout 4 smartctl -i -H -A "$dev" 2>/dev/null | sed 's/^/    /' | head -n 30
    fi
}

explorar_discos() {
    [ "$HAS_FZF" = true ] || { alerta "fzf no está instalado; se muestra el primer disco."; [ ${#DISCOS[@]} -gt 0 ] && detalle_dispositivo "${DISCOS[0]}"; pausa; return 0; }

    local lista="" d
    for d in "${DISCOS[@]}"; do
        lista+="$d  $(icono_nivel "${DK_LEVEL[$d]:-0}")  $(recortar "${DK_KIND[$d]:-}" 11)  $(recortar "${DK_MODEL[$d]:-}" 24)  ${DK_VERD[$d]:-}\n"
    done
    [ -z "$lista" ] && { alerta "No hay discos que explorar."; pausa; return 0; }

    # Con un solo disco FZF no aporta nada (una única línea que además ya se
    # está previsualizando): se muestra el detalle directamente.
    if [ ${#DISCOS[@]} -eq 1 ]; then
        stk_limpiar
        stk_header
        detalle_dispositivo "${DISCOS[0]}"
        pausa
        return 0
    fi

    local preview_cmd header_cmd header
    printf -v preview_cmd 'bash %q --detalle {1}' "$SELF_PATH"
    header_cmd=$(stk_header_cmd "$SELF_PATH")
    header=$(stk_header)   # cabecera inicial: bg-transform-header la refresca después

    printf '%b' "$lista" | stk_fzf_ejecutar "Disco" "$header" "ANÁLISIS DE DISCOS" \
        --ansi \
        --height=~90% \
        --layout=reverse \
        --no-sort \
        --header-first \
        --border=rounded \
        --border-label=" ANÁLISIS DE DISCOS " \
        --prompt="➤ Disco: " \
        --header="$header" \
        --preview="$preview_cmd" \
        --preview-window="right:62%:wrap" \
        --bind="every(5):bg-transform-header:$header_cmd" \
        --color="border:#ff5555,pointer:#92ff92,header:#5fb2ff,label:#5fb2ff,marker:#92ff92"
}

# --- Espacio por directorios, bajo demanda ---
analizar_espacio() {
    actualizar_layout
    stk_limpiar
    stk_header
    echo -e " ${MAGENTA}--- TOP DE ESPACIO POR DIRECTORIOS (bajo demanda) ---${RESET}"
    echo -e " ${GRIS_CLARO}Rutas seguras, sin cruzar montajes. '/' no se analiza por defecto.${RESET}"

    local -a rutas=()
    local r
    for r in /home /var /tmp /root /opt /srv; do
        [ -d "$r" ] && [ -r "$r" ] && rutas+=("$r")
    done
    if [ ${#rutas[@]} -eq 0 ]; then
        alerta "No hay directorios accesibles para analizar."
        pausa
        return 0
    fi

    # Sin timeout no se lanza ningún recorrido: era la causa del cuelgue.
    if ! command -v timeout >/dev/null 2>&1; then
        echo -e "\n ${AMARILLO}⚠ 'timeout' no disponible: se omiten los recorridos para no colgarse.${RESET}"
        echo -e "   ${GRIS_CLARO}Usa 'df -h' o instala coreutils para esta opción.${RESET}"
        pausa
        return 0
    fi

    echo -e "\n ${AZUL}Analizando ${#rutas[@]} ruta(s)... (Ctrl+C para cancelar)${RESET}"
    local inicio=$SECONDS raiz lineas

    for raiz in "${rutas[@]}"; do
        echo -e "\n ${AZUL_BRILLANTE}➤ $raiz${RESET}"
        lineas=$(timeout -k 2 15 du -x -h --max-depth=1 --exclude=/var/lib/snapd "$raiz" 2>/dev/null | sort -hr | head -n 10)
        [ -z "$lineas" ] && lineas=$(timeout -k 2 15 du -x -h -d 1 "$raiz" 2>/dev/null | sort -hr | head -n 10)
        if [ -n "$lineas" ]; then
            echo "$lineas" | sed 's/^/   /'
        else
            echo -e "   ${GRIS_CLARO}N/D (sin permisos o tiempo agotado)${RESET}"
        fi
    done

    echo -e "\n ${AZUL_BRILLANTE}➤ Archivos grandes (>200 MB)${RESET}"
    lineas=$(timeout -k 2 25 find "${rutas[@]}" -xdev -type f -size +200M -printf '%s|%p\n' 2>/dev/null \
        | sort -t'|' -k1,1rn | head -n 10)
    if [ -n "$lineas" ]; then
        local bytes ruta
        while IFS='|' read -r bytes ruta; do
            printf '   %8s  %s\n' "$(formato_mb "$bytes")" "$(recortar "$ruta" $(( ANCHO - 18 )))"
        done <<< "$lineas"
    else
        # BusyBox find no tiene -printf: fallback acotado también con timeout.
        lineas=$(timeout -k 2 25 find "${rutas[@]}" -xdev -type f -size +200M -exec du -h {} + 2>/dev/null | sort -hr | head -n 10)
        [ -n "$lineas" ] && echo "$lineas" | sed 's/^/   /' || echo "   Ninguno o sin permisos"
    fi

    echo -e "\n ${VERDE}✔ Completado en $(( SECONDS - inicio )) s${RESET}"
    pausa
}

# --- Informe en texto plano ---
generar_informe() {
    local dir="$INFORME_DIR"
    mkdir -p "$dir" 2>/dev/null || dir="${TMPDIR:-/tmp}"
    local archivo="$dir/hard4me_$(date +%Y%m%d_%H%M%S).txt"
    local d fila id

    {
        echo "HARD4ME v$V - Informe de análisis $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Sistema: $STK_OS | Kernel: $STK_KERNEL | Host: $STK_HOST"
        echo "Usuario: $STK_USER | root: $ES_ROOT"
        echo "============================================================"
        echo "ESTADO GLOBAL: $(case "$NIVEL_GLOBAL" in 2) echo CRITICO;; 1) echo ATENCION;; *) echo OPTIMO;; esac)"
        echo "Discos: $CONT_DISCOS (SSD: $CONT_SSD, HDD: $CONT_HDD, NVMe: $CONT_NVME)"
        echo "Críticos: $CONT_CRITICOS | Avisos: $CONT_AVISOS"
        echo "============================================================"
        echo "DISPOSITIVOS"
        for d in "${DISCOS[@]}"; do
            printf '%-12s %-11s %-12s %-9s %-10s %s\n' \
                "$d" "${DK_KIND[$d]:-?}" "${DK_HEALTH[$d]:-N/D}" \
                "${DK_TEMP[$d]:-N/D}" "${DK_LIFE[$d]:-N/D}" "${DK_VERD[$d]:-}"
            printf '   modelo=%s | serial=%s | firmware=%s | bus=%s | montaje=%s\n' \
                "${DK_MODEL[$d]:-N/D}" "${DK_SERIAL[$d]:-N/D}" "${DK_FIRMWARE[$d]:-N/D}" \
                "${DK_BUS[$d]:-N/D}" "${DK_MOUNT[$d]:-N/D}"
            printf '   horas=%s | reasignados=%s | pendientes=%s | inconrrectables=%s | log=%s | autotest=%s\n' \
                "${DK_HOURS[$d]:-N/D}" "${DK_REALLOC[$d]:-N/D}" "${DK_PENDING[$d]:-N/D}" \
                "${DK_UNCORR[$d]:-N/D}" "${DK_ERRLOG[$d]:-N/D}" "${DK_SELFTEST[$d]:-N/D}"
        done
        echo "============================================================"
        echo "CAPACIDAD E INODOS"
        for id in "${FS_FILAS[@]}"; do
            printf '%-24s %-10s %9s %9s %9s uso=%s inodos=%s\n' \
                "${FS_MOUNT[$id]:-?}" "${FS_TYPE[$id]:-?}" "${FS_SIZE[$id]:-—}" \
                "${FS_USED[$id]:-—}" "${FS_AVAIL[$id]:-—}" "${FS_PCT[$id]:-—}" "${FS_IPCT[$id]:-—}"
        done
        echo "============================================================"
        echo "RENDIMIENTO (1 s)"
        for fila in "${PERF_FILAS[@]}"; do echo "  $fila"; done
        echo "============================================================"
        echo "CAPAS Y SUBSISTEMAS"
        for fila in "${LAYER_FILAS[@]}"; do echo "  $fila"; done
        echo "============================================================"
        echo "Generado por HARD4ME (solo lectura; no se lanzaron tests ni reparaciones)."
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
    echo -e "${CIAN}HARD4ME v${V} - ${DESCRIPCION}${RESET}"
    echo -e "${BLANCO}Autor:${RESET} ${AUTOR}"
    echo ""
    echo -e "${AMARILLO}Uso:${RESET} bash $0 [OPCIÓN]"
    echo ""
    echo -e "  ${VERDE}--detalle DISCO${RESET}   Muestra el análisis en árbol de un disco (p. ej. sda, nvme0n1)."
    echo -e "  ${VERDE}--stk-header${RESET}      Uso interno para la cabecera viva de FZF."
    echo -e "  ${VERDE}--help${RESET}            Muestra esta ayuda."
    echo ""
    echo -e "${AZUL}Dentro del dashboard:${RESET} [f] explorar · [d] espacio · [r] refrescar · [i] informe · [q] salir"
    echo -e "${ROJO_BRILLANTE}No exige root. Solo lectura: no lanza tests, scrubs ni reparaciones.${RESET}"
}

# ==============================================================================
# --- PUNTO DE ENTRADA ---
# ==============================================================================
cargar_todo() {
    cargar_dispositivos
    cargar_capacidad
    cargar_rendimiento
    cargar_capas
    cargar_temperatura
}

main() {
    detectar_sistema

    if [ "$HARD4ME_SOLO" = true ]; then
        case "${1:-}" in
            --stk-header|--logo-header) stk_header; exit 0 ;;
            --detalle)
                if [ -n "${2:-}" ]; then
                    cargar_dispositivos
                    detalle_dispositivo "$2"
                fi
                exit 0
                ;;
            --help|-h) mostrar_ayuda; exit 0 ;;
        esac
    fi

    # Ofrecer dependencias solo en modo interactivo (nunca en preview/cron).
    if [ -t 0 ] && [ -t 1 ]; then
        ofrecer_instalar smartctl smartmontools "health de discos ATA/SAS"
        ofrecer_instalar nvme nvme-cli "health de discos NVMe"
    fi

    # Sin TTY (redirección, cron, preview): una sola captura y salir
    if [ ! -t 0 ] || [ ! -t 1 ] || [ -z "${TERM:-}" ] || [ "$TERM" = "dumb" ]; then
        cargar_todo
        renderizar_pantalla
        exit 0
    fi

    # Pantalla alternativa sin terminfo (secuencias ANSI de stk_header.sh).
    stk_alt_screen_on
    stk_cursor_off
    trap 'stk_alt_screen_off; stk_cursor_on; exit 0' SIGINT SIGTERM

    local tecla=""
    while true; do
        cargar_todo
        renderizar_pantalla

        tecla=""
        read -r -n 1 -s -t 3 tecla || tecla=""
        case "$tecla" in
            f|F)
                stk_alt_screen_off; stk_cursor_on
                explorar_discos
                stk_alt_screen_on; stk_cursor_off
                ;;
            d|D)
                stk_alt_screen_off; stk_cursor_on
                analizar_espacio
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
    pintar "$VERDE" "Análisis completado. No se ha modificado ningún disco."
    stk_salir "HARD4ME" "Saliendo de HARD4ME..."
}

main "$@"
