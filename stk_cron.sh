#!/bin/bash
# ==============================================================================
#                 GESTOR DE TAREAS AUTOMATIZADAS (CRON)
# ==============================================================================
# Pasamos a cron4me
# ==============================================================================
ver="v 5.4"
# --- DETECCIÓN ROBUSTA DE DIRECTORIO Y BÚSQUEDA ---
SOURCE="${BASH_SOURCE[0]}"
while [ -h "$SOURCE" ]; do
    DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
    SOURCE="$(readlink "$SOURCE")"
    [[ $SOURCE != /* ]] && SOURCE="$DIR/$SOURCE"
done
SCRIPT_DIR="$( cd -P "$( dirname "$SOURCE" )" >/dev/null 2>&1 && pwd )"
STK2_SCRIPT="$SCRIPT_DIR/stk2.sh"

# Si no está en su carpeta, buscar stk2.sh en todo el sistema del usuario
if [ ! -f "$STK2_SCRIPT" ]; then
    STK2_SCRIPT=$(find /home /root -maxdepth 4 -name "stk2.sh" 2>/dev/null | head -n 1)
    if [ -n "$STK2_SCRIPT" ]; then
        SCRIPT_DIR="$(dirname "$STK2_SCRIPT")"
    else
        echo -e "\033[91m❌ Error: No se pudo localizar stk2.sh en el sistema.\033[0m"
        exit 1
    fi
fi

# --- CAPA DE COMPATIBILIDAD STK (TERM / fzf / TTY / rutas) ---
if [ -r "$SCRIPT_DIR/stk_header.sh" ]; then
    # shellcheck source=stk_header.sh
    source "$SCRIPT_DIR/stk_header.sh"
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

# --- BIBLIOTECA COMPARTIDA DEL MODO AUTOMÁTICO ---
# Misma lógica de limpieza, auditoría, servicios, actualización y lock
# que usa stk2.sh. La bitácora es el archivo común del proyecto.
LOG_FILE="/var/log/stk_mantenimiento.log"
LOG_INFO="INFO"
LOG_WARN="WARN"
LOG_ERR="ERROR"

STK_AUTO_LIB="$SCRIPT_DIR/stk_auto_lib.sh"
if [ ! -f "$STK_AUTO_LIB" ]; then
    STK_AUTO_LIB=$(find /home /root /usr/local -maxdepth 5 -name "stk_auto_lib.sh" 2>/dev/null | head -n 1)
fi
if [ -f "$STK_AUTO_LIB" ]; then
    # shellcheck source=stk_auto_lib.sh
    source "$STK_AUTO_LIB"
else
    echo -e "\033[91m❌ Error: No se encontró la biblioteca $STK_AUTO_LIB.\033[0m" >&2
    exit 1
fi

# mostrar_logo
mostrar_logo() {
    echo -e "${CIAN}   ██████ ██████   ██████  ███   ██ ██   ██ ███   ███ ███████${RESET}"
    echo -e "${AZUL_BRILLANTE}  ██      ██   ██ ██    ██ ████  ██ ██   ██ ████ ████ ██     ${RESET}"
    echo -e "${AZUL}  ██      ██████  ██    ██ ██ ██ ██ ███████ ██ ███ ██ █████  ${RESET}"
    echo -e "${AZUL}  ██      ██   ██ ██    ██ ██  ████      ██ ██     ██ ██     ${RESET}"
    echo -e "${AZUL_BRILLANTE}   ██████ ██   ██  ██████  ██   ███      ██ ██     ██ ███████${RESET}"
    echo -e "${VERDE_BRILLANTE}---               CRON TASK MANAGER $ver               ---${RESET}"
    echo -e "${CIAN}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
}

# Definir fzf_estilo
fzf_estilo() {
    local prompt_text="$1"
    local header_text="$2"
    stk_fzf_ejecutar "$prompt_text" "$header_text" "" \
        --ansi \
        --height=18 \
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
    "version": "$ver",
    "configuracion": {
        "schedule": null,
        "descripcion": null,
        "activado": false,
        "fecha_activacion": null,
        "ultima_ejecucion": null,
        "notificaciones": true
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


# CREAR WRAPPER 
crear_wrapper_cron() {
    # La ruta de la biblioteca se resuelve al generar el wrapper. El resto del
    # script se escribe literalmente (comillas en el heredoc) para no expandir
    # las variables que debe usar el cron en tiempo de ejecución.
    local STK_AUTO_LIB_PATH="$SCRIPT_DIR/stk_auto_lib.sh"
    {
        cat << EOF
#!/bin/bash
# ==============================================================================
#  STK - WRAPPER Y EJECUTOR DE TAREAS AUTOMÁTICAS (CRON)
#  Generado por stk_cron.sh. Comparte la lógica con el modo auto de stk2.sh.
# ==============================================================================
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export HOME="/root"
export TERM="linux"
export LANG="es_ES.UTF-8"

STK_AUTO_LIB="$STK_AUTO_LIB_PATH"

CRON_CONFIG_FILE="/etc/stk/cron/tasks.json"
CRON_LOG_FILE="/var/log/stk_cron.log"
CRON_RESUMEN_FILE="/var/log/stk_cron_resumen.log"

if [ ! -f "\$STK_AUTO_LIB" ]; then
    STK_AUTO_LIB=\$(find /home /root /usr/local -maxdepth 5 -name "stk_auto_lib.sh" 2>/dev/null | head -n 1)
fi
if [ -f "\$STK_AUTO_LIB" ]; then
    # shellcheck source=stk_auto_lib.sh
    source "\$STK_AUTO_LIB"
else
    echo "❌ No se encuentra \$STK_AUTO_LIB" >&2
    exit 1
fi
EOF

        cat << 'EOF'

log_cron_exec() {
    local nivel="${1:-INFO}"
    local mensaje="${2}"
    local fecha
    fecha=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$fecha] [$nivel] [root] - $mensaje" >> "$CRON_LOG_FILE"
}

# ------------------------------------------------------------------------------
# NOTIFICACIONES
#  - No instalan paquetes automáticamente: si falta notify-send, se omite.
#  - Leo el ÚLTIMO BLOQUE COMPLETO del resumen (no las últimas N líneas),
#    porque el detalle de las tareas es largo y antes ocultaba los resultados.
#  - Uso el bus DBus de la sesión del usuario; no necesito DISPLAY/WAYLAND.
# ------------------------------------------------------------------------------
enviar_notificacion() {
    local notif_activas="true"
    if command -v jq >/dev/null 2>&1; then
        notif_activas=$(jq -r 'if .configuracion.notificaciones == null then "true" else (.configuracion.notificaciones | tostring) end' "$CRON_CONFIG_FILE" 2>/dev/null)
        [ -z "$notif_activas" ] && notif_activas="true"
    elif grep -q '"notificaciones"[[:space:]]*:[[:space:]]*false' "$CRON_CONFIG_FILE" 2>/dev/null; then
        notif_activas="false"
    fi
    if [ "$notif_activas" != "true" ]; then
        log_cron_exec "INFO" "Notificaciones desactivadas; se omite el aviso."
        return 0
    fi

    if ! command -v notify-send >/dev/null 2>&1; then
        log_cron_exec "INFO" "notify-send no disponible; no se instala nada automáticamente. Aviso omitido."
        return 0
    fi

    [ -f "$CRON_RESUMEN_FILE" ] || return 1

    local usuario_activo
    usuario_activo=$(who 2>/dev/null | grep -E '(:[0-9]|tty[0-9]|x11|wayland)' | awk '{print $1}' | head -n 1)
    [ -z "$usuario_activo" ] && usuario_activo=$(loginctl list-sessions --no-legend 2>/dev/null | awk '{print $3}' | head -n 1)
    if [ -z "$usuario_activo" ]; then
        log_cron_exec "INFO" "Sin usuario con sesión activa; aviso omitido."
        return 0
    fi

    local user_id
    user_id=$(id -u "$usuario_activo" 2>/dev/null)
    local dbus_socket="/run/user/${user_id}/bus"
    if [ -z "$user_id" ] || [ "$user_id" -eq 0 ] || [ ! -S "$dbus_socket" ]; then
        log_cron_exec "INFO" "Sin bus de usuario activo ($dbus_socket); aviso omitido."
        return 0
    fi

    # Último bloque completo, delimitado por "RESUMEN EJECUCIÓN".
    local ultimo_bloque inicio
    inicio=$(grep -n "RESUMEN EJECUCIÓN" "$CRON_RESUMEN_FILE" 2>/dev/null | tail -1 | cut -d: -f1)
    if [ -n "$inicio" ]; then
        ultimo_bloque=$(tail -n +"$inicio" "$CRON_RESUMEN_FILE")
    else
        ultimo_bloque=$(tail -n 60 "$CRON_RESUMEN_FILE")
    fi
    [ -n "$ultimo_bloque" ] || return 1

    local titulo="Cron4me: Informe de ejecución programada"
    local urgencia="normal" icono="dialog-information" estado="✅ EJECUCIÓN EXITOSA"
    if printf '%s\n' "$ultimo_bloque" | grep -qE '^[[:space:]]*❌ Tarea \['; then
        urgencia="critical"; icono="dialog-error"; estado="❌ HUBO FALLOS EN LA EJECUCIÓN"
    elif printf '%s\n' "$ultimo_bloque" | grep -qE '⚠️|⚠ '; then
        urgencia="normal"; icono="dialog-warning"; estado="⚠️ ATENCIÓN / ALERTAS"
    fi

    local resumen_tareas avisos mensaje
    resumen_tareas=$(printf '%s\n' "$ultimo_bloque" | grep -E '^[[:space:]]*[✅❌] Tarea \[' | sed 's/^[[:space:]]*//' | head -n 10)
    avisos=$(printf '%s\n' "$ultimo_bloque" | grep -E '^[[:space:]]*(⚠️|⚠|🔄|🧠|♻️)' | sed 's/^[[:space:]]*//' | cut -c1-140 | head -n 5)

    mensaje="$(printf 'Estado: %s\n\n' "$estado")"
    [ -n "$resumen_tareas" ] && mensaje+="$(printf 'Tareas:\n%s\n' "$resumen_tareas")"
    [ -n "$avisos" ] && mensaje+="$(printf '\nIncidencias:\n%s\n' "$avisos")"

    local -a notificar=(notify-send -u "$urgencia" -i "$icono" -t 10000 "$titulo" "$mensaje")
    if [ "$(id -u)" -eq 0 ] && [ "$user_id" -ne 0 ]; then
        if command -v runuser >/dev/null 2>&1; then
            runuser -u "$usuario_activo" -- env \
                DBUS_SESSION_BUS_ADDRESS="unix:path=${dbus_socket}" \
                XDG_RUNTIME_DIR="/run/user/${user_id}" \
                "${notificar[@]}" 2>/dev/null
        else
            sudo -u "$usuario_activo" env \
                DBUS_SESSION_BUS_ADDRESS="unix:path=${dbus_socket}" \
                XDG_RUNTIME_DIR="/run/user/${user_id}" \
                "${notificar[@]}" 2>/dev/null
        fi
    else
        DBUS_SESSION_BUS_ADDRESS="unix:path=${dbus_socket}" \
        XDG_RUNTIME_DIR="/run/user/${user_id}" \
        "${notificar[@]}" 2>/dev/null
    fi
    return 0
}

# ------------------------------------------------------------------------------
# EJECUCIÓN DE TAREAS (implementaciones en stk_auto_lib.sh)
# ------------------------------------------------------------------------------
ejecutar_auto_actualizacion() {
    log_cron_exec "INFO" "▶ Inicio: Actualización del sistema"
    echo "🔄 INICIANDO ACTUALIZACIÓN DEL SISTEMA..."
    echo "🛟 Punto de recuperación previo:"
    stk_snapshot || echo "⚠️ No se pudo crear punto de recuperación"

    stk_actualizar
    local res=$?
    if [ $res -eq 0 ]; then
        log_cron_exec "INFO" "✅ Actualización completada"
        echo "✅ Actualización completada correctamente."
    else
        log_cron_exec "ERROR" "❌ Actualización falló con código $res"
        echo "❌ Error al ejecutar la actualización (Código $res)."
    fi
    if [ ${#ACT_INCIDENCIAS[@]} -gt 0 ]; then
        echo "⚠️ Incidencias detectadas (también en la bitácora):"
        local inc
        for inc in "${ACT_INCIDENCIAS[@]}"; do echo "   • $inc"; done
    fi
    return $res
}

ejecutar_auto_limpieza() {
    log_cron_exec "INFO" "▶ Inicio: Limpieza segura del sistema"
    echo "🧹 INICIANDO LIMPIEZA SEGURA DEL SISTEMA..."
    stk_limpieza auto
    local res=$?
    if [ $res -eq 0 ]; then
        log_cron_exec "INFO" "✅ Limpieza completada"
        echo "✅ Limpieza completada correctamente."
    else
        log_cron_exec "ERROR" "❌ Limpieza falló"
        echo "❌ Error al ejecutar la limpieza."
    fi
    return $res
}

ejecutar_auto_auditoria() {
    log_cron_exec "INFO" "▶ Inicio: Auditoría de seguridad"
    echo "🔍 AUDITORÍA DE SEGURIDAD (RESUMEN)"
    echo "----------------------------------------"
    stk_auditoria
    echo "📊 $RES_SEGURIDAD"
    if [ ${#SEC_ALERTAS[@]} -gt 0 ]; then
        echo "⚠️ Alertas detectadas:"
        local alt
        for alt in "${SEC_ALERTAS[@]}"; do echo "  • $alt"; done
    else
        echo "✅ No se detectaron alertas de seguridad."
    fi
    return 0
}

ejecutar_auto_servicios() {
    log_cron_exec "INFO" "▶ Inicio: Reporte de servicios"
    echo "📊 REPORTE DE SERVICIOS (Systemd)"
    echo "----------------------------------------"
    stk_servicios
    echo "$RES_SERVICIOS"
    [ "$REBOOT_REQUIRED" = true ] && echo "🔄 Reinicio recomendado${REBOOT_PKGS:+ (paquetes: $REBOOT_PKGS)}"
    [ "$KERNEL_PENDIENTE" = true ] && echo "🧠 Kernel nuevo instalado; se aplicará al reiniciar"
    [ -n "$NEEDRESTART" ] && echo "♻️ Servicios que necesitan reinicio: $NEEDRESTART"
    [ ${#SVC_FAILED_ARR[@]} -gt 0 ] && return 1
    return 0
}

ejecutar_auto_ufw() {
    log_cron_exec "INFO" "▶ Inicio: Auditoría UFW"
    echo "🛡️ AUDITORÍA UFW"
    echo "----------------------------------------"
    if ! command -v ufw >/dev/null 2>&1; then
        echo "❌ UFW no está instalado en el sistema."
        return 1
    fi
    echo "📋 Estado de UFW:"
    ufw status verbose 2>/dev/null | head -20
    if [ -f "/var/log/ufw.log" ]; then
        echo ""
        echo "📊 Estadísticas:"
        echo "  • Bloqueos totales: $(grep -c "UFW BLOCK" /var/log/ufw.log 2>/dev/null | tail -1)"
        echo "🔍 Últimos bloqueos:"
        grep "UFW BLOCK" /var/log/ufw.log 2>/dev/null | tail -5 | while read -r line; do
            echo "  • $line"
        done
    else
        echo "  ℹ️ No se encontró el log de UFW."
    fi
    return 0
}

PARAM_SCHED="$1"

if [ -n "$PARAM_SCHED" ] && command -v jq >/dev/null 2>&1; then
    TAREAS=$(jq -r --arg sched "$PARAM_SCHED" '.tareas[] | select((.schedule | gsub("&"; "") | trim) == $sched) | .id' "$CRON_CONFIG_FILE" 2>/dev/null | tr "\n" " ")
else
    TAREAS=$(jq -r ".tareas[] | .id" "$CRON_CONFIG_FILE" 2>/dev/null | tr "\n" " ")
fi

if [ -z "$(echo "$TAREAS" | tr -d '[:space:]')" ]; then
    log_cron_exec "WARN" "No hay tareas programadas para este horario."
    echo "⚠️ No hay tareas programadas para este horario."
    exit 0
fi

# Lock COMPARTIDO con stk2.sh: evita que el cron y el modo auto interactivo
# ejecuten apt/dnf/pacman al mismo tiempo.
if ! stk_lock_adquirir; then
    log_cron_exec "WARN" "Lock ocupado: ya hay otra ejecución del modo auto; se omiten las tareas."
    echo "⚠️ Ya hay otra ejecución del modo auto en curso."
    exit 0
fi

T_INICIO=$(date +%s)
RESULTADOS=()
DETALLES_INFORME=""

for tarea in $TAREAS; do
    LOG_TEMP=$(mktemp)
    STATUS_CODE=0

    case "$tarea" in
        "actualizacion") ejecutar_auto_actualizacion > "$LOG_TEMP" 2>&1; STATUS_CODE=$? ;;
        "limpieza")      ejecutar_auto_limpieza > "$LOG_TEMP" 2>&1; STATUS_CODE=$? ;;
        "auditoria")     ejecutar_auto_auditoria > "$LOG_TEMP" 2>&1; STATUS_CODE=$? ;;
        "servicios")     ejecutar_auto_servicios > "$LOG_TEMP" 2>&1; STATUS_CODE=$? ;;
        "ufw")           ejecutar_auto_ufw > "$LOG_TEMP" 2>&1; STATUS_CODE=$? ;;
    esac

    if [ $STATUS_CODE -eq 0 ]; then
        RESULTADOS+=("✅ Tarea [$tarea] finalizada exitosamente.")
    else
        RESULTADOS+=("❌ Tarea [$tarea] falló (Código: $STATUS_CODE).")
    fi

    DETALLES_INFORME+="--- Salida de $tarea ---\n"
    DETALLES_INFORME+="$(cat "$LOG_TEMP")\n\n"
    rm -f "$LOG_TEMP"

    while pgrep -x "pacman" >/dev/null || pgrep -x "apt-get" >/dev/null; do
        sleep 2
    done
    sleep 5
done

stk_lock_liberar

T_FIN=$(date +%s)
DURACION=$((T_FIN - T_INICIO))

{
    echo "═══════════════════════════════════════════════════════════════"
    echo "📊 RESUMEN EJECUCIÓN - $(date "+%Y-%m-%d %H:%M:%S")"
    echo "═══════════════════════════════════════════════════════════════"
    echo "⏱️  Duración: ${DURACION} segundos"
    echo "📋 Tareas: $TAREAS"
    echo ""
    for resultado in "${RESULTADOS[@]}"; do
        echo "  $resultado"
    done
    echo ""
    echo "--- DETALLES DE LA EJECUCIÓN ---"
    echo -e "$DETALLES_INFORME"
    echo "═══════════════════════════════════════════════════════════════"
} >> "$CRON_RESUMEN_FILE"

TMP_JSON=$(mktemp)
jq --arg fecha "$(date '+%Y-%m-%d %H:%M:%S')" '.configuracion.ultima_ejecucion = $fecha' "$CRON_CONFIG_FILE" > "$TMP_JSON" 2>/dev/null && mv "$TMP_JSON" "$CRON_CONFIG_FILE"
rm -f "$TMP_JSON"

enviar_notificacion
exit 0
EOF
    } > "$STK_AUTO_WRAPPER"

    chmod +x "$STK_AUTO_WRAPPER"
}

