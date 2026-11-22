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

# Impresora de color compartida. Los módulos que definen la suya propia la
# sobrescriben sin problema; los que no (p. ej. hard4me) heredan esta.
pintar() {
    printf '%b\n' "${1:-}${2:-}${RESET}"
}

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

# ==============================================================================
# CAPA DE COMPATIBILIDAD: terminfo / fzf / TTY / rutas / avisos
# ------------------------------------------------------------------------------
# Se activa explícitamente con `stk_caps_init` desde cada script principal.
# Nada de esto es fatal: se degrada la funcionalidad y se avisa una sola vez.
# ==============================================================================

STK_COMPAT_INICIALIZADA=false
# Detección silenciosa al cargar la librería: así stk_limpiar funciona incluso
# en módulos que aún no han llamado a stk_caps_init (y en previews de fzf).
# Se prueba a abrir /dev/tty: dentro de $(...) stdin es una tubería, pero el
# terminal sigue disponible, así que [ -t 0 ] daría un falso "sin TTY".
if { : < /dev/tty; } 2>/dev/null; then
    STK_CAP_TTY=true
else
    STK_CAP_TTY=false
fi
STK_TERM_ORIGINAL=""
STK_FZF_VERSION=""
STK_FZF_DISPONIBLE=false
STK_FZF_CON_SOCK=false
STK_FZF_FLAG_BORDER_LABEL=false
STK_CURL_UNIX=false
STK_TMP_DIR_ELEGIDO=""
STK_HEADER_REFRESH_CMD=()
STK_AVISOS=()
declare -A STK_AVISOS_VISTOS=()

# Comparador de versiones sin `sort -V` (GNU-only). 0 si "$1" >= "$2".
stk_version_ge() {
    local v1="${1//[^0-9.]/}" v2="${2//[^0-9.]/}"
    local -a a=() b=()
    local IFS=.
    read -r -a a <<< "$v1"
    read -r -a b <<< "$v2"
    local n=${#a[@]} i x y
    [ ${#b[@]} -gt "$n" ] && n=${#b[@]}
    for (( i = 0; i < n; i++ )); do
        x="${a[i]:-0}"; y="${b[i]:-0}"
        [[ "$x" =~ ^[0-9]+$ ]] || x=0
        [[ "$y" =~ ^[0-9]+$ ]] || y=0
        [ "$x" -gt "$y" ] && return 0
        [ "$x" -lt "$y" ] && return 1
    done
    return 0
}

# Aviso centralizado: nivel informacion/aviso/error, deduplicado por codigo.
stk_avisar() {
    local nivel="${1:-info}" codigo="${2:-general}" mensaje="${3:-}"
    local prefijo
    case "$nivel" in
        error) prefijo="${ROJO}ERROR${RESET}" ;;
        warn)  prefijo="${AMARILLO}AVISO${RESET}" ;;
        *)     prefijo="${AZUL}INFO ${RESET}" ;;
    esac
    [ -n "${STK_AVISOS_VISTOS[$codigo]:-}" ] && return 0
    STK_AVISOS_VISTOS[$codigo]=1
    STK_AVISOS+=("$nivel|$codigo|$mensaje")
    printf '[STK][%b] %b\n' "$prefijo" "$mensaje" >&2
    local logf="${LOG_FILE:-}"
    if [ -n "$logf" ] && [ -w "$logf" ]; then
        printf '[%s] [%s] [STK-CAPS] - %s\n' \
            "$(date '+%Y-%m-%d %H:%M:%S')" "${nivel^^}" "$mensaje" >> "$logf" 2>/dev/null || true
    fi
}

