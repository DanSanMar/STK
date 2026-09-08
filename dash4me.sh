#!/bin/bash

# --- CONFIGURACIÓN DE COLORES ---
RESET='\e[0m'
NEGRITA='\e[1m'
VERDE_BRILLANTE='\e[92m'
VERDE='\e[32m'
AMARILLO='\e[33m'
AMARILLO_BRILLANTE='\e[93m'
AZUL='\e[34m'
AZUL_BRILLANTE='\e[94m'
CIAN='\e[36m'
CIAN_BRILLANTE='\e[96m'
ROJO='\e[31m'
ROJO_BRILLANTE='\e[91m'
BLANCO='\e[97m'

dibujar_barra() {
    local porcentaje=$1
    local color=$VERDE_BRILLANTE
    local total_bloques=20
    local rellenos=$(( porcentaje * total_bloques / 100 ))
    if [ "$porcentaje" -gt 85 ]; then color=$ROJO_BRILLANTE
    elif [ "$porcentaje" -gt 60 ]; then color=$AMARILLO_BRILLANTE
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
            "cpu")   echo -e "${ROJO_BRILLANTE}${NEGRITA}CRÍTICO (Sobrecarga)${RESET}" ;;
            "ram")   echo -e "${ROJO_BRILLANTE}${NEGRITA}CRÍTICO (Sin memoria)${RESET}" ;;
            "disco") echo -e "${ROJO_BRILLANTE}${NEGRITA}CRÍTICO (Disco lleno)${RESET}" ;;
            "swap")  echo -e "${ROJO_BRILLANTE}${NEGRITA}CRÍTICO (Threshing)${RESET}" ;;
        esac
    elif [ "$val" -gt 65 ]; then echo -e "${AMARILLO_BRILLANTE}${NEGRITA}ALTO (Carga)${RESET}"
    else echo -e "${VERDE_BRILLANTE}${NEGRITA}ÓPTIMO${RESET}"; fi
}

obtener_resumen_inicio() {
    local uptime_raw=$(uptime -p 2>/dev/null | sed -e 's/up //' -e 's/ hours\?,*/h/' -e 's/ minutes\?,*/m/' -e 's/ days\?,*/d/')
    local uptime_str=${uptime_raw:-"N/A"}
    local load_avg=$(uptime 2>/dev/null | awk -F'load average:' '{ print $2 }' | sed 's/^[ \t]*//')
    
    local svcs_failed=0
    local failed_names=""
    if command -v systemctl &>/dev/null; then
        failed_names=$(systemctl list-units --state=failed --no-legend 2>/dev/null | awk '{print $1}' | tr '\n' ' ')
        svcs_failed=$(systemctl list-units --state=failed --no-legend 2>/dev/null | wc -l)
    fi

    local usbs=$(lsblk -o MOUNTPOINT -n 2>/dev/null | grep -c -E "^/(media|run/media|mnt)")

    # Definir texto de servicios según el estado
    local svcs_str=""
    if [ "$svcs_failed" -gt 0 ]; then
        svcs_str="${ROJO_BRILLANTE}Fallidos ($svcs_failed): ${AMARILLO_BRILLANTE}${failed_names}${RESET}"
    else
        svcs_str="${VERDE_BRILLANTE}OK (0 fallidos)${RESET}"
    fi

    # Definir texto de unidades externas según el estado
    local usbs_str=""
    if [ "$usbs" -gt 0 ]; then
        usbs_str="${AMARILLO_BRILLANTE}$usbs montada(s)${RESET}"
    else
        usbs_str="${BLANCO}Ninguna${RESET}"
    fi

    echo -e "\e[K   ${NEGRITA}${BLANCO}Tiempo activo:${RESET} ${CIAN_BRILLANTE}$uptime_str${RESET} | ${NEGRITA}${BLANCO}Carga media:${RESET} ${AMARILLO_BRILLANTE}$load_avg${RESET}"
    echo -e "\e[K   ${NEGRITA}${BLANCO}Servicios:${RESET} $svcs_str | ${NEGRITA}${BLANCO}Unidades ext.:${RESET} $usbs_str"
}