# FIN CREAR WRAPPER

# ============================================================================
#                   FUNCIONES DE CONSULTA DE ESTADO
# ============================================================================

verificar_cron_stk() {
    crontab -l 2>/dev/null | grep -q "$CRON_STK_ID"
}

obtener_frecuencia_descripcion() {
    if [ -f "$CRON_CONFIG_FILE" ]; then
        if command -v jq &>/dev/null; then
            local frecs
            frecs=$(jq -r '.tareas[].frecuencia' "$CRON_CONFIG_FILE" 2>/dev/null | sort -u | tr '\n' ', ' | sed 's/, $//')
            echo "${frecs:-Ninguna}"
        else
            echo "Configurada"
        fi
    else
        echo "Ninguna"
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

notificaciones_estado() {
    if [ -f "$CRON_CONFIG_FILE" ] && command -v jq &>/dev/null; then
        local estado
        estado=$(jq -r 'if .configuracion.notificaciones == null then "true" else (.configuracion.notificaciones | tostring) end' "$CRON_CONFIG_FILE" 2>/dev/null)
        echo "${estado:-true}"
    elif [ -f "$CRON_CONFIG_FILE" ] && grep -q '"notificaciones"[[:space:]]*:[[:space:]]*false' "$CRON_CONFIG_FILE" 2>/dev/null; then
        echo "false"
    else
        echo "true"
    fi
}

obtener_ultima_ejecucion() {
    if [ -f "$CRON_RESUMEN_FILE" ]; then
        local ultima_fecha
        # Extrae la fecha del último bloque impreso en el log de resumen
        ultima_fecha=$(grep "RESUMEN EJECUCIÓN" "$CRON_RESUMEN_FILE" 2>/dev/null | tail -1 | cut -d'-' -f2- | xargs)
        if [ -n "$ultima_fecha" ]; then
            echo "$ultima_fecha"
            return
        fi
    fi

    if [ -f "$CRON_LOG_FILE" ] && [ -s "$CRON_LOG_FILE" ]; then
        # Extrae la marca de tiempo de la última línea registrada en el log general
        tail -1 "$CRON_LOG_FILE" | sed 's/^\[//' | cut -d']' -f1
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
    stk_limpiar
    mostrar_logo
    echo ""
    pintar "$CIAN" "--- PASO 1: SELECCIONAR LA TAREA A PROGRAMAR ---"
    echo ""

    local opciones_p1="1. Modo Completo (Todas las tareas)
2. Actualización 
3. Limpieza 
4. Auditoría de seguridad
5. Reporte de servicios
6. Auditoría Firewall UFW
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
                seleccionadas=$(echo -e -n "$fzf_input" | stk_fzf_ejecutar "Seleccione tareas" "SELECCIONAR MÚLTIPLES (TAB + ENTER)" "TAREAS" \
                    --ansi --height=18 --reverse --border=rounded \
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
    stk_limpiar
    mostrar_logo
    echo ""
    pintar "$CIAN" "--- PASO 2: SELECCIONAR EL PERÍODO / FRECUENCIA ---"
    echo ""
    pintar "$VERDE_BRILLANTE" "Tareas seleccionadas para programar:"
    for tarea in "${TAREAS_SELECCIONADAS[@]}"; do
        echo -e "   ${VERDE}•${RESET} ${tarea#*:}"
    done
    echo ""

    local opciones_p2="1. Arranque (Boot+300)
2. Arranque (Boot+600)
3. Diaria (Hora configurable)
4. Semanal (Día y Hora configurable)
5. Personalizada (Sintaxis Cron libre)
6. Cancelar"

    local opc_p2=""
    if command -v fzf &>/dev/null; then
        local sel2
        sel2=$(echo -e "$opciones_p2" | fzf_estilo "Paso 2/2: Elija período" "PASO 2: CONFIGURAR FRECUENCIA")
        [ -z "$sel2" ] && return
        opc_p2=$(echo "$sel2" | awk -F'.' '{print $1}' | tr -d ' ')
    else
        echo -e "$opciones_p2"
        echo ""
        echo -ne "${AMARILLO}Seleccione frecuencia (1-6): ${RESET}"
        read -r opc_p2
    fi

    local cron_line=""
    local descripcion_freq=""

    case "$opc_p2" in
        1)
            cron_line="@reboot sleep 300 &&"
            descripcion_freq="Al iniciar el sistema + 5 minutos"
            ;;
        2)
            cron_line="@reboot sleep 600 &&"
            descripcion_freq="Al iniciar el sistema + 10 minutos"
            ;;



        3)
            echo -ne "${CIAN}Ingrese la hora 0-23 [3]: ${RESET}"
            read -r hora
            hora=${hora:-3}
            if [[ ! "$hora" =~ ^[0-9]+$ ]] || [ "$hora" -lt 0 ] || [ "$hora" -gt 23 ]; then
                hora=3
            fi
            cron_line="0 $hora * * *"
            descripcion_freq="Diaria a las ${hora}:00"
            ;;
        4)
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
        5)
            stk_limpiar
            mostrar_logo
            echo ""
            pintar "$CIAN" "════════════════════════════════════════════════════════════"
            pintar "$VERDE_BRILLANTE" "📖 GUÍA EXTENDIDA DE SINTAXIS CRON"
            pintar "$CIAN" "════════════════════════════════════════════════════════════"
            echo ""
            echo -e "${AMARILLO}1. FORMATO ESTÁNDAR (5 Campos):${RESET}"
            echo -e "   ┌───────────── minuto (0 - 59)"
            echo -e "   │ ┌─────────── hora (0 - 23)"
            echo -e "   │ │ ┌───────── día del mes (1 - 31)"
            echo -e "   │ │ │ ┌────── mes (1 - 12)"
            echo -e "   │ │ │ │ ┌──── día de la semana (0 - 6) (0=Domingo)"
            echo -e "   │ │ │ │ │"
            echo -e "   * * * * *"
            echo ""
            echo -e "${AMARILLO}2. EJEMPLOS FRECUENTES DE HORA Y DÍA:${RESET}"
            echo -e "   ${VERDE}• 0 3 * * *${RESET}          → Todos los días a las 03:00 AM"
            echo -e "   ${VERDE}• 30 22 * * *${RESET}         → Todos los días a las 10:30 PM"
            echo -e "   ${VERDE}• 0 12 * * 1${RESET}         → Todos los lunes a las 12:00 PM"
            echo -e "   ${VERDE}• 0 0 1 * *${RESET}          → El día 1 de cada mes a medianoche"
            echo ""
            echo -e "${AMARILLO}3. EJEMPLOS DE INTERVALOS REPETITIVOS:${RESET}"
            echo -e "   ${VERDE}• 0 */4 * * *${RESET}        → Cada 4 horas exactamente"
            echo -e "   ${VERDE}• */30 * * * *${RESET}       → Cada 30 minutos"
            echo -e "   ${VERDE}• 0 9-18 * * 1-5${RESET}     → Cada hora laborable (9 AM a 6 PM, Lun-Vie)"
            echo ""
            echo -e "${AMARILLO}4. MACROS DE ARRANQUE / REBOOT:${RESET}"
            echo -e "   ${VERDE}• @reboot sleep 120${RESET}   → 2 minutos después del encendido"
            echo -e "   ${VERDE}• @reboot sleep 300${RESET}   → 5 minutos después del encendido"
            echo -e "   ${VERDE}• @reboot sleep 600${RESET}   → 10 minutos después del encendido"
            echo ""
            pintar "$CIAN" "════════════════════════════════════════════════════════════"
            echo -e "${ROJO_BRILLANTE}Nota:${RESET} No es necesario incluir '&&' al final; el ejecutable lo procesa solo."
            echo ""
            echo -ne "${AMARILLO}Ingrese expresión Cron deseada: ${RESET}"
            read -r custom_schedule

            # Sanitización automática: remueve '&&' accidental y espacios de más
            custom_schedule=$(echo "$custom_schedule" | sed 's/&&//g' | xargs)

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

    # Crear lista JSON con las tareas seleccionadas en este flujo
    local json_nuevas_tareas="["
    for i in "${!tareas[@]}"; do
        local tarea_id="${tareas[$i]%%:*}"
        local tarea_desc="${tareas[$i]#*:}"
        
        # Generar un ID único por ejecución para permitir el mismo tipo de tarea en distintos horarios
        local item_id="${tarea_id}_$(date +%s%N)"
        
        [ $i -gt 0 ] && json_nuevas_tareas+=","
        json_nuevas_tareas+="{\"item_id\":\"$item_id\",\"id\":\"$tarea_id\",\"descripcion\":\"$tarea_desc\",\"schedule\":\"$cron_line\",\"frecuencia\":\"$descripcion\"}"
    done
    json_nuevas_tareas+="]"

    local tmp_json=$(mktemp)
    
    # Acumular tareas en el array mediante jq (.tareas + $nuevas) sin sobrescribir las previas
    jq --arg fecha "$(date '+%Y-%m-%d %H:%M:%S')" \
       --argjson nuevas "$json_nuevas_tareas" \
       '.configuracion.activado = true |
        .configuracion.fecha_activacion = $fecha |
        .tareas = (.tareas + $nuevas)' \
       "$CRON_CONFIG_FILE" > "$tmp_json"

    mv "$tmp_json" "$CRON_CONFIG_FILE"
    chmod 600 "$CRON_CONFIG_FILE"
}

