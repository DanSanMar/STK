#!/bin/bash
# Verificador estático de stk.sh y sus librerías. No requiere root y NO
# ejecuta el script: solo comprueba sintaxis, paridad, bloques, estilo e
# integridad de stk2.sh. Uso: ./verificar_stk.sh

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STK="$DIR/stk.sh"
REF="$DIR/stk2.sh"
UI_LIB="$DIR/stk_ui_lib.sh"
MENU_LIB="$DIR/stk_menu_lib.sh"
HASH_REF="0f58edd5f53835fb201f6b8fcbfb6c4c86b697bda3a030499beea65d70e285d7"

fallos=0
ok()    { echo "[OK]     $1"; }
mal()   { echo "[ERROR]  $1"; fallos=$((fallos + 1)); }
aviso() { echo "[AVISO]  $1"; }

if [ ! -r "$STK" ]; then
    echo "[ERROR] No se encuentra $STK"
    exit 1
fi

TODOS=("$STK")
for lib in "$UI_LIB" "$MENU_LIB"; do
    if [ -r "$lib" ]; then
        TODOS+=("$lib")
    else
        mal "No se encuentra $(basename "$lib")"
    fi
done

# 1. Sintaxis de todos los archivos
for f in "${TODOS[@]}" "$REF"; do
    if bash -n "$f" 2>/dev/null; then
        ok "bash -n $(basename "$f")"
    else
        mal "bash -n $(basename "$f")"
    fi
done

# 2. stk2.sh intacto
if [ -r "$REF" ]; then
    actual=$(sha256sum "$REF" | awk '{print $1}')
    if [ "$actual" = "$HASH_REF" ]; then
        ok "stk2.sh intacto"
    else
        mal "stk2.sh ha cambiado (hash $actual)"
    fi
fi

# 3. Funciones: ninguna original perdida y sin duplicados en el conjunto
if [ -r "$REF" ]; then
    ref_funcs=$(grep -oE '^[A-Za-z_][A-Za-z0-9_]*\(\)' "$REF" | sort)
    stk_funcs=$(cat "${TODOS[@]}" | grep -oE '^[A-Za-z_][A-Za-z0-9_]*\(\)' | sort)
    perdidas=$(comm -23 <(echo "$ref_funcs") <(echo "$stk_funcs"))
    if [ -z "$perdidas" ]; then
        ok "funciones originales presentes ($(echo "$ref_funcs" | wc -l)/$(echo "$ref_funcs" | wc -l))"
    else
        mal "faltan funciones: $(echo "$perdidas" | tr '\n' ' ')"
    fi
    dup=$(echo "$stk_funcs" | uniq -d)
    [ -z "$dup" ] && ok "sin funciones duplicadas" || mal "funciones duplicadas: $dup"
    echo "[INFO]   total de funciones: $(echo "$stk_funcs" | wc -l)"
fi

# 4. Estructura de bloques (solo en stk.sh)
bloques=$(grep -cE '^# [1-5]\. ' "$STK")
[ "$bloques" -eq 5 ] && ok "5 bloques principales" || mal "bloques principales: $bloques (esperados 5)"
grep -q '^# 5\.4 Arranque' "$STK" && ok "sección 5.4 Arranque" || mal "falta la sección 5.4 Arranque"

# 5. Huecos excesivos y comentarios huérfanos en todos los archivos
huecos=$(awk 'FNR==1{b=0} NF==0 {if(!abierto){ini=FNR; abierto=1}; next} abierto {if(FNR-ini>=3) print FILENAME ":" ini "-" FNR-1; abierto=0}' "${TODOS[@]}")
[ -z "$huecos" ] && ok "sin tramos de 3+ líneas vacías" || mal "huecos excesivos: $huecos"

huerfanos=$(awk '
    FNR==1 {comentario_anterior=0; vacios=0}
    /^[[:space:]]*#/ {
        if (vacios >= 2 && comentario_anterior) print FILENAME ":" FNR-1
        comentario_anterior=1; vacios=0; next
    }
    NF==0 {vacios++; next}
    {comentario_anterior=0; vacios=0}
' "${TODOS[@]}")
[ -z "$huerfanos" ] && ok "sin comentarios huérfanos" || mal "comentarios huérfanos en: $huerfanos"

# 6. Estilo de menús y selector en todos los archivos
sin_arrow=$(grep -nHE '[0-9]+\. +Volver' "${TODOS[@]}")
[ -z "$sin_arrow" ] && ok "todas las opciones 'Volver' usan ↩" || mal "opciones 'Volver' sin arrow: $sin_arrow"

directo=$(grep -nHE '^[[:space:]]*[^#]*\|[[:space:]]*fzf([[:space:]]|$)|^[[:space:]]*fzf[[:space:]]' "${TODOS[@]}" | grep -v 'stk_fzf')
[ -z "$directo" ] && ok "ninguna llamada directa a fzf" || mal "llamadas directas a fzf: $directo"

# 7. Estilo defensivo
seteo=$(grep -nHE '^set -[eu]' "${TODOS[@]}")
[ -z "$seteo" ] && ok "sin set -e/set -u" || mal "set -e/set -u detectado: $seteo"

# 8. Scripts externos que consumen la capa de UI compartida
EXTERNOS=("$DIR/dash4me.sh" "$DIR/stop4me.sh" "$DIR/stk_cron.sh")
MINIMOS=(11 20 29)
for i in 0 1 2; do
    f="${EXTERNOS[$i]}"
    nombre=$(basename "$f")
    if [ ! -r "$f" ]; then
        mal "No se encuentra $nombre"
        continue
    fi
    if bash -n "$f" 2>/dev/null; then
        ok "bash -n $nombre"
    else
        mal "bash -n $nombre"
    fi
    total=$(grep -cE '^[A-Za-z_][A-Za-z0-9_]*\(\)' "$f")
    if [ "$total" -ge "${MINIMOS[$i]}" ]; then
        ok "$nombre conserva sus funciones ($total)"
    else
        mal "$nombre tiene $total funciones (mínimo ${MINIMOS[$i]})"
    fi
    dup=$(grep -oE '^[A-Za-z_][A-Za-z0-9_]*\(\)' "$f" | sort | uniq -d)
    [ -z "$dup" ] && ok "$nombre sin funciones duplicadas" || mal "$nombre duplica: $dup"
done

lib_funcs=$(grep -oE '^[A-Za-z_][A-Za-z0-9_]*\(\)' "$UI_LIB" | sort)
for f in "${EXTERNOS[@]}"; do
    colisiones=$(comm -12 <(echo "$lib_funcs") \
                          <(grep -oE '^[A-Za-z_][A-Za-z0-9_]*\(\)' "$f" | sort))
    [ -z "$colisiones" ] && ok "$(basename "$f") sin colisiones con la UI" \
                         || aviso "$(basename "$f") redefine: $(echo "$colisiones" | tr '\n' ' ')"
done

# Informativo: whitespace heredado de stk2.sh
finales=$(cat "${TODOS[@]}" | grep -c '[[:blank:]]$')
aviso "líneas con espacio final (heredadas): $finales"

echo ""
if [ "$fallos" -eq 0 ]; then
    echo "RESULTADO: OK — stk.sh y sus librerías cumplen el contrato de estilo."
    exit 0
fi
echo "RESULTADO: $fallos fallo(s)."
exit 1