stk_resumen_avisos() {
    [ ${#STK_AVISOS[@]} -gt 0 ] || return 0
    local entrada nivel codigo mensaje errores=0 avisos=0
    for entrada in "${STK_AVISOS[@]}"; do
        IFS='|' read -r nivel codigo mensaje <<< "$entrada"
        if [ "$nivel" = "error" ]; then errores=$((errores + 1)); else avisos=$((avisos + 1)); fi
    done
    printf '%b\n' "${AZUL}Resumen de compatibilidad:${RESET} $avisos aviso(s), $errores error(es). Detalles en ${LOG_FILE:-log}."
}

# --- TERMINFO ---
stk_term_valido() {
    local t="${1:-}"
    [ -z "$t" ] && return 1
    [ "$t" = "dumb" ] && return 1
    if command -v infocmp >/dev/null 2>&1; then
        infocmp -1 "$t" >/dev/null 2>&1 && return 0
    fi
    if command -v tput >/dev/null 2>&1; then
        tput -T "$t" longname >/dev/null 2>&1 && return 0
    fi
    return 1
}

stk_term_sanitizar() {
    STK_TERM_ORIGINAL="${TERM:-<vacío>}"
    stk_term_valido "${TERM:-}" && return 0
    local candidato
    for candidato in xterm-256color screen-256color xterm vt100; do
        if stk_term_valido "$candidato"; then
            export TERM="$candidato"
            stk_avisar warn term_fallback \
                "TERM='$STK_TERM_ORIGINAL' no existe en este servidor; usando $candidato. Para conservarlo: infocmp -x $STK_TERM_ORIGINAL | ssh usuario@servidor -- tic -x -"
            return 0
        fi
    done
    stk_avisar warn term_fallback \
        "TERM='$STK_TERM_ORIGINAL' no es válido y no hay alternativa conocida; la interfaz puede degradarse."
    return 1
}

# --- RUTAS TEMPORALES Y LOG ---
# Deja la ruta elegida en STK_TMP_DIR_ELEGIDO (sin subshell para conservar avisos).
stk_elegir_tmp() {
    local base dir
    for base in "${TMPDIR:-}" "${XDG_RUNTIME_DIR:-}" "/run/user/${UID:-}" /tmp /dev/shm; do
        [ -n "$base" ] || continue
        dir=$(mktemp -d "$base/stk.XXXXXX" 2>/dev/null) || continue
        [ -d "$dir" ] && [ -w "$dir" ] || continue
        if [ -n "${TMPDIR:-}" ] && [ "$base" != "$TMPDIR" ]; then
            stk_avisar warn tmp_fallback "TMPDIR no escribible; usando $dir"
        fi
        STK_TMP_DIR_ELEGIDO="$dir"
        printf '%s' "$dir"
        return 0
    done
    STK_TMP_DIR_ELEGIDO="${TMPDIR:-/tmp}"
    printf '%s' "$STK_TMP_DIR_ELEGIDO"
    return 1
}

stk_elegir_log() {
    local logf="${LOG_FILE:-}"
    [ -z "$logf" ] && return 0
    if [ -e "$logf" ]; then
        [ -w "$logf" ] && return 0
    else
        [ -w "$(dirname "$logf" 2>/dev/null)" ] && return 0
    fi
    local alt="${XDG_STATE_HOME:-$HOME/.local/state}/stk/stk_mantenimiento.log"
    mkdir -p "$(dirname "$alt")" 2>/dev/null || alt="${TMPDIR:-/tmp}/stk_mantenimiento_${UID:-0}.log"
    LOG_FILE="$alt"
    stk_avisar warn log_fallback "Sin permiso para escribir el log del sistema; usando $LOG_FILE"
}

# --- SONDEO ÚNICO ---
stk_caps_init() {
    [ "$STK_COMPAT_INICIALIZADA" = true ] && return 0
    STK_COMPAT_INICIALIZADA=true

    stk_term_sanitizar

    if { : < /dev/tty; } 2>/dev/null; then
        STK_CAP_TTY=true
    else
        stk_avisar info sin_tty "Sin TTY: los menús pasarán a modo no interactivo."
    fi

    if command -v fzf >/dev/null 2>&1; then
        STK_FZF_DISPONIBLE=true
        STK_FZF_VERSION=$(fzf --version 2>/dev/null | awk '{print $1}')
        if fzf --help 2>/dev/null | grep -q -- '--border-label'; then
            STK_FZF_FLAG_BORDER_LABEL=true
        fi
        if stk_curl_soporta_unix; then STK_CURL_UNIX=true; fi
        if stk_version_ge "$STK_FZF_VERSION" 0.66.0 && [ "$STK_CURL_UNIX" = true ]; then
            STK_FZF_CON_SOCK=true
        elif [ -n "$STK_FZF_VERSION" ] && ! stk_version_ge "$STK_FZF_VERSION" 0.66.0; then
            stk_avisar info fzf_header_plano \
                "fzf $STK_FZF_VERSION: cabecera animada desactivada (los sockets UNIX requieren >= 0.66)."
        fi
    else
        stk_avisar warn fzf_ausente \
            "fzf no está en el PATH; los menús usarán el modo textual. Revisa el PATH bajo sudo (secure_path)."
    fi

    stk_elegir_log
    # No se crea aquí un directorio temporal: en módulos, stk_caps_init puede
    # ejecutarse dentro de $(...) y el trap de limpieza no se heredaría.
    # stk_fzf_ejecutar usa STK_TMP_DIR si existe, o TMPDIR directamente.
    if [ -n "${FZF_DEFAULT_OPTS:-}" ]; then
        stk_avisar info fzf_env \
            "FZF_DEFAULT_OPTS se ignora en los menús STK para evitar conflictos de opciones."
    fi

    local locale_actual="${LC_ALL:-${LC_CTYPE:-${LANG:-}}}"
    if [ -z "$locale_actual" ] || [ "$locale_actual" = "POSIX" ] \
        || [[ "$locale_actual" =~ ^C(\.|_|$) ]]; then
        stk_avisar info locale_c \
            "Locale sin UTF-8 ('${locale_actual:-vacío}'): emoji y caracteres anchos pueden medirse mal. Usa LANG=C.UTF-8."
    fi
}

stk_curl_soporta_unix() {
    command -v curl >/dev/null 2>&1 || return 1
    { curl --help all 2>/dev/null || curl --help 2>/dev/null; } | grep -q -- '--unix-socket'
}

# --- SUSTITUTOS TERMINFO-INDEPENDIENTES ---
stk_limpiar() {
    if [ "$STK_CAP_TTY" = true ]; then
        printf '\e[H\e[2J\e[3J'
    else
        printf '\n'
    fi
}

stk_alt_screen_on()  { printf '\e[?1049h\e[22;0;0t'; }
stk_alt_screen_off() { printf '\e[?1049l\e[23;0;0t'; }
stk_cursor_off()     { printf '\e[?25l'; }
stk_cursor_on()      { printf '\e[?12l\e[?25h'; }

# --- MENÚ TEXTUAL (sin fzf o sin TTY) ---
stk_menu_texto() {
    local prompt="$1"; shift
    local -a opciones=("$@")
    [ ${#opciones[@]} -gt 0 ] || return 1

    printf '%b\n' "${AMARILLO}➤ $prompt (modo textual):${RESET}" >&2
    local i
    for i in "${!opciones[@]}"; do
        printf '  %2d) %s\n' "$((i + 1))" "${opciones[$i]}" >&2
    done

    if [ "$STK_CAP_TTY" != true ]; then
        stk_avisar info menu_sin_tty "Sin TTY: no se puede elegir en '$prompt'."
        return 1
    fi

    local respuesta=""
    while :; do
        printf '%b' "${CIAN}Elige un número (Enter=cancelar): ${RESET}" >&2
        IFS= read -r respuesta </dev/tty || respuesta=""
        [ -z "$respuesta" ] && return 130
        [[ "$respuesta" =~ ^[0-9]+$ ]] || continue
        [ "$respuesta" -ge 1 ] && [ "$respuesta" -le ${#opciones[@]} ] || continue
        printf '%s\n' "${opciones[$((respuesta - 1))]}"
        return 0
    done
}

# --- EJECUTOR UNIFICADO DE FZF CON FALLBACKS ---
# Uso: printf ... | stk_fzf_ejecutar <prompt> <header> <titulo> [args de fzf...]
stk_fzf_ejecutar() {
    local prompt="$1" header_inicial="$2" titulo="$3"; shift 3
    local -a args=("$@")
    local -a lineas=()
    local rc

    # Inicialización perezosa: los módulos que aún no llaman a stk_caps_init
    # siguen teniendo menús con todas las capacidades detectadas.
    [ "$STK_COMPAT_INICIALIZADA" = true ] || stk_caps_init

    mapfile -t lineas

    if [ "$STK_CAP_TTY" != true ] || [ "$STK_FZF_DISPONIBLE" != true ]; then
        stk_menu_texto "$prompt" "${lineas[@]}"
        return $?
    fi

    # fzf antiguo: quitar --border-label y el '~' de --height=~NN%.
    if [ "$STK_FZF_FLAG_BORDER_LABEL" != true ]; then
        local -a filtrados=() arg
        for arg in "${args[@]}"; do
            case "$arg" in
                --border-label*) continue ;;
                --height=~*) arg="--height=${arg#--height=~}" ;;
            esac
            filtrados+=("$arg")
        done
        args=("${filtrados[@]}")
        stk_avisar warn fzf_flags_antiguos \
            "fzf $STK_FZF_VERSION: se omitieron opciones no soportadas (border-label, height ~)."
    fi

    if [ "$STK_FZF_CON_SOCK" = true ]; then
        local sockdir="${STK_TMP_DIR:-${TMPDIR:-/tmp}}"
        local sock="$sockdir/fzf_${UID:-0}_${BASHPID:-$$}.sock"
        local ticker header
        (
            sleep_pid=""
            trap 'kill "$sleep_pid" 2>/dev/null; exit 0' TERM INT
            while :; do
                sleep "${LOGO_INTERVALO:-3}" & sleep_pid=$!
                wait "$sleep_pid" || exit 0
                header="$header_inicial"
                if [ ${#STK_HEADER_REFRESH_CMD[@]} -gt 0 ]; then
                    header=$("${STK_HEADER_REFRESH_CMD[@]}" 2>/dev/null) || header="$header_inicial"
                fi
                [ -n "$header" ] || header="$header_inicial"
                curl -s -o /dev/null --max-time 2 --unix-socket "$sock" \
                    -X POST http://localhost/ \
                    --data-binary "change-header($header)" 2>/dev/null || exit 0
            done
        ) </dev/null >/dev/null 2>&1 &
        ticker=$!
        printf '%s\n' "${lineas[@]}" | FZF_DEFAULT_OPTS="" fzf "${args[@]}" --listen="$sock"
        rc=$?
        kill "$ticker" 2>/dev/null
        wait "$ticker" 2>/dev/null
        rm -f "$sock"
    else
        printf '%s\n' "${lineas[@]}" | FZF_DEFAULT_OPTS="" fzf "${args[@]}"
        rc=$?
    fi

    # Red de seguridad: 2 = error de fzf (opción desconocida, socket inválido...).
    # 1 = sin coincidencias y 130 = cancelación con ESC: no se reintenta.
    if [ "$rc" -eq 2 ]; then
        stk_avisar error fzf_reintento \
            "fzf devolvió $rc en '$prompt'; se reintenta con opciones mínimas."
        printf '%s\n' "${lineas[@]}" | FZF_DEFAULT_OPTS="" \
            fzf --ansi --height=15 --reverse --prompt="➤ $prompt: "
        rc=$?
    fi
    return "$rc"
}

stk_diagnostico() {
    printf '%b\n' "${AZUL}=== STK · diagnóstico de compatibilidad ===${RESET}"
    printf '  Sistema       : %s\n' "$(. /etc/os-release 2>/dev/null; printf '%s' "${PRETTY_NAME:-${ID:-Linux}}")"
    printf '  Bash          : %s\n' "${BASH_VERSION:-?}"
    printf '  TERM          : %s (original: %s)\n' "${TERM:-<vacío>}" "${STK_TERM_ORIGINAL:-?}"
    printf '  TTY           : %s\n' "$STK_CAP_TTY"
    printf '  fzf           : %s\n' "${STK_FZF_VERSION:-no instalado}"
    printf '  fzf socket    : %s\n' "$STK_FZF_CON_SOCK"
    printf '  fzf border-lbl: %s\n' "$STK_FZF_FLAG_BORDER_LABEL"
    printf '  curl --unix   : %s\n' "$STK_CURL_UNIX"
    printf '  Temporal      : %s\n' "${STK_TMP_DIR:-${TMPDIR:-/tmp}}"
    printf '  Log           : %s\n' "${LOG_FILE:-?}"
    printf '  Avisos        : %s\n' "${#STK_AVISOS[@]}"
    stk_resumen_avisos
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

    # Si el título completo no cabe (p. ej. 60 columnas con subtítulo largo),
    # se usan variantes cada vez más cortas ANTES de calcular el relleno.
    # Así se evita desbordar la línea, tanto en install4me como en hard4me.
    if [ "$ancho_titulo" -gt $(( cols - 2 )) ]; then
        local corto_plano corto_colorido
        corto_plano="⚡ ${STK_MODULO} | ${STK_SUBTITULO} | v${STK_VERSION} ⚡"
        corto_colorido="${AZUL_BRILLANTE}⚡ ${NEGRITA}${STK_COLOR_LOGO}${STK_MODULO}${RESET} ${AZUL_OSCURO}| ${STK_COLOR_DASH}${STK_SUBTITULO}${RESET} ${AZUL_OSCURO}| ${STK_COLOR_VER}v${STK_VERSION}${RESET} ${AZUL_BRILLANTE}⚡${RESET}"
        if [ "$(stk_ancho_texto "$corto_plano")" -gt $(( cols - 2 )) ]; then
            corto_plano="⚡ ${STK_MODULO} v${STK_VERSION} ⚡"
            corto_colorido="${AZUL_BRILLANTE}⚡ ${NEGRITA}${STK_COLOR_LOGO}${STK_MODULO}${RESET} ${STK_COLOR_VER}v${STK_VERSION}${RESET} ${AZUL_BRILLANTE}⚡${RESET}"
        fi
        titulo_plano="$corto_plano"
        titulo_colorido="$corto_colorido"
        ancho_titulo=$(stk_ancho_texto "$titulo_plano")
    fi

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

# --- MENÚ FZF ESTÁNDAR (con fallback textual) ---
stk_fzf_menu() {
    local prompt_text="$1"
    local titulo="$2"
    local altura="${3:-18}"
    stk_fzf_ejecutar "$prompt_text" "" "$titulo" \
        --ansi \
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
