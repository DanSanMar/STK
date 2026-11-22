#!/usr/bin/env bash
# Pruebas de la capa de compatibilidad de STK (stk_header.sh).
# No necesita root ni terminal interactiva.
# Uso: bash tests/compat.sh

set -uo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../stk_header.sh
source "$DIR/stk_header.sh"

pass=0
fail=0
ok()   { printf '  \033[32mPASS\033[0m %s\n' "$1"; pass=$((pass + 1)); }
ko()   { printf '  \033[31mFAIL\033[0m %s\n' "$1"; fail=$((fail + 1)); }
true_if() { if eval "$1"; then ok "$2"; else ko "$2"; fi; }

reset_caps() {
    STK_COMPAT_INICIALIZADA=false
    STK_CAP_TTY=false
    STK_FZF_DISPONIBLE=false
    STK_FZF_CON_SOCK=false
    STK_FZF_FLAG_BORDER_LABEL=false
    STK_CURL_UNIX=false
    STK_FZF_VERSION=""
    STK_AVISOS=()
    STK_AVISOS_VISTOS=()
    STK_HEADER_REFRESH_CMD=()
    FZF_DEFAULT_OPTS=""
    LOGO_INTERVALO=1
}

TMP_TEST=$(mktemp -d /tmp/stk-compat-test.XXXXXX)
trap 'rm -rf "$TMP_TEST" "${STK_TMP_DIR:-}"' EXIT

STUB_DIR="$TMP_TEST/bin"
mkdir -p "$STUB_DIR"
cat > "$STUB_DIR/fzf" <<'STUB'
#!/usr/bin/env bash
{
    printf 'FZF_DEFAULT_OPTS=%s\n' "${FZF_DEFAULT_OPTS-}"
    printf 'ARGS=%s\n' "$*"
} >> "${STK_TEST_LOG:-/dev/null}"
case "${1:-}" in
    --version) echo "${STK_TEST_FZF_VERSION:-0.60.3} (stub)"; exit 0 ;;
    --help)    printf '%s\n' "${STK_TEST_FZF_HELP:---ansi --listen --border-label --header-first --height --color}"; exit 0 ;;
esac
primera=""
while IFS= read -r linea; do
    [ -z "$primera" ] && primera="$linea"
done
printf '%s\n' "$primera"
exit "${STK_TEST_FZF_RC:-0}"
STUB
chmod +x "$STUB_DIR/fzf"

echo "== 1. Comparador de versiones (sin sort -V) =="
true_if 'stk_version_ge 0.66.0 0.66.0'   "0.66.0 >= 0.66.0"
true_if 'stk_version_ge 0.75.0 0.66.0'   "0.75.0 >= 0.66.0"
true_if '! stk_version_ge 0.60.3 0.66.0' "0.60.3 <  0.66.0"
true_if '! stk_version_ge "" 0.66.0'     "vacío  <  0.66.0"
true_if 'stk_version_ge 0.66 0.66.0'     "0.66   == 0.66.0"

echo "== 2. Sanitización de TERM desconocido =="
reset_caps
TERM_ORIGINAL="${TERM:-}"
TERM="terminal-inexistente-xyz"
stk_caps_init
true_if '[ "$TERM" = "xterm-256color" ]'             "TERM cambiado a xterm-256color"
true_if '[ "$STK_TERM_ORIGINAL" = "terminal-inexistente-xyz" ]' "TERM original conservado"
true_if '[ -n "${STK_AVISOS_VISTOS[term_fallback]:-}" ]' "aviso term_fallback emitido"
TERM="$TERM_ORIGINAL"

echo "== 3. fzf antiguo (0.60.3): sin socket UNIX =="
reset_caps
STK_CAP_TTY=true   # simulamos TTY para forzar la rama de fzf
export STK_TEST_LOG="$TMP_TEST/old.log"
export STK_TEST_FZF_VERSION="0.60.3"
export STK_TEST_FZF_HELP="--ansi --listen --header-first --height --color"
PATH="$STUB_DIR:$PATH" stk_caps_init
STK_CAP_TTY=true           # caps_init la resetea al no haber TTY real
STK_COMPAT_INICIALIZADA=true
true_if '[ "$STK_FZF_CON_SOCK" = "false" ]' "socket desactivado con fzf 0.60.3"
true_if '[ -n "${STK_AVISOS_VISTOS[fzf_header_plano]:-}" ]' "aviso de cabecera plana"
salida=$(printf '1. Uno\n2. Dos\n' | PATH="$STUB_DIR:$PATH" stk_fzf_ejecutar "Probar" "header" "TITULO" --ansi --border-label=" X " --height=~90%)
true_if '[ "$salida" = "1. Uno" ]'                    "menú devuelve la selección del stub"
true_if '! grep -q -- "--listen" "$STK_TEST_LOG"'     "no se pasa --listen a fzf antiguo"
true_if '! grep -q -- "--border-label" "$STK_TEST_LOG"' "se retira --border-label no soportado"
true_if 'grep -q -- "--height=90%" "$STK_TEST_LOG"'   "se retira el '~' de --height=~90%"