# ==========================================
# 🌐 TELEMETRÍA Y RED (NUEVA FUNCIÓN)
# ==========================================
obtener_info_red() {
    # Interfaz principal por defecto
    local iface=$(ip route 2>/dev/null | grep default | awk '{print $5}' | head -n1)
    local ip_local="Sin IP"
    local rx_gb=0; local tx_gb=0

    if [ -n "$iface" ]; then
        ip_local=$(ip -4 addr show "$iface" 2>/dev/null | grep -oP '(?<=inet\s)\d+(\.\d+){3}')
        local rx_bytes=$(cat /sys/class/net/"$iface"/statistics/rx_bytes 2>/dev/null || echo 0)
        local tx_bytes=$(cat /sys/class/net/"$iface"/statistics/tx_bytes 2>/dev/null || echo 0)
        rx_gb=$(awk "BEGIN {printf \"%.2f\", $rx_bytes/1073741824}")
        tx_gb=$(awk "BEGIN {printf \"%.2f\", $tx_bytes/1073741824}")
    else
        iface="N/A"
    fi

    # Comprobación rápida de conectividad hacia Internet (Timeout de 1s)
   local status_ping="${ROJO_BRILLANTE}Desconectado${RESET}"

    # 1. Lista de direcciones IP fiables y públicas
    local ips_ip_check=("1.1.1.1" "8.8.8.8" "9.9.9.9")
    local ip_exitosa=""

    # Probar la lista de IPs con ping
    for ip in "${ips_ip_check[@]}"; do
        if ping -c 1 -W 1 "$ip" &>/dev/null; then
            ip_exitosa="$ip"
            break
        fi
    done

    if [[ -n "$ip_exitosa" ]]; then
        status_ping="${VERDE_BRILLANTE}OK a ($ip_exitosa)${RESET}"
    else
        # 2. Fallback: Si ICMP (ping) está bloqueado, probar resolución/conexión por puerto 80/443 (HTTP/TCP)
        if nc -zw1 1.1.1.1 53 &>/dev/null || curl -sI --connect-timeout 2 http://www.google.com &>/dev/null; then
            status_ping="${VERDE_BRILLANTE}OK (TCP/HTTP)${RESET}"
        fi
    fi

    echo -e "\e[K${AZUL_BRILLANTE}─── 🌐 TELEMETRÍA Y RED ───${RESET}"
    echo -e "\e[K   ${NEGRITA}${BLANCO}Interfaz princ.:${RESET} ${AZUL_BRILLANTE}${iface}${RESET} (${CIAN_BRILLANTE}${ip_local}${RESET})"
    echo -e "\e[K   ${NEGRITA}${BLANCO}Tráfico I/O:${RESET}     RX: ${VERDE_BRILLANTE}${rx_gb} GB${RESET} | TX: ${AMARILLO_BRILLANTE}${tx_gb} GB${RESET}"
    echo -e "\e[K   ${NEGRITA}${BLANCO}Salida a Internet:${RESET} Ping $status_ping"
}

