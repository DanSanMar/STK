#!/bin/bash
# ==============================================================================
#                 GESTOR DE TAREAS AUTOMATIZADAS (CRON)
# ==============================================================================
# Pasamos a cron4me
# ==============================================================================
ver="v 4.6"
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
    fzf --ansi \
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
# CREAR WRAPPER 
crear_wrapper_cron() {
    cat << 'EOF' > "$STK_AUTO_WRAPPER"
#!/bin/bash
# ==============================================================================
#           STK - WRAPPER Y EJECUTOR DE TAREAS AUTOMÁTICAS (CRON)
# ==============================================================================
export PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"
export HOME="/root"
export TERM="linux"
export LANG="es_ES.UTF-8"

CRON_CONFIG_FILE="/etc/stk/cron/tasks.json"
CRON_LOG_FILE="/var/log/stk_cron.log"
CRON_RESUMEN_FILE="/var/log/stk_cron_resumen.log"

# --- FUNCIÓN DE LOGGING ÚNICA ---
log_cron_exec() {
    local nivel="${1:-INFO}"
    local mensaje="${2}"
    local fecha=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$fecha] [$nivel] [root] - $mensaje" >> "$CRON_LOG_FILE"
}

# ==============================================================================
#                 SUBRUTINAS TÉCNICAS (ACTUALIZACIÓN Y LIMPIEZA)
# ==============================================================================

Actualizar_sistema() {
    local status=0
    if command -v pacman &>/dev/null; then
        echo "📦 Sincronizando repositorios y sistema (PACMAN)..."
        pacman -Syu --noconfirm || status=1
    elif command -v apt-get &>/dev/null; then
        echo "📦 Sincronizando repositorios y sistema (APT)..."
        apt-get update -y && apt-get upgrade -y || status=1
    fi

    if command -v flatpak &>/dev/null; then
        echo "📦 Actualizando paquetes Flatpak..."
        flatpak update -y || true
    fi

    return $status
}

super_limpieza() {
    local status=0
    if command -v pacman &>/dev/null; then
        echo "🧹 Limpiando caché de paquetes y huérfanos (PACMAN)..."
        pacman -Sc --noconfirm &>/dev/null || true
        local huerfanos=$(pacman -Qtdq 2>/dev/null)
        if [ -n "$huerfanos" ]; then
            pacman -Rns $huerfanos --noconfirm || status=1
        fi
    elif command -v apt-get &>/dev/null; then
        echo "🧹 Limpiando caché y paquetes no requeridos (APT)..."
        apt-get autoremove -y && apt-get clean || status=1
    fi

    # Limpieza de logs journalctl > 7 días
    if command -v journalctl &>/dev/null; then
        journalctl --vacuum-time=7d &>/dev/null || true
    fi

    return $status
}

# ==============================================================================
#                 VERSIONES AUTOMÁTICAS (Sin interacción)
# ==============================================================================

ejecutar_auto_actualizacion() {
    log_cron_exec "INFO" "▶ Inicio: Actualización del sistema"
    echo "🔄 INICIANDO ACTUALIZACIÓN DEL SISTEMA..."
    Actualizar_sistema
    local res=$?
    if [ $res -eq 0 ]; then
        log_cron_exec "INFO" "✅ Actualización completada"
        echo "✅ Actualización completada correctamente."
    else
        log_cron_exec "ERROR" "❌ Actualización falló"
        echo "❌ Error al ejecutar la actualización."
    fi
    return $res
}

