#!/bin/bash
# ==============================================================================
#                 GESTOR DE TAREAS AUTOMATIZADAS (CRON)
# ==============================================================================
# STK - Módulo de programación automática de tareas
# Versión: 1.0
# 
# Este script se integra con stk2.sh y permite programar tareas automáticas
# usando el sistema CRON del sistema.
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

# Cargar funciones y colores de stk2.sh
if [ -f "$STK2_SCRIPT" ]; then
    source "$STK2_SCRIPT"
else
    # Fallback de colores si no se puede cargar
    RESET='\e[0m'
    VERDE_BRILLANTE='\e[92m'
    VERDE='\e[32m'
    AMARILLO='\e[33m'
    AZUL='\e[34m'
    CIAN='\e[36m'
    MAGENTA='\e[35m'
    ROJO='\e[31m'
    ROJO_BRILLANTE='\e[91m'
    BLANCO='\e[97m'
fi

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
    # Crear directorio de configuración
    if [ ! -d "$CRON_CONFIG_DIR" ]; then
        mkdir -p "$CRON_CONFIG_DIR"
        chmod 755 "$CRON_CONFIG_DIR"
    fi
    
    # Crear archivo de configuración inicial
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
    
    # Crear archivos de log
    for log in "$CRON_LOG_FILE" "$CRON_RESUMEN_FILE"; do
        if [ ! -f "$log" ]; then
            touch "$log"
            chmod 640 "$log"
        fi
    done
    
    # Crear wrapper para CRON
    crear_wrapper_cron
}

# ============================================================================
#                   FUNCIONES DE LOG
# ============================================================================

log_cron() {
    local NIVEL="${1:-INFO}"
    local MENSAJE="${2}"
    local FECHA=$(date '+%Y-%m-%d %H:%M:%S')
    
    echo "[$FECHA] [$NIVEL] [root] - $MENSAJE" >> "$CRON_LOG_FILE"
    
    # También registrar en el log principal de STK
    if declare -f registrar_log >/dev/null 2>&1; then
        registrar_log "$NIVEL" "[CRON] $MENSAJE"
    fi
}

# ============================================================================
#                   CREACIÓN DEL WRAPPER PARA CRON
# ============================================================================

