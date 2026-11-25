#!/bin/bash
# Verificador estático de stk.sh. No requiere root y NO ejecuta el script:
# solo comprueba sintaxis, paridad, bloques, estilo e integridad de stk2.sh.
# Uso: ./verificar_stk.sh

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STK="$DIR/stk.sh"
REF="$DIR/stk2.sh"
HASH_REF="0f58edd5f53835fb201f6b8fcbfb6c4c86b697bda3a030499beea65d70e285d7"

fallos=0
ok()   { echo "[OK]     $1"; }
mal()  { echo "[ERROR]  $1"; fallos=$((fallos + 1)); }
aviso(){ echo "[AVISO]  $1"; }

if [ ! -r "$STK" ]; then
    echo "[ERROR] No se encuentra $STK"
    exit 1
fi

# 1. Sintaxis
if bash -n "$STK" 2>/dev/null; then ok "bash -n stk.sh"; else mal "bash -n stk.sh"; fi
if [ -r "$REF" ] && bash -n "$REF" 2>/dev/null; then ok "bash -n stk2.sh"; else mal "bash -n stk2.sh"; fi

# 2. stk2.sh intacto
if [ -r "$REF" ]; then
    actual=$(sha256sum "$REF" | awk '{print $1}')
    if [ "$actual" = "$HASH_REF" ]; then
        ok "stk2.sh intacto"
    else
        mal "stk2.sh ha cambiado (hash $actual)"
    fi
else
    mal "No se encuentra stk2.sh"
fi

# 3. Funciones: ninguna original perdida y sin duplicados
if [ -r "$REF" ]; then
    ref_funcs=$(grep -oE '^[A-Za-z_][A-Za-z0-9_]*\(\)' "$REF" | sort)
    stk_funcs=$(grep -oE '^[A-Za-z_][A-Za-z0-9_]*\(\)' "$STK" | sort)
    perdidas=$(comm -23 <(echo "$ref_funcs") <(echo "$stk_funcs"))
    if [ -z "$perdidas" ]; then
        ok "funciones originales presentes ($(echo "$ref_funcs" | wc -l)/$(echo "$ref_funcs" | wc -l))"
    else
        mal "faltan funciones: $(echo "$perdidas" | tr '\n' ' ')"
    fi
    dup=$(echo "$stk_funcs" | uniq -d)
    [ -z "$dup" ] && ok "sin funciones duplicadas" || mal "funciones duplicadas: $dup"
    echo "[INFO]   total de funciones en stk.sh: $(echo "$stk_funcs" | wc -l)"
fi

# 4. Estructura de bloques
bloques=$(grep -cE '^# [1-5]\. ' "$STK")
[ "$bloques" -eq 5 ] && ok "5 bloques principales" || mal "bloques principales: $bloques (esperados 5)"
grep -q '^# 5\.4 Arranque' "$STK" && ok "sección 5.4 Arranque" || mal "falta la sección 5.4 Arranque"

# 5. Huecos excesivos y comentarios huérfanos
huecos=$(awk 'NF==0 {if(!abierto){ini=NR; abierto=1}; next} abierto {if(NR-ini>=3) print ini "-" NR-1; abierto=0}' "$STK")
[ -z "$huecos" ] && ok "sin tramos de 3+ líneas vacías" || mal "huecos excesivos: $huecos"

huerfanos=$(awk '
    /^[[:space:]]*#/ {
        if (vacios >= 2 && comentario_anterior) print NR-1
        comentario_anterior=1; vacios=0; next
    }
    NF==0 {vacios++; next}
    {comentario_anterior=0; vacios=0}
' "$STK")
[ -z "$huerfanos" ] && ok "sin comentarios huérfanos" || mal "comentarios huérfanos en: $huerfanos"

# 6. Estilo de menús y selector
sin_arrow=$(grep -nE '[0-9]+\. +Volver' "$STK")
[ -z "$sin_arrow" ] && ok "todas las opciones 'Volver' usan ↩" || mal "opciones 'Volver' sin arrow: $sin_arrow"

directo=$(grep -nE '^[[:space:]]*[^#]*\|[[:space:]]*fzf([[:space:]]|$)|^[[:space:]]*fzf[[:space:]]' "$STK" | grep -v 'stk_fzf')
[ -z "$directo" ] && ok "ninguna llamada directa a fzf" || mal "llamadas directas a fzf: $directo"

# 7. Estilo defensivo
if grep -qE '^set -[eu]' "$STK"; then mal "set -e/set -u detectado"; else ok "sin set -e/set -u"; fi

# Informativo: whitespace heredado de stk2.sh
finales=$(grep -c '[[:blank:]]$' "$STK")
aviso "líneas con espacio final (heredadas): $finales"

echo ""
if [ "$fallos" -eq 0 ]; then
    echo "RESULTADO: OK — stk.sh cumple el contrato de estilo."
    exit 0
fi
echo "RESULTADO: $fallos fallo(s)."
exit 1
