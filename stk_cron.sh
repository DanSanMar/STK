#!/bin/bash
# ==============================================================================
#                 GESTOR DE TAREAS AUTOMATIZADAS (CRON)
# ==============================================================================
# STK - Módulo de programación automática de tareas
# Versión: 2.0 (Flujo guiado por pasos: 1. Tarea -> 2. Período)
# ==============================================================================

# --- DETECCIÓN DE DIRECTORIO Y CARGA DE CONFIGURACIÓN ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
STK2_SCRIPT="$SCRIPT_DIR/stk2.sh"

# Verificar que existe stk2.sh
if [ ! -f "$STK2_SCRIPT" ]; then
    echo -e "\033[91m❌ Error: No se encuentra stk2.sh en el mismo directorio\033[0m"
    echo -e "\033[33mEjecuta este script desde el directorio donde está stk2.sh\033[0m"
    exit 1
fi

# Definir colores propios
RESET='\e[0m'
VERDE_BRILLANTE='\e[92m'
VERDE='\e[32m'
AMARILLO='\e[33m'
AZUL='\e[34m'
CIAN='\e[36m'
MAGENTA='\e[35m'
ROJO='\e[31m'
ROJO_BRILLANTE='\e[91m'
AZUL_BRILLANTE='\e[94m'
BLANCO='\e[97m'

# Definir función pintar propia
pintar() { 
    local COLOR="$1" 
    local MENSAJE="$2" 
    echo -e "${COLOR}${MENSAJE}${RESET}"
}

# Definir mostrar_logo
mostrar_logo() {
    echo -e "${CIAN}  ██████  ████████ ██   ██${RESET}"
    echo -e "${AZUL_BRILLANTE}  ██         ██    ██  ██ ${RESET}"
    echo -e "${AZUL}  ██████     ██    █████  ${RESET}"
    echo -e "${AZUL}       ██    ██    ██  ██ ${RESET}"
    echo -e "${AZUL_BRILLANTE}  ██████     ██    ██   ██${RESET}"
    echo -e "${VERDE_BRILLANTE}  CRON TASK MANAGER v2.0${RESET}"
    echo -e "${CIAN}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
}

# Definir fzf_estilo
fzf_estilo() {
    local prompt_text="$1"
    local header_text="$2"
    fzf --ansi \
        --height=15 \
        --reverse \
        --border=rounded \
        --prompt="➤ $prompt_text: " \
        --header="$header_text" \
        --color="border:#00ffff,pointer:#92ff92,header:#5fb2ff"
}

# --- CONFIGURACIÓN ---
CRON_CONFIG_DIR="/etc/stk/cron"
CRON_CONFIG_FILE="$CRON_CONFIG_DIR/tasks.json"
CRON_LOG_FILE="/var/log/stk_cron.log"
CRON_RESUMEN_FILE="/var/log/stk_cron_resumen.log"
CRON_STK_ID="# STK-AUTO-MAINTENANCE"
STK_AUTO_WRAPPER="/usr/local/bin/stk_auto_wrapper.sh"

# --- DECLARACIÓN DE TAREAS DISPONIBLES ---
declare -A TAREAS_DISPONIBLES=(
    ["actualizacion"]="🔄 Actualizar sistema"
    ["limpieza"]="🧹 Limpiar sistema"
    ["auditoria"]="🔍 Auditoría de seguridad"
    ["servicios"]="📊 Reporte de servicios"
    ["ufw"]="🛡️ Auditoría UFW"
)

declare -a TAREAS_SELECCIONADAS=()

# ============================================================================
#                   FUNCIONES DE INICIALIZACIÓN
# ============================================================================

inicializar_estructura() {
    if [ ! -d "$CRON_CONFIG_DIR" ]; then
        mkdir -p "$CRON_CONFIG_DIR"
        chmod 755 "$CRON_CONFIG_DIR"
    fi
    
    if [ ! -f "$CRON_CONFIG_FILE" ]; then
        cat > "$CRON_CONFIG_FILE" << 'EOF'
{
    "version": "1.0",
    "configuracion": {
        "schedule": null,
        "descripcion": null,
        "activado": false,
        "fecha_activacion": null,
        "ultima_ejecucion": null
    },
    "tareas": []
}
EOF
        chmod 600 "$CRON_CONFIG_FILE"
    fi
    
    for log in "$CRON_LOG_FILE" "$CRON_RESUMEN_FILE"; do
        if [ ! -f "$log" ]; then
            touch "$log"
            chmod 640 "$log"
        fi
    done
    
    crear_wrapper_cron
}

# ============================================================================
#                   FUNCIONES DE LOG Y WRAPPER
# ============================================================================

log_cron() {
    local NIVEL="${1:-INFO}"
    local MENSAJE="${2}"
    local FECHA=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$FECHA] [$NIVEL] [root] - $MENSAJE" >> "$CRON_LOG_FILE"
    if declare -f registrar_log >/dev/null 2>&1; then
        registrar_log "$NIVEL" "[CRON] $MENSAJE"
    fi
}

crear_wrapper_cron() {
    cat << 'EOF' > "$STK_AUTO_WRAPPER"
#!/bin/bash
# STK - Wrapper para tareas automáticas CRON
# Generado automáticamente - No modificar manualmente
# ==============================================================================

export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export HOME="/root"
export TERM="linux"

CRON_CONFIG_FILE="/etc/stk/cron/tasks.json"
CRON_LOG_FILE="/var/log/stk_cron.log"
CRON_RESUMEN_FILE="/var/log/stk_cron_resumen.log"

STK_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ ! -f "$STK_DIR/stk2.sh" ]; then
    for dir in "/opt/STK" "/usr/local/STK" "$HOME/STK"; do
        if [ -f "$dir/stk2.sh" ]; then
            STK_DIR="$dir"
            break
        fi
    done