monitor_rendimiento() {
    if command -v tput &> /dev/null; then
        tput smcup
        tput civis
    fi

    trap "tput rmcup 2>/dev/null; tput cnorm 2>/dev/null; exit 0" SIGINT SIGTERM
    
    while true; do
        OUTPUT=$(
            echo -ne "\e[H"
            echo -e "\e[K ${AZUL_BRILLANTE}----- ⚡ \e[1;97mDASH\e[36m4\e[92mME \e[0;34m|\e[0;90m LITE DASHBOARD |${CIAN} V 1.3 test${AZUL_BRILLANTE}  ⚡-----\e[0m"
            echo -e "\e[K ${CIAN}Auto-refresco: 3s | ENTER=Actualizar | Ctrl+C=Salir${RESET}"

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
            CPU_DETAIL=$(top -bn1 | grep "Cpu(s)" | awk '{printf "User: %.1f%% | Sys: %.1f%% | WA (I/O): %.1f%%", $2, $4, $10}')

            # Métricas RAM (Sanitizadas)
            RAM_INFO=$(free -m | grep -i "mem:")
            RAM_TOTAL_MB=$(echo $RAM_INFO | awk '{print $2}')
            RAM_USED_MB=$(echo $RAM_INFO | awk '{print $3}')
            RAM_DISP_MB=$(echo $RAM_INFO | awk '{print $7}')
            
            RAM_TOTAL_MB=${RAM_TOTAL_MB:-1} # Evita división por cero
            RAM_USED_MB=${RAM_USED_MB:-0}
            RAM_DISP_MB=${RAM_DISP_MB:-0}

            RAM_PERC=$(( RAM_USED_MB * 100 / RAM_TOTAL_MB ))
            G_TOTAL=$(awk "BEGIN {printf \"%.1f\", $RAM_TOTAL_MB/1024}")
            G_USED=$(awk "BEGIN {printf \"%.1f\", $RAM_USED_MB/1024}")
            G_DISP=$(awk "BEGIN {printf \"%.1f\", $RAM_DISP_MB/1024}")

            # Métricas SWAP (Validación segura de enteros)
            SWAP_INFO=$(free -m | grep -i "swap:")
            SWAP_TOTAL=$(echo $SWAP_INFO | awk '{print $2}')
            SWAP_USED=$(echo $SWAP_INFO | awk '{print $3}')
            
            # Forzar conversión a enteros limpios
            SWAP_TOTAL=${SWAP_TOTAL:-0}
            SWAP_USED=${SWAP_USED:-0}
            SWAP_TOTAL=$(echo "$SWAP_TOTAL" | tr -dc '0-9')
            SWAP_USED=$(echo "$SWAP_USED" | tr -dc '0-9')
            : "${SWAP_TOTAL:=0}"
            : "${SWAP_USED:=0}"

            SWAP_PERC=0
            if [ "$SWAP_TOTAL" -gt 0 ]; then
                SWAP_PERC=$(( SWAP_USED * 100 / SWAP_TOTAL ))
            fi

            # Métricas Disco
            DISCO_DATA=$(df -h / | awk 'NR==2 {print $2, $3, $4, $5}')
            D_TOTAL=$(echo $DISCO_DATA | awk '{print $1}')
            D_USADO=$(echo $DISCO_DATA | awk '{print $2}')
            D_LIBRE=$(echo $DISCO_DATA | awk '{print $3}')
            D_PERC=$(echo $DISCO_DATA | awk '{print $4}' | tr -d '%')

            echo -e "\e[K${AZUL_BRILLANTE}─── 📊 RENDIMIENTO EN TIEMPO REAL ───${RESET}"
            echo -ne "\e[K${NEGRITA}${VERDE_BRILLANTE} *** CARGA CPU: ${RESET}"; dibujar_barra $CPU_PERC; echo -e " -> $(interpretar $CPU_PERC 'cpu')"
            echo -ne "\e[K${NEGRITA}${AZUL_BRILLANTE} +++ USO RAM:   ${RESET}"; dibujar_barra $RAM_PERC; echo -e " -> $(interpretar $RAM_PERC 'ram')"
            
            if [ "$SWAP_TOTAL" -gt 0 ]; then
                echo -ne "\e[K${NEGRITA}${CIAN_BRILLANTE} --- USO SWAP:  ${RESET}"; dibujar_barra $SWAP_PERC; echo -e " -> $(interpretar $SWAP_PERC 'swap')"
            fi

            echo -ne "\e[K${NEGRITA}${CIAN_BRILLANTE} *** USO DISCO: ${RESET}"; dibujar_barra $D_PERC; echo -e " -> $(interpretar $D_PERC 'disco')"
            echo -e "\e[K${AZUL_BRILLANTE}─── 💻 SISTEMA ───${RESET}"
            echo -e "\e[K${NEGRITA}${AMARILLO}PROCESADOR:${RESET} ${BLANCO}${CPU_MODEL}${RESET}"
            echo -e "\e[K${NEGRITA}${AMARILLO}NÚCLEOS:${RESET}    ${CIAN_BRILLANTE}${CPU_CORES}${RESET} hilos | ${NEGRITA}${AMARILLO}FREQ:${RESET} ${CIAN_BRILLANTE}${CPU_GHZ}${RESET} GHz"
            echo -e "\e[K   ${NEGRITA}${BLANCO}CPU:${RESET}   ${CIAN_BRILLANTE}${CPU_DETAIL}${RESET}"
            echo -e "\e[K   ${NEGRITA}${BLANCO}RAM:${RESET}   ${VERDE_BRILLANTE}${G_USED}GB${RESET} usados / ${BLANCO}${G_TOTAL}GB${RESET} total (Disp: ${AZUL_BRILLANTE}${G_DISP}GB${RESET})"
            echo -e "\e[K   ${NEGRITA}${BLANCO}DISCO:${RESET} ${VERDE_BRILLANTE}${D_USADO}${RESET} usados / ${BLANCO}${D_TOTAL}${RESET} total (Libre: ${AZUL_BRILLANTE}${D_LIBRE}${RESET})"
            
            obtener_resumen_inicio
            obtener_info_arranque
            obtener_info_red
            obtener_info_seguridad

            

            echo -ne "\e[J"
        )
        
        echo -e "$OUTPUT"
        read -t 4.9 -n 1 -s key
    done
}