activar_tarea_cron() {
    local cron_line="$1"
    local descripcion="$2"

    if [ ! -f "$STK_AUTO_WRAPPER" ]; then
        crear_wrapper_cron
    fi

    # 1. Guardar y acumular en el JSON
    guardar_configuracion_cron "$cron_line" "$descripcion" "${TAREAS_SELECCIONADAS[@]}"

    # 2. Limpiar entradas previas en crontab
    crontab -l 2>/dev/null | grep -v "$CRON_STK_ID" | crontab -

    # 3. Generar 1 línea por cada SCHEDULE ÚNICO separando cron de los comandos
    local lineas_cron=""
    while IFS= read -r sched; do
        [ -z "$sched" ] && continue
        local sched_limpio
        sched_limpio=$(echo "$sched" | sed 's/&&//g' | xargs)

        if [[ "$sched_limpio" == @reboot* ]]; then
            # Si incluye sleep (ej. "@reboot sleep 120"), mover el sleep tras la directiva @reboot
            local tiempo_sleep
            tiempo_sleep=$(echo "$sched_limpio" | grep -oP 'sleep \d+' || true)
            
            if [ -n "$tiempo_sleep" ]; then
                lineas_cron+="@reboot ${tiempo_sleep} && ${STK_AUTO_WRAPPER} \"${sched_limpio}\" >/dev/null 2>&1 ${CRON_STK_ID}\n"
            else
                lineas_cron+="@reboot ${STK_AUTO_WRAPPER} \"${sched_limpio}\" >/dev/null 2>&1 ${CRON_STK_ID}\n"
            fi
        else
            # Para expresiones estándar de cron (ej. "0 3 * * *")
            lineas_cron+="${sched_limpio} ${STK_AUTO_WRAPPER} \"${sched_limpio}\" >/dev/null 2>&1 ${CRON_STK_ID}\n"
        fi
    done < <(jq -r '.tareas[].schedule' "$CRON_CONFIG_FILE" | sed 's/&&//g' | sort -u)

    (crontab -l 2>/dev/null; echo -e -n "$lineas_cron") | crontab -

    if [ $? -eq 0 ]; then
        log_cron "INFO" "Tareas CRON sincronizadas correctamente en crontab"
        mostrar_resumen_final "$cron_line" "$descripcion"
    else
        pintar "$ROJO" "❌ Error al activar las tareas en CRON."
        read -p "Presione Enter..."
    fi
}
# ============================================================================
#                 NUEVAS FUNCIONES DE EDICIÓN Y ELIMINACIÓN
# ============================================================================