fi

if [ ! -f "$STK_DIR/stk2.sh" ]; then
    echo "[$(date)] [ERROR] - No se encuentra stk2.sh" >> "$CRON_LOG_FILE"
    exit 1
fi

cd "$STK_DIR"

if [ ! -f "$CRON_CONFIG_FILE" ]; then
    echo "[$(date)] [ERROR] - No hay configuración de tareas" >> "$CRON_LOG_FILE"
    exit 1
fi

if command -v jq &>/dev/null; then
    TAREAS=$(jq -r ".tareas[] | .id" "$CRON_CONFIG_FILE" 2>/dev/null | tr "\n" " ")
else
    TAREAS=$(grep -o "\"id\":\"[^\"]*\"" "$CRON_CONFIG_FILE" 2>/dev/null | cut -d'"' -f4 | tr "\n" " ")
fi

if [ -z "$TAREAS" ]; then
    echo "[$(date)] [ERROR] - No hay tareas configuradas" >> "$CRON_LOG_FILE"
    exit 1
fi

FECHA_INICIO=$(date "+%Y-%m-%d %H:%M:%S")
T_INICIO=$(date +%s)
RESULTADOS=()
TAREAS_EJECUTADAS=()

echo "" >> "$CRON_LOG_FILE"
echo "[$(date)] [INFO] ═══════════════════════════════════════════" >> "$CRON_LOG_FILE"
echo "[$(date)] [INFO] 🚀 INICIO EJECUCIÓN AUTOMÁTICA" >> "$CRON_LOG_FILE"
echo "[$(date)] [INFO] 📋 Tareas: $TAREAS" >> "$CRON_LOG_FILE"
echo "[$(date)] [INFO] ═══════════════════════════════════════════" >> "$CRON_LOG_FILE"

for tarea in $TAREAS; do
    TAREAS_EJECUTADAS+=("$tarea")
    echo "[$(date)] [INFO] ▶ Ejecutando: $tarea" >> "$CRON_LOG_FILE"
    
    LOG_TEMP=$(mktemp)
    
    case "$tarea" in
        "actualizacion")
            bash "$STK_DIR/stk2.sh" --auto-actualizacion > "$LOG_TEMP" 2>&1
            if [ $? -eq 0 ]; then
                RESULTADOS+=("✅ ACTUALIZACIÓN: Completada")
                echo "[$(date)] [INFO] ✅ Actualización exitosa" >> "$CRON_LOG_FILE"
            else
                RESULTADOS+=("❌ ACTUALIZACIÓN: Falló")
                echo "[$(date)] [ERROR] ❌ Actualización falló" >> "$CRON_LOG_FILE"
            fi
            ;;
        "limpieza")
            bash "$STK_DIR/stk2.sh" --auto-limpieza > "$LOG_TEMP" 2>&1
            if [ $? -eq 0 ]; then
                RESULTADOS+=("✅ LIMPIEZA: Completada")
                echo "[$(date)] [INFO] ✅ Limpieza exitosa" >> "$CRON_LOG_FILE"
            else
                RESULTADOS+=("❌ LIMPIEZA: Falló")
                echo "[$(date)] [ERROR] ❌ Limpieza falló" >> "$CRON_LOG_FILE"
            fi
            ;;
        "auditoria")
            bash "$STK_DIR/stk2.sh" --auto-auditoria > "$LOG_TEMP" 2>&1
            if [ $? -eq 0 ]; then
                RESULTADOS+=("✅ AUDITORÍA: Completada")
                echo "[$(date)] [INFO] ✅ Auditoría exitosa" >> "$CRON_LOG_FILE"
            else
                RESULTADOS+=("❌ AUDITORÍA: Falló")
                echo "[$(date)] [ERROR] ❌ Auditoría falló" >> "$CRON_LOG_FILE"
            fi
            ;;
        "servicios")
            bash "$STK_DIR/stk2.sh" --auto-servicios > "$LOG_TEMP" 2>&1
            if [ $? -eq 0 ]; then
                RESULTADOS+=("✅ SERVICIOS: Reporte generado")
                echo "[$(date)] [INFO] ✅ Reporte de servicios generado" >> "$CRON_LOG_FILE"
            else
                RESULTADOS+=("❌ SERVICIOS: Falló")
                echo "[$(date)] [ERROR] ❌ Reporte de servicios falló" >> "$CRON_LOG_FILE"
            fi
            ;;
        "ufw")
            bash "$STK_DIR/stk2.sh" --auto-ufw > "$LOG_TEMP" 2>&1
            if [ $? -eq 0 ]; then
                RESULTADOS+=("✅ UFW: Auditoría completada")
                echo "[$(date)] [INFO] ✅ Auditoría UFW exitosa" >> "$CRON_LOG_FILE"
            else
                RESULTADOS+=("❌ UFW: Falló")
                echo "[$(date)] [ERROR] ❌ Auditoría UFW falló" >> "$CRON_LOG_FILE"
            fi
            ;;
        *)
            RESULTADOS+=("❌ TAREA DESCONOCIDA: $tarea")
            echo "[$(date)] [ERROR] ❌ Tarea desconocida: $tarea" >> "$CRON_LOG_FILE"
            ;;
    esac
    
    if [ -s "$LOG_TEMP" ]; then
        cat "$LOG_TEMP" >> "/var/log/stk_cron_${tarea}.log" 2>/dev/null
    fi
    rm -f "$LOG_TEMP"
done

T_FIN=$(date +%s)
DURACION=$((T_FIN - T_INICIO))

