#!/bin/bash

# --- CONFIGURACIÓN DE COLORES ---
RESET='\e[0m'
NEGRITA='\e[1m'
VERDE_BRILLANTE='\e[92m'
VERDE='\e[32m'
AMARILLO='\e[33m'
AZUL='\e[34m'
AZUL_BRILLANTE='\e[94m'
CIAN='\e[36m'
ROJO='\e[31m'
ROJO_BRILLANTE='\e[91m'
BLANCO='\e[97m'

mostrar_logo_dash4me() {
    echo -e "\e[K${CIAN}  ██████╗  █████╗ ███████╗██╗  ██╗██╗  ██╗███╗   ███╗███████╗"
    echo -e "\e[K${AZUL_BRILLANTE}  ██╔══██╗██╔══██╗██╔════╝██║  ██║██║  ██║████╗ ████║██╔════╝"
    echo -e "\e[K${AZUL}  ██║  ██║███████║███████╗███████║███████║██╔████╔██║█████╗  "
    echo -e "\e[K${AZUL}  ██║  ██║██╔══██║╚════██║██╔══██║╚════██║██║╚██╔╝██║██╔══╝  "
    echo -e "\e[K${AZUL_BRILLANTE}  ██████╔╝██║  ██║███████║██║  ██║     ██║██║ ╚═╝ ██║███████╗"
    echo -e "\e[K${VERDE_BRILLANTE}  ╚═════╝ ╚═╝  ╚═╝╚══════╝╚═╝  ╚═╝     ╚═╝╚═╝     ╚═╝╚══════╝${RESET}"
    echo -e "\e[K${AZUL}  ------------------------------------------------------------${RESET}"
}

dibujar_barra() {
    local porcentaje=$1
    local color=$VERDE
    local total_bloques=20
    local rellenos=$(( porcentaje * total_bloques / 100 ))
    if [ "$porcentaje" -gt 85 ]; then color=$ROJO
    elif [ "$porcentaje" -gt 60 ]; then color=$AMARILLO
    fi
    printf "${color}["
    for ((i=0; i<rellenos; i++)); do printf "■"; done
    for ((i=rellenos; i<total_bloques; i++)); do printf " "; done
    printf "] %3d%%${RESET}" "$porcentaje"
}

interpretar() {
    local val=$1
    local tipo=$2
    if [ "$val" -gt 85 ]; then
        case "$tipo" in
            "cpu")   echo -e "${ROJO_BRILLANTE}CRÍTICO (Sobrecarga)${RESET}" ;;
            "ram")   echo -e "${ROJO_BRILLANTE}CRÍTICO (Sin memoria)${RESET}" ;;
            "disco") echo -e "${ROJO_BRILLANTE}CRÍTICO (Disco lleno)${RESET}" ;;
        esac
    elif [ "$val" -gt 65 ]; then echo -e "${AMARILLO}ALTO (Carga)${RESET}"
    else echo -e "${VERDE}ÓPTIMO${RESET}"; fi
}

obtener_resumen_inicio() {
    local uptime_str=$(uptime -p 2>/dev/null | sed 's/up //')
    local load_avg=$(uptime | awk -F'load average:' '{ print $2 }' | sed 's/^[ \t]*//')
    local svcs_failed=0
    if command -v systemctl &>/dev/null; then
        svcs_failed=$(systemctl list-units --state=failed --no-legend 2>/dev/null | wc -l)
    fi
    local usbs=$(lsblk -o MOUNTPOINT -n 2>/dev/null | grep -E "^/(media|run/media|mnt)" | wc -l)

    echo -e "\e[K${CIAN}------------- RESUMEN DE ARRANQUE -----------${RESET}"
    echo -e "\e[K   ${BLANCO}Encendido:${RESET} $uptime_str | ${BLANCO}Carga media:${RESET} $load_avg"
    
    if [ "$svcs_failed" -gt 0 ]; then
        echo -e "\e[K   ${ROJO_BRILLANTE}Servicios fallidos:${RESET} $svcs_failed (Revisar con systemctl)"
    else
        echo -e "\e[K   ${VERDE}Estado Servicios:${RESET} Todos funcionando correctamente"
    fi

    if [ "$usbs" -gt 0 ]; then
        echo -e "\e[K   ${AMARILLO}Unidades externas:${RESET} $usbs montada(s)"
    fi
}

