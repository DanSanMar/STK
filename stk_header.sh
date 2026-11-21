#!/usr/bin/env bash

# ==============================================================================
# STK_HEADER - Biblioteca de cabeceras responsive para los módulos de STK
# ==============================================================================
# Uso:
#   source "$SCRIPT_DIR/stk_header.sh"
#   stk_init "MODULO" "1.0" "SUBTITULO"   # la línea extra es opcional
#   stk_header                           # pinta la cabecera
#   stk_fzf_menu "Seleccione" "MODULO"   # FZF con paleta y border-label
#   stk_salir "MODULO"                   # salida con guard de integración
# ==============================================================================

# --- PALETA CANÓNICA (idéntica a la de STK / PROC4ME) ---
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
BLANCO_NEGRITA='\e[1;97m'
GRIS_CLARO='\e[37m'

FZF_COLORES="border:#ff5555,pointer:#92ff92,header:#5fb2ff,label:#5fb2ff,prompt:#5fb2ff,marker:#92ff92"

PALETA_STK=(
    "$ROJO" "$AZUL_BRILLANTE" "$VERDE_BRILLANTE" "$AMARILLO_BRILLANTE"
    "$CIAN_BRILLANTE" "$ROJO_BRILLANTE" "$AZUL_CLARO" "$VERDE" "$AMARILLO" "$CIAN"
)

STK_MODULO=""
STK_VERSION=""
STK_SUBTITULO=""
STK_EXTRA=""
STK_OS=""
STK_KERNEL=""
STK_HOST=""
STK_USER=""

# --- DETECCIÓN DE ANCHO / ALTO (robusta incluso con stdout redirigido) ---
stk_detectar_columnas() {
    local cols=""
    [ -r /dev/tty ] && cols=$( { stty size </dev/tty 2>/dev/null; } 2>/dev/null | awk '{print $2}')
    [[ "$cols" =~ ^[0-9]+$ ]] && [ "$cols" -gt 0 ] || cols=$(tput cols 2>/dev/null)
    [[ "$cols" =~ ^[0-9]+$ ]] && [ "$cols" -gt 0 ] || cols="${COLUMNS:-80}"
    [[ "$cols" =~ ^[0-9]+$ ]] && [ "$cols" -gt 0 ] || cols=80
    printf '%s' "$cols"
}

stk_detectar_filas() {
    local filas=""
    [ -r /dev/tty ] && filas=$( { stty size </dev/tty 2>/dev/null; } 2>/dev/null | awk '{print $1}')
    [[ "$filas" =~ ^[0-9]+$ ]] && [ "$filas" -gt 0 ] || filas=$(tput lines 2>/dev/null)
    [[ "$filas" =~ ^[0-9]+$ ]] && [ "$filas" -gt 0 ] || filas="${LINES:-24}"
    [[ "$filas" =~ ^[0-9]+$ ]] && [ "$filas" -gt 0 ] || filas=24
    printf '%s' "$filas"
}

# --- MEDIDA REAL DE COLUMNAS (wc -L tiene en cuenta caracteres anchos/emoji) ---
stk_limpiar_ansi() {
    sed -E 's/\x1B\[[0-9;]*[a-zA-Z]//g; s/\e\[[0-9;]*[a-zA-Z]//g'
}