echo "[$(date)] [INFO] ═══════════════════════════════════════════" >> "$CRON_LOG_FILE"
echo "[$(date)] [INFO] 📊 RESUMEN FINAL" >> "$CRON_LOG_FILE"
echo "[$(date)] [INFO] ⏱️  Tiempo: ${DURACION}s" >> "$CRON_LOG_FILE"
for resultado in "${RESULTADOS[@]}"; do
    echo "[$(date)] [INFO]    $resultado" >> "$CRON_LOG_FILE"
done
echo "[$(date)] [INFO] 🏁 FIN EJECUCIÓN" >> "$CRON_LOG_FILE"
echo "[$(date)] [INFO] ═══════════════════════════════════════════" >> "$CRON_LOG_FILE"

{
    echo "═══════════════════════════════════════════════════════════════"
    echo "📊 RESUMEN EJECUCIÓN - $(date "+%Y-%m-%d %H:%M:%S")"
    echo "═══════════════════════════════════════════════════════════════"
    echo "⏱️  Duración: ${DURACION} segundos"
    echo "📋 Tareas: ${#RESULTADOS[@]}"
    echo ""
    for resultado in "${RESULTADOS[@]}"; do
        echo "  $resultado"
    done
    echo "═══════════════════════════════════════════════════════════════"
} >> "$CRON_RESUMEN_FILE"

if command -v jq &>/dev/null && [ -f "$CRON_CONFIG_FILE" ]; then
    tmp_json=$(mktemp)
    jq --arg fecha "$(date "+%Y-%m-%d %H:%M:%S")" ".configuracion.ultima_ejecucion = \$fecha" "$CRON_CONFIG_FILE" > "$tmp_json" 2>/dev/null
    if [ $? -eq 0 ]; then
        mv "$tmp_json" "$CRON_CONFIG_FILE"
        chmod 600 "$CRON_CONFIG_FILE"
    else
        rm -f "$tmp_json"
    fi
fi

exit 0
EOF

    chmod +x "$STK_AUTO_WRAPPER"
    log_cron "INFO" "Wrapper CRON creado: $STK_AUTO_WRAPPER"
}

# ============================================================================
#                   FUNCIONES DE CONSULTA DE ESTADO
# ============================================================================

verificar_cron_stk() {
    crontab -l 2>/dev/null | grep -q "$CRON_STK_ID"
}

obtener_frecuencia_descripcion() {
    if [ -f "$CRON_CONFIG_FILE" ]; then
        if command -v jq &>/dev/null; then
            jq -r '.configuracion.descripcion // "No configurada"' "$CRON_CONFIG_FILE" 2>/dev/null || echo "No configurada"
        else
            grep -oP '"descripcion":\s*"\K[^"]+' "$CRON_CONFIG_FILE" 2>/dev/null || echo "No configurada"
        fi
    else
        echo "No configurada"
    fi
}

obtener_tareas_configuradas() {
    if [ -f "$CRON_CONFIG_FILE" ]; then
        if command -v jq &>/dev/null; then
            jq -r '.tareas[] | .descripcion' "$CRON_CONFIG_FILE" 2>/dev/null | tr '\n' ', ' | sed 's/, $//' || echo "Ninguna"
        else
            grep -oP '"descripcion":\s*"\K[^"]+' "$CRON_CONFIG_FILE" 2>/dev/null | tr '\n' ', ' | sed 's/, $//' || echo "Ninguna"
        fi
    else
        echo "Ninguna"
    fi
}

obtener_ultima_ejecucion() {
    if [ -f "$CRON_LOG_FILE" ]; then
        local ultima_linea
        ultima_linea=$(grep -E "INICIO|FIN" "$CRON_LOG_FILE" 2>/dev/null | tail -1)
        if [ -n "$ultima_linea" ]; then
            echo "$ultima_linea" | sed 's/^\[//' | cut -d']' -f1
        else
            echo "Sin registros"
        fi
    else
        echo "Sin registros"
    fi
}

# ============================================================================
#             NUEVO FLUJO GUIADO SECUENCIAL (TAREA -> FRECUENCIA)
# ============================================================================

