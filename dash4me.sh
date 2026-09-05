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
    # Uptime limpio (formato: 3h 12m)
    local uptime_raw=$(uptime -p 2>/dev/null | sed -e 's/up //' -e 's/ hours\?,*/h/' -e 's/ minutes\?,*/m/' -e 's/ days\?,*/d/')
    local uptime_str=${uptime_raw:-"N/A"}
    
    # Carga media (1 min, 5 min, 15 min)
    local load_avg=$(uptime 2>/dev/null | awk -F'load average:' '{ print $2 }' | sed 's/^[ \t]*//')
    
    # Servicios fallidos en systemd
    local svcs_failed=0
    local failed_names=""
    if command -v systemctl &>/dev/null; then
        failed_names=$(systemctl list-units --state=failed --no-legend 2>/dev/null | awk '{print $1}' | tr '\n' ' ')
        svcs_failed=$(systemctl list-units --state=failed --no-legend 2>/dev/null | wc -l)
    fi

    # Dispositivos extraíbles montados (/media, /run/media, /mnt, /media/$USER)
    local usbs=$(lsblk -o MOUNTPOINT -n 2>/dev/null | grep -c -E "^/(media|run/media|mnt)")

    echo -e "\e[K${CIAN}------------- ESTADO DEL SISTEMA ------------${RESET}"
    echo -e "\e[K   ${BLANCO}Tiempo activo:${RESET} $uptime_str | ${BLANCO}Carga media:${RESET} $load_avg"
    
    # Impresión fija de servicios
    if [ "$svcs_failed" -gt 0 ]; then
        echo -e "\e[K   ${ROJO_BRILLANTE}Servicios fallidos ($svcs_failed):${RESET} ${AMARILLO}${failed_names}${RESET}"
    else
        echo -e "\e[K   ${VERDE}Estado Servicios:${RESET} OK (0 fallidos)"
    fi

    # Impresión fija de unidades externas para evitar saltos en la pantalla
    if [ "$usbs" -gt 0 ]; then
        echo -e "\e[K   ${AMARILLO}Unidades externas:${RESET} $usbs montada(s)"
    else
        echo -e "\e[K   ${BLANCO}Unidades externas:${RESET} Ninguna"
    fi
}