stk_ancho_texto() {
    local texto="$1" limpio ancho
    limpio=$(printf '%s' "$texto" | stk_limpiar_ansi)
    if printf '' | wc -L >/dev/null 2>&1; then
        ancho=$(printf '%s\n' "$limpio" | wc -L)
    else
        ancho=${#limpio}
    fi
    [[ "$ancho" =~ ^[0-9]+$ ]] || ancho=${#limpio}
    printf '%s' "$ancho"
}

stk_recortar() {
    local texto="$1" max="$2" ancho
    ancho=$(stk_ancho_texto "$texto")
    while [ "$ancho" -gt "$max" ] && [ -n "$texto" ]; do
        texto="${texto%?}"
        ancho=$(stk_ancho_texto "$texto")
    done
    printf '%s' "$texto"
}

stk_repetir() {
    local caracter="$1" veces="$2" salida="" i
    for (( i = 0; i < veces; i++ )); do salida+="$caracter"; done
    printf '%s' "$salida"
}

# --- INICIALIZACIÓN ---
stk_init() {
    STK_MODULO="${1:-STK}"
    STK_VERSION="${2:-}"
    STK_SUBTITULO="${3:-ALL4ME}"
    STK_EXTRA="${4:-}"

    STK_OS=$( . /etc/os-release 2>/dev/null; printf '%s' "${PRETTY_NAME:-${ID:-Linux}}" )
    STK_KERNEL=$(uname -r 2>/dev/null || printf 'N/D')
    STK_HOST=$(hostname 2>/dev/null || cat /etc/hostname 2>/dev/null || printf 'Desconocido')
    STK_USER="${SUDO_USER:-${USER:-$(id -un 2>/dev/null)}}"
}

stk_colores() {
    local epoch base total=${#PALETA_STK[@]}
    epoch=$(date +%s 2>/dev/null)
    [[ "$epoch" =~ ^[0-9]+$ ]] || epoch=0
    base=$(( (epoch / 3) % total ))
    STK_COLOR_LOGO="${PALETA_STK[$base]}"
    STK_COLOR_DASH="${PALETA_STK[$(( (base + 3) % total ))]}"
    STK_COLOR_VER="${PALETA_STK[$(( (base + 6) % total ))]}"
}

# --- CABECERA RESPONSIVE ---
# Modos: completo (>=90 columnas y >=20 filas), normal (>=60), compacto (<60 o pantalla baja).
stk_header() {
    local cols alto modo hora titulo_plano titulo_colorido ancho_titulo relleno izq der
    cols=$(stk_detectar_columnas)
    alto=$(stk_detectar_filas)

    modo="completo"
    [ "$alto" -lt 20 ] && modo="compacto"
    [ "$cols" -lt 60 ] && modo="compacto"
    if [ "$modo" != "compacto" ] && [ "$cols" -lt 90 ]; then
        modo="normal"
    fi

    stk_colores
    hora=$(date '+%H:%M:%S')

    # Barra superior con segmentos de colores rotativos (estilo PROC4ME).
    # La versión plana se usa solo para medir el ancho real.
    titulo_plano="⚡ ${STK_MODULO} | ${STK_SUBTITULO} | By: DanSanMar | v${STK_VERSION} :${hora}: ⚡"
    titulo_colorido="${AZUL_BRILLANTE}⚡ ${NEGRITA}${STK_COLOR_LOGO}${STK_MODULO}${RESET} ${AZUL_OSCURO}| ${STK_COLOR_DASH}${STK_SUBTITULO}${RESET} ${AZUL_OSCURO}| ${AZUL}By: DanSanMar${RESET} ${AZUL_OSCURO}| ${STK_COLOR_VER}v${STK_VERSION}${RESET} ${BLANCO}:${hora}: ${AZUL_BRILLANTE}⚡${RESET}"

    if [ "$modo" = "compacto" ]; then
        # En pantallas estrechas se priorizan módulo, versión, autor y hora.
        local corto_plano="⚡ ${STK_MODULO} v${STK_VERSION} By: DanSanMar :${hora}: ⚡"
        local corto_colorido="${AZUL_BRILLANTE}⚡ ${NEGRITA}${STK_COLOR_LOGO}${STK_MODULO}${RESET} ${STK_COLOR_VER}v${STK_VERSION}${RESET} ${AZUL}By: DanSanMar${RESET} ${BLANCO}:${hora}:${AZUL_BRILLANTE} ⚡${RESET}"
        if [ "$(stk_ancho_texto "$corto_plano")" -le $((cols - 1)) ]; then
            printf '%b\n' "$corto_colorido"
        else
            printf '%b%s%b\n' "$STK_COLOR_LOGO" "$(stk_recortar "$corto_plano" $((cols - 1)))" "$RESET"
        fi
        return 0
    fi

    # Barra llena: el título queda centrado por relleno de '━', no por espacios.
    ancho_titulo=$(stk_ancho_texto "$titulo_plano")
    relleno=$(( cols - ancho_titulo - 2 ))
    [ "$relleno" -lt 0 ] && relleno=0
    izq=$(( relleno / 2 ))
    der=$(( relleno - izq ))
    printf '%b%s %b %s%b\n' \
        "$AZUL_BRILLANTE" "$(stk_repetir '━' "$izq")" \
        "$titulo_colorido" \
        "$(stk_repetir '━' "$der")" "$AZUL_BRILLANTE"

    printf '%b%s%b\n' "$CIAN" "$(stk_repetir '━' "$cols")" "$RESET"

    if [ "$modo" = "completo" ]; then
        echo -e " ${AMARILLO}Sistema:${RESET} ${AZUL}${STK_OS}${RESET}  ${AMARILLO}Kernel:${RESET} ${AZUL}${STK_KERNEL}${RESET}"
        echo -e " ${AMARILLO}Host:${RESET} ${AZUL}${STK_HOST}${RESET}  ${AMARILLO}Usuario:${RESET} ${AZUL}${STK_USER}${RESET}"
        [ -n "$STK_EXTRA" ] && echo -e " $STK_EXTRA"
    else
        echo -e " ${AMARILLO}Sistema:${RESET} ${AZUL}${STK_OS}${RESET}"
        [ -n "$STK_EXTRA" ] && echo -e " $STK_EXTRA"
    fi

    printf '%b%s%b\n' "$CIAN" "$(stk_repetir '━' "$cols")" "$RESET"
}

# --- MENÚ FZF ESTÁNDAR ---
stk_fzf_menu() {
    local prompt_text="$1"
    local titulo="$2"
    local altura="${3:-18}"
    fzf --ansi \
        --height="$altura" \
        --reverse \
        --border=rounded \
        --border-label=" $titulo " \
        --prompt="➤ $prompt_text: " \
        --color="$FZF_COLORES"
}

# Comando para refrescar la cabecera en caliente desde FZF:
#   --bind "every(5):bg-transform-header:$(stk_header_cmd "$SELF_PATH")"
stk_header_cmd() {
    printf 'bash %q --stk-header' "${1:-$0}"
}

# --- SALIDA CON GUARD DE INTEGRACIÓN ---
stk_salir() {
    local modulo="${1:-STK}"
    local mensaje="${2:-Saliendo de $modulo...}"
    echo -e "\n${VERDE}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    pintar "$AZUL" "$mensaje"
    pintar "$VERDE" "¡Gracias por usar $modulo con All4me!"
    echo -e "${VERDE}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"
    # BASH_SOURCE[0] = esta librería; [1] = el módulo que la invocó.
    # Si el módulo se ejecutó con bash, termina el hijo; si se hizo source, devuelve el control.
    if [[ "${BASH_SOURCE[1]:-}" == "$0" ]]; then
        exit 0
    fi
}

# Punto de entrada directo: permite usar la librería como generador de cabecera para FZF.
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
    case "${1:-}" in
        --stk-header)
            stk_init "${2:-STK}" "${3:-}" "${4:-ALL4ME}"
            stk_header
            exit 0
            ;;
    esac
fi