obtener_info_arranque() {
    local boot_time="N/A"
    local boot_sec=0
    if command -v systemd-analyze &>/dev/null; then
        boot_time=$(systemd-analyze 2>/dev/null | head -n 1 | awk -F'=' '{print $2}' | xargs)
        # Extrae de forma limpia solo los segundos/milisegundos totales
        boot_sec=$(echo "$boot_time" | grep -oP '\d+(\.\d+)?(?=s)' | tail -n1)
    fi

    local last_boot=$(uptime -s 2>/dev/null || who -b 2>/dev/null | awk '{print $3,$4}')
    local media_str="N/A"
    local comparativa=""
    
    # Recopilar tiempo de arranque de los últimos registros disponibles en el Journal
    if command -v journalctl &>/dev/null && [ -n "$boot_sec" ]; then
        local suma=0
        local count=0
        
        for i in {0..4}; do
            # Busca la línea nativa "Startup finished in..." que systemd escribe en cada boot
            local t=$(journalctl -b -$i -u systemd-logind.service 2>/dev/null | grep -oP 'Startup finished in .+= \K[0-9.]+(?=s)' | head -n 1)
            
            # Fallback genérico por si no encuentra el servicio específico
            if [ -z "$t" ]; then
                t=$(journalctl -b -$i 2>/dev/null | grep -oP 'Startup finished in .+= \K[0-9.]+(?=s)' | head -n 1)
            fi

            if [ -n "$t" ]; then
                suma=$(awk "BEGIN {print $suma + $t}")
                count=$((count + 1))
            fi
        done
        
        if [ "$count" -gt 0 ]; then
            local media=$(awk "BEGIN {printf \"%.2f\", $suma / $count}")
            media_str="${media}s (últimos $count)"
            
            local diff=$(awk "BEGIN {printf \"%.2f\", $boot_sec - $media}")
            local es_mayor=$(awk "BEGIN {print ($diff > 0.5)?1:0}")
            local es_menor=$(awk "BEGIN {print ($diff < -0.5)?1:0}")

            if [ "$es_mayor" -eq 1 ]; then
                comparativa=" ${ROJO_BRILLANTE}(+${diff}s más lento)${RESET}"
            elif [ "$es_menor" -eq 1 ]; then
                comparativa=" ${VERDE_BRILLANTE}(${diff}s más rápido)${RESET}"
            else
                comparativa=" ${VERDE_BRILLANTE}(Promedio habitual)${RESET}"
            fi
        fi
    fi

    echo -e "\e[K${AZUL_BRILLANTE}─── 🚀 ARRANQUE ───${RESET}"
    echo -e "\e[K   ${NEGRITA}${AZUL_BRILLANTE}Último arranque:${RESET} ${BLANCO}$last_boot${RESET}"  
    echo -e "\e[K   ${NEGRITA}${AZUL_BRILLANTE}Tiempo:${RESET} ${BLANCO}${boot_time:-"N/A"}${RESET}${comparativa}"
    echo -e "\e[K   ${NEGRITA}${AZUL_BRILLANTE}Media de arranque:${RESET} ${BLANCO}$media_str${RESET}"
}

obtener_info_seguridad() {
    if command -v ufw &>/dev/null; then
        UFW_STATUS=$(ufw status | head -n 1 | awk '{print $2}')
        [ "$UFW_STATUS" = "active" ] && UFW_PRINT="${VERDE_BRILLANTE}Activo${RESET}" || UFW_PRINT="${ROJO_BRILLANTE}Inactivo${RESET}"
    else
        UFW_PRINT="${AMARILLO_BRILLANTE}No instalado${RESET}"
    fi

    # Sesiones SSH y Puertos TCP escuchando
    SSH_SESSIONS=$(ss -tn state established '( dport = :22 or sport = :22 )' 2>/dev/null | tail -n +2 | wc -l)
    LISTEN_PORTS=$(ss -tuln 2>/dev/null | grep -c "LISTEN")

    REVERSE_SHELLS=$(ss -tupn state established 2>/dev/null | grep -E '(bash|sh|zsh|python|perl|nc|socat)' | wc -l)
    if [ "$REVERSE_SHELLS" -gt 0 ]; then
        REV_PRINT="${ROJO_BRILLANTE}${NEGRITA}⚠️ ALERTA: $REVERSE_SHELLS sospechosa(s)${RESET}"
    else
        REV_PRINT="${VERDE_BRILLANTE}Ninguna detectada${RESET}"
    fi

    SUDO_USERS=$(ps aux | grep -v grep | grep -c "sudo")
    
    echo -e "\e[K${AZUL_BRILLANTE}─── 🛡️ SEGURIDAD ───${RESET}"
    echo -e "\e[K   ${NEGRITA}${AZUL_BRILLANTE}Firewall (UFW):${RESET} $UFW_PRINT | ${NEGRITA}${AZUL_BRILLANTE}Puertos escuchando:${RESET} ${BLANCO}$LISTEN_PORTS${RESET}"
    echo -e "\e[K   ${NEGRITA}${AZUL_BRILLANTE}Conexiones SSH (p22):${RESET} ${BLANCO}$SSH_SESSIONS${RESET} | ${NEGRITA}${AZUL_BRILLANTE}Procesos Sudo activos:${RESET} ${BLANCO}$SUDO_USERS${RESET}"
    echo -e "\e[K   ${NEGRITA}${AZUL_BRILLANTE}Shells Sospechosas:${RESET} $REV_PRINT"
}

monitor_rendimiento