crear_wrapper_cron() {
    local wrapper_content='#!/bin/bash
# STK - Wrapper para tareas automáticas CRON
# Generado automáticamente - No modificar manualmente
# ==============================================================================

# Cargar entorno
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export HOME="/root"
export TERM="linux"

# Directorio del script STK
STK_DIR="'"$SCRIPT_DIR"'"
if [ ! -f "$STK_DIR/stk2.sh" ]; then
    for dir in "/opt/STK" "/usr/local/STK" "$HOME/STK"; do
        if [ -f "$dir/stk2.sh" ]; then
            STK_DIR="$dir"
            break
        fi
    done
fi

if [ ! -f "$STK_DIR/stk2.sh" ]; then
    echo "[$(date)] [ERROR] - No se encuentra stk2.sh" >> '"$CRON_LOG_FILE"'
    exit 1
fi

cd "$STK_DIR"

# Cargar configuración
CONFIG_FILE="'"$CRON_CONFIG_FILE"'"
if [ ! -f "$CONFIG_FILE" ]; then
    echo "[$(date)] [ERROR] - No hay configuración de tareas" >> '"$CRON_LOG_FILE"'
    exit 1
fi

# Obtener lista de tareas
if command -v jq &>/dev/null; then
    TAREAS=$(jq -r ".tareas[] | .id" "$CONFIG_FILE" 2>/dev/null | tr "\n" " ")
else
    TAREAS=$(grep -o "\"id\":\"[^\"]*\"" "$CONFIG_FILE" 2>/dev/null | cut -d'"' -f4 | tr "\n" " ")
fi

if [ -z "$TAREAS" ]; then
    echo "[$(date)] [ERROR] - No hay tareas configuradas" >> '"$CRON_LOG_FILE"'
    exit 1
fi

# Variables para el resumen
FECHA_INICIO=$(date "+%Y-%m-%d %H:%M:%S")
T_INICIO=$(date +%s)
RESULTADOS=()
TAREAS_EJECUTADAS=()

# Registrar inicio
echo "" >> '"$CRON_LOG_FILE"'
echo "[$(date)] [INFO] ═══════════════════════════════════════════" >> '"$CRON_LOG_FILE"'
echo "[$(date)] [INFO] 🚀 INICIO EJECUCIÓN AUTOMÁTICA" >> '"$CRON_LOG_FILE"'
echo "[$(date)] [INFO] 📋 Tareas: $TAREAS" >> '"$CRON_LOG_FILE"'
echo "[$(date)] [INFO] ═══════════════════════════════════════════" >> '"$CRON_LOG_FILE"'

# Ejecutar tareas
for tarea in $TAREAS; do
    TAREAS_EJECUTADAS+=("$tarea")
    
    echo "[$(date)] [INFO] ▶ Ejecutando: $tarea" >> '"$CRON_LOG_FILE"'
    
    LOG_TEMP=$(mktemp)
    
    case "$tarea" in
        "actualizacion")
            bash "$STK_DIR/stk2.sh" --auto-actualizacion > "$LOG_TEMP" 2>&1
            if [ $? -eq 0 ]; then
                RESULTADOS+=("✅ ACTUALIZACIÓN: Completada")
                echo "[$(date)] [INFO] ✅ Actualización exitosa" >> '"$CRON_LOG_FILE"'
            else
                RESULTADOS+=("❌ ACTUALIZACIÓN: Falló")
                echo "[$(date)] [ERROR] ❌ Actualización falló" >> '"$CRON_LOG_FILE"'
            fi
            ;;
        "limpieza")
            bash "$STK_DIR/stk2.sh" --auto-limpieza > "$LOG_TEMP" 2>&1
            if [ $? -eq 0 ]; then
                RESULTADOS+=("✅ LIMPIEZA: Completada")
                echo "[$(date)] [INFO] ✅ Limpieza exitosa" >> '"$CRON_LOG_FILE"'
            else
                RESULTADOS+=("❌ LIMPIEZA: Falló")
                echo "[$(date)] [ERROR] ❌ Limpieza falló" >> '"$CRON_LOG_FILE"'
            fi
            ;;
        "auditoria")
            bash "$STK_DIR/stk2.sh" --auto-auditoria > "$LOG_TEMP" 2>&1
            if [ $? -eq 0 ]; then
                RESULTADOS+=("✅ AUDITORÍA: Completada")
                echo "[$(date)] [INFO] ✅ Auditoría exitosa" >> '"$CRON_LOG_FILE"'
            else
                RESULTADOS+=("❌ AUDITORÍA: Falló")
                echo "[$(date)] [ERROR] ❌ Auditoría falló" >> '"$CRON_LOG_FILE"'
            fi
            ;;
        "servicios")
            bash "$STK_DIR/stk2.sh" --auto-servicios > "$LOG_TEMP" 2>&1
            if [ $? -eq 0 ]; then
                RESULTADOS+=("✅ SERVICIOS: Reporte generado")
                echo "[$(date)] [INFO] ✅ Reporte de servicios generado" >> '"$CRON_LOG_FILE"'
            else
                RESULTADOS+=("❌ SERVICIOS: Falló")
                echo "[$(date)] [ERROR] ❌ Reporte de servicios falló" >> '"$CRON_LOG_FILE"'
            fi
            ;;
        "ufw")
            bash "$STK_DIR/stk2.sh" --auto-ufw > "$LOG_TEMP" 2>&1
            if [ $? -eq 0 ]; then
                RESULTADOS+=("✅ UFW: Auditoría completada")
                echo "[$(date)] [INFO] ✅ Auditoría UFW exitosa" >> '"$CRON_LOG_FILE"'
            else
                RESULTADOS+=("❌ UFW: Falló")
                echo "[$(date)] [ERROR] ❌ Auditoría UFW falló" >> '"$CRON_LOG_FILE"'
            fi
            ;;
        *)
            RESULTADOS+=("❌ TAREA DESCONOCIDA: $tarea")
            echo "[$(date)] [ERROR] ❌ Tarea desconocida: $tarea" >> '"$CRON_LOG_FILE"'
            ;;
    esac
    
    # Guardar salida detallada
    if [ -s "$LOG_TEMP" ]; then
        cat "$LOG_TEMP" >> "/var/log/stk_cron_${tarea}.log" 2>/dev/null
    fi
    rm -f "$LOG_TEMP"
done

# Calcular tiempo total
T_FIN=$(date +%s)
DURACION=$((T_FIN - T_INICIO))