eliminar_tarea_especifica() {
    local item_a_eliminar="$1"

    if [ ! -f "$CRON_CONFIG_FILE" ]; then
        pintar "$ROJO" "❌ No se encontró el archivo de configuración."
        read -p "Presione Enter..."
        return 1
    fi

    local total_restantes
    total_restantes=$(jq --arg item_id "$item_a_eliminar" '[.tareas[] | select(.item_id != $item_id)] | length' "$CRON_CONFIG_FILE")
    local tmp_json=$(mktemp)

    if [ "$total_restantes" -eq 0 ]; then
        # Si no quedan tareas, limpiar todo crontab y desactivar
        crontab -l 2>/dev/null | grep -v "$CRON_STK_ID" | crontab -
        jq '.tareas = [] | .configuracion.activado = false' "$CRON_CONFIG_FILE" > "$tmp_json"
        mv "$tmp_json" "$CRON_CONFIG_FILE"
        chmod 600 "$CRON_CONFIG_FILE"
        pintar "$AMARILLO" "⚠️ Al no quedar tareas, el programador automático se ha desactivado."
    else
        # Filtrar eliminando únicamente el item_id seleccionado
        jq --arg item_id "$item_a_eliminar" '.tareas = [.tareas[] | select(.item_id != $item_id)]' "$CRON_CONFIG_FILE" > "$tmp_json"
        mv "$tmp_json" "$CRON_CONFIG_FILE"
        chmod 600 "$CRON_CONFIG_FILE"

        # Sincronizar crontab con las tareas restantes
        crontab -l 2>/dev/null | grep -v "$CRON_STK_ID" | crontab -
        local lineas_cron=""
        while IFS= read -r sched; do
            [ -z "$sched" ] && continue
            lineas_cron+="${sched} ${STK_AUTO_WRAPPER} ${CRON_STK_ID}\n"
        done < <(jq -r '.tareas[].schedule' "$CRON_CONFIG_FILE" | sort -u)

        (crontab -l 2>/dev/null; echo -e -n "$lineas_cron") | crontab -
        log_cron "INFO" "Tarea eliminada (ID Único: $item_a_eliminar)"
        pintar "$VERDE_BRILLANTE" "✔ Tarea eliminada correctamente."
    fi
    sleep 2
}

