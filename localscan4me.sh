#!/usr/bin/env bash

# ==============================================================================
# LOCALSCAN4ME - Dashboard de redes locales (auditoría interna)
# ==============================================================================
# Inventario de todas las redes locales, exposición de puertos/servicios,
# higiene de configuración y revisión TLS. Perspectiva de auditor interno:
# solo lectura, sin explotación. Solo en redes propias o autorizadas.
# Se ejecuta solo (bash localscan4me.sh) o desde STK.
# ==============================================================================

V="1.1"
DESCRIPCION="Dashboard de redes locales: inventario, puertos expuestos y revisión TLS"
AUTOR="DanSanMar"

set -Eeuo pipefail
IFS=$'\n\t'
umask 077

# --- BIBLIOTECA DE CABECERAS STK (paleta, menús FZF y salida) ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF_PATH="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"
STK_HEADER="$SCRIPT_DIR/stk_header.sh"
if [ ! -f "$STK_HEADER" ]; then
    STK_HEADER=$(find /home /root /usr/local -maxdepth 5 -name "stk_header.sh" 2>/dev/null | head -n 1)
fi
if [ -f "$STK_HEADER" ]; then
    # shellcheck source=stk_header.sh
    source "$STK_HEADER"
else
    echo "❌ No se encuentra $STK_HEADER. LOCALSCAN4ME no puede iniciarse." >&2
    exit 1
fi

stk_init "LOCALSCAN4ME" "$V" "LOCAL NETWORK DASHBOARD"

# Uso interno: FZF pide la cabecera en caliente con bg-transform-header.
if [[ "${BASH_SOURCE[0]}" == "$0" ]] && [ "${1:-}" = "--stk-header" ]; then
    stk_header
    exit 0
fi

# --- LOG CENTRALIZADO ---
LOG_FILE="/var/log/stk_mantenimiento.log"
LOG_INFO="INFO"
LOG_WARN="WARN"
LOG_ERR="ERROR"

registrar_log() {
    local NIVEL="${1:-INFO}" MENSAJE="${2:-}" FECHA
    [ -w "$LOG_FILE" ] || return 0
    FECHA=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$FECHA] [$NIVEL] [${SUDO_USER:-${USER:-$(id -un 2>/dev/null)}}] - [LOCALSCAN4ME] $MENSAJE" >> "$LOG_FILE" 2>/dev/null || true
}

if [ ! -f "$LOG_FILE" ]; then
    umask 027
    touch "$LOG_FILE" 2>/dev/null || true
    chmod 640 "$LOG_FILE" 2>/dev/null || true
fi

# --- DETECCIÓN DEL GESTOR DE PAQUETES (dependencias bajo pregunta) ---
Package=""
OS_ID="unknown"
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID="${ID:-unknown}"
fi

case "$OS_ID" in
    debian|ubuntu|linuxmint|pop|kali|raspbian) Package="apt" ;;
    fedora|rhel|centos|rocky|almalinux)        Package="dnf" ;;
    arch|manjaro|endeavouros|garuda)           Package="pacman" ;;
    opensuse*|suse)                            Package="zypper" ;;
    *)
        if command -v apt &>/dev/null;    then Package="apt"
        elif command -v dnf &>/dev/null;  then Package="dnf"
        elif command -v pacman &>/dev/null; then Package="pacman"
        elif command -v zypper &>/dev/null; then Package="zypper"
        else Package="unknown"; fi
        ;;
esac

INMUTABLE=false
if [ -f /run/ostree-booted ] && command -v rpm-ostree &>/dev/null; then
    INMUTABLE=true
    [ "$Package" = "unknown" ] && Package="dnf"
fi

# --- USUARIO Y RUTAS ---
REAL_USER=$(logname 2>/dev/null || echo "${SUDO_USER:-$USER}")
GRUPO_REAL=$(id -gn "$REAL_USER" 2>/dev/null || echo "$REAL_USER")

if command -v xdg-user-dir >/dev/null 2>&1; then
    DESKTOP_PATH=$(sudo -u "$REAL_USER" xdg-user-dir DESKTOP 2>/dev/null || true)
fi
[ -z "${DESKTOP_PATH:-}" ] && DESKTOP_PATH="/home/$REAL_USER/Desktop"
[ ! -d "$DESKTOP_PATH" ] && DESKTOP_PATH="/home/$REAL_USER/Escritorio"

# --- TEMPORALES ---
WORKDIR=$(mktemp -d /tmp/localscan4me_XXXXXX)
chmod 700 "$WORKDIR"
HOSTS_FILE="$WORKDIR/hosts_cache.txt"
RESULTS_DIR="$WORKDIR/results"
mkdir -p "$RESULTS_DIR"
: > "$HOSTS_FILE"

cleanup() { [ -d "$WORKDIR" ] && rm -rf "$WORKDIR"; }
trap cleanup EXIT

# --- ESTADO ---
REDES_DISPONIBLES=()   # "iface|CIDR"
REDES_ELEGIDAS=()      # "iface|CIDR"
TARGET_IP=""
TARGET_RED=""
MODO=0
MODO_DIRECTO=false     # true = auditar un host sin inventariar la red
REPORTE_ACTUAL=""

# ---------- UTILIDADES ----------
unir() { local IFS=' '; printf '%s' "$*"; }
seccion()  { echo ""; pintar "$MAGENTA" "── $1 ──"; }
aviso()    { pintar "$AMARILLO_BRILLANTE" "  ⚠️  $1"; }
ok()       { pintar "$VERDE_BRILLANTE" "  ✔ $1"; }
pausa()    { echo ""; read -r -p "  Presione Enter para continuar..." _ || true; }