monitor_rendimiento() {
    if command -v tput &> /dev/null; then
        tput civis
    fi

    trap "tput cnorm 2>/dev/null; clear; exit 0" SIGINT SIGTERM
    
    # Se limpia la pantalla UNA SOLA VEZ al arrancar
    clear

    while true; do
        # Redirigimos la salida a una variable para evitar redibujados intermedios
        OUTPUT=$(
            echo -ne "\e[H" # Mueve el cursor a la esquina superior izquierda sin limpiar
            mostrar_logo_dash4me
            echo -e "\e[K${NEGRITA}-------- MONITOR DE SISTEMA DASH4ME (Ctrl+C para salir) --------${RESET}"
            echo -e "\e[K${CIAN}Tasa Auto-refresco: 5s | Pulsa ENTER para actualizar antes${RESET}\n"

            CPU_MODEL=$(grep -m1 "model name" /proc/cpuinfo | cut -d: -f2 | sed -e 's/^[ \t]*//' -e 's/(R)//g' -e 's/(TM)//g' -e 's/  */ /g')
            CPU_CORES=$(nproc)
            CPU_MHZ=$(grep -m1 "cpu MHz" /proc/cpuinfo | awk '{print int($4)}')
            CPU_GHZ=$(awk "BEGIN {printf \"%.2f\", $CPU_MHZ/1000}")

            CPU_STATS=$(grep 'cpu ' /proc/stat)
            IDLE_1=$(echo $CPU_STATS | awk '{print $5}')
            TOTAL_1=$(echo $CPU_STATS | awk '{print $2+$3+$4+$5+$6+$7+$8}')
            sleep 0.1
            CPU_STATS=$(grep 'cpu ' /proc/stat)
            IDLE_2=$(echo $CPU_STATS | awk '{print $5}')
            TOTAL_2=$(echo $CPU_STATS | awk '{print $2+$3+$4+$5+$6+$7+$8}')
            CPU_PERC=$((100 * ((TOTAL_2-TOTAL_1)-(IDLE_2-IDLE_1)) / (TOTAL_2-TOTAL_1) ))
            CPU_DETAIL=$(top -bn1 | grep "Cpu(s)" | awk '{printf "User: %.1f%% | System: %.1f%%", $2, $4}')

            RAM_INFO=$(free -m | grep "Mem:")
            RAM_TOTAL_MB=$(echo $RAM_INFO | awk '{print $2}')
            RAM_USED_MB=$(echo $RAM_INFO | awk '{print $3}')
            RAM_DISP_MB=$(echo $RAM_INFO | awk '{print $7}')
            RAM_PERC=$(( RAM_USED_MB * 100 / RAM_TOTAL_MB ))
            G_TOTAL=$(awk "BEGIN {printf \"%.1f\", $RAM_TOTAL_MB/1024}"); G_USED=$(awk "BEGIN {printf \"%.1f\", $RAM_USED_MB/1024}"); G_DISP=$(awk "BEGIN {printf \"%.1f\", $RAM_DISP_MB/1024}")

            DISCO_DATA=$(df -h / | awk 'NR==2 {print $2, $3, $4, $5}')
            D_TOTAL=$(echo $DISCO_DATA | awk '{print $1}'); D_USADO=$(echo $DISCO_DATA | awk '{print $2}'); D_LIBRE=$(echo $DISCO_DATA | awk '{print $3}'); D_PERC=$(echo $DISCO_DATA | awk '{print $4}' | tr -d '%')

            echo -e "\e[K${AMARILLO}PROCESADOR:${RESET} ${BLANCO}${CPU_MODEL}${RESET}"
            echo -e "\e[K${AMARILLO}NÚCLEOS:${RESET}    ${BLANCO}${CPU_CORES} hilos${RESET} | ${AMARILLO}FREQ:${RESET} ${BLANCO}${CPU_GHZ} GHz${RESET}\n"

            echo -ne "\e[K${VERDE}CARGA CPU: ${RESET}"; dibujar_barra $CPU_PERC; echo -e " -> $(interpretar $CPU_PERC 'cpu')"
            echo -ne "\e[K${AZUL}USO RAM:   ${RESET}"; dibujar_barra $RAM_PERC; echo -e " -> $(interpretar $RAM_PERC 'ram')"
            echo -ne "\e[K${CIAN}USO DISCO: ${RESET}"; dibujar_barra $D_PERC; echo -e " -> $(interpretar $D_PERC 'disco')"

            echo -e "\e[K\n${CIAN}------------- METRICAS DETALLADAS -----------${RESET}"
            echo -e "\e[K   ${BLANCO}CPU:${RESET}   ${CPU_DETAIL} | ${BLANCO}Hilos:${RESET} ${CPU_CORES}"
            echo -e "\e[K   ${BLANCO}RAM:${RESET}   ${G_USED}GB usados / ${G_TOTAL}GB total (Disp: ${G_DISP}GB)"
            echo -e "\e[K   ${BLANCO}DISCO:${RESET} ${D_USADO} usados / ${D_TOTAL} total (Libre: ${D_LIBRE})"
            
            obtener_resumen_inicio
            obtener_info_arranque
            obtener_info_seguridad

            echo -e "\e[K${CIAN}--------------------------------------------${RESET}"
            echo -e "\e[K\n${BLANCO}Presione Ctrl+C para salir${RESET}"
        )
        
        # Imprime toda la pantalla de una sola vez
        echo -e "$OUTPUT"

        read -t 4.9 -n 1 -s key
    done
}