echo "== 4. fzf moderno (0.75.0): socket UNIX disponible =="
reset_caps
STK_CAP_TTY=true
export STK_TEST_LOG="$TMP_TEST/new.log"
export STK_TEST_FZF_VERSION="0.75.0"
unset STK_TEST_FZF_HELP
PATH="$STUB_DIR:$PATH" stk_caps_init
STK_CAP_TTY=true
STK_COMPAT_INICIALIZADA=true
true_if '[ "$STK_FZF_CON_SOCK" = "true" ]' "socket activado con fzf 0.75.0"
salida=$(printf '1. Uno\n2. Dos\n' | PATH="$STUB_DIR:$PATH" stk_fzf_ejecutar "Probar" "header" "TITULO" --ansi --border-label=" X ")
true_if '[ "$salida" = "1. Uno" ]'                "menú con socket devuelve selección"
true_if 'grep -q -- "--listen=" "$STK_TEST_LOG"'  "se pasa --listen con socket"

echo "== 5. FZF_DEFAULT_OPTS se ignora =="
reset_caps
STK_CAP_TTY=true
export STK_TEST_LOG="$TMP_TEST/env.log"
export STK_TEST_FZF_VERSION="0.60.3"
export FZF_DEFAULT_OPTS="--preview 'echo hola' --tmux center"
PATH="$STUB_DIR:$PATH" stk_caps_init
STK_CAP_TTY=true
STK_COMPAT_INICIALIZADA=true
printf '1. Uno\n' | PATH="$STUB_DIR:$PATH" stk_fzf_ejecutar "Probar" "" "TITULO" --ansi >/dev/null
true_if 'grep -q "^FZF_DEFAULT_OPTS=$" "$STK_TEST_LOG"' "FZF_DEFAULT_OPTS llega vacío a fzf"
true_if '[ -n "${STK_AVISOS_VISTOS[fzf_env]:-}" ]'      "aviso fzf_env emitido"
unset FZF_DEFAULT_OPTS

echo "== 6. Sin TTY: fallback no interactivo =="
reset_caps
if printf '1. Uno\n2. Dos\n' | stk_fzf_ejecutar "Probar" "" "TITULO" --ansi >/dev/null 2>&1; then
    ko "sin TTY no debe devolver éxito"
else
    ok "sin TTY devuelve fallo controlado"
fi

echo "== 7. limpieza sin terminfo =="
reset_caps
salida=$(stk_limpiar)
true_if '[ -z "$salida" ]' "stk_limpiar no depende de TERM"

echo "== 8. Códigos de salida de fzf =="
reset_caps
STK_CAP_TTY=true
STK_COMPAT_INICIALIZADA=true
STK_FZF_DISPONIBLE=true
export STK_TEST_LOG="$TMP_TEST/rc.log"
export STK_TEST_FZF_RC=130
printf '1. Uno\n' | PATH="$STUB_DIR:$PATH" stk_fzf_ejecutar "Probar" "" "TITULO" --ansi >/dev/null 2>&1
true_if '[ "$(grep -c "^ARGS=" "$STK_TEST_LOG")" -eq 1 ]' "ESC (130) no provoca reintento"
export STK_TEST_FZF_RC=2
printf '1. Uno\n' | PATH="$STUB_DIR:$PATH" stk_fzf_ejecutar "Probar" "" "TITULO" --ansi >/dev/null 2>&1
true_if '[ "$(grep -c "^ARGS=" "$STK_TEST_LOG")" -eq 3 ]' "error (2) provoca reintento con opciones mínimas"
unset STK_TEST_FZF_RC

echo
printf 'Resultado: %d PASS, %d FAIL\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