# Generar resumen en el log
echo "[$(date)] [INFO] ═══════════════════════════════════════════" >> '"$CRON_LOG_FILE"'
echo "[$(date)] [INFO] 📊 RESUMEN FINAL" >> '"$CRON_LOG_FILE"'
echo "[$(date)] [INFO] ⏱️  Tiempo: ${DURACION}s" >> '"$CRON_LOG_FILE"'
for resultado in "${RESULTADOS[@]}"; do
    echo "[$(date)] [INFO]    $resultado" >> '"$CRON_LOG_FILE"'
done
echo "[$(date)] [INFO] 🏁 FIN EJECUCIÓN" >> '"$CRON_LOG_FILE"'
echo "[$(date)] [INFO] ═══════════════════════════════════════════" >> '"$CRON_LOG_FILE"'

# Guardar resumen en archivo específico
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
} >> "'"$CRON_RESUMEN_FILE"'"

# Actualizar configuración
if command -v jq &>/dev/null && [ -f "$CONFIG_FILE" ]; then
    tmp_json=$(mktemp)
    jq --arg fecha "$(date "+%Y-%m-%d %H:%M:%S")" ".configuracion.ultima_ejecucion = \$fecha" "$CONFIG_FILE" > "$tmp_json" 2>/dev/null
    if [ $? -eq 0 ]; then
        mv "$tmp_json" "$CONFIG_FILE"
        chmod 600 "$CONFIG_FILE"
    else
        rm -f "$tmp_json"
    fi
fi

exit 0
'

    echo "$wrapper_content" > "$STK_AUTO_WRAPPER"
    chmod +x "$STK_AUTO_WRAPPER"
    log_cron "INFO" "Wrapper CRON creado: $STK_AUTO_WRAPPER"
}

# ============================================================================
#                   FUNCIONES DE ESTADO
# ============================================================================

verificar_cron_stk() {
    crontab -l 2>/dev/null | grep -q "$CRON_STK_ID"
}