programar_nueva_tarea() {
    TAREAS_SELECCIONADAS=()
    
    # ------------------------------------------------------------------------
    # PASO 1: SELECCIÓN DE TAREAS
    # ------------------------------------------------------------------------
    clear
    mostrar_logo
    echo ""
    pintar "$CIAN" "--- PASO 1: SELECCIONAR LA TAREA A PROGRAMAR ---"
    echo ""

    local opciones_p1="1. Modo Completo (Todas las tareas)
2. Actualización del sistema
3. Limpieza del sistema
4. Auditoría de seguridad
5. Reporte de servicios
6. Auditoría UFW
7. Selección Múltiple Personalizada
8. Cancelar"

    local opc_p1=""
    if command -v fzf &>/dev/null; then
        local sel
        sel=$(echo -e "$opciones_p1" | fzf_estilo "Paso 1/2: Elija la tarea" "PASO 1: SELECCIÓN DE TAREA")
        [ -z "$sel" ] && return
        opc_p1=$(echo "$sel" | awk -F'.' '{print $1}' | tr -d ' ')
    else
        echo -e "$opciones_p1"
        echo ""
        echo -ne "${AMARILLO}Seleccione opción (1-8): ${RESET}"
        read -r opc_p1
    fi

    case "$opc_p1" in
        1)
            for key in "${!TAREAS_DISPONIBLES[@]}"; do
                TAREAS_SELECCIONADAS+=("$key:${TAREAS_DISPONIBLES[$key]}")
            done
            ;;
        2) TAREAS_SELECCIONADAS+=("actualizacion:${TAREAS_DISPONIBLES[actualizacion]}") ;;
        3) TAREAS_SELECCIONADAS+=("limpieza:${TAREAS_DISPONIBLES[limpieza]}") ;;
        4) TAREAS_SELECCIONADAS+=("auditoria:${TAREAS_DISPONIBLES[auditoria]}") ;;
        5) TAREAS_SELECCIONADAS+=("servicios:${TAREAS_DISPONIBLES[servicios]}") ;;
        6) TAREAS_SELECCIONADAS+=("ufw:${TAREAS_DISPONIBLES[ufw]}") ;;
        7)
            local fzf_input=""
            for key in "${!TAREAS_DISPONIBLES[@]}"; do
                fzf_input+="$key: ${TAREAS_DISPONIBLES[$key]}\n"
            done

            if ! command -v fzf &>/dev/null; then
                for key in "${!TAREAS_DISPONIBLES[@]}"; do
                    echo -e "${CIAN}${key}${RESET}: ${TAREAS_DISPONIBLES[$key]}"
                done
                echo -ne "${AMARILLO}IDs separados por espacio: ${RESET}"
                read -r tareas_input
                IFS=' ' read -ra tareas_array <<< "$tareas_input"
                for t_id in "${tareas_array[@]}"; do
                    if [[ -n "${TAREAS_DISPONIBLES[$t_id]}" ]]; then
                        TAREAS_SELECCIONADAS+=("$t_id:${TAREAS_DISPONIBLES[$t_id]}")
                    fi
                done
            else
                local seleccionadas
                seleccionadas=$(echo -e -n "$fzf_input" | fzf --ansi --height=18 --reverse --border=rounded \
                    --prompt="➤ Usa TAB para marcar varias: " \
                    --header="SELECCIONAR MÚLTIPLES (TAB + ENTER)" --multi)
                
                [ -z "$seleccionadas" ] && return
                
                while IFS= read -r line; do
                    [ -z "$line" ] && continue
                    local t_id=$(echo "$line" | cut -d':' -f1 | tr -d ' ')
                    if [[ -n "${TAREAS_DISPONIBLES[$t_id]}" ]]; then
                        TAREAS_SELECCIONADAS+=("$t_id:${TAREAS_DISPONIBLES[$t_id]}")
                    fi
                done <<< "$seleccionadas"
            fi
            ;;
        *) return ;;
    esac

    if [ ${#TAREAS_SELECCIONADAS[@]} -eq 0 ]; then
        pintar "$ROJO" "❌ No se seleccionó ninguna tarea."
        sleep 2
        return
    fi

    # ------------------------------------------------------------------------
    # PASO 2: SELECCIÓN DE FRECUENCIA / PERÍODO
    # ------------------------------------------------------------------------
    clear
    mostrar_logo
    echo ""
    pintar "$CIAN" "--- PASO 2: SELECCIONAR EL PERÍODO / FRECUENCIA ---"
    echo ""
    pintar "$VERDE_BRILLANTE" "Tareas seleccionadas para programar:"
    for tarea in "${TAREAS_SELECCIONADAS[@]}"; do
        echo -e "   ${VERDE}•${RESET} ${tarea#*:}"
    done
    echo ""

    local opciones_p2="1. Al iniciar el sistema (Boot)
2. Diaria (Hora configurable)
3. Semanal (Día y Hora configurable)
4. Personalizada (Sintaxis Cron libre)
5. Cancelar"

    local opc_p2=""
    if command -v fzf &>/dev/null; then
        local sel2
        sel2=$(echo -e "$opciones_p2" | fzf_estilo "Paso 2/2: Elija período" "PASO 2: CONFIGURAR FRECUENCIA")
        [ -z "$sel2" ] && return
        opc_p2=$(echo "$sel2" | awk -F'.' '{print $1}' | tr -d ' ')
    else
        echo -e "$opciones_p2"
        echo ""
        echo -ne "${AMARILLO}Seleccione frecuencia (1-5): ${RESET}"
        read -r opc_p2
    fi

    local cron_line=""
    local descripcion_freq=""

    case "$opc_p2" in
        1)
            cron_line="@reboot sleep 300"
            descripcion_freq="Al iniciar el sistema"
            ;;
        2)
            echo -ne "${CIAN}Ingrese la hora 0-23 [3]: ${RESET}"
            read -r hora
            hora=${hora:-3}
            if [[ ! "$hora" =~ ^[0-9]+$ ]] || [ "$hora" -lt 0 ] || [ "$hora" -gt 23 ]; then
                hora=3
            fi
            cron_line="0 $hora * * *"
            descripcion_freq="Diaria a las ${hora}:00"
            ;;
        3)
            echo -e "${CIAN}Días: 0=Dom, 1=Lun, 2=Mar, 3=Mié, 4=Jue, 5=Vie, 6=Sáb${RESET}"
            echo -ne "${CIAN}Ingrese el día 0-6 [1]: ${RESET}"
            read -r dia
            dia=${dia:-1}
            [[ ! "$dia" =~ ^[0-6]$ ]] && dia=1
            echo -ne "${CIAN}Ingrese la hora 0-23 [3]: ${RESET}"
            read -r hora
            hora=${hora:-3}
            if [[ ! "$hora" =~ ^[0-9]+$ ]] || [ "$hora" -lt 0 ] || [ "$hora" -gt 23 ]; then
                hora=3
            fi
            cron_line="0 $hora * * $dia"
            descripcion_freq="Semanal día $dia a las ${hora}:00"
            ;;
        4)
            echo -e "${CIAN}Formato: Minuto Hora Día Mes DíaSemana (Ej: 0 12 * * *)${RESET}"
            echo -ne "${AMARILLO}Ingrese expresión Cron: ${RESET}"
            read -r custom_schedule
            if [ -z "$custom_schedule" ]; then
                pintar "$ROJO" "❌ Formato vacío. Operación cancelada."
                sleep 2
                return
            fi
            cron_line="$custom_schedule"
            descripcion_freq="Personalizado: $custom_schedule"
            ;;
        *) return ;;
    esac

    # ------------------------------------------------------------------------
    # CONFIRMACIÓN Y ACTIVACIÓN
    # ------------------------------------------------------------------------
    echo ""
    pintar "$CIAN" "═══════════════════════════════════════════════"
    pintar "$VERDE_BRILLANTE" "📋 CONFIRMACIÓN DE RESUMEN"
    pintar "$CIAN" "═══════════════════════════════════════════════"
    echo -e "${AMARILLO}Frecuencia:${RESET} ${AZUL}$descripcion_freq${RESET}"
    echo -e "${AMARILLO}Schedule:${RESET}   ${AZUL}$cron_line${RESET}"
    echo -e "${AMARILLO}Tareas:${RESET}"
    for tarea in "${TAREAS_SELECCIONADAS[@]}"; do
        echo -e "   ${VERDE}•${RESET} ${tarea#*:}"
    done
    echo ""
    echo -ne "${ROJO_BRILLANTE}¿Confirmar y programar en CRON? s/N: ${RESET}"
    read -r confirm

    if [[ "$confirm" =~ ^[sS]$ ]]; then
        activar_tarea_cron "$cron_line" "$descripcion_freq"
    else
        pintar "$AZUL" "Operación cancelada."
        read -p "Presione Enter..."
    fi
}

