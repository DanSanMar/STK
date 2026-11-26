# ==============================================================================
# stk_ui_lib.sh - capa de UI de STK (colores, logo, selector y mensajes)
# Se carga desde stk.sh. No ejecuta nada por sí sola.
# ==============================================================================

# Versión única del ecosistema STK. Cada módulo añade su sufijo al mostrarla.
STK_VERSION="7.0.0"

# Valores por defecto para módulos que no definen la paleta completa.
NEGRITA="${NEGRITA:-\e[1m}"
ROJO="${ROJO:-\e[31m}"
ROJO_BRILLANTE="${ROJO_BRILLANTE:-\e[91m}"
VERDE="${VERDE:-\e[32m}"
VERDE_BRILLANTE="${VERDE_BRILLANTE:-\e[92m}"
AMARILLO="${AMARILLO:-\e[33m}"
AMARILLO_BRILLANTE="${AMARILLO_BRILLANTE:-\e[93m}"
AZUL="${AZUL:-\e[34m}"
AZUL_OSCURO="${AZUL_OSCURO:-\e[0;34m}"
AZUL_BRILLANTE="${AZUL_BRILLANTE:-\e[94m}"
AZUL_CLARO="${AZUL_CLARO:-\e[38;5;117m}"
CIAN="${CIAN:-\e[36m}"
CIAN_BRILLANTE="${CIAN_BRILLANTE:-\e[96m}"
BLANCO="${BLANCO:-\e[97m}"
AUTOR="${AUTOR:-DanSanMar}"
HOST_STK="${HOST_STK:-$(hostname 2>/dev/null || echo N/D)}"
SO_STK="${SO_STK:-$(. /etc/os-release 2>/dev/null; printf '%s' "${PRETTY_NAME:-N/D}")}"
KERNEL_STK="${KERNEL_STK:-$(uname -r 2>/dev/null || echo N/D)}"
IMMUTABLE="${IMMUTABLE:-false}"
FZF_COLORES="${FZF_COLORES:-border:#ff5555,pointer:#92ff92,header:#5fb2ff,label:#5fb2ff,prompt:#5fb2ff,marker:#92ff92}"

PALETA_LOGO=(
    "$ROJO"
    "$AZUL_BRILLANTE"
    "$VERDE_BRILLANTE"
    "$AMARILLO_BRILLANTE"
    "$CIAN_BRILLANTE"
    "$ROJO_BRILLANTE"
    "$AZUL_CLARO"
    "$VERDE"
    "$AMARILLO"
    "$CIAN"
)
LOGO_INTERVALO=3      # Segundos entre cada cambio de color del logo