obtener_frecuencia_descripcion() {
    if [ -f "$CRON_CONFIG_FILE" ]; then
        if command -v jq &>/dev/null; then
            jq -r '.configuracion.descripcion // "No configurada"' "$CRON_CONFIG_FILE" 2>/dev/null || echo "No configurada"
        else
            grep -o '"descripcion":"[^"]*"' "$CRON_CONFIG_FILE" 2>/dev/null | cut -d'"' -f4 || echo "No configurada"
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
            grep -o '"descripcion":"[^"]*"' "$CRON_CONFIG_FILE" 2>/dev/null | cut -d'"' -f4 | tr '\n' ', ' | sed 's/, $//' || echo "Ninguna"
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
#                   FUNCIONES DE SELECCIÓN DE TAREAS
# ============================================================================

seleccionar_tareas() {
    local modo="$1"
    clear
    mostrar_logo
    echo ""
    pintar "$CIAN" "--- SELECCIÓN DE TAREAS A PROGRAMAR ---"
    echo ""

    # Si es modo completo, seleccionar todas
    if [[ "$modo" == "completo" ]]; then
        TAREAS_SELECCIONADAS=()
        for key in "${!TAREAS_DISPONIBLES[@]}"; do
            TAREAS_SELECCIONADAS+=("$key:${TAREAS_DISPONIBLES[$key]}")
        done
        pintar "$VERDE_BRILLANTE" "✅ Modo completo: todas las tareas seleccionadas"
        echo ""
        echo -e "${AMARILLO}Tareas seleccionadas:${RESET}"
        for tarea in "${TAREAS_SELECCIONADAS[@]}"; do
            echo -e "  ${VERDE}•${RESET} ${tarea#*:}"
        done
        echo ""
        read -p "Presione Enter para continuar..."
        return
    fi

    # Construir lista para fzf
    local fzf_input=""
    for key in "${!TAREAS_DISPONIBLES[@]}"; do
        fzf_input+="[ ] $key: ${TAREAS_DISPONIBLES[$key]}\n"
    done

    if ! command -v fzf &>/dev/null; then
        pintar "$ROJO" "❌ fzf no está instalado. Usando selección manual."
        echo ""
        for key in "${!TAREAS_DISPONIBLES[@]}"; do
            echo -e "${CIAN}${key}${RESET}: ${TAREAS_DISPONIBLES[$key]}"
        done
        echo ""
        echo -e "${AMARILLO}Ingresa los IDs de las tareas (separados por espacio):${RESET}"
        read -r -a tareas_input
        
        TAREAS_SELECCIONADAS=()
        for tarea_id in "${tareas_input[@]}"; do
            if [[ -n "${TAREAS_DISPONIBLES[$tarea_id]}" ]]; then
                TAREAS_SELECCIONADAS+=("$tarea_id:${TAREAS_DISPONIBLES[$tarea_id]}")
            fi
        done
    else
        local seleccionadas
        seleccionadas=$(echo -e "$fzf_input" | fzf --ansi \
            --height=18 \
            --reverse \
            --border=rounded \
            --prompt="➤ Seleccione tareas (TAB para múltiple): " \
            --header="SELECCIONE LAS TAREAS A AUTOMATIZAR" \
            --multi \
            --delimiter=" " \
            --with-nth=2..)

        if [ -z "$seleccionadas" ]; then
            pintar "$AMARILLO" "No se seleccionó ninguna tarea. Cancelando."
            sleep 2
            return
        fi

        TAREAS_SELECCIONADAS=()
        while IFS= read -r line; do
            local tarea_id=$(echo "$line" | awk '{print $2}' | cut -d: -f1)
            if [[ -n "${TAREAS_DISPONIBLES[$tarea_id]}" ]]; then
                TAREAS_SELECCIONADAS+=("$tarea_id:${TAREAS_DISPONIBLES[$tarea_id]}")
            fi
        done <<< "$seleccionadas"
    fi

    if [ ${#TAREAS_SELECCIONADAS[@]} -gt 0 ]; then
        echo ""
        pintar "$VERDE_BRILLANTE" "✅ Tareas seleccionadas:"
        for tarea in "${TAREAS_SELECCIONADAS[@]}"; do
            echo -e "   ${VERDE}•${RESET} ${tarea#*:}"
        done
        echo ""
    else
        pintar "$ROJO" "❌ No se seleccionó ninguna tarea válida."
    fi
    read -p "Presione Enter para confirmar..."
}

# ============================================================================
#                   FUNCIONES DE CONFIGURACIÓN DE FRECUENCIA
# ============================================================================

configurar_frecuencia() {
    local tipo="$1"
    clear
    mostrar_logo
    echo ""
    pintar "$CIAN" "--- CONFIGURAR FRECUENCIA DE EJECUCIÓN ---"
    echo ""

    if [ ${#TAREAS_SELECCIONADAS[@]} -eq 0 ]; then
        pintar "$ROJO" "❌ No hay tareas seleccionadas. Primero selecciona las tareas."
        read -p "Presione Enter..."
        return
    fi

    local cron_line=""
    local descripcion_freq=""

    case "$tipo" in
        "boot")
            echo -e "${AMARILLO}⏰ Al iniciar el sistema (5 minutos después de arrancar)${RESET}"
            cron_line="@reboot sleep 300"
            descripcion_freq="Al iniciar el sistema"
            ;;
        "diaria")
            echo -e "${AMARILLO}⏰ Ejecución diaria${RESET}"
            echo -ne "${CIAN}Ingrese la hora (0-23) [3]: ${RESET}"
            read -r hora
            hora=${hora:-3}
            if [[ ! "$hora" =~ ^[0-9]+$ ]] || [ "$hora" -lt 0 ] || [ "$hora" -gt 23 ]; then
                pintar "$ROJO" "❌ Hora inválida. Usando 3:00 AM"
                hora=3
            fi
            cron_line="0 $hora * * *"
            descripcion_freq="Diaria a las ${hora}:00"
            ;;
        "semanal")
            echo -e "${AMARILLO}⏰ Ejecución semanal${RESET}"
            echo -e "${CIAN}Días disponibles:${RESET}"
            echo "  0=Dom  1=Lun  2=Mar  3=Mié  4=Jue  5=Vie  6=Sáb"
            echo -ne "${CIAN}Ingrese el día (0-6) [1]: ${RESET}"
            read -r dia
            dia=${dia:-1}
            if [[ ! "$dia" =~ ^[0-6]$ ]]; then
                pintar "$ROJO" "❌ Día inválido. Usando Lunes (1)"
                dia=1
            fi
            echo -ne "${CIAN}Ingrese la hora (0-23) [3]: ${RESET}"
            read -r hora
            hora=${hora:-3}
            if [[ ! "$hora" =~ ^[0-9]+$ ]] || [ "$hora" -lt 0 ] || [ "$hora" -gt 23 ]; then
                pintar "$ROJO" "❌ Hora inválida. Usando 3:00 AM"
                hora=3
            fi
            cron_line="0 $hora * * $dia"
            descripcion_freq="Semanal (día $dia a las ${hora}:00)"
            ;;
        "custom")
            echo -e "${AMARILLO}⏰ Configuración personalizada${RESET}"
            echo -e "${CIAN}Formato cron: ${BLANCO}Minuto Hora Dia Mes DiaSemana${RESET}"
            echo -e "${CIAN}Ejemplos:${RESET}"
            echo "  ${AMARILLO}0 12 * * *${RESET}  → Todos los días a las 12:00"
            echo "  ${AMARILLO}*/30 * * * *${RESET} → Cada 30 minutos"
            echo "  ${AMARILLO}0 9 * * 1-5${RESET}  → De lunes a viernes a las 9:00"
            echo ""
            echo -ne "${AMARILLO}Ingrese el schedule cron: ${RESET}"
            read -r custom_schedule
            if [ -z "$custom_schedule" ]; then
                pintar "$ROJO" "❌ Schedule vacío. Cancelando."
                sleep 2
                return
            fi
            cron_line="$custom_schedule"
            descripcion_freq="Personalizado: $custom_schedule"
            ;;
    esac

    # Mostrar resumen y confirmar
    echo ""
    pintar "$CIAN" "═══════════════════════════════════════════════"
    pintar "$VERDE_BRILLANTE" "📋 RESUMEN DE CONFIGURACIÓN"
    pintar "$CIAN" "═══════════════════════════════════════════════"
    echo -e "${AMARILLO}Frecuencia:${RESET} ${AZUL}$descripcion_freq${RESET}"
    echo -e "${AMARILLO}Schedule:${RESET}   ${AZUL}$cron_line${RESET}"
    echo ""
    echo -e "${AMARILLO}Tareas programadas:${RESET}"
    for tarea in "${TAREAS_SELECCIONADAS[@]}"; do
        echo -e "   ${VERDE}•${RESET} ${tarea#*:}"
    done
    echo ""
    echo -ne "${ROJO_BRILLANTE}¿Confirmar y activar tarea? (s/N): ${RESET}"
    read -r confirm

    if [[ "$confirm" =~ ^[sS]$ ]]; then
        activar_tarea_cron "$cron_line" "$descripcion_freq"
    else
        pintar "$AZUL" "Operación cancelada."
        read -p "Presione Enter..."
    fi
}

# ============================================================================
#                   FUNCIONES DE ACTIVACIÓN
# ============================================================================

guardar_configuracion_cron() {
    local cron_line="$1"
    local descripcion="$2"
    shift 2
    local tareas=("$@")

    local json_tareas="["
    for i in "${!tareas[@]}"; do
        local tarea_id="${tareas[$i]%%:*}"
        local tarea_desc="${tareas[$i]#*:}"
        
        if [ $i -gt 0 ]; then json_tareas+=","; fi
        json_tareas+="{\"id\":\"$tarea_id\",\"descripcion\":\"$tarea_desc\"}"
    done
    json_tareas+="]"

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
    "tareas": $json_tareas
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

    # Eliminar tarea existente
    crontab -l 2>/dev/null | grep -v "$CRON_STK_ID" | crontab -

    # Añadir nueva tarea
    (crontab -l 2>/dev/null; echo "$cron_full $CRON_STK_ID") | crontab -

    if [ $? -eq 0 ]; then
        log_cron "INFO" "Tarea CRON activada: $descripcion ($cron_line)"
        mostrar_resumen_final "$cron_line" "$descripcion"
    else
        pintar "$ROJO" "❌ Error al activar la tarea automática."
        log_cron "ERROR" "Error al activar CRON"
        read -p "Presione Enter..."
    fi
}

# ============================================================================
#                   RESUMEN FINAL
# ============================================================================

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
    
    log_cron "INFO" "Tarea CRON activada: $descripcion ($cron_line)"
    
    echo ""
    read -p "Presione Enter para volver al menú..."
}