guardar_configuracion_cron() {
    local cron_line="$1"
    local descripcion="$2"
    shift 2
    local tareas=("$@")

    # Construir el array JSON con las nuevas tareas seleccionadas
    local json_nuevas_tareas="["
    for i in "${!tareas[@]}"; do
        local tarea_id="${tareas[$i]%%:*}"
        local tarea_desc="${tareas[$i]#*:}"
        
        if [ $i -gt 0 ]; then json_nuevas_tareas+=","; fi
        json_nuevas_tareas+="{\"id\":\"$tarea_id\",\"descripcion\":\"$tarea_desc\"}"
    done
    json_nuevas_tareas+="]"

    # Si el archivo JSON ya existe y contiene jq, fusionamos las tareas evitando duplicados por ID
    if [ -f "$CRON_CONFIG_FILE" ] && command -v jq &>/dev/null; then
        local tmp_json
        tmp_json=$(mktemp)
        
        jq --arg schedule "$cron_line" \
           --arg desc "$descripcion" \
           --arg fecha "$(date '+%Y-%m-%d %H:%M:%S')" \
           --argjson nuevas "$json_nuevas_tareas" \
           '.configuracion.schedule = $schedule |
            .configuracion.descripcion = $desc |
            .configuracion.activado = true |
            .configuracion.fecha_activacion = $fecha |
            .tareas = ( (.tareas + $nuevas) | unique_by(.id) )' \
           "$CRON_CONFIG_FILE" > "$tmp_json" 2>/dev/null

        if [ $? -eq 0 ]; then
            mv "$tmp_json" "$CRON_CONFIG_FILE"
            chmod 600 "$CRON_CONFIG_FILE"
            log_cron "INFO" "Configuración actualizada y fusionada: $descripcion ($cron_line)"
            return 0
        else
            rm -f "$tmp_json"
        fi
    fi

    # Respaldo fallback (creación inicial si el archivo no existía)
    cat > "$CRON_CONFIG_FILE" << EOF
{
    "version": "1.0",
    "configuracion": {
        "schedule": "$cron_line",
        "descripcion": "$descripcion",
        "activado": true,
        "fecha_activacion": "$(date '+%Y-%m-%d %H:%M:%S')",
        "ultima_ejecucion": "Pendiente"
    },
    "tareas": $json_nuevas_tareas
}
EOF
    chmod 600 "$CRON_CONFIG_FILE"
    log_cron "INFO" "Configuración guardada: $descripcion ($cron_line)"
}

activar_tarea_cron() {
    local cron_line="$1"
    local descripcion="$2"

    if [ ! -f "$STK_AUTO_WRAPPER" ]; then
        crear_wrapper_cron
    fi

    guardar_configuracion_cron "$cron_line" "$descripcion" "${TAREAS_SELECCIONADAS[@]}"

    local cron_full="$cron_line $STK_AUTO_WRAPPER"

    crontab -l 2>/dev/null | grep -v "$CRON_STK_ID" | crontab -
    (crontab -l 2>/dev/null; echo "$cron_full $CRON_STK_ID") | crontab -

    if [ $? -eq 0 ]; then
        log_cron "INFO" "Tarea CRON activada: $descripcion ($cron_line)"
        
        # Recuperar todas las tareas acumuladas para mostrarlas correctamente en el resumen
        if command -v jq &>/dev/null && [ -f "$CRON_CONFIG_FILE" ]; then
            TAREAS_SELECCIONADAS=()
            while IFS= read -r line; do
                [ -n "$line" ] && TAREAS_SELECCIONADAS+=("$line")
            done < <(jq -r '.tareas[] | .id + ":" + .descripcion' "$CRON_CONFIG_FILE" 2>/dev/null)
        fi

        mostrar_resumen_final "$cron_line" "$descripcion"
    else
        pintar "$ROJO" "❌ Error al activar la tarea automática."
        log_cron "ERROR" "Error al activar CRON"
        read -p "Presione Enter..."
    fi
}
# ============================================================================
#                 NUEVAS FUNCIONES DE EDICIÓN Y ELIMINACIÓN
# ============================================================================