# --- VALIDACIÓN Y CÁLCULO DE REDES ---
validar_cidr() {
    local cidr="$1" ip pref o
    [[ "$cidr" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}/[0-9]{1,2}$ ]] || return 1
    ip="${cidr%/*}"
    pref="${cidr#*/}"
    (( 10#$pref >= 0 && 10#$pref <= 32 )) || return 1
    local IFS='.'
    for o in $ip; do
        (( 10#$o >= 0 && 10#$o <= 255 )) || return 1
    done
    return 0
}

ip_a_int() {
    local IFS=. a b c d
    [[ "${1:-}" =~ ^([0-9]{1,3}\.){3}[0-9]{1,3}$ ]] || return 1
    read -r a b c d <<< "$1" || return 1
    printf '%s' "$(( (10#$a << 24) + (10#$b << 16) + (10#$c << 8) + 10#$d ))"
}

# ¿La red $1 (CIDR) contiene a la red/host $2 (CIDR)?
cidr_contiene() {
    local base="$1" sub="$2" bip bpref sip spref bint sint mask
    bip="${base%/*}"; bpref="${base#*/}"
    sip="${sub%/*}";  spref="${sub#*/}"
    [[ "$bpref" =~ ^[0-9]+$ && "$spref" =~ ^[0-9]+$ ]] || return 1
    [ "$spref" -lt "$bpref" ] && return 1
    bint=$(ip_a_int "$bip") || return 1
    sint=$(ip_a_int "$sip") || return 1
    mask=$(( (0xFFFFFFFF << (32 - bpref)) & 0xFFFFFFFF ))
    [ $(( bint & mask )) -eq $(( sint & mask )) ]
}

# Número aproximado de direcciones de un CIDR (para avisar de barridos largos).
cidr_hosts() {
    local pref="${1##*/}"
    [[ "$pref" =~ ^[0-9]+$ ]] || { echo 0; return; }
    [ "$pref" -ge 31 ] && { echo 1; return; }
    echo $(( 2 ** (32 - pref) ))
}

es_iface_virtual() {
    case "${1:-}" in
        docker*|br-*|virbr*|veth*|vmnet*|vboxnet*|tailscale*|tun*|tap*|wg*|zt*|podman*|cni*|flannel*|lxcbr*|lxdbr*) return 0 ;;
        *) return 1 ;;
    esac
}

iface_para_cidr() {
    local cidr="$1" e ifc icidr
    for e in "${REDES_DISPONIBLES[@]}"; do
        ifc="${e%%|*}"; icidr="${e#*|}"
        if cidr_contiene "$icidr" "$cidr" || cidr_contiene "$cidr" "$icidr"; then
            echo "$ifc"
            return 0
        fi
    done
    ifc=$(ip route get "${cidr%/*}" 2>/dev/null | awk '/dev/ {print $5; exit}') || ifc=""
    if [ -z "$ifc" ]; then
        ifc=$(ip route show default 2>/dev/null | awk '/default/ {print $5; exit}') || ifc=""
    fi
    echo "${ifc:-eth0}"
}

# nmap con reintento sin privilegios: -sS necesita CAP_NET_RAW; si falla, -sT.
# NMAP_MOSTRAR_ERR=true deja pasar stderr (progreso de --stats-every).
nmap_ejecutar() {
    local errf="$WORKDIR/nmap.err" rc=0
    local mostrar="${NMAP_MOSTRAR_ERR:-false}"
    local -a alt=()
    local a tiene_ss=false
    for a in "$@"; do
        [ "$a" = "-sS" ] && { tiene_ss=true; a="-sT"; }
        alt+=("$a")
    done

    if [ "$mostrar" = true ]; then
        nmap "$@" || rc=$?
    else
        : > "$errf"
        nmap "$@" 2>"$errf" || rc=$?
    fi

    if [ "$rc" -ne 0 ] && [ "$tiene_ss" = true ]; then
        rc=0
        if [ "$mostrar" = true ]; then
            nmap "${alt[@]}" || rc=$?
        else
            nmap "${alt[@]}" 2>>"$errf" || rc=$?
        fi
    fi

    if [ "$rc" -ne 0 ] && [ "$mostrar" != true ]; then
        sed 's/^/  [nmap] /' "$errf" >&2 || true
    fi
    return "$rc"
}

nombre_modo() {
    case "${1:-0}" in
        1) echo "Inventario e identificación" ;;
        2) echo "Exposición de servicios" ;;
        3) echo "Higiene de configuración" ;;
        4) echo "Revisión TLS/cifrado" ;;
        5) echo "Barrido de red" ;;
        *) echo "—" ;;
    esac
}

actualizar_extra() {
    local redes_txt="N/D" pkg_mostrar="${Package:-N/A}" e
    local -a cidrs=()
    for e in "${REDES_ELEGIDAS[@]}"; do cidrs+=("${e#*|}"); done
    if [ ${#cidrs[@]} -gt 2 ]; then
        redes_txt="${#cidrs[@]} redes seleccionadas"
    elif [ ${#cidrs[@]} -gt 0 ]; then
        redes_txt=$(unir "${cidrs[@]}")
    fi
    [ "$INMUTABLE" = true ] && pkg_mostrar="rpm-ostree"
    if [ "$MODO_DIRECTO" = true ] && [ -n "$TARGET_IP" ]; then
        redes_txt="host $TARGET_IP"
    fi
    STK_EXTRA="${VERDE}Modo:${RESET} ${AZUL}Auditoría interna${RESET} | ${CIAN}Objetivo:${RESET} ${BLANCO}${redes_txt}${RESET} | ${CIAN}Pkg:${RESET} ${AZUL}${pkg_mostrar}${RESET}"
}

# Logo compartido: se usa como header de FZF (con refresco vivo) y, en modo
# textual (sin fzf), se imprime una sola vez por menú en la salida de error.
logo_texto() {
    actualizar_extra
    stk_header
}

MENU_TEXTO=""
header_refresco() {
    local logo
    logo=$(logo_texto)
    printf '%s\n%s\n%s' "$logo" \
        "${AMARILLO}   Uso exclusivo en redes propias o autorizadas. Solo lectura.${RESET}" \
        "$MENU_TEXTO"
}

salir() {
    registrar_log "$LOG_INFO" "Sesión finalizada - localscan4me v$V"
    stk_salir "LOCALSCAN4ME" "Saliendo de LocalScan4Me..."
    exit 0
}
trap salir INT TERM

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${ROJO_BRILLANTE}⚠️ Error: este script requiere privilegios de root.${RESET}"
        echo -e "${AMARILLO}Prueba con: sudo $0${RESET}"
        exit 1
    fi
}

instalar_fzf_binario() {
    local archivo_arch tmp_dir url
    case "$(uname -m)" in
        x86_64) archivo_arch="linux_amd64" ;;
        aarch64|arm64) archivo_arch="linux_arm64" ;;
        *) return 1 ;;
    esac
    command -v curl >/dev/null 2>&1 || return 1
    url=$(curl -fsSL "https://api.github.com/repos/junegunn/fzf/releases/latest" 2>/dev/null \
        | grep "browser_download_url" | grep -i "${archivo_arch}.tar.gz" | head -n 1 \
        | cut -d '"' -f 4) || true
    [ -z "$url" ] && return 1
    tmp_dir=$(mktemp -d) || return 1
    if curl -fsSL "$url" -o "$tmp_dir/fzf.tar.gz" 2>/dev/null \
        && tar -xzf "$tmp_dir/fzf.tar.gz" -C "$tmp_dir" fzf 2>/dev/null; then
        install -m 0755 "$tmp_dir/fzf" /usr/local/bin/fzf
        rm -rf "$tmp_dir"
        return 0
    fi
    rm -rf "$tmp_dir"
    return 1
}