# ============================================================================
#                   FUNCIONES DE INFORMACIÓN
# ============================================================================

ver_configuracion_cron() {
    clear
    mostrar_logo
    echo ""
    pintar "$CIAN" "--- CONFIGURACIÓN ACTUAL ---"
    echo ""
    
    if [ -f "$CRON_CONFIG_FILE" ]; then
        pintar "$VERDE_BRILLANTE" "✅ Configuración activa:"
        echo ""
        if command -v jq &>/dev/null; then
            cat "$CRON_CONFIG_FILE" | jq '.' 2>/dev/null || cat "$CRON_CONFIG_FILE"
        else
            cat "$CRON_CONFIG_FILE"
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
    pintar "$CIAN" "--- DESACTIVAR TAREA AUTOMÁTICA ---"
    echo ""

    if ! verificar_cron_stk; then
        pintar "$AMARILLO" "⚠️ No hay una tarea automática activa."
        read -p "Presione Enter..."
        return
    fi

    local config_actual
    config_actual=$(obtener_frecuencia_descripcion)
    echo -e "${AMARILLO}Tarea actual:${RESET} $config_actual"
    echo ""
    echo -ne "${ROJO_BRILLANTE}¿Desactivar la tarea automática? (s/N): ${RESET}"
    read -r confirm

    if [[ "$confirm" =~ ^[sS]$ ]]; then
        crontab -l 2>/dev/null | grep -v "$CRON_STK_ID" | crontab -
        
        if [ -f "$CRON_CONFIG_FILE" ]; then
            if command -v jq &>/dev/null; then
                local tmp_json=$(mktemp)
                if jq '.configuracion.activado = false' "$CRON_CONFIG_FILE" > "$tmp_json" 2>/dev/null; then
                    mv "$tmp_json" "$CRON_CONFIG_FILE"
                    chmod 600 "$CRON_CONFIG_FILE"
                else
                    rm -f "$tmp_json"
                fi
            else
                sed -i 's/"activado": true/"activado": false/' "$CRON_CONFIG_FILE"
            fi
        fi
        
        pintar "$VERDE_BRILLANTE" "✔ Tarea automática desactivada con éxito."
        log_cron "WARN" "Tarea CRON desactivada"
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
    # Inicializar estructura al primer uso
    inicializar_estructura
    
    while true; do
        clear
        mostrar_logo
        echo ""
        pintar "$MAGENTA" "═══════════════════════════════════════════════"
        pintar "$BLANCO"  "   📅 GESTOR DE TAREAS AUTOMATIZADAS (CRON)"
        pintar "$MAGENTA" "═══════════════════════════════════════════════"
        echo ""

        # Mostrar estado actual
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

        # Menú principal
        local opciones="
╔══════════════════════════════════════════════════════════════╗
║  📌 CONFIGURAR TAREAS                                       ║
║    1. 🤖 Modo Auto Completo                                 ║
║    2. 🔄 Actualización del sistema                          ║
║    3. 🧹 Limpieza del sistema                               ║
║    4. 🔍 Auditoría de seguridad                             ║
║    5. 📊 Reporte de servicios                               ║
║    6. 🛡️ Auditoría UFW                                     ║
║                                                             ║
║  ⏰ FRECUENCIA DE EJECUCIÓN                                 ║
║    7. 🚀 Al iniciar el sistema                              ║
║    8. 📅 Diaria (hora configurable)                         ║
║    9. 📆 Semanal (día configurable)                         ║
║   10. ⚙️ Personalizado (cron libre)                         ║
║                                                             ║
║  📋 INFORMACIÓN                                             ║
║   11. 📖 Ver configuración actual                           ║
║   12. 📄 Ver logs de ejecución                              ║
║   13. 📊 Ver resumen última ejecución                       ║
║                                                             ║
║   14. 🛑 Desactivar tarea automática                        ║
║   15. ↩ Volver                                              ║
╚══════════════════════════════════════════════════════════════╝"

        if command -v fzf &>/dev/null; then
            local sel
            sel=$(echo -e "$opciones" | fzf_estilo "Seleccione" "G E S T O R  D E  T A R E A S")
            if [ $? -ne 0 ] || [ -z "$sel" ] || [[ "${sel:0:2}" == "15" ]]; then
                break
            fi
        else
            echo -e "$opciones"
            echo -ne "${AMARILLO}Seleccione una opción (1-15): ${RESET}"
            read -r sel
            if [ -z "$sel" ] || [ "$sel" == "15" ]; then
                break
            fi
        fi

        case ${sel:0:2} in
            1)  seleccionar_tareas "completo" ;;
            2)  seleccionar_tareas "actualizacion" ;;
            3)  seleccionar_tareas "limpieza" ;;
            4)  seleccionar_tareas "auditoria" ;;
            5)  seleccionar_tareas "servicios" ;;
            6)  seleccionar_tareas "ufw" ;;
            7)  configurar_frecuencia "boot" ;;
            8)  configurar_frecuencia "diaria" ;;
            9)  configurar_frecuencia "semanal" ;;
            10) configurar_frecuencia "custom" ;;
            11) ver_configuracion_cron ;;
            12) ver_logs_cron ;;
            13) ver_resumen_cron ;;
            14) desactivar_cron ;;
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