eliminar_tarea_especifica() {
    local id_a_eliminar="$1"

    if [ ! -f "$CRON_CONFIG_FILE" ] || ! command -v jq &>/dev/null; then
        pintar "$ROJO" "❌ Se requiere 'jq' y un archivo de configuración válido."
        read -p "Presione Enter..."
        return 1
    fi

    # Contar cuántas tareas quedarán
    local total_restantes
    total_restantes=$(jq --arg id "$id_a_eliminar" '[.tareas[] | select(.id != $id)] | length' "$CRON_CONFIG_FILE")

    local tmp_json=$(mktemp)

    if [ "$total_restantes" -eq 0 ]; then
        # Si no quedan tareas, desactivamos el CRON completamente
        crontab -l 2>/dev/null | grep -v "$CRON_STK_ID" | crontab -
        jq --arg id "$id_a_eliminar" \
           '.tareas = [] | .configuracion.activado = false' \
           "$CRON_CONFIG_FILE" > "$tmp_json"
        
        pintar "$AMARILLO" "⚠️ Al no quedar tareas, el programador automátiico se ha desactivado."
    else
        # Eliminar solo la tarea seleccionada manteniendo la configuración de cron
        jq --arg id "$id_a_eliminar" \
           '.tareas = [.tareas[] | select(.id != $id)]' \
           "$CRON_CONFIG_FILE" > "$tmp_json"
    fi

    if [ $? -eq 0 ]; then
        mv "$tmp_json" "$CRON_CONFIG_FILE"
        chmod 600 "$CRON_CONFIG_FILE"
        log_cron "INFO" "Tarea eliminada individualmente: $id_a_eliminar"
        pintar "$VERDE_BRILLANTE" "✔ Tarea '$id_a_eliminar' eliminada correctamente."
    else
        rm -f "$tmp_json"
        pintar "$ROJO" "❌ Error al actualizar el archivo JSON."
    fi
    sleep 2
}

gestionar_tareas_individuales() {
    while true; do
        clear
        mostrar_logo
        echo ""
        pintar "$CIAN" "--- GESTIÓN INDIVIDUAL DE TAREAS ---"
        echo ""

        if [ ! -f "$CRON_CONFIG_FILE" ] || ! command -v jq &>/dev/null; then
            pintar "$ROJO" "❌ No hay configuración activa o falta la herramienta 'jq'."
            read -p "Presione Enter..."
            return
        fi

        # Extraer tareas actuales en formato clave:valor
        local tareas_raw
        tareas_raw=$(jq -r '.tareas[] | .id + ":" + .descripcion' "$CRON_CONFIG_FILE" 2>/dev/null)

        if [ -z "$tareas_raw" ]; then
            pintar "$AMARILLO" "⚠️ No hay tareas activas en la lista."
            read -p "Presione Enter..."
            return
        fi

        echo -e "${AMARILLO}Seleccione una tarea para administrar:${RESET}"
        echo ""

        local lista_opciones=""
        local i=1
        declare -A mapa_tareas

        while IFS= read -r linea; do
            [ -z "$linea" ] && continue
            local t_id="${linea%%:*}"
            local t_desc="${linea#*:}"
            mapa_tareas[$i]="$t_id:$t_desc"
            lista_opciones+="$i. $t_desc ($t_id)\n"
            ((i++))
        done <<< "$tareas_raw"

        lista_opciones+="$i. Volver"

        local seleccion=""
        if command -v fzf &>/dev/null; then
            local sel
            sel=$(echo -e "$lista_opciones" | fzf_estilo "Seleccione Tarea" "TAREAS ACTIVAS")
            [ -z "$sel" ] && break
            seleccion=$(echo "$sel" | awk -F'.' '{print $1}' | tr -d ' ')
        else
            echo -e "$lista_opciones"
            echo ""
            echo -ne "${AMARILLO}Opción (1-$i): ${RESET}"
            read -r seleccion
        fi

        if [ "$seleccion" -eq "$i" ] || [ -z "$seleccion" ]; then
            break
        fi

        local tarea_elegida="${mapa_tareas[$seleccion]}"
        local sel_id="${tarea_elegida%%:*}"
        local sel_desc="${tarea_elegida#*:}"

        # Submenú de acción para la tarea seleccionada
        clear
        mostrar_logo
        echo ""
        pintar "$VERDE_BRILLANTE" "Tarea: $sel_desc ($sel_id)"
        echo ""
        echo -e "1. 🗑️ Eliminar esta tarea"
        echo -e "2. ↩ Volver"
        echo ""
        echo -ne "${AMARILLO}Seleccione acción: ${RESET}"
        read -r accion

        case "$accion" in
            1)
                echo -ne "${ROJO_BRILLANTE}¿Eliminar '$sel_desc' de la programación? s/N: ${RESET}"
                read -r conf_elim
                if [[ "$conf_elim" =~ ^[sS]$ ]]; then
                    eliminar_tarea_especifica "$sel_id"
                fi
                ;;
            *) ;;
        esac
    done
}