gestionar_tareas_individuales() {
    while true; do
        stk_limpiar
        mostrar_logo
        echo ""
        pintar "$CIAN" "--- ELIMINACIÓN DE TAREAS ---"
        echo ""

        if [ ! -f "$CRON_CONFIG_FILE" ]; then
            pintar "$ROJO" "❌ No hay configuración activa."
            read -p "Presione Enter..."
            return
        fi

        # Extraer item_id, descripcion y frecuencia para mostrar información clara
        local tareas_raw
        tareas_raw=$(jq -r '.tareas[] | .item_id + "|" + .descripcion + " (" + .frecuencia + ")"' "$CRON_CONFIG_FILE" 2>/dev/null)

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
            local item_id="${linea%%|*}"
            local t_desc="${linea#*|}"
            mapa_tareas[$i]="$item_id|$t_desc"
            lista_opciones+="$i. $t_desc\n"
            ((i++))
        done <<< "$tareas_raw"

        local opc_eliminar_todas=$i
        lista_opciones+="$i. 🗑️  Eliminar TODAS las tareas\n"
        ((i++))
        
        local opc_volver=$i
        lista_opciones+="$i. ↩ Volver"

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

        if [ "$seleccion" -eq "$opc_volver" ] || [ -z "$seleccion" ]; then
            break
        fi

        if [ "$seleccion" -eq "$opc_eliminar_todas" ]; then
            local confirm_todas=""
            if command -v fzf &>/dev/null; then
                confirm_todas=$(echo -e "No\nSí" | fzf_estilo "¿Seguro que desea eliminar TODAS las tareas?" "CONFIRMACIÓN")
            else
                echo -ne "${ROJO_BRILLANTE}¿Seguro que desea eliminar TODAS las tareas? s/N: ${RESET}"
                read -r conf_input
                [[ "$conf_input" =~ ^[sS]$ ]] && confirm_todas="Sí"
            fi

            if [ "$confirm_todas" == "Sí" ]; then
                desactivar_cron
                break
            fi
            continue
        fi

        local tarea_elegida="${mapa_tareas[$seleccion]}"
        local sel_item_id="${tarea_elegida%%|*}"
        local sel_desc="${tarea_elegida#*|}"

        local confirm_indiv=""
        if command -v fzf &>/dev/null; then
            confirm_indiv=$(echo -e "No\nSí" | fzf_estilo "¿Eliminar '$sel_desc'?" "CONFIRMACIÓN ELIMINACIÓN")
        else
            echo -ne "${ROJO_BRILLANTE}¿Eliminar '$sel_desc'? s/N: ${RESET}"
            read -r conf_input
            [[ "$conf_input" =~ ^[sS]$ ]] && confirm_indiv="Sí"
        fi

        if [ "$confirm_indiv" == "Sí" ]; then
            eliminar_tarea_especifica "$sel_item_id"
        fi
    done
}