monitor_rendimiento() {
    if command -v tput &> /dev/null; then
        tput smcup   # Entrar al buffer alternativo
        tput civis   # Ocultar cursor
    fi

    # Restaurar terminal al salir
    trap "tput rmcup 2>/dev/null; tput cnorm 2>/dev/null; exit 0" SIGINT SIGTERM
    
    while true; do
        # Redirigimos la salida a una variable para evitar redibujados intermedios
        OUTPUT=$(
            echo -ne "\e[H" # Mueve el cursor a la esquina superior izquierda sin limpiar
            echo -e "\e[K ${AZUL_BRILLANTE}----- ⚡ \e[1;97mDASH\e[36m4\e[92mME \e[0;34m|\e[0;90m LITE DASHBOARD |${CIAN} V 1.1${AZUL_BRILLANTE}  ⚡-----\e[0m"
            echo -e "\e[K${CIAN}Auto-refresco: 3s | ENTER=Actualizar | Ctrl+C=Salir${RESET}\n"

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
            echo -e "\e[K   ${BLANCO}CPU:${RESET}   ${CPU_DETAIL}${RESET}"
            echo -e "\e[K   ${BLANCO}RAM:${RESET}   ${G_USED}GB usados / ${G_TOTAL}GB total (Disp: ${G_DISP}GB)"
            echo -e "\e[K   ${BLANCO}DISCO:${RESET} ${D_USADO} usados / ${D_TOTAL} total (Libre: ${D_LIBRE})"
            
            obtener_resumen_inicio
            obtener_info_arranque
            obtener_info_seguridad

            echo -e "\e[K${CIAN}--------------------------------------------${RESET}"
           
            
            # Limpiar cualquier línea sobrante hacia abajo
            echo -ne "\e[J"
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
    # 1. Obtener tiempo del arranque actual (extrae el total en segundos/milisegundos)
    local boot_time="N/A"
    local boot_sec=0
    if command -v systemd-analyze &>/dev/null; then
        boot_time=$(systemd-analyze 2>/dev/null | head -n 1 | awk -F'=' '{print $2}' | xargs)
        # Extraer solo el número flotante final (ej: "14.450s" -> "14.45")
        boot_sec=$(echo "$boot_time" | awk '{print $NF}' | tr -d 's')
    fi

    # 2. Último reinicio registrado
    local last_boot=$(uptime -s 2>/dev/null || who -b 2>/dev/null | awk '{print $3,$4}')

    # 3. Calcular la media de los últimos 5 arranques usando journalctl
    local media_str="N/A"
    local comparativa=""
    
    if command -v journalctl &>/dev/null && [ -n "$boot_sec" ]; then
        # Extrae los tiempos totales de booteo de los últimos 5 arranques
        local tiempos=$(journalctl -b -0 -b -1 -b -2 -b -3 -b -4 _COMM=systemd-analyze 2>/dev/null | grep -oP '=\s*\K[0-9.]+(?=s)' | head -n 5)
        
        if [ -n "$tiempos" ]; then
            local suma=0
            local count=0
            for t in $tiempos; do
                suma=$(awk "BEGIN {print $suma + $t}")
                count=$((count + 1))
            done
            
            if [ "$count" -gt 0 ]; then
                local media=$(awk "BEGIN {printf \"%.2f\", $suma / $count}")
                media_str="${media}s (últimos $count)"
                
                # Comparar arranque actual vs media
                local diff=$(awk "BEGIN {printf \"%.2f\", $boot_sec - $media}")
                local es_mayor=$(awk "BEGIN {print ($diff > 0.5)?1:0}")
                local es_menor=$(awk "BEGIN {print ($diff < -0.5)?1:0}")

                if [ "$es_mayor" -eq 1 ]; then
                    comparativa=" ${ROJO_BRILLANTE}(+${diff}s más lento)${RESET}"
                elif [ "$es_menor" -eq 1 ]; then
                    comparativa=" ${VERDE_BRILLANTE}(${diff}s más rápido)${RESET}"
                else
                    comparativa=" ${VERDE}(Promedio habitual)${RESET}"
                fi
            fi
        fi
    fi

    echo -e "\e[K${AZUL}⚡ Último arranque:${RESET} $last_boot"
    echo -e "\e[K${AZUL}⏱️  Tiempo de booteo:${RESET} ${BLANCO}${boot_time}${RESET}${comparativa}"
    echo -e "\e[K${AZUL}📊 Media de arranque:${RESET} $media_str"
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

    # 2. Conexiones SSH entrantes legítimas (puerto 22 o sshd)
    SSH_SESSIONS=$(ss -tn state established '( dport = :22 or sport = :22 )' 2>/dev/null | tail -n +2 | wc -l)

    # 3. Detección de posibles Reverse Shells (puertos arbitrarios)
    REVERSE_SHELLS=$(ss -tupn state established 2>/dev/null | grep -E '(bash|sh|zsh|python|perl|nc|socat)' | wc -l)
    if [ "$REVERSE_SHELLS" -gt 0 ]; then
        REV_PRINT="${ROJO_BRILLANTE}⚠️ ALERTA: $REVERSE_SHELLS sospechosa(s)${RESET}"
    else
        REV_PRINT="${VERDE}Ninguna detectada${RESET}"
    fi

    # 4. Sesiones con privilegios SUDO activas
    SUDO_USERS=$(ps aux | grep -v grep | grep -c "sudo")

    echo -e "\e[K${AZUL}🛡️ Firewall (UFW):${RESET} $UFW_PRINT"
    echo -e "\e[K${AZUL}👥 Conexiones SSH (p22):${RESET} $SSH_SESSIONS"
    echo -e "\e[K${AZUL}🚨 Shells Sospechosas:${RESET} $REV_PRINT"
    echo -e "\e[K${AZUL}🔑 Procesos Sudo activos:${RESET} $SUDO_USERS"
}

monitor_rendimiento