mostrar_resumen_final() {
    local cron_line="$1"
    local descripcion="$2"
    
    clear
    echo -e "${VERDE_BRILLANTE}"
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║                                                                  ║"
    echo "║                  ✅ TAREA AUTOMÁTICA ACTIVADA                    ║"
    echo "║                                                                  ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
    echo -e "${RESET}"
    echo ""
    echo -e "${CIAN}═══════════════════════════════════════════════════════════════${RESET}"
    echo -e "${AMARILLO}📅 CONFIGURACIÓN:${RESET}"
    echo -e "   ${VERDE}•${RESET} Frecuencia: ${AZUL}$descripcion${RESET}"
    echo -e "   ${VERDE}•${RESET} Schedule:   ${AZUL}$cron_line${RESET}"
    echo ""
    echo -e "${AMARILLO}📋 TAREAS PROGRAMADAS:${RESET}"
    for tarea in "${TAREAS_SELECCIONADAS[@]}"; do
        echo -e "   ${VERDE}✓${RESET} ${tarea#*:}"
    done
    echo ""
    echo -e "${AMARILLO}📂 LOGS:${RESET}"
    echo -e "   ${VERDE}•${RESET} General:    ${AZUL}$CRON_LOG_FILE${RESET}"
    echo -e "   ${VERDE}•${RESET} Resumen:    ${AZUL}$CRON_RESUMEN_FILE${RESET}"
    echo -e "   ${VERDE}•${RESET} Config:     ${AZUL}$CRON_CONFIG_FILE${RESET}"
    echo ""
    echo -e "${CIAN}═══════════════════════════════════════════════════════════════${RESET}"
    
    read -p "Presione Enter para volver al menú..."
}

# ============================================================================
#                   FUNCIONES DE INFORMACIÓN Y GESTIÓN
# ============================================================================

ver_configuracion_cron() {
    clear
    mostrar_logo
    echo ""
    pintar "$CIAN" "--- CONFIGURACIÓN ACTUAL ---"
    echo ""
    
    if [ -f "$CRON_CONFIG_FILE" ]; then
        if command -v jq &>/dev/null; then
            local schedule=$(jq -r '.configuracion.schedule // "No definido"' "$CRON_CONFIG_FILE")
            local desc=$(jq -r '.configuracion.descripcion // "Sin descripción"' "$CRON_CONFIG_FILE")
            local activado=$(jq -r '.configuracion.activado // false' "$CRON_CONFIG_FILE")
            local fecha_act=$(jq -r '.configuracion.fecha_activacion // "N/A"' "$CRON_CONFIG_FILE")
            local ult_ejec=$(jq -r '.configuracion.ultima_ejecucion // "Nunca"' "$CRON_CONFIG_FILE")
            local total_tareas=$(jq -r '.tareas | length' "$CRON_CONFIG_FILE" 2>/dev/null || echo 0)

            if [ "$activado" == "true" ] && [ "$total_tareas" -gt 0 ]; then
                echo -e "Estado general:   ${VERDE_BRILLANTE}ACTIVO${RESET}"
            else
                echo -e "Estado general:   ${ROJO}INACTIVO${RESET}"
            fi

            echo -e "Frecuencia global:${AZUL}$desc${RESET}"
            echo -e "Cron Expression:  ${AZUL}$schedule${RESET}"
            echo -e "Activado el:      ${AZUL}$fecha_act${RESET}"
            echo -e "Última ejecución: ${AZUL}$ult_ejec${RESET}"
            echo ""
            echo -e "${AMARILLO}Tareas actualmente registradas ($total_tareas):${RESET}"
            
            if [ "$total_tareas" -gt 0 ]; then
                jq -r '.tareas[] | "  • " + .descripcion + " (ID: " + .id + ")"' "$CRON_CONFIG_FILE"
            else
                echo -e "  ${ROJO}(Ninguna tarea en la lista)${RESET}"
            fi
        else
            grep -oP '"descripcion":\s*"\K[^"]+' "$CRON_CONFIG_FILE" | sed 's/^/  • /'
        fi
    else
        pintar "$ROJO" "❌ No hay configuración activa."
    fi
    echo ""
    read -p "Presione Enter para continuar..."
}

ver_logs_cron() {
    clear
    mostrar_logo
    echo ""
    pintar "$CIAN" "--- LOGS DE EJECUCIÓN CRON ---"
    echo ""
    
    if [ -f "$CRON_LOG_FILE" ]; then
        echo -e "${AMARILLO}Últimas 30 líneas del log general:${RESET}"
        echo -e "${CIAN}═══════════════════════════════════════════════${RESET}"
        tail -n 30 "$CRON_LOG_FILE"
        echo -e "${CIAN}═══════════════════════════════════════════════${RESET}"
        echo ""
        
        echo -e "${AMARILLO}Logs específicos de tareas:${RESET}"
        for tarea in actualizacion limpieza auditoria servicios ufw; do
            local log_file="/var/log/stk_cron_${tarea}.log"
            if [ -f "$log_file" ]; then
                local size=$(du -h "$log_file" 2>/dev/null | cut -f1)
                echo -e "  ${VERDE}•${RESET} $tarea: $size"
            fi
        done
        
        echo ""
        echo -e "${AMARILLO}Tamaño total del log:${RESET} $(du -h "$CRON_LOG_FILE" | cut -f1)"
    else
        pintar "$ROJO" "❌ No hay logs de ejecución aún."
    fi
    echo ""
    read -p "Presione Enter para continuar..."
}

ver_resumen_cron() {
    clear
    mostrar_logo
    echo ""
    pintar "$CIAN" "--- RESUMEN ÚLTIMA EJECUCIÓN CRON ---"
    echo ""
    
    if [ -f "$CRON_RESUMEN_FILE" ]; then
        echo -e "${AMARILLO}Último resumen:${RESET}"
        echo -e "${CIAN}═══════════════════════════════════════════════${RESET}"
        tail -n 20 "$CRON_RESUMEN_FILE"
        echo -e "${CIAN}═══════════════════════════════════════════════${RESET}"
        echo ""
        echo -ne "${AMARILLO}¿Ver resumen completo? (s/N): ${RESET}"
        read -r ver_completo
        if [[ "$ver_completo" =~ ^[sS]$ ]]; then
            clear
            cat "$CRON_RESUMEN_FILE"
            echo ""
        fi
    else
        pintar "$ROJO" "❌ No hay resúmenes de ejecución aún."
    fi
    echo ""
    read -p "Presione Enter para continuar..."
}