mostrar_resumen_final() {
    local cron_line="$1"
    local descripcion="$2"
    
    stk_limpiar
    echo -e "${VERDE_BRILLANTE}"
    echo "╔═════════════════════════════════════════════════════════════╗"
    echo "║                                                             ║"
    echo "║                  ✅ TAREA AUTOMÁTICA ACTIVADA               ║"
    echo "║                                                             ║"
    echo "╚═════════════════════════════════════════════════════════════╝"
    echo -e "${RESET}"
    echo ""
    echo -e "${CIAN}══════════════════════════════════════════════════════════${RESET}"
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
    stk_limpiar
    mostrar_logo
    echo ""
    pintar "$CIAN" "--- CONFIGURACIÓN ACTUAL ---"
    echo ""
    
    if [ -f "$CRON_CONFIG_FILE" ]; then
        local activado=$(jq -r '.configuracion.activado // false' "$CRON_CONFIG_FILE")
        local fecha_act=$(jq -r '.configuracion.fecha_activacion // "N/A"' "$CRON_CONFIG_FILE")
        local ult_ejec=$(jq -r '.configuracion.ultima_ejecucion // "Nunca"' "$CRON_CONFIG_FILE")
        local total_tareas=$(jq -r '.tareas | length' "$CRON_CONFIG_FILE" 2>/dev/null || echo 0)

        if [ "$activado" == "true" ] && [ "$total_tareas" -gt 0 ]; then
            echo -e "Estado general:   ${VERDE_BRILLANTE}ACTIVO${RESET}"
        else
            echo -e "Estado general:   ${ROJO}INACTIVO${RESET}"
        fi

        if [ "$(notificaciones_estado)" == "true" ]; then
            echo -e "Notificaciones:   ${VERDE_BRILLANTE}🔔 ACTIVADAS${RESET}"
        else
            echo -e "Notificaciones:   ${ROJO}🔕 DESACTIVADAS${RESET}"
        fi

        echo -e "Activado el:      ${AZUL}$fecha_act${RESET}"
        echo -e "Última ejecución: ${AZUL}$ult_ejec${RESET}"
        echo ""
        echo -e "${AMARILLO}Tareas programadas ($total_tareas):${RESET}"
        
        if [ "$total_tareas" -gt 0 ]; then
            jq -r '.tareas[] | "  • " + .descripcion + "\n    ↳ Frecuencia: " + .frecuencia + " (" + .schedule + ")"' "$CRON_CONFIG_FILE"
        else
            echo -e "  ${ROJO}(Ninguna tarea programada)${RESET}"
        fi
    else
        pintar "$ROJO" "❌ No hay configuración activa."
    fi
    echo ""
    read -p "Presione Enter para continuar..."
}