# ==========================================
# 🚀 DATOS DE ARRANQUE Y SISTEMA
# ==========================================
obtener_info_arranque() {
    # Tiempo de booteo (Kernel + Userspace)
    if command -v systemd-analyze &>/dev/null; then
        BOOT_TIME=$(systemd-analyze | awk -F'=' '{print $2}' | xargs)
    else
        BOOT_TIME="N/A"
    fi

    # Último reinicio registrado
    LAST_BOOT=$(uptime -s 2>/dev/null || who -b | awk '{print $3,$4}')

    echo -e "${AZUL}⚡ Último arranque:${RESET} $LAST_BOOT"
    echo -e "${AZUL}⏱️  Tiempo de booteo:${RESET} $BOOT_TIME"
}

# ==========================================
# 🛡️ AUDITORÍA RÁPIDA DE SEGURIDAD
# ==========================================
obtener_info_seguridad() {
    # 1. Estado del Firewall (UFW)
    if command -v ufw &>/dev/null; then
        UFW_STATUS=$(ufw status | head -n 1 | awk '{print $2}')
        [ "$UFW_STATUS" = "active" ] && UFW_PRINT="${VERDE}Activo${RESET}" || UFW_PRINT="${ROJO}Inactivo${RESET}"
    else
        UFW_PRINT="${AMARILLO}No instalado${RESET}"
    fi

    # 2. Conexiones SSH activas en este momento
    SSH_SESSIONS=$(who | grep -c "pts/")

    # 3. Sesiones con privilegios SUDO activas
    SUDO_USERS=$(ps aux | grep -v grep | grep -c "sudo")

    # 4. Intentos fallidos de SSH / Login (Si existe faillog o journalctl)
    INTENTOS_FALLIDOS=0
    if command -v journalctl &>/dev/null; then
        INTENTOS_FALLIDOS=$(journalctl -u ssh -u sshd --since "24 hours ago" 2>/dev/null | grep -c "Failed password")
    fi

    echo -e "${AZUL}🛡️ Firewall (UFW):${RESET} $UFW_PRINT"
    echo -e "${AZUL}👥 Sesiones SSH activas:${RESET} $SSH_SESSIONS"
    echo -e "${AZUL}🔑 Procesos Sudo activos:${RESET} $SUDO_USERS"
    echo -e "${AZUL}⚠️ Fallos SSH (24h):${RESET} ${AMARILLO}${INTENTOS_FALLIDOS}${RESET}"
}

case "$1" in
    -m|--monitor|"")
        monitor_rendimiento
        ;;
    *)
        echo "Uso: $0 [-m|--monitor]"
        exit 1
        ;;
esac