ejecutar_auto_limpieza() {
    log_cron_exec "INFO" "▶ Inicio: Limpieza del sistema"
    echo "🧹 INICIANDO LIMPIEZA DEL SISTEMA..."
    super_limpieza
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
    
    local total_checks=0
    local checks_passed=0
    local alertas=()
    
    # 1. UID 0
    ((total_checks++))
    if [ $(awk -F: '$3 == 0 {print $1}' /etc/passwd 2>/dev/null | wc -l) -eq 1 ]; then
        ((checks_passed++))
    else
        alertas+=("Múltiples usuarios con UID 0")
    fi
    
    # 2. Cuentas sin contraseña
    ((total_checks++))
    if [ -z "$(awk -F: '($2 == "" || $2 == "!") {print $1}' /etc/shadow 2>/dev/null)" ]; then
        ((checks_passed++))
    else
        alertas+=("Cuentas inactivas o sin contraseña")
    fi
    
    # 3. Firewall
    ((total_checks++))
    if command -v ufw &>/dev/null && ufw status | grep -q "active"; then
        ((checks_passed++))
    else
        alertas+=("Firewall inactivo o sin reglas")
    fi
    
    # 4. SSH
    ((total_checks++))
    if command -v ss &>/dev/null; then
        if ! ss -tulpn 2>/dev/null | grep LISTEN | grep -E "0\.0\.0\.0:22|:::22|\*:22" &>/dev/null; then
            ((checks_passed++))
        else
            alertas+=("SSH expuesto en puerto 22")
        fi
    else
        ((checks_passed++))
    fi
    
    # 5. MAC (SELinux/AppArmor)
    ((total_checks++))
    if command -v getenforce &>/dev/null && [ "$(getenforce 2>/dev/null)" == "Enforcing" ]; then
        ((checks_passed++))
    elif command -v aa-status &>/dev/null && aa-status --enabled 2>/dev/null; then
        ((checks_passed++))
    else
        alertas+=("Sin módulo MAC activo")
    fi
    
    local score=$(( (checks_passed * 100) / total_checks ))
    echo "📊 Puntuación: ${score}% (${checks_passed}/${total_checks})"
    
    if [ ${#alertas[@]} -gt 0 ]; then
        echo "⚠️ Alertas detectadas:"
        for alt in "${alertas[@]}"; do
            echo "  • $alt"
        done
    else
        echo "✅ No se detectaron alertas de seguridad."
    fi
    return 0
}

ejecutar_auto_servicios() {
    log_cron_exec "INFO" "▶ Inicio: Reporte de servicios"
    echo "📊 REPORTE DE SERVICIOS (Systemd)"
    echo "----------------------------------------"
    
    local failed_services
    failed_services=$(systemctl list-units --state=failed --no-legend --plain 2>/dev/null | awk '{print $1}')
    
    if [ -n "$failed_services" ]; then
        local count=$(echo "$failed_services" | wc -l)
        echo "⚠️ Servicios fallidos detectados: $count"
        echo "$failed_services" | while read -r svc; do
            echo "  • $svc"
        done
        return 1
    else
        echo "✅ Todos los servicios operan correctamente."
        return 0
    fi
}

ejecutar_auto_ufw() {
    log_cron_exec "INFO" "▶ Inicio: Auditoría UFW"
    echo "🛡️ AUDITORÍA UFW"
    echo "----------------------------------------"
    
    if ! command -v ufw &>/dev/null; then
        echo "❌ UFW no está instalado en el sistema."
        return 1
    fi
    
    echo "📋 Estado de UFW:"
    ufw status verbose 2>/dev/null | head -20
    
    if [ -f "/var/log/ufw.log" ]; then
        echo ""
        echo "📊 Estadísticas:"
        local block_count=$(grep -c "UFW BLOCK" /var/log/ufw.log 2>/dev/null | tail -1)
        echo "  • Bloqueos totales: $block_count"
        echo ""
        echo "🔍 Últimos bloqueos:"
        grep "UFW BLOCK" /var/log/ufw.log 2>/dev/null | tail -5 | while read -r line; do
            echo "  • $line"
        done
    else
        echo "  ℹ️ No se encontró el log de UFW."
    fi
    return 0
}
# ==============================================================================
#           VERIFICACIÓN E INSTALACIÓN DE DEPENDENCIAS (PACMAN / APT)
# ==============================================================================

verificar_dependencias() {
    local pkgs_faltantes=()

    # 1. Verificar si notify-send está disponible
    if ! command -v notify-send &>/dev/null; then
        pkgs_faltantes+=("libnotify")
    fi

    # 2. Si faltan paquetes, intentamos instalar de forma desatendida
    if [ ${#pkgs_faltantes[@]} -gt 0 ]; then
        log_cron "WARN" "Instalando dependencias faltantes: ${pkgs_faltantes[*]}"
        
        if command -v pacman &>/dev/null; then
            # Arch Linux / Manjaro / EndeavourOS
            pacman -Sy --noconfirm --needed "${pkgs_faltantes[@]}" &>/dev/null
        elif command -v apt-get &>/dev/null; then
            # Debian / Ubuntu / Kali
            apt-get update -y &>/dev/null && apt-get install -y "${pkgs_faltantes[@]}" &>/dev/null
        fi
    fi
}

# ==============================================================================
#           SISTEMA DE NOTIFICACIÓN 
# ==============================================================================

# Función auxiliar para abrir el informe dentro del contexto del usuario gráfico
abrir_informe_grafico() {
    local usuario="$1"
    local user_id="$2"
    local archivo="$3"
    local dbus_socket="/run/user/${user_id}/bus"

    sudo -u "$usuario" \
        DBUS_SESSION_BUS_ADDRESS="unix:path=${dbus_socket}" \
        DISPLAY="${DISPLAY:-:0}" \
        bash -c "
            if command -v xdg-open &>/dev/null; then
                xdg-open '$archivo' &>/dev/null &
            elif command -v x-terminal-emulator &>/dev/null; then
                x-terminal-emulator -e less +G '$archivo' &>/dev/null &
            elif command -v gnome-terminal &>/dev/null; then
                gnome-terminal -- less +G '$archivo' &>/dev/null &
            elif command -v xterm &>/dev/null; then
                xterm -e less +G '$archivo' &>/dev/null &
            fi
        " &>/dev/null &
}

enviar_notificacion() {
    verificar_dependencias

    # 1. Detectar usuario activo en sesión gráfica o TTY
    local usuario_activo
    usuario_activo=$(who | grep -E '(:[0-9]|tty[0-9]|x11|wayland)' | awk '{print $1}' | head -n 1)
    [ -z "$usuario_activo" ] && usuario_activo=$(loginctl list-sessions --no-legend 2>/dev/null | awk '{print $3}' | head -n 1)
    [ -z "$usuario_activo" ] && usuario_activo=$(whoami)
    [ -z "$usuario_activo" ] && return 1

    local user_id
    user_id=$(id -u "$usuario_activo" 2>/dev/null)
    [ -z "$user_id" ] && return 1

    [ ! -f "$CRON_RESUMEN_FILE" ] && return 1

    # 2. Extraer el último bloque de ejecución
    local ultimo_bloque
    ultimo_bloque=$(awk '/═══════════════════════════════════════════════════════════════/{block=""} {block=block $0 "\n"} END{printf "%s", block}' "$CRON_RESUMEN_FILE" 2>/dev/null)
    [ -z "$ultimo_bloque" ] && ultimo_bloque=$(tail -n 50 "$CRON_RESUMEN_FILE")

    # 3. Construir mensaje
    local titulo="STK: Informe de Tareas Automáticas"
    local mensaje=""
    local urgencia="normal"
    local icono="dialog-information"

    if echo "$ultimo_bloque" | grep -qi "AUDITORÍA"; then
        local puntuacion=$(echo "$ultimo_bloque" | grep "Puntuación:" | tail -1 | sed 's/.*Puntuación: \([^)]*\).*/\1/' | xargs)
        mensaje+="🔍 Auditoría: ${puntuacion:-Sin datos}\n"
    fi

    if echo "$ultimo_bloque" | grep -q "❌"; then
        urgencia="critical"
        icono="dialog-warning"
    fi

    [ -z "$mensaje" ] && mensaje="✅ Ejecución finalizada sin incidencias."
    
    # Formatear el archivo como enlace HTML accesible
    mensaje+="\n📁 Log: <a href=\"file://$CRON_RESUMEN_FILE\">$CRON_RESUMEN_FILE</a>"

    # 4. Envío DBus interactivo con proceso persistente de captura de acción
    if command -v notify-send &>/dev/null; then
        local dbus_socket="/run/user/${user_id}/bus"
        
        if [ -S "$dbus_socket" ]; then
            sudo -u "$usuario_activo" \
                DBUS_SESSION_BUS_ADDRESS="unix:path=${dbus_socket}" \
                DISPLAY="${DISPLAY:-:0}" \
                nohup bash -c '
                    res=$(notify-send -u "'"$urgencia"'" -i "'"$icono"'" -t 20000 \
                        --action="default=Abrir informe completo" \
                        --action="abrir=📋 Abrir Log" \
                        "'"$titulo"'" "'$(echo -e "$mensaje")'" 2>/dev/null)
                    
                    if [ "$res" = "default" ] || [ "$res" = "abrir" ]; then
                        if command -v xdg-open &>/dev/null; then
                            xdg-open "'"$CRON_RESUMEN_FILE"'" &>/dev/null &
                        elif command -v x-terminal-emulator &>/dev/null; then
                            x-terminal-emulator -e less +G "'"$CRON_RESUMEN_FILE"'" &>/dev/null &
                        fi
                    fi
                ' >/dev/null 2>&1 &
            return 0
        fi
    fi

    # Fallback Terminal
    if command -v wall &>/dev/null; then
        printf "\n========================================\n  %s\n========================================\n%s\n========================================\n\n" \
            "$titulo" "$mensaje" | wall 2>/dev/null
    fi

    return 0
}}

# ==============================================================================
#                 FLUJO PRINCIPAL DE EJECUCIÓN
# ==============================================================================

TAREA_ARG="$1"
if [ -n "$TAREA_ARG" ]; then
    TAREAS="$TAREA_ARG"
elif command -v jq &>/dev/null; then
    TAREAS=$(jq -r ".tareas[] | .id" "$CRON_CONFIG_FILE" 2>/dev/null | tr "\n" " ")
else
    TAREAS=$(grep -o "\"id\":\"[^\"]*\"" "$CRON_CONFIG_FILE" 2>/dev/null | cut -d'"' -f4 | tr "\n" " ")
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
        RESULTADOS+=("✅ ${tarea^^}: Completada")
    else
        RESULTADOS+=("❌ ${tarea^^}: Falló (Código $STATUS_CODE)")
    fi
    
    if [ -s "$LOG_TEMP" ]; then
        cat "$LOG_TEMP" >> "/var/log/stk_cron_${tarea}.log" 2>/dev/null
        DETALLES_INFORME+="$(cat "$LOG_TEMP")$(printf '\n\n')"
    fi
    rm -f "$LOG_TEMP"
done

T_FIN=$(date +%s)
DURACION=$((T_FIN - T_INICIO))

# Guardar informe en el Log de Resumen de ejecuciones
{
    echo "═══════════════════════════════════════════════════════════════"
    echo "📊 RESUMEN EJECUCIÓN - $(date "+%Y-%m-%d %H:%M:%S")"
    echo "═══════════════════════════════════════════════════════════════"
    echo "⏱️  Duración: ${DURACION} segundos"
    echo "📋 Tarea: $TAREA_ARG"
    echo ""
    for resultado in "${RESULTADOS[@]}"; do
        echo "  $resultado"
    done
    echo ""
    echo "--- DETALLES DE LA EJECUCIÓN ---"
    echo -e "$DETALLES_INFORME"
    echo "═══════════════════════════════════════════════════════════════"
} >> "$CRON_RESUMEN_FILE"

# Actualizar fecha de última ejecución
TMP_JSON=$(mktemp)
jq --arg fecha "$(date '+%Y-%m-%d %H:%M:%S')" '.configuracion.ultima_ejecucion = $fecha' "$CRON_CONFIG_FILE" > "$TMP_JSON" 2>/dev/null && mv "$TMP_JSON" "$CRON_CONFIG_FILE"

enviar_notificacion

exit 0
EOF

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
    clear
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

    # Crear objetos JSON donde cada tarea incluye su propia frecuencia y schedule
    local json_nuevas_tareas="["
    for i in "${!tareas[@]}"; do
        local tarea_id="${tareas[$i]%%:*}"
        local tarea_desc="${tareas[$i]#*:}"
        
        if [ $i -gt 0 ]; then json_nuevas_tareas+=","; fi
        json_nuevas_tareas+="{\"id\":\"$tarea_id\",\"descripcion\":\"$tarea_desc\",\"schedule\":\"$cron_line\",\"frecuencia\":\"$descripcion\"}"
    done
    json_nuevas_tareas+="]"

    if [ -f "$CRON_CONFIG_FILE" ] && command -v jq &>/dev/null; then
        local tmp_json=$(mktemp)
        jq --arg fecha "$(date '+%Y-%m-%d %H:%M:%S')" \
           --argjson nuevas "$json_nuevas_tareas" \
           '.configuracion.activado = true |
            .configuracion.fecha_activacion = $fecha |
            .tareas = ( (.tareas + $nuevas) | unique_by(.id) )' \
           "$CRON_CONFIG_FILE" > "$tmp_json" 2>/dev/null

        if [ $? -eq 0 ]; then
            mv "$tmp_json" "$CRON_CONFIG_FILE"
            chmod 600 "$CRON_CONFIG_FILE"
            return 0
        else
            rm -f "$tmp_json"
        fi
    fi

    cat > "$CRON_CONFIG_FILE" << EOF
{
    "version": "$ver",
    "configuracion": {
        "activado": true,
        "fecha_activacion": "$(date '+%Y-%m-%d %H:%M:%S')",
        "ultima_ejecucion": "Pendiente"
    },
    "tareas": $json_nuevas_tareas
}
EOF
    chmod 600 "$CRON_CONFIG_FILE"
}

activar_tarea_cron() {
    local cron_line="$1"
    local descripcion="$2"

    if [ ! -f "$STK_AUTO_WRAPPER" ]; then
        crear_wrapper_cron
    fi

    guardar_configuracion_cron "$cron_line" "$descripcion" "${TAREAS_SELECCIONADAS[@]}"

    # Limpiar entradas antiguas del script en crontab
    crontab -l 2>/dev/null | grep -v "$CRON_STK_ID" | crontab -

    # Generar entradas de crontab independientes para cada tarea según su schedule
    if command -v jq &>/dev/null && [ -f "$CRON_CONFIG_FILE" ]; then
        local lineas_cron=""
        while IFS= read -r item; do
            [ -z "$item" ] && continue
            local t_id=$(echo "$item" | cut -d'|' -f1)
            local t_sched=$(echo "$item" | cut -d'|' -f2)
            lineas_cron+="${t_sched} ${STK_AUTO_WRAPPER} ${t_id} ${CRON_STK_ID}\n"
        done < <(jq -r '.tareas[] | .id + "|" + .schedule' "$CRON_CONFIG_FILE" 2>/dev/null)

        (crontab -l 2>/dev/null; echo -e -n "$lineas_cron") | crontab -
    fi

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
        
        pintar "$AMARILLO" "⚠️ Al no quedar tareas, el programador automático se ha desactivado."
    else
        # Eliminar solo la tarea seleccionada manteniendo la configuración de cron
        jq --arg id "$id_a_eliminar" \
           '.tareas = [.tareas[] | select(.id != $id)]' \
           "$CRON_CONFIG_FILE" > "$tmp_json"
           
        # --- AÑADIR ESTA REGENERACIÓN DE CRONTAB ---
        mv "$tmp_json" "$CRON_CONFIG_FILE"
        chmod 600 "$CRON_CONFIG_FILE"

        crontab -l 2>/dev/null | grep -v "$CRON_STK_ID" | crontab -
        local lineas_cron=""
        while IFS= read -r item; do
            [ -z "$item" ] && continue
            local t_id=$(echo "$item" | cut -d'|' -f1)
            local t_sched=$(echo "$item" | cut -d'|' -f2)
            lineas_cron+="${t_sched} ${STK_AUTO_WRAPPER} ${t_id} ${CRON_STK_ID}\n"
        done < <(jq -r '.tareas[] | .id + "|" + .schedule' "$CRON_CONFIG_FILE" 2>/dev/null)

        (crontab -l 2>/dev/null; echo -e -n "$lineas_cron") | crontab -
        log_cron "INFO" "Tarea eliminada e índex de crontab actualizado: $id_a_eliminar"
        pintar "$VERDE_BRILLANTE" "✔ Tarea '$id_a_eliminar' eliminada correctamente."
        sleep 2
        return 0
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
            local activado=$(jq -r '.configuracion.activado // false' "$CRON_CONFIG_FILE")
            local fecha_act=$(jq -r '.configuracion.fecha_activacion // "N/A"' "$CRON_CONFIG_FILE")
            local ult_ejec=$(jq -r '.configuracion.ultima_ejecucion // "Nunca"' "$CRON_CONFIG_FILE")
            local total_tareas=$(jq -r '.tareas | length' "$CRON_CONFIG_FILE" 2>/dev/null || echo 0)

            if [ "$activado" == "true" ] && [ "$total_tareas" -gt 0 ]; then
                echo -e "Estado general:   ${VERDE_BRILLANTE}ACTIVO${RESET}"
            else
                echo -e "Estado general:   ${ROJO}INACTIVO${RESET}"
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
logs_resumen() {
    clear
    mostrar_logo
    echo ""
    
    ver_logs_cron

    clear
    mostrar_logo
    echo ""

    ver_resumen_cron
}
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

        local opciones_fzf="1. Programar Tareas
2. Gestionar/Eliminar tareas 
3. Configuración actual
4. Ver Logs/Resumen
5. Desactivar TODAS las tareas
6. Volver"

        # Captura la selección del usuario mediante fzf_estilo
        local seleccion
        seleccion=$(echo "$opciones_fzf" | fzf_estilo "Selecciona una opción" "Menú de Tareas Automatizadas")

        # Si presiona ESC o se cancela, sale del bucle
        if [ -z "$seleccion" ]; then
            break
        fi

        # Extrae el número inicial del string seleccionado (ej: "1")
        local opcion_num
        opcion_num=$(echo "$seleccion" | awk '{print $1}' | tr -d '.')

        case "$opcion_num" in
            1) programar_nueva_tarea ;;
            2) gestionar_tareas_individuales ;;
            3) ver_configuracion_cron ;;
            4) logs_resumen ;;
            5) desactivar_cron ;;
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