ver_logs_cron() {
    stk_limpiar
    mostrar_logo
    echo ""
    pintar "$CIAN" "--- LOGS DE EJECUCIÓN CRON ---"
    echo ""
    
    if [ -f "$CRON_LOG_FILE" ]; then
        
        echo -e "${CIAN}═══════════════════════════════════════════════${RESET}"
        tail -n 18 "$CRON_LOG_FILE"
        echo -e "${CIAN}═══════════════════════════════════════════════${RESET}"
        
        
        echo -e "${AMARILLO}Logs específicos de tareas:${RESET}"
        for tarea in actualizacion limpieza auditoria servicios ufw; do
            local log_file="/var/log/stk_cron_${tarea}.log"
            if [ -f "$log_file" ]; then
                local size=$(du -h "$log_file" 2>/dev/null | cut -f1)
                echo -e "  ${VERDE}•${RESET} $tarea: $size"
            fi
        done
        
        
        echo -e "${AMARILLO}Tamaño total del log:${RESET} $(du -h "$CRON_LOG_FILE" | cut -f1)"
    else
        pintar "$ROJO" "❌ No hay logs de ejecución aún."
    fi
    echo ""
    pintar "$CIAN" "--- ÚLTIMOS LOGS DE EJECUCIÓN CRON ---"
    echo ""
    read -p "Presione cualquier tecla para ver el resumen..."
}

