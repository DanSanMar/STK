# ==============================================================================
# stk_ui_lib.sh - capa de UI de STK (colores, logo, selector y mensajes)
# Se carga desde stk.sh. No ejecuta nada por sí sola.
# ==============================================================================

pintar() {
    local COLOR="$1"
    local MENSAJE="$2"
    echo -e "${COLOR}${MENSAJE}${RESET}"
}
# Helpers de UI: unifican mensaje + pausa opcional. El segundo argumento
# es el texto exacto de la pausa; si se omite, no se espera al usuario.
stk_mostrar_error() {
    local mensaje="$1" aviso="${2:-}"
    pintar "$ROJO" "$mensaje"
    [ -n "$aviso" ] && read -p "$aviso"
    return 0
}
stk_mostrar_info() {
    local mensaje="$1" aviso="${2:-}"
    pintar "$AMARILLO" "$mensaje"
    [ -n "$aviso" ] && read -p "$aviso"
    return 0
}
stk_mostrar_exito() {
    local mensaje="$1" aviso="${2:-}"
    pintar "$VERDE" "$mensaje"
    [ -n "$aviso" ] && read -p "$aviso"
    return 0
}
# Pausa estándar al volver de un módulo o submenú.
stk_volver_menu() {
    local aviso="${1:-Presione Enter para volver al menú...}"
    echo ""
    read -p "$aviso"
}
logo_barra() {
    actualizar_colores_logo

    local hora
    hora=$(date '+%H:%M:%S')

    echo -e " ${AZUL_BRILLANTE}--- ⚡ ${NEGRITA}${COLOR_LOGO}STK${RESET} ${AZUL_OSCURO}- ${COLOR_DASH}ALL4ME${RESET} ${AZUL_OSCURO}- ${COLOR_VER}v${V}${RESET} ${AZUL_OSCURO}| ${AMARILLO}By:${RESET} ${AZUL}${AUTOR}${RESET} ${BLANCO}:${hora}: ${AZUL_BRILLANTE}⚡---${RESET}"
}
logo_texto() {
    local modo="${1:-completo}"

    logo_barra
    echo -e " ${CIAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"

    # En pantallas bajas se recorta la cabecera para no ocultar el menú.
    case "$modo" in
        compacto)
            dashboard_cacheado
            return
            ;;
        medio)
            echo -e " ${AMARILLO}Host:${RESET} ${AZUL}${HOST_STK}${RESET}  ${AMARILLO}SO:${RESET} ${AZUL}${SO_STK}${RESET}"
            dashboard_cacheado
            return
            ;;
    esac

    echo -e " ${AMARILLO}Host:${RESET} ${AZUL}${HOST_STK}${RESET}  ${AMARILLO}SO:${RESET} ${AZUL}${SO_STK}${RESET}  ${AMARILLO}Kernel:${RESET} ${AZUL}${KERNEL_STK}${RESET}"
    if [ "$IMMUTABLE" = true ]; then
        echo -e " ${AMARILLO}Entorno:${RESET} ${AZUL}Inmutable · rpm-ostree${RESET}"
    fi
    dashboard_cacheado
}
mostrar_logo() {
    echo ""
    logo_texto
}
# Selector único: estilos "simple" (listas), "marco" (menús) y
# "preview" (submenús con vista previa). Cuarto argumento = script de preview.
# fzf_estilo() y stk_fzf_menu() son wrappers públicos que delegan aquí.
stk_fzf() {
    local estilo="$1" prompt_text="$2" dato="${3:-}" preview="${4:-}"
    local filas modo logo header_text
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
        preview)
            fzf_args=(
                --ansi
                --height=80%
                --layout=reverse
                --no-sort
                --border=rounded
                --border-label=" $dato "
                --prompt="➤ $prompt_text: "
                --header="$dato  ·  Shift+↑/↓ desplaza preview"
                --color="$FZF_COLORES"
            )
            if [ -n "$preview" ]; then
                fzf_args+=(
                    --preview="bash -c $(printf '%q' "$preview") _ {}"
                    --preview-window="right:55%:wrap"
                )
            fi
            stk_fzf_ejecutar "$prompt_text" "$dato" "$dato" "${fzf_args[@]}"
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
            stk_fzf_ejecutar "$prompt_text" "$header_text" "" "${fzf_args[@]}"
            ;;
    esac
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