actualizar_colores_logo() {
    # El color avanza una posición cada LOGO_INTERVALO segundos (epoch / intervalo).
    local epoch total=${#PALETA_LOGO[@]}
    epoch=$(date +%s 2>/dev/null)
    [[ "$epoch" =~ ^[0-9]+$ ]] || epoch=0

    local base=$(( (epoch / LOGO_INTERVALO) % total ))

    COLOR_LOGO="${PALETA_LOGO[$base]}"
    COLOR_DASH="${PALETA_LOGO[$(( (base + 3) % total ))]}"
    COLOR_VER="${PALETA_LOGO[$(( (base + 6) % total ))]}"
}

stk_version_texto() {
    local modulo="${1:-}"
    if [ -n "$modulo" ]; then
        echo -e "${CIAN}STK${RESET} v${BLANCO}${STK_VERSION}${RESET} · ${AZUL_BRILLANTE}${modulo}${RESET}"
    else
        echo -e "${CIAN}STK${RESET} v${BLANCO}${STK_VERSION}${RESET}"
    fi
}

pintar() {
    local COLOR="$1"
    local MENSAJE="$2"
    echo -e "${COLOR}${MENSAJE}${RESET}"
}
# Helpers de UI: unifican mensaje + pausa opcional. El segundo argumento
# es el texto exacto de la pausa; si se omite, no se espera al usuario.
_stk_pausa_interactiva() {
    local aviso="$1"
    local prev_trap
    prev_trap=$(trap -p SIGINT)
    if declare -F salir >/dev/null 2>&1; then
        trap "stk_limpiar; trap salir SIGINT SIGTERM; return" SIGINT
    fi
    read -p "$aviso"
    if [ -n "$prev_trap" ]; then
        eval "$prev_trap"
    elif declare -F salir >/dev/null 2>&1; then
        trap salir SIGINT SIGTERM
    fi
}

stk_mostrar_error() {
    local mensaje="$1" aviso="${2:-}"
    pintar "$ROJO" "$mensaje"
    [ -n "$aviso" ] && _stk_pausa_interactiva "$aviso"
    return 0
}
stk_mostrar_info() {
    local mensaje="$1" aviso="${2:-}"
    pintar "$AMARILLO" "$mensaje"
    [ -n "$aviso" ] && _stk_pausa_interactiva "$aviso"
    return 0
}
stk_mostrar_exito() {
    local mensaje="$1" aviso="${2:-}"
    pintar "$VERDE" "$mensaje"
    [ -n "$aviso" ] && _stk_pausa_interactiva "$aviso"
    return 0
}
# Pausa estándar al volver de un módulo o submenú.
stk_volver_menu() {
    local aviso="${1:-Presione Enter para volver al menú...}"
    echo ""
    _stk_pausa_interactiva "$aviso"
}
logo_barra() {
    actualizar_colores_logo

    local hora
    hora=$(date '+%H:%M:%S')

    echo -e " ${AZUL_BRILLANTE}--- ⚡ ${NEGRITA}${COLOR_LOGO}STK${RESET} ${AZUL_OSCURO}- ${COLOR_DASH}ALL4ME${RESET} ${AZUL_OSCURO}- ${COLOR_VER}v${STK_VERSION}${RESET} ${AZUL_OSCURO}| ${AMARILLO}By:${RESET} ${AZUL}${AUTOR}${RESET} ${BLANCO}:${hora}: ${AZUL_BRILLANTE}⚡---${RESET}"
}
logo_texto() {
    local modo="${1:-completo}"

    logo_barra
    echo -e " ${CIAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

    # En pantallas bajas se recorta la cabecera para no ocultar el menú.
    case "$modo" in
        compacto)
            declare -F dashboard_cacheado >/dev/null 2>&1 && dashboard_cacheado
            return 0
            ;;
        medio)
            echo -e " ${AMARILLO}Host:${RESET} ${AZUL}${HOST_STK}${RESET}  ${AMARILLO}SO:${RESET} ${AZUL}${SO_STK}${RESET}"
            declare -F dashboard_cacheado >/dev/null 2>&1 && dashboard_cacheado
            return 0
            ;;
    esac

    echo -e " ${AMARILLO}Host:${RESET} ${AZUL}${HOST_STK}${RESET}  ${AMARILLO}SO:${RESET} ${AZUL}${SO_STK}${RESET}  ${AMARILLO}Kernel:${RESET} ${AZUL}${KERNEL_STK}${RESET}"
    if [ "$IMMUTABLE" = true ]; then
        echo -e " ${AMARILLO}Entorno:${RESET} ${AZUL}Inmutable · rpm-ostree${RESET}"
    fi
    declare -F dashboard_cacheado >/dev/null 2>&1 && dashboard_cacheado
    return 0
}
mostrar_logo() {
    echo ""
    logo_texto
}
# Compone la cabecera completa de un módulo: logo STK + dashboard + contexto.
stk_modulo_header_compuesto() {
    local modo="${1:-completo}" dato="${2:-}"
    local logo header dash_fn dash
    logo=$(logo_texto "$modo")
    header="$logo"
    if [ -n "${STK_MODULO:-}" ]; then
        dash_fn="stk_dash_${STK_MODULO,,}"
        if declare -F "$dash_fn" >/dev/null 2>&1; then
            dash=$("$dash_fn" 2>/dev/null)
            [ -n "$dash" ] && header="$logo"$'\n'"$dash"
        fi
    fi
    [ -n "$dato" ] && header="$header"$'\n'"  $dato"
    printf '%s' "$header"
}

# Selector único: "simple" (listas), "marco" (menús), "preview" (submenús)
# y "modulo" (recuadro STK + dashboard propio + vista previa).
# Cuarto argumento = script de preview.
# fzf_estilo() y stk_fzf_menu() son wrappers públicos que delegan aquí.
stk_fzf() {
    local estilo="$1" prompt_text="$2" dato="${3:-}" preview="${4:-}"
    local filas modo logo header_text dash_fn dash header
    local fzf_args=()

    case "$estilo" in
        marco)
            filas=$(stty size </dev/tty 2>/dev/null | awk '{print $1}')
            [[ "$filas" =~ ^[0-9]+$ ]] || filas="${LINES:-24}"

            # Cabecera adaptativa: en terminales bajas se recorta para no cortar opciones.
            if [ "$filas" -lt 24 ]; then
                modo="compacto"
            elif [ "$filas" -lt 32 ]; then
                modo="medio"
            else
                modo="completo"
            fi

            logo=$(logo_texto "$modo")

            fzf_args=(
                --ansi
                --height=~90%
                --layout=reverse
                --no-sort
                --header-first
                --border=rounded
                --border-label=" $dato "
                --prompt="➤ $prompt_text: "
                --header="$logo"
                --color="$FZF_COLORES"
            )

            # El ticker usa este comando para regenerar el logo en caliente.
            STK_HEADER_REFRESH_CMD=(logo_texto "$modo")
            stk_fzf_ejecutar "$prompt_text" "$logo" "$dato" "${fzf_args[@]}"
            ;;
        modulo)
            # Estilo común para módulos: mismo marco rojo y cabecera STK, con
            # un dashboard propio opcional (stk_dash_<modulo> en minúsculas).
            filas=$(stty size </dev/tty 2>/dev/null | awk '{print $1}')
            [[ "$filas" =~ ^[0-9]+$ ]] || filas="${LINES:-24}"

            if [ "$filas" -lt 24 ]; then
                modo="compacto"
            elif [ "$filas" -lt 32 ]; then
                modo="medio"
            else
                modo="completo"
            fi

            header=$(stk_modulo_header_compuesto "$modo" "$dato")

            fzf_args=(
                --ansi
                --height=~90%
                --layout=reverse
                --no-sort
                --header-first
                --border=rounded
                --border-label=" System Tool Kit "
                --prompt="➤ $prompt_text: "
                --header="$header"
                --color="$FZF_COLORES"
            )
            if [ -n "$preview" ]; then
                fzf_args+=(
                    --preview="bash -c $(printf '%q' "$preview") _ {}"
                    --preview-window="right:40%:wrap"
                )
            fi

            # El ticker refresca la cabecera completa para no perder dashboard/dato.
            STK_HEADER_REFRESH_CMD=(stk_modulo_header_compuesto "$modo" "$dato")
            stk_fzf_ejecutar "$prompt_text" "$header" "System Tool Kit" "${fzf_args[@]}"
            ;;
        preview)
            header_text="$dato  ·  Shift+↑/↓ desplaza preview"
            fzf_args=(
                --ansi
                --height=80%
                --layout=reverse
                --no-sort
                --border=rounded
                --border-label=" $dato "
                --prompt="➤ $prompt_text: "
                --header="$header_text"
                --color="$FZF_COLORES"
            )
            if [ -n "$preview" ]; then
                fzf_args+=(
                    --preview="bash -c $(printf '%q' "$preview") _ {}"
                    --preview-window="right:40%:wrap"
                )
            fi
            # Cabecera estática: evita que un refresh anterior borre el texto.
            STK_HEADER_REFRESH_CMD=()
            stk_fzf_ejecutar "$prompt_text" "$header_text" "$dato" "${fzf_args[@]}"
            ;;
        simple|*)
            header_text="$dato"
            fzf_args=(
                --ansi
                --height=15
                --reverse
                --border=rounded
                --prompt="➤ $prompt_text: "
                --header="$header_text"
                --color="$FZF_COLORES"
            )
            STK_HEADER_REFRESH_CMD=()
            stk_fzf_ejecutar "$prompt_text" "$header_text" "" "${fzf_args[@]}"
            ;;
    esac
}
# Devuelve 0 si la selección de fzf debe tratarse como cancelación/volver.
# Uso: sel=$(... | fzf_estilo ...); rc=$?; if stk_fzf_cancelado "$rc" "$sel"; then ...
stk_fzf_cancelado() {
    local rc="${1:-0}"
    local sel="${2:-}"
    [[ $rc -ne 0 || -z "$sel" || "$sel" == *"Volver"* ]]
}

fzf_estilo() {
    stk_fzf simple "$1" "${2:-}"
}
stk_fzf_menu() {
    stk_fzf marco "$1" "${2:-}"
}
mostrar_spinner() {
    local caracteres="/-\|"
    while true; do
        for (( i=0; i<${#caracteres}; i++ )); do
            printf "\r${AZUL_BRILLANTE}[%c]${RESET} Procesando..." "${caracteres:$i:1}"
            sleep 0.1
        done
    done
}
mostrar_ayuda() {
    echo -e "${CIAN}STK - System Tool Kit v${V}${RESET}"
    echo -e "${BLANCO}Uso:${RESET} sudo $0 [OPCIÓN]"
    echo ""
    echo -e "${AMARILLO}Opciones de línea de comandos:${RESET}"
    echo -e "  ${VERDE}-m, --monitor${RESET}          Abre el monitor de rendimiento del sistema."
    echo -e "  ${VERDE}-a, --audit${RESET}            Ejecuta la auditoría de seguridad del sistema."
    echo -e "  ${VERDE}-u, --update${RESET}           Actualiza los paquetes del sistema y repositorios."
    echo -e "  ${VERDE}-c, --clean${RESET}            Ejecuta la súper limpieza de espacio e imprevistos."
    echo -e "  ${VERDE}-l, --logs${RESET}             Muestra las últimas entradas de la bitácora STK."
    echo -e "  ${VERDE}-b, --backup${RESET}           Accede directamente al menú de copias de seguridad."
    echo -e "  ${VERDE}-A, --auto${RESET}             Ejecuta el modo automático de mantenimiento integral."
    echo -e "  ${VERDE}-D, --disk${RESET}             Abre el análisis y monitorización del disco (HARD4ME)."
    echo -e "  ${VERDE}-v, --version${RESET}          Muestra la versión del script y sale."
    echo -e "  ${VERDE}-h, --help, ayuda${RESET}      Muestra este mensaje de ayuda."
    echo ""
    echo -e "  ${AZUL}Sin argumentos:${RESET}        Abre el menú interactivo con FZF."
    echo ""
    exit 0
}