ver_resumen_cron() {
    stk_limpiar
    mostrar_logo
        
    if [ -f "$CRON_RESUMEN_FILE" ]; then
        echo -e "${AMARILLO}Último resumen de ejecución cron:${RESET}"
        echo -e "${CIAN}═══════════════════════════════════════════════${RESET}"
        tail -n 100 "$CRON_RESUMEN_FILE"
        
    else
        pintar "$ROJO" "❌ No hay resúmenes de ejecución aún."
    fi
    echo ""
    pintar "$CIAN" "--- FINAL DEL RESUMEN ÚLTIMAS EJECUCIONES CRON ---"
    echo ""
    read -p "Presione cualquier tecla para continuar..."
}

configurar_notificaciones() {
    if [ ! -f "$CRON_CONFIG_FILE" ]; then
        pintar "$ROJO" "❌ No hay configuración. Programa una tarea primero."
        read -p "Presione Enter..."
        return
    fi

    while true; do
        stk_limpiar
        mostrar_logo
        echo ""
        pintar "$CIAN" "--- NOTIFICACIONES DE TAREAS AUTOMÁTICAS ---"
        echo ""

        local estado_actual
        estado_actual=$(notificaciones_estado)
        if [ "$estado_actual" == "true" ]; then
            echo -e "Estado actual: ${VERDE_BRILLANTE}🔔 ACTIVADAS${RESET}"
        else
            echo -e "Estado actual: ${ROJO}🔕 DESACTIVADAS${RESET}"
        fi
        echo ""
        echo -e "${AMARILLO}Las notificaciones avisan en el escritorio del usuario al terminar cada ejecución.${RESET}"
        echo -e "${AMARILLO}Desactivarlas no afecta a las tareas: solo silencia los avisos.${RESET}"
        echo ""

        local opciones="1. Activar notificaciones
2. Desactivar notificaciones
3. ↩ Volver"

        local opc=""
        if command -v fzf &>/dev/null; then
            local sel
            sel=$(echo -e "$opciones" | fzf_estilo "Selecciona una opción" "NOTIFICACIONES CRON")
            [ -z "$sel" ] && return
            opc=$(echo "$sel" | awk -F'.' '{print $1}' | tr -d ' ')
        else
            echo -e "$opciones"
            echo ""
            echo -ne "${AMARILLO}Seleccione opción (1-3): ${RESET}"
            read -r opc
        fi

        local nuevo_estado=""
        case "$opc" in
            1) nuevo_estado="true" ;;
            2) nuevo_estado="false" ;;
            *) return ;;
        esac

        if [ "$nuevo_estado" == "$estado_actual" ]; then
            pintar "$AZUL" "Las notificaciones ya están en ese estado."
            sleep 2
            continue
        fi

        local tmp_json=$(mktemp)
        if jq --argjson val "$nuevo_estado" '.configuracion.notificaciones = $val' "$CRON_CONFIG_FILE" > "$tmp_json" 2>/dev/null; then
            mv "$tmp_json" "$CRON_CONFIG_FILE"
            chmod 600 "$CRON_CONFIG_FILE"
            if [ "$nuevo_estado" == "true" ]; then
                pintar "$VERDE_BRILLANTE" "✔ Notificaciones ACTIVADAS."
                log_cron "INFO" "Notificaciones de tareas CRON activadas"
            else
                pintar "$VERDE_BRILLANTE" "✔ Notificaciones DESACTIVADAS."
                log_cron "INFO" "Notificaciones de tareas CRON desactivadas"
            fi
        else
            rm -f "$tmp_json"
            pintar "$ROJO" "❌ No se pudo guardar la preferencia de notificaciones."
        fi
        sleep 2
    done
}

desactivar_cron() {
    stk_limpiar
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
            local notif_actual
            notif_actual=$(notificaciones_estado)
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
    "version": "$ver",
    "configuracion": {
        "schedule": null,
        "descripcion": "Ninguna",
        "activado": false,
        "fecha_activacion": null,
        "ultima_ejecucion": null,
        "notificaciones": $notif_actual
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
logs_resumen() {
    stk_limpiar
    mostrar_logo
    echo ""
    
    ver_logs_cron

    stk_limpiar
    mostrar_logo
    echo ""

    ver_resumen_cron
}
gestionar_tareas_auto() {
    inicializar_estructura
    
    while true; do
        stk_limpiar
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
            if [ "$(notificaciones_estado)" == "true" ]; then
                echo -e "   ${AMARILLO}Notificaciones:${RESET}   ${VERDE}🔔 Activadas${RESET}"
            else
                echo -e "   ${AMARILLO}Notificaciones:${RESET}   ${ROJO}🔕 Desactivadas${RESET}"
            fi
        else
            echo -e "${ROJO}❌ No hay tareas programadas${RESET}"
        fi
        echo ""
        echo -e "${CIAN}═══════════════════════════════════════════════${RESET}"
        echo ""

        local opciones_fzf="1. Programar Tareas
2. Desactivar Tareas
3. Configuración actual
4. Ver Logs/Resumen
5. Notificaciones (Activar/Desactivar)
6. Volver"

        local seleccion
        seleccion=$(echo "$opciones_fzf" | fzf_estilo "Selecciona una opción" "Menú de Tareas Automatizadas")

        [ -z "$seleccion" ] && break

        case "$(echo "$seleccion" | awk '{print $1}' | tr -d '.')" in
            1) programar_nueva_tarea ;;
            2) gestionar_tareas_individuales ;;
            3) ver_configuracion_cron ;;
            4) logs_resumen ;;
            5) configurar_notificaciones ;;
            6) break ;;
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