instalar_dependencias() {
    local paquetes=("$@") capa=() p
    registrar_log "$LOG_INFO" "Instalación de dependencias solicitada: $(unir "${paquetes[@]}")"

    if [ "$INMUTABLE" = true ]; then
        if command -v rpm-ostree >/dev/null 2>&1; then
            rpm-ostree refresh-md >/dev/null 2>&1 || true
            for p in "${paquetes[@]}"; do
                [ "$p" = "fzf" ] || capa+=("$p")
            done
            if [ ${#capa[@]} -gt 0 ]; then
                if rpm-ostree install --idempotent --allow-inactive --apply-live "${capa[@]}"; then
                    registrar_log "$LOG_INFO" "Dependencias aplicadas en vivo: $(unir "${capa[@]}")"
                elif rpm-ostree install --idempotent --allow-inactive "${capa[@]}"; then
                    aviso "Los paquetes quedaron preparados: reinicia para usarlos."
                    registrar_log "$LOG_INFO" "Dependencias preparadas (reinicio pendiente): $(unir "${capa[@]}")"
                else
                    registrar_log "$LOG_ERR" "Fallo al instalar dependencias: $(unir "${capa[@]}")"
                fi
            fi
        fi
        if ! command -v fzf >/dev/null 2>&1; then
            instalar_fzf_binario || registrar_log "$LOG_ERR" "No se pudo instalar el binario estático de fzf"
        fi
        hash -r 2>/dev/null || true
        return 0
    fi

    echo -e "${AZUL}🔄 Actualizando repositorios ($Package)...${RESET}"
    case "$Package" in
        apt)    apt update -y -qq || true; apt install -y "${paquetes[@]}" ;;
        dnf)    dnf install -y "${paquetes[@]}" ;;
        pacman) pacman -S --needed --noconfirm "${paquetes[@]}" ;;
        zypper) zypper refresh >/dev/null 2>&1 || true; zypper install -y "${paquetes[@]}" ;;
        *)
            echo -e "${ROJO}❌ No se detectó un gestor de paquetes compatible.${RESET}"
            return 1
            ;;
    esac
    hash -r 2>/dev/null || true
}