desactivar_cron() {
    clear
    mostrar_logo
    echo ""
    pintar "$CIAN" "--- DESACTIVAR TAREAS AUTOMÁTICAS ---"
    echo ""

    if ! verificar_cron_stk && [ ! -f "$CRON_CONFIG_FILE" ]; then
        pintar "$AMARILLO" "⚠️ No hay tareas automáticas activas."
        read -p "Presione Enter..."
        return
    fi

    local config_actual
    config_actual=$(obtener_frecuencia_descripcion)
    echo -e "${AMARILLO}Configuración actual:${RESET} $config_actual"
    echo ""
    echo -ne "${ROJO_BRILLANTE}¿Desactivar y eliminar TODAS las tareas programadas? (s/N): ${RESET}"
    read -r confirm

    if [[ "$confirm" =~ ^[sS]$ ]]; then
        # 1. Eliminar entrada en crontab
        crontab -l 2>/dev/null | grep -v "$CRON_STK_ID" | crontab -
        
        # 2. Resetear el archivo JSON adecuadamente
        if [ -f "$CRON_CONFIG_FILE" ]; then
            if command -v jq &>/dev/null; then
                local tmp_json=$(mktemp)
                jq '.configuracion.activado = false | 
                    .configuracion.schedule = null | 
                    .configuracion.descripcion = "Ninguna" | 
                    .tareas = []' "$CRON_CONFIG_FILE" > "$tmp_json" 2>/dev/null
                
                if [ $? -eq 0 ]; then
                    mv "$tmp_json" "$CRON_CONFIG_FILE"
                    chmod 600 "$CRON_CONFIG_FILE"
                else
                    rm -f "$tmp_json"
                fi
            else
                cat > "$CRON_CONFIG_FILE" << EOF
{
    "version": "1.0",
    "configuracion": {
        "schedule": null,
        "descripcion": "Ninguna",
        "activado": false,
        "fecha_activacion": null,
        "ultima_ejecucion": null
    },
    "tareas": []
}
EOF
                chmod 600 "$CRON_CONFIG_FILE"
            fi
        fi
        
        pintar "$VERDE_BRILLANTE" "✔ Todas las tareas automáticas han sido desactivadas."
        log_cron "WARN" "Todas las tareas CRON fueron desactivadas"
    else
        pintar "$AZUL" "Operación cancelada."
    fi
    echo ""
    read -p "Presione Enter para continuar..."
}

# ============================================================================
#                   MENÚ PRINCIPAL
# ============================================================================

gestionar_tareas_auto() {
    inicializar_estructura
    
    while true; do
        clear
        mostrar_logo
        echo ""
        pintar "$MAGENTA" "═══════════════════════════════════════════════"
        pintar "$BLANCO"  "   📅 GESTOR DE TAREAS AUTOMATIZADAS (CRON)"
        pintar "$MAGENTA" "═══════════════════════════════════════════════"
        echo ""

        if verificar_cron_stk; then
            local config_actual=$(obtener_frecuencia_descripcion)
            local tareas_activas=$(obtener_tareas_configuradas)
            echo -e "${VERDE_BRILLANTE}✅ TAREA ACTIVA${RESET}"
            echo -e "   ${AMARILLO}Frecuencia:${RESET} ${AZUL}$config_actual${RESET}"
            echo -e "   ${AMARILLO}Tareas:${RESET} ${AZUL}$tareas_activas${RESET}"
            echo -e "   ${AMARILLO}Última ejecución:${RESET} ${AZUL}$(obtener_ultima_ejecucion)${RESET}"
        else
            echo -e "${ROJO}❌ No hay tareas programadas${RESET}"
        fi
        echo ""
        echo -e "${CIAN}═══════════════════════════════════════════════${RESET}"
        echo ""

        local opciones_fzf="1. Programar/Añadir Tareas (Paso a Paso)
2. Gestionar/Eliminar tareas individuales
3. Ver configuración actual
4. Ver logs de ejecución
5. Ver resumen última ejecución
6. Desactivar TODAS las tareas
7. Volver"

        local opcion_num=""

        if command -v fzf &>/dev/null; then
            local sel
            sel=$(echo -e "$opciones_fzf" | fzf_estilo "Seleccione una opción" "G E S T O R  D E  T A R E A S")
            if [ $? -ne 0 ] || [ -z "$sel" ]; then
                break
            fi
            opcion_num=$(echo "$sel" | awk -F'.' '{print $1}' | tr -d ' ')
        else
            echo -e " 1. Programar/Automatizar Tareas (Paso a Paso)"
            echo -e " 2. Ver configuración"
            echo -e " 3. Ver logs"
            echo -e " 4. Ver resumen"
            echo -e " 5. Desactivar tarea"
            echo -e " 6. Volver"
            echo ""
            echo -ne "${AMARILLO}Seleccione una opción (1-6): ${RESET}"
            read -r opcion_num
        fi

        if [ "$opcion_num" == "6" ]; then
            break
        fi

        case "$opcion_num" in
            1) programar_nueva_tarea ;;
            2) gestionar_tareas_individuales ;;
            3) ver_configuracion_cron ;;
            4) ver_logs_cron ;;
            5) ver_resumen_cron ;;
            6) desactivar_cron ;;
            7) break ;;
        esac
    done
}

# ============================================================================
#                   PUNTO DE ENTRADA
# ============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    if [ "$EUID" -ne 0 ]; then
        echo -e "${ROJO_BRILLANTE}⚠️ Este script requiere privilegios de root.${RESET}"
        echo -e "${AMARILLO}Ejecuta: sudo $0${RESET}"
        exit 1
    fi
    
    gestionar_tareas_auto
fi