# Comprueba herramientas y pregunta antes de instalar lo que falte.
# nmap es obligatorio; arp-scan (inventario ARP rápido) y fzf (menús) son
# opcionales: sin ellos se usan el fallback nmap -sn y los menús de texto.
check_tools() {
    local requeridas=(nmap)
    local opcionales=(arp-scan fzf)
    local basicas=(ip awk sed grep mktemp)
    local faltantes=() opc_faltantes=() restantes=() t respuesta=""
    for t in "${requeridas[@]}" "${basicas[@]}"; do
        command -v "$t" >/dev/null 2>&1 || faltantes+=("$t")
    done
    for t in "${opcionales[@]}"; do
        command -v "$t" >/dev/null 2>&1 || opc_faltantes+=("$t")
    done
    if [ ${#faltantes[@]} -eq 0 ] && [ ${#opc_faltantes[@]} -eq 0 ]; then
        return 0
    fi

    seccion "DEPENDENCIAS FALTANTES"
    [ ${#faltantes[@]} -gt 0 ] && echo -e "${AMARILLO}  Obligatorias: ${BLANCO}$(unir "${faltantes[@]}")${RESET}"
    [ ${#opc_faltantes[@]} -gt 0 ] && echo -e "${CIAN}  Recomendadas: ${BLANCO}$(unir "${opc_faltantes[@]}")${RESET}"
    echo -e "${CIAN}  arp-scan acelera el inventario; fzf mejora los menús.${RESET}"
    echo ""
    read -r -p $'  \e[1;33m¿Deseas instalar las dependencias faltantes ahora? (s/n): \e[0m' respuesta || respuesta=""
    if [[ "${respuesta,,}" =~ ^(s|si|y|yes)$ ]]; then
        instalar_dependencias "${faltantes[@]}" "${opc_faltantes[@]}" || true
    else
        registrar_log "$LOG_WARN" "Instalación de dependencias cancelada: $(unir "${faltantes[@]}" "${opc_faltantes[@]}")"
        if [ ${#faltantes[@]} -gt 0 ]; then
            aviso "Sin las dependencias obligatorias no se puede continuar."
            return 1
        fi
    fi

    for t in "${faltantes[@]}"; do
        command -v "$t" >/dev/null 2>&1 || restantes+=("$t")
    done
    if [ ${#restantes[@]} -gt 0 ]; then
        echo -e "${ROJO_BRILLANTE}❌ Siguen faltando: $(unir "${restantes[@]}")${RESET}"
        registrar_log "$LOG_ERR" "Dependencias no disponibles tras el intento: $(unir "${restantes[@]}")"
        return 1
    fi
    local sin_opc=()
    for t in "${opc_faltantes[@]}"; do
        command -v "$t" >/dev/null 2>&1 || sin_opc+=("$t")
    done
    if [ ${#sin_opc[@]} -gt 0 ]; then
        aviso "Se continúa sin: $(unir "${sin_opc[@]}")."
        registrar_log "$LOG_WARN" "Dependencias opcionales ausentes: $(unir "${sin_opc[@]}")"
    else
        ok "Dependencias disponibles."
    fi
    return 0
}

# Menú FZF con el logo de STK como header (y refresco en caliente).
fzf_con_logo() {
    local prompt="$1" titulo="$2" texto="$3"; shift 3
    local header
    local -a extra=()
    MENU_TEXTO="$texto"
    header=$(header_refresco)
    [ "${STK_FZF_FLAG_BORDER_LABEL:-false}" = true ] && extra+=(--border-label=" $titulo ")
    STK_HEADER_REFRESH_CMD=(header_refresco)
    # Sin fzf o sin TTY el menú es textual y no muestra cabecera: se imprime
    # aquí una sola vez (por stderr, fuera del pipe de las opciones).
    if [ "${STK_CAP_TTY:-false}" != true ] || [ "${STK_FZF_DISPONIBLE:-false}" != true ]; then
        printf '%s\n' "$header" >&2
    fi
    stk_fzf_ejecutar "$prompt" "$header" "$titulo" \
        --ansi --reverse --no-sort --border=rounded \
        --prompt="➤ $prompt: " \
        --header="$header" \
        --color="$FZF_COLORES" "${extra[@]}" "$@"
}

# ---------- DESCUBRIR Y ELEGIR REDES ----------
descubrir_redes() {
    REDES_DISPONIBLES=()
    local iface cidr entrada vistos_default="" e
    declare -A visto=() visto_cidr=()

    vistos_default=$(ip route show default 2>/dev/null | awk '/default/ {print $5; exit}') || true

    while IFS=' ' read -r iface cidr; do
        [ -z "$iface" ] && continue
        [[ "$iface" == lo ]] && continue
        [ -z "$cidr" ] && continue
        [[ -n "${visto[$iface]:-}" ]] && continue
        visto[$iface]=1
        REDES_DISPONIBLES+=("$iface|$cidr")
    done <<< "$(ip -o -4 addr show scope global 2>/dev/null | awk '{print $2, $4}')"

    # La interfaz por defecto va primero; luego el resto.
    if [ -n "$vistos_default" ] && [ ${#REDES_DISPONIBLES[@]} -gt 1 ]; then
        local ordenada=()
        for e in "${REDES_DISPONIBLES[@]}"; do
            [ "${e%%|*}" = "$vistos_default" ] && ordenada+=("$e")
        done
        for e in "${REDES_DISPONIBLES[@]}"; do
            [ "${e%%|*}" != "$vistos_default" ] && ordenada+=("$e")
        done
        REDES_DISPONIBLES=("${ordenada[@]}")
    fi

    # Deduplicar por CIDR (una misma subred puede aparecer en dos interfaces).
    local -a final=()
    for e in "${REDES_DISPONIBLES[@]}"; do
        cidr="${e#*|}"
        [[ -n "${visto_cidr[$cidr]:-}" ]] && continue
        visto_cidr[$cidr]=1
        final+=("$e")
    done
    REDES_DISPONIBLES=("${final[@]}")

    if [ ${#REDES_DISPONIBLES[@]} -eq 0 ]; then
        echo -e "${ROJO_BRILLANTE}❌ No se detectaron redes IPv4 activas.${RESET}"
        registrar_log "$LOG_ERR" "No se detectaron redes IPv4 activas"
        exit 1
    fi
    return 0
}

seleccionar_red() {
    local opciones=() entrada iface cidr i=3 elegida num manual host_op salir_op iface_manual
    local -a fisicas=()
    local respuesta="" total_hosts=0 h e
    MODO_DIRECTO=false

    for entrada in "${REDES_DISPONIBLES[@]}"; do
        es_iface_virtual "${entrada%%|*}" || fisicas+=("$entrada")
    done
    [ ${#fisicas[@]} -gt 0 ] || fisicas=("${REDES_DISPONIBLES[@]}")

    actualizar_extra
    echo -e "${AZUL}Seleccione la red a auditar:${RESET}"

    opciones+=("1. Redes físicas detectadas (${#fisicas[@]})")
    opciones+=("2. Todas las redes, incluidas virtuales (${#REDES_DISPONIBLES[@]})")
    for entrada in "${REDES_DISPONIBLES[@]}"; do
        iface="${entrada%%|*}"
        cidr="${entrada#*|}"
        if es_iface_virtual "$iface"; then
            opciones+=("$i. $iface  —  $cidr  [virtual]")
        else
            opciones+=("$i. $iface  —  $cidr")
        fi
        i=$((i + 1))
    done
    manual=$i
    opciones+=("$i. Introducir red manualmente (CIDR)")
    host_op=$((i + 1))
    opciones+=("$host_op. Auditar un host/IP concreto (sin inventario)")
    salir_op=$((i + 2))
    opciones+=("$salir_op. Salir del auditor")

    elegida=$(printf '%s\n' "${opciones[@]}" \
        | fzf_con_logo "Red" "REDES LOCALES DISPONIBLES" \
            "Elige red, 'Todas', CIDR manual o un host concreto" \
            --height=50%) || true
    [[ -z "$elegida" ]] && salir

    num="${elegida%%.*}"
    REDES_ELEGIDAS=()
    case "$num" in
        1) REDES_ELEGIDAS=("${fisicas[@]}") ;;
        2) REDES_ELEGIDAS=("${REDES_DISPONIBLES[@]}") ;;
        "$manual")
            read -r -p "  CIDR (ej. 192.168.10.0/24): " cidr || cidr=""
            if ! validar_cidr "$cidr"; then
                aviso "CIDR no válido. Formato esperado: 192.168.10.0/24 (octetos 0-255, prefijo 0-32)."
                return 1
            fi
            iface_manual=$(iface_para_cidr "$cidr")
            ok "Interfaz asociada: $iface_manual"
            REDES_ELEGIDAS=("$iface_manual|$cidr")
            ;;
        "$host_op")
            read -r -p "  IP del host (ej. 192.168.1.50): " TARGET_IP || TARGET_IP=""
            if ! validar_cidr "$TARGET_IP/32"; then
                aviso "IP no válida. Formato esperado: 192.168.1.50"
                TARGET_IP=""
                return 1
            fi
            MODO_DIRECTO=true
            TARGET_RED="—"
            for e in "${REDES_DISPONIBLES[@]}"; do
                if cidr_contiene "${e#*|}" "$TARGET_IP/32"; then
                    TARGET_RED="$e"
                    REDES_ELEGIDAS=("$e")
                    break
                fi
            done
            ok "Objetivo directo: $TARGET_IP"
            ;;
        "$salir_op") salir ;;
        *)
            [[ "$num" =~ ^[0-9]+$ ]] || return 1
            entrada="${REDES_DISPONIBLES[$((num - 3))]:-}"
            [ -n "$entrada" ] || return 1
            REDES_ELEGIDAS=("$entrada")
            ;;
    esac

    # Aviso y confirmación si el inventario va a cubrir demasiadas direcciones.
    if [ "$MODO_DIRECTO" != true ]; then
        for entrada in "${REDES_ELEGIDAS[@]}"; do
            h=$(cidr_hosts "${entrada#*|}")
            total_hosts=$((total_hosts + h))
        done
    fi
    if [ "$MODO_DIRECTO" != true ] && [ "$total_hosts" -gt 4096 ]; then
        echo ""
        aviso "El inventario cubrirá ~$total_hosts direcciones y puede tardar mucho."
        echo -e "${CIAN}  Sugerencia: elige una red concreta o un CIDR más pequeño.${RESET}"
        read -r -p "  ¿Continuar de todos modos? (s/n): " respuesta || respuesta=""
        case "${respuesta,,}" in
            s|si|y|yes) ;;
            *) return 1 ;;
        esac
    fi

    actualizar_extra
    if [ "$MODO_DIRECTO" = true ]; then
        registrar_log "$LOG_INFO" "Auditoría directa de host: $TARGET_IP"
    else
        registrar_log "$LOG_INFO" "Red(es) seleccionada(s): $(unir "${REDES_ELEGIDAS[@]}")"
    fi
    return 0
}

# ---------- INVENTARIO DE TODAS LAS REDES ELEGIDAS ----------
registrar_host() {
    local ip="$1" mac="${2:-}" vendor="${3:-}" red="$4" nombre="${5:-}"
    [[ "$ip" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || return 0
    [[ -n "${HOSTS_VISTOS[$ip]:-}" ]] && return 0
    HOSTS_VISTOS[$ip]=1
    # El formato interno usa '|' como separador: se neutraliza en los campos.
    mac="${mac//|//}"
    vendor="${vendor//|//}"
    red="${red//|//}"
    nombre="${nombre//|//}"
    printf '%s|%s|%s|%s|%s\n' "$ip" "${mac:-—}" "${vendor:-Desconocido}" "$red" "${nombre:-—}" >> "$HOSTS_FILE"
}

reconocimiento_inicial() {
    declare -gA HOSTS_VISTOS=()
    local entrada iface cidr salida ip mac vendor nombre linea total antes redes_ok=0
    local hosts_red tmo

    # Inventario limpio en cada pasada: evita mezclar hosts de redes anteriores.
    : > "$HOSTS_FILE"

    seccion "INVENTARIO DE RED"
    for entrada in "${REDES_ELEGIDAS[@]}"; do
        iface="${entrada%%|*}"
        cidr="${entrada#*|}"
        antes=$(wc -l < "$HOSTS_FILE" | tr -d ' ')
        hosts_red=$(cidr_hosts "$cidr")
        echo -e "${AZUL}➜${RESET} Reconociendo ${BLANCO}$cidr${RESET} (${iface}) ..."

        salida=""
        # ARP solo tiene sentido en redes L2 con más de una dirección.
        if [ "$hosts_red" -gt 1 ] && command -v arp-scan >/dev/null 2>&1; then
            tmo=$(( hosts_red > 4096 ? 600 : 120 ))
            if command -v timeout >/dev/null 2>&1; then
                salida=$(timeout "$tmo" arp-scan --interface="$iface" --retry=1 "$cidr" 2>/dev/null) || salida=""
            else
                salida=$(arp-scan --interface="$iface" --retry=1 "$cidr" 2>/dev/null) || salida=""
            fi
        fi
        if ! grep -q '^[0-9]' <<< "$salida"; then
            salida=$(nmap_ejecutar -Pn -sn "$cidr" 2>/dev/null) || salida=""
        fi

        # Formato arp-scan: IP  TAB  MAC  TAB  Fabricante
        while IFS=$'\t' read -r ip mac vendor; do
            registrar_host "$ip" "$mac" "$vendor" "$cidr" ""
        done <<< "$(grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' <<< "$salida")"

        # Formato nmap -sn (fallback): report + MAC Address (si existe).
        ip=""; mac=""; vendor=""; nombre=""
        while IFS= read -r linea; do
            if [[ "$linea" == "Nmap scan report for"* ]]; then
                # Host anterior sin MAC (red enrutada, VPN, /32): registrarlo igual.
                [ -n "$ip" ] && registrar_host "$ip" "" "" "$cidr" "$nombre"
                nombre=$(sed -n 's/^Nmap scan report for \([^ ]*\) (\([0-9.]*\)).*/\1/p' <<< "$linea")
                ip=$(sed -n 's/.*(\([0-9.]*\)).*/\1/p' <<< "$linea")
                [ -z "$ip" ] && ip=$(awk '{print $NF}' <<< "$linea")
                [ "$nombre" = "$ip" ] && nombre=""
            elif [[ "$linea" == "MAC Address: "* ]]; then
                mac=$(awk '{print $3}' <<< "$linea")
                vendor=$(sed -n 's/.*(\(.*\)).*/\1/p' <<< "$linea")
                registrar_host "$ip" "$mac" "$vendor" "$cidr" "$nombre"
                ip=""; mac=""; vendor=""; nombre=""
            fi
        done <<< "$(grep -E 'Nmap scan report for|MAC Address:' <<< "$salida")"
        # Último host de la salida si no tenía línea MAC.
        [ -n "$ip" ] && registrar_host "$ip" "" "" "$cidr" "$nombre"

        if [ "$(wc -l < "$HOSTS_FILE" | tr -d ' ')" -gt "$antes" ]; then
            redes_ok=$((redes_ok + 1))
        fi
    done

    if [ ! -s "$HOSTS_FILE" ]; then
        echo -e "${ROJO_BRILLANTE}❌ No se encontraron hosts activos en las redes seleccionadas.${RESET}"
        registrar_log "$LOG_WARN" "Inventario sin hosts en $(unir "${REDES_ELEGIDAS[@]}")"
        return 1
    fi

    total=$(wc -l < "$HOSTS_FILE" | tr -d ' ')
    ok "Dispositivos detectados: $total  |  Redes con hosts: $redes_ok"
    registrar_log "$LOG_INFO" "Inventario completado: $total dispositivos en $(unir "${REDES_ELEGIDAS[@]}")"
    resumen_inventario
    return 0
}

resumen_inventario() {
    local ip mac vendor red nombre cant
    declare -A POR_RED=() POR_VENDOR=()
    echo ""
    echo -e "${CIAN}┌───────────────────────── RESUMEN DEL INVENTARIO ─────────────────────────┐${RESET}"
    while IFS='|' read -r ip mac vendor red nombre; do
        POR_RED[$red]=$(( ${POR_RED[$red]:-0} + 1 ))
        POR_VENDOR[$vendor]=$(( ${POR_VENDOR[$vendor]:-0} + 1 ))
    done < "$HOSTS_FILE"
    for red in "${!POR_RED[@]}"; do
        printf '  %b  %-24s %s hosts\n' "${AZUL}●${RESET}" "$red" "${POR_RED[$red]}"
    done
    echo -e "${CIAN}└──────────────────────────────────────────────────────────────────────────┘${RESET}"
    echo ""
    pintar "$AMARILLO_BRILLANTE" "  Fabricantes más habituales:"
    for vendor in "${!POR_VENDOR[@]}"; do
        cant=${POR_VENDOR[$vendor]}
        [ "$cant" -lt 2 ] && continue
        printf '%s\t%s\n' "$cant" "$vendor"
    done | sort -rn | head -8 | while IFS=$'\t' read -r cant vendor; do
        printf '    %-42s %s\n' "$vendor" "$cant"
    done || true
    pausa
}

# ---------- SELECCIONAR HOST ----------
seleccionar_host() {
    local seleccion ip mac vendor red nombre
    seleccion=$(awk -F'|' '{printf "%s | %s | %s | %s | %s\n", $1, $2, $3, $4, $5}' "$HOSTS_FILE" \
        | fzf_con_logo "Host" "INVENTARIO DE DISPOSITIVOS" \
            "ESC: volver a redes · Busca por IP, MAC o fabricante" \
            --height=50%) || true
    [[ -z "$seleccion" ]] && return 1

    IFS='|' read -r ip mac vendor red nombre <<< "${seleccion// | /|}"
    TARGET_IP="$ip"
    TARGET_RED="$red"
    registrar_log "$LOG_INFO" "Host seleccionado: $TARGET_IP ($vendor) en $TARGET_RED"
    return 0
}

# ---------- PERFILES ----------
seleccionar_modo_scan() {
    local opciones=() elegida
    opciones=(
        "1. Inventario e identificación de dispositivo"
        "2. Exposición de servicios (Top 100 puertos + versiones)"
        "3. Higiene de configuración (puertos + scripts seguros + SO)"
        "4. Revisión TLS/cifrado (cifrados SSL/TLS)"
        "5. Barrido de toda la red (Top 100 + resumen de exposición)"
        "6. Volver al inventario de hosts"
    )
    local ayuda="Solo lectura · 1-4: un host · 5: toda la red"
    [ "$MODO_DIRECTO" = true ] && ayuda="Solo lectura · objetivo: $TARGET_IP"
    elegida=$(printf '%s\n' "${opciones[@]}" \
        | fzf_con_logo "Perfil" "PERFILES DE AUDITORÍA INTERNA" \
            "$ayuda" \
            --height=40%) || true
    [[ -z "$elegida" ]] && return 1

    case "${elegida%%.*}" in
        1|2|3|4) MODO="${elegida%%.*}" ;;
        5) MODO=5 ;;
        *) return 1 ;;
    esac
    registrar_log "$LOG_INFO" "Perfil $MODO seleccionado"
    return 0
}

# ---------- BARRIDO DE RED ----------
barrido_red() {
    local cidr="${TARGET_RED#*|}" salida="$RESULTS_DIR/barrido_red.txt" criticos linea_critica n=0

    if [[ "$cidr" != */* ]] || ! validar_cidr "$cidr"; then
        aviso "El barrido necesita un CIDR de red; el objetivo actual no lo tiene."
        return 1
    fi

    seccion "BARRIDO DE EXPOSICIÓN EN $cidr"
    echo -e "${AMARILLO}  Esto puede tardar varios minutos. Nmap muestra el progreso en vivo.${RESET}"
    echo ""

    local err_previo="${NMAP_MOSTRAR_ERR:-false}"
    NMAP_MOSTRAR_ERR=true
    nmap_ejecutar -Pn -sS -T4 --top-ports 100 --open --stats-every 10s --host-timeout 90s \
        "$cidr" | tee "$salida" || true
    NMAP_MOSTRAR_ERR="$err_previo"

    REPORTE_ACTUAL="$salida"

    echo ""
    pintar "$AZUL_BRILLANTE" "  ── hosts con puertos abiertos ──"
    awk '
        /^Nmap scan report for/ { host=$NF; gsub(/[()]/,"",host) }
        /^[0-9]+\/tcp/ && $2=="open" { printf "  %-16s %-12s %s\n", host, $1, $3 }
    ' "$salida" | sort -u | head -40 || true

    # Se conserva el host junto al puerto: en un barrido de red es lo útil.
    criticos=$(awk '
        /^Nmap scan report for/ { host=$NF; gsub(/[()]/,"",host) }
        /^[0-9]+\/tcp/ && $2=="open" {
            split($1,p,"/")
            if (p[1] ~ /^(21|22|23|445|3389|3306|5432|6379|27017|5900|8080|9200)$/)
                printf "%s  %-10s %s\n", host, $1, $3
        }' "$salida" | sort -u) || criticos=""
    echo ""
    if [ -n "$criticos" ]; then
        pintar "$ROJO_BRILLANTE" "  ⚠️  Servicios a revisar por el auditor (pueden ser legítimos):"
        while IFS= read -r linea_critica; do
            [ -n "$linea_critica" ] || continue
            printf '    %s\n' "$linea_critica"
            n=$((n + 1))
            [ "$n" -ge 20 ] && break
        done <<< "$criticos"
        echo -e "${CIAN}  Recomendación: confirmar necesidad, restringir por firewall/ACL y exigir cifrado.${RESET}"
    else
        ok "No aparecieron servicios sensibles en el Top 100."
    fi
    registrar_log "$LOG_INFO" "Barrido de red finalizado: $cidr"
    return 0
}

# ---------- REVISIÓN DE UN HOST ----------
ejecutar_scan() {
    local out="$RESULTS_DIR/${TARGET_IP}"
    REPORTE_ACTUAL="${out}.txt"

    if [ "$MODO" -eq 5 ]; then
        REPORTE_ACTUAL=""
        barrido_red
        return $?
    fi

    echo ""
    echo -e "${AMARILLO}┌────────────────────────────────────────────────────────┐${RESET}"
    echo -e "${AMARILLO}│${RESET}  ${VERDE_BRILLANTE}🚀 AUDITORÍA EN CURSO${RESET}                                  ${AMARILLO}│${RESET}"
    echo -e "${AMARILLO}│${RESET}  ${AZUL}Objetivo:${RESET} ${BLANCO}$TARGET_IP${RESET}  ${CIAN}Red:${RESET} ${BLANCO}${TARGET_RED#*|}${RESET}        ${AMARILLO}│${RESET}"
    echo -e "${AMARILLO}└────────────────────────────────────────────────────────┘${RESET}"
    echo ""
    registrar_log "$LOG_INFO" "Iniciando perfil $MODO sobre $TARGET_IP"

    case "$MODO" in
        1)
            local datos ip mac vendor red nombre nmap_raw tipo_predicho vendor_lower netbios_name lineas_puertos
            datos=$(grep -F "$TARGET_IP|" "$HOSTS_FILE" | head -n 1) || datos=""
            IFS='|' read -r ip mac vendor red nombre <<< "$datos"
            mac="${mac:-—}"; vendor="${vendor:-—}"; nombre="${nombre:-—}"
            echo -e "${AZUL}[i] Identificación del dispositivo...${RESET}"
            echo -e "${VERDE_BRILLANTE}MAC (ARP):${RESET} $mac    ${VERDE_BRILLANTE}Fabricante:${RESET} $vendor    ${VERDE_BRILLANTE}Nombre:${RESET} $nombre"
            echo "--------------------------------------------------"

            {
                echo "=================================================="
                echo "INVENTARIO DE DISPOSITIVO: $TARGET_IP"
                echo "Red: ${TARGET_RED#*|}"
                echo "MAC (ARP): $mac"
                echo "Fabricante (ARP): $vendor"
                echo "Nombre detectado: $nombre"
                echo "=================================================="
            } > "${out}.txt"

            nmap_raw=$(nmap_ejecutar -Pn -sS -sV -T4 -p 80,135,139,445,443,5353,5357,62078 \
                --script="nbstat,smb-os-discovery" "$TARGET_IP" 2>/dev/null) || true
            echo "$nmap_raw" >> "${out}.txt"

            tipo_predicho="No identificado / Genérico (firewall estricto)"
            vendor_lower=$(echo "$vendor" | tr '[:upper:]' '[:lower:]')

            if [[ "$vendor_lower" == *"amazon"* ]] || [[ "$nmap_raw" == *"Amazon"* ]]; then
                tipo_predicho="Altavoz inteligente / dispositivo Echo"
            elif [[ "$vendor_lower" == *"google"* ]] || [[ "$nmap_raw" == *"Google"* ]] || [[ "$nmap_raw" == *"Chromecast"* ]]; then
                tipo_predicho="Asistente Google Home / Chromecast"
            elif [[ "$vendor_lower" == *"tuya"* ]] || [[ "$vendor_lower" == *"espressif"* ]] \
                || [[ "$vendor_lower" == *"tp-link"* ]] || [[ "$vendor_lower" == *"sonoff"* ]] \
                || [[ "$vendor_lower" == *"xiaomi"* ]] || [[ "$vendor_lower" == *"yeelight"* ]]; then
                tipo_predicho="Dispositivo IoT doméstico (enchufe, bombilla, domótica)"
            elif [[ "$vendor_lower" == *"apple"* ]] && echo "$nmap_raw" | grep -q "62078"; then
                tipo_predicho="Dispositivo Apple (iPhone o iPad)"
            elif [[ "$vendor_lower" == *"huawei"* ]] || [[ "$vendor_lower" == *"samsung"* ]] \
                || [[ "$vendor_lower" == *"oppo"* ]] || [[ "$vendor_lower" == *"xiaomi communications"* ]]; then
                tipo_predicho="Teléfono móvil / smartphone"
            elif echo "$nmap_raw" | grep -iqE "windows|microsoft|workgroup|netbios"; then
                tipo_predicho="Ordenador personal (Windows)"
            elif echo "$nmap_raw" | grep -qE "135/|139/|445/|5357/"; then
                tipo_predicho="Ordenador / servidor con servicios de red activos"
            elif [[ "$vendor_lower" == *"intel"* ]] || [[ "$vendor_lower" == *"asustek"* ]] \
                || [[ "$vendor_lower" == *"gigabyte"* ]] || [[ "$vendor_lower" == *"msi"* ]]; then
                tipo_predicho="Ordenador de sobremesa / portátil"
            fi

            echo -e "${AMARILLO}🔍 RESULTADO DEL INVENTARIO:${RESET}"
            echo "--------------------------------------------------"
            echo -e "${VERDE_BRILLANTE}[+] TIPO DE DISPOSITIVO:${RESET} ${BLANCO}$tipo_predicho${RESET}"
            netbios_name=$(echo "$nmap_raw" \
                | awk '/NetBIOS computer name/ {print $5; exit}' \
                | tr -d ',\r' \
                | sed 's/\\0x[0-9A-Fa-f][0-9A-Fa-f]//g') || true
            if [[ -n "$netbios_name" && "$netbios_name" != "—" ]]; then
                echo -e "${VERDE_BRILLANTE}[+] NOMBRE DEL EQUIPO:${RESET} ${BLANCO}$netbios_name${RESET}"
                echo "Nombre de red detectado: $netbios_name" >> "${out}.txt"
            fi
            echo "--------------------------------------------------"
            echo "Tipo de dispositivo: $tipo_predicho" >> "${out}.txt"

            echo ""
            echo -e "${AZUL}Detalles técnicos:${RESET}"
            echo "$nmap_raw" | grep "Host is up" || true
            lineas_puertos=$(echo "$nmap_raw" | grep -E "^[0-9]+/tcp|^[0-9]+/udp" || true)
            if [[ -n "$lineas_puertos" ]]; then
                echo -e "${BLANCO}PORT      STATE    SERVICE    VERSION${RESET}"
                echo "$lineas_puertos"
            else
                echo -e "${AMARILLO}[!] Puertos tácticos cerrados o filtrados (firewall estricto).${RESET}"
            fi
            echo "$nmap_raw" | grep -E "Host script results:|\|_nbstat:" -A 2 || true
            ;;
        2) : > "${out}.txt"
           nmap_ejecutar -Pn -sS -sV -T4 --top-ports 100 --stats-every 5s --host-timeout 5m "$TARGET_IP" | tee -a "${out}.txt" || true ;;
        3) : > "${out}.txt"
           nmap_ejecutar -Pn -sS -sV -O -T4 --top-ports 100 --script "safe" --stats-every 5s --host-timeout 5m "$TARGET_IP" | tee -a "${out}.txt" || true ;;
        4) : > "${out}.txt"
           nmap_ejecutar -Pn -sS -sV -O -T4 --top-ports 100 --script "safe,ssl-enum-ciphers" --stats-every 5s --host-timeout 10m "$TARGET_IP" | tee -a "${out}.txt" || true ;;
    esac

    registrar_log "$LOG_INFO" "Revisión finalizada para $TARGET_IP (perfil $MODO)"
    return 0
}

# ---------- REPORTE ----------
guardar_reporte() {
    local fecha reporte objetivo etiqueta red_txt destino
    fecha=$(date +"%Y%m%d_%H%M%S")
    if [ "$MODO" -eq 5 ]; then
        objetivo="${TARGET_RED#*|}"
        etiqueta="red_${objetivo//\//_}"
    else
        objetivo="$TARGET_IP"
        etiqueta="host_${objetivo//\//_}"
    fi
    red_txt="${TARGET_RED#*|}"

    destino="$DESKTOP_PATH"
    if [ ! -d "$destino" ]; then
        if mkdir -p "$destino" 2>/dev/null; then
            chown "$REAL_USER:$GRUPO_REAL" "$destino" 2>/dev/null || true
        fi
    fi
    # Si el Escritorio no existe ni es escribible, no perder el informe.
    [ -w "$destino" ] || destino="${HOME:-/root}"
    reporte="$destino/Reporte_${etiqueta}_${fecha}.txt"

    if [[ -f "$REPORTE_ACTUAL" ]]; then
        if ! {
            echo "=================================================="
            echo " AUDITORÍA INTERNA DE RED - LOCALSCAN4ME v$V"
            echo "=================================================="
            echo "Objetivo:   $objetivo"
            echo "Red:        $red_txt"
            echo "Perfil:     $(nombre_modo "$MODO")"
            echo "Fecha:      $(date)"
            echo "Redes:      $(unir "${REDES_ELEGIDAS[@]}")"
            echo "--------------------------------------------------"
            cat "$REPORTE_ACTUAL"
        } > "$reporte" 2>/dev/null; then
            aviso "No se pudo escribir el reporte en $destino"
            registrar_log "$LOG_ERR" "Fallo al escribir reporte: $reporte"
            return 1
        fi
        chown "$REAL_USER:$GRUPO_REAL" "$reporte" 2>/dev/null || true
        echo -e "${VERDE_BRILLANTE}[+] Reporte guardado en:${RESET} $reporte"
        registrar_log "$LOG_INFO" "Reporte exportado: $reporte"
    else
        aviso "No hay resultados de esa revisión para exportar."
        return 1
    fi
}

preguntar_guardar() {
    local respuesta=""
    echo ""
    read -r -p $'  \e[1;33m¿Exportar el resultado a tu Escritorio? (s/n): \e[0m' respuesta || respuesta=""
    case "${respuesta,,}" in
        s|si|y|yes) guardar_reporte ;;
        *) echo -e "${AZUL}Resultado de sesión descartado.${RESET}" ;;
    esac
}

# ---------- BUCLE PRINCIPAL ----------
main() {
    check_root
    if ! check_tools; then
        registrar_log "$LOG_ERR" "Abortado: dependencias no disponibles"
        exit 1
    fi
    # Inicializar una sola vez: los submenús se ejecutan en subshell y heredarán
    # el estado, evitando repetir avisos de compatibilidad en cada menú.
    stk_caps_init
    # fzf antiguo: el wrapper avisaría en cada submenú; ya se informó al iniciar.
    STK_AVISOS_VISTOS[fzf_flags_antiguos]=1
    descubrir_redes

    while true; do
        if ! seleccionar_red; then
            continue
        fi

        # Modo directo: auditar un host sin inventariar la red.
        if [ "$MODO_DIRECTO" = true ]; then
            while true; do
                if ! seleccionar_modo_scan; then
                    break
                fi
                ejecutar_scan || true
                preguntar_guardar || true
                echo ""
                echo -e "${AMARILLO}Presione [ENTER] para volver a los perfiles...${RESET}"
                read -r || true
            done
            MODO_DIRECTO=false
            continue
        fi

        if ! reconocimiento_inicial; then
            continue
        fi
        while true; do
            # ESC en el inventario vuelve a la selección de red.
            if ! seleccionar_host; then
                break
            fi
            # Tras cada auditoría se vuelve al menú de perfiles del mismo host.
            while true; do
                # Opción 6 o ESC vuelven a la lista de hosts (no a la de redes).
                if ! seleccionar_modo_scan; then
                    break
                fi
                ejecutar_scan || true
                preguntar_guardar || true
                echo ""
                echo -e "${AMARILLO}Presione [ENTER] para volver a los perfiles...${RESET}"
                read -r || true
            done
        done
    done
}

registrar_log "$LOG_INFO" "Inicio de sesión - localscan4me v$V"
main "$@"
