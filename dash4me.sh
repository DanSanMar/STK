#!/bin/bash

# --- CONFIGURACIÓN DE COLORES ---
RESET='\e[0m'
NEGRITA='\e[1m'

# Variantes y tonos específicos
BLANCO_NEGRITA='\e[1;97m'
GRIS_CLARO='\e[0;90m'
AZUL_OSCURO='\e[0;34m'

# Colores estándar
VERDE_BRILLANTE='\e[92m'
VERDE='\e[32m'
AMARILLO='\e[33m'
AMARILLO_BRILLANTE='\e[93m'
AZUL='\e[34m'
AZUL_BRILLANTE='\e[94m'
AZUL_CLARO='\e[38;5;117m'
CIAN='\e[36m'
CIAN_BRILLANTE='\e[96m'
ROJO='\e[31m'
ROJO_BRILLANTE='\e[91m'
BLANCO='\e[97m'

# --- COLORES PARA GPU ---
VERDE_GPU='\e[38;5;47m'      # Verde brillante para temperatura normal
AMARILLO_GPU='\e[38;5;226m'   # Amarillo para temperatura media
ROJO_GPU='\e[38;5;209m'       # Rojo para alta temperatura
CIAN_GPU='\e[38;5;94m'        # Cian para GPU en general
AZUL_GRISACEO='\e[38;5;244m'  # Gris azulado para util

VER="V 1.6.3-GPU"
VER_DASH="\e[0;90m-\e[0m"


dibujar_barra() {
    local valor=$1
    local tipo=${2:-"uso"} # "uso" (porcentaje 0-100) o "temp" (grados 0-100°C)
    local max=100
    local color=$VERDE_BRILLANTE
    local total_bloques=20
    
    # Asegurar que el valor no exceda el máximo para el gráfico
    [ "$valor" -gt "$max" ] && valor=$max
    local rellenos=$(( valor * total_bloques / max ))
    
    if [ "$tipo" = "temp" ]; then
        if [ "$valor" -gt 85 ]; then color=$ROJO_BRILLANTE
        elif [ "$valor" -gt 75 ]; then color=$AMARILLO_BRILLANTE
        fi
        printf "${color}["
        for ((i=0; i<rellenos; i++)); do printf "■"; done
        for ((i=rellenos; i<total_bloques; i++)); do printf " "; done
        printf "] %3d°C${RESET}" "$valor"
    else
        if [ "$valor" -gt 85 ]; then color=$ROJO_BRILLANTE
        elif [ "$valor" -gt 60 ]; then color=$AMARILLO_BRILLANTE
        fi
        printf "${color}["
        for ((i=0; i<rellenos; i++)); do printf "■"; done
        for ((i=rellenos; i<total_bloques; i++)); do printf " "; done
        printf "] %3d%%${RESET}" "$valor"
    fi
}

interpretar() {
    local val=$1
    local tipo=$2
    
    case "$tipo" in
        "cpu")
            if [ "$val" -gt 85 ]; then echo -e "${ROJO_BRILLANTE}${NEGRITA}CRÍTICO (Sobrecarga)${RESET}"
            elif [ "$val" -gt 65 ]; then echo -e "${AMARILLO_BRILLANTE}${NEGRITA}ALTO (Carga)${RESET}"
            else echo -e "${VERDE_BRILLANTE}${NEGRITA}ÓPTIMO${RESET}"; fi
            ;;
        "ram")
            if [ "$val" -gt 85 ]; then echo -e "${ROJO_BRILLANTE}${NEGRITA}CRÍTICO (Sin memoria)${RESET}"
            elif [ "$val" -gt 65 ]; then echo -e "${AMARILLO_BRILLANTE}${NEGRITA}ALTO (Carga)${RESET}"
            else echo -e "${VERDE_BRILLANTE}${NEGRITA}ÓPTIMO${RESET}"; fi
            ;;
        "vram")
            if [ "$val" -gt 85 ]; then echo -e "${ROJO_BRILLANTE}${NEGRITA}CRÍTICO (VRAM saturada)${RESET}"
            elif [ "$val" -gt 65 ]; then echo -e "${AMARILLO_BRILLANTE}${NEGRITA}ALTO (Carga VRAM)${RESET}"
            else echo -e "${VERDE_BRILLANTE}${NEGRITA}ÓPTIMO${RESET}"; fi
            ;;
        "disco")
            if [ "$val" -gt 85 ]; then echo -e "${ROJO_BRILLANTE}${NEGRITA}CRÍTICO (Disco lleno)${RESET}"
            elif [ "$val" -gt 65 ]; then echo -e "${AMARILLO_BRILLANTE}${NEGRITA}ALTO (Carga)${RESET}"
            else echo -e "${VERDE_BRILLANTE}${NEGRITA}ÓPTIMO${RESET}"; fi
            ;;
        "swap")
            if [ "$val" -gt 85 ]; then echo -e "${ROJO_BRILLANTE}${NEGRITA}CRÍTICO (Threshing)${RESET}"
            elif [ "$val" -gt 65 ]; then echo -e "${AMARILLO_BRILLANTE}${NEGRITA}ALTO (Carga)${RESET}"
            else echo -e "${VERDE_BRILLANTE}${NEGRITA}ÓPTIMO${RESET}"; fi
            ;;
        "gpu_temp") 
            if [ "$val" -gt 85 ]; then
                echo -e "${ROJO_GPU}${NEGRITA}CRÍTICO (>85°C)${RESET}"
            elif [ "$val" -gt 75 ]; then
                echo -e "${AMARILLO_GPU}ELEVADA (76-85°C)${RESET}"
            else
                echo -e "${VERDE_GPU}NORMAL${RESET}"
            fi
            ;;
        "gpu_util") 
            if [ "$val" -gt 90 ]; then
                echo -e "${ROJO_GPU}${NEGRITA}GPU SATURADA (${val}%)${RESET}"
            elif [ "$val" -gt 70 ]; then
                echo -e "${AMARILLO_GPU}ALTA UTILIZACIÓN (${val}%)${RESET}"
            else
                echo -e "${VERDE_GPU}UTILIZACIÓN NORMAL (${val}%)${RESET}"
            fi
            ;;
        *) 
            echo -e "${VERDE_BRILLANTE}${NEGRITA}ÓPTIMO${RESET}"
            ;;
    esac
}


# --- FUNCIÓN PARA MONITOR GPU ---
obtener_info_gpu() {
    if ! command -v nvidia-smi &>/dev/null; then
        echo -e "\e[K${CIAN_GPU}- 🎮 GPU (NVIDIA) - N/A${RESET}"
        return
    fi
    
    local nvidia_output
    nvidia_output=$(nvidia-smi --query-gpu=name,uuid,temperature.gpu,fan.speed,memory.used,memory.total,utilization.gpu --format=csv,noheader,nounits 2>/dev/null | head -n 1)
    
    if [ $? -ne 0 ] || [ -z "$nvidia_output" ]; then
        echo -e "\e[K${CIAN_GPU}- 🎮 GPU (NVIDIA) - No detectada o sin driver${RESET}"
        return
    fi

    IFS=',' read -r gpu_model gpu_uuid gpu_temp gpu_fan gpu_mem_used gpu_mem_total gpu_util <<< "$nvidia_output"

    # Sanitizar y limpiar espacios
    gpu_model=$(echo "$gpu_model" | xargs)
    gpu_uuid=$(echo "$gpu_uuid" | xargs)
    gpu_temp=$(echo "$gpu_temp" | tr -dc '0-9')
    gpu_fan=$(echo "$gpu_fan" | tr -dc '0-9')
    gpu_mem_used=$(echo "$gpu_mem_used" | tr -dc '0-9')
    gpu_mem_total=$(echo "$gpu_mem_total" | tr -dc '0-9')
    gpu_util=$(echo "$gpu_util" | tr -dc '0-9')

    : "${gpu_temp:=0}"
    : "${gpu_fan:=0}"
    : "${gpu_mem_used:=0}"
    : "${gpu_mem_total:=0}"
    : "${gpu_util:=0}"

    local uuid_display=""
    if [ -n "$gpu_uuid" ] && [ "$gpu_uuid" != "N/A" ]; then
        uuid_display=" (UUID: ${gpu_uuid:0:12}...)"
    fi

    echo -e "\e[K${CIAN_GPU}- 🎮 DETALLES DE GPU$uuid_display:${RESET}"
    echo -e "\e[K   ${NEGRITA}${BLANCO}Modelo:${RESET} ${VERDE_GPU}${gpu_model}${RESET}"

    if [ "$gpu_mem_total" -gt 0 ]; then
        local mem_g_used=$(awk "BEGIN {printf \"%.2f\", $gpu_mem_used/1024}")
        local mem_g_total=$(awk "BEGIN {printf \"%.2f\", $gpu_mem_total/1024}")
        echo -e "\e[K   ${NEGRITA}${BLANCO}VRAM Memoria:${RESET} ${VERDE_GPU}${mem_g_used} GB${RESET} / ${CIAN_GPU}${mem_g_total} GB${RESET} | ${AZUL_GRISACEO}FAN: ${CIAN_GPU}${gpu_fan}%${RESET} | ${AZUL_GRISACEO}Carga NPU/Core: ${CIAN_GPU}${gpu_util}%${RESET}"
    else
        echo -e "\e[K   ${NEGRITA}${BLANCO}Estado:${RESET} ${CIAN_GPU}Sin lectura VRAM${RESET} | ${AZUL_GRISACEO}FAN: ${gpu_fan}%${RESET}"
    fi

    # Guardar valores globalmente para las barras en monitor_rendimiento
    LAST_GPU_TEMP=$gpu_temp
    LAST_GPU_UTIL=$gpu_util
    if [ "$gpu_mem_total" -gt 0 ]; then
        LAST_GPU_VRAM_PCT=$(( gpu_mem_used * 100 / gpu_mem_total ))
    else
        LAST_GPU_VRAM_PCT=0
    fi
}

# ==========================================
# 🌐 TELEMETRÍA Y RED
# ==========================================
obtener_info_red() {
    read -r iface ip_local <<< "$(ip route get 1.1.1.1 2>/dev/null | awk '{print $5, $7; exit}')"
    
    local rx_gb="0.00"
    local tx_gb="0.00"

    if [ -n "$iface" ] && [ "$iface" != "lo" ]; then
        local rx_bytes=$(cat /sys/class/net/"$iface"/statistics/rx_bytes 2>/dev/null || echo 0)
        local tx_bytes=$(cat /sys/class/net/"$iface"/statistics/tx_bytes 2>/dev/null || echo 0)
        
        read -r rx_gb tx_gb <<< "$(awk -v rx="$rx_bytes" -v tx="$tx_bytes" 'BEGIN {printf "%.2f %.2f", rx/1073741824, tx/1073741824}')"
    else
        iface="N/A"
        ip_local="Sin IP"
    fi

    local status_ping="${ROJO_BRILLANTE}Desconectado${RESET}"
    
    if command -v nc &>/dev/null && nc -zw1 1.1.1.1 53 &>/dev/null; then
        status_ping="${VERDE_BRILLANTE}OK (1.1.1.1:53)${RESET}"
    elif ping -c 1 -w 1 8.8.8.8 &>/dev/null; then
        status_ping="${VERDE_BRILLANTE}OK (8.8.8.8)${RESET}"
    elif curl -sI --connect-timeout 1 http://www.google.com &>/dev/null; then
        status_ping="${VERDE_BRILLANTE}OK (HTTP)${RESET}"
    fi

    echo -e "\e[K${AZUL_CLARO}- 🌐 TELEMETRÍA Y RED -${RESET}"
    echo -e "\e[K   ${NEGRITA}${BLANCO}Interfaz:${RESET} ${AZUL_BRILLANTE}${iface}${RESET} (${CIAN_BRILLANTE}${ip_local}${RESET}) ${NEGRITA}${BLANCO}Ping:${RESET} $status_ping"
    echo -e "\e[K   ${NEGRITA}${BLANCO}Tráfico I/O:${RESET} RX: ${VERDE_BRILLANTE}${rx_gb} GB${RESET} | TX: ${AMARILLO}${tx_gb} GB${RESET}"
}

# ==========================================
# 🛡️ SEGURIDAD
# ==========================================
obtener_info_seguridad() {
    local ufw_print="${AMARILLO_BRILLANTE}No instalado${RESET}"
    if command -v ufw &>/dev/null; then
        local ufw_status=$(ufw status 2>/dev/null | head -n 1 | awk '{print $2}')
        if [ "$ufw_status" = "active" ]; then
            ufw_print="${VERDE_BRILLANTE}Activo${RESET}"
        else
            ufw_print="${ROJO_BRILLANTE}Inactivo${RESET}"
        fi
    fi

    local ssh_sessions
    ssh_sessions=$(ss -tn state established '( dport = :22 or sport = :22 )' 2>/dev/null | tail -n +2 | wc -l)

    local sudo_count=0
    local sudo_procs=""
    local sudo_pids=$(pgrep -x sudo 2>/dev/null)
    if [ -n "$sudo_pids" ]; then
        sudo_count=$(echo "$sudo_pids" | wc -l)
        sudo_procs=$(ps -o args= -p $sudo_pids 2>/dev/null | awk '{
            for(i=1;i<=NF;i++) {
                if ($i !~ /^-/ && $i != "sudo") {
                    print $i; break
                }
            }
        }' | xargs -n1 basename 2>/dev/null | sort -u | tr '\n' ' ')
    fi

    local rev_print="${VERDE_BRILLANTE}Ninguna detectada${RESET}"
    local rev_details=""
    
    local raw_shells
    raw_shells=$(ss -tupn state established 2>/dev/null | grep -E '(bash|sh|zsh|python|perl|nc|socat)')

    if [ -n "$raw_shells" ]; then
        local reverse_shells
        reverse_shells=$(echo "$raw_shells" | wc -l)
        rev_print="${ROJO_BRILLANTE}${NEGRITA}⚠️ ALERTA: $reverse_shells sospechosa(s)${RESET}"

        rev_details=$(echo "$raw_shells" | awk '{
            proc="desconocido";
            if (match($0, /users:\(\("([^"]+)"/, m)) proc=m[1];
            local_addr=$5;
            remote_addr=$6;
            print proc " (" local_addr " -> " remote_addr ")"
        }' | tr '\n' ' ' | sed 's/ $//')
    fi

    local listen_info
    listen_info=$(ss -tulnp 2>/dev/null | awk 'NR>1 {
        split($5, a, ":"); 
        port=a[length(a)]; 
        proc="desconocido"; 
        if (match($0, /users:\(\("([^"]+)"/, m)) proc=m[1]; 
        if (port ~ /^[0-9]+$/) print port " (" proc ")"
    }' | sort -nu -k1,1 | head -n 6 | tr '\n' ' ' | sed 's/ $//')
    
    [ -z "$listen_info" ] && listen_info="Ninguno"

    echo -e "\e[K${AZUL_CLARO}- 🛡️ SEGURIDAD -${RESET}"
    echo -e "\e[K   ${NEGRITA}${AZUL_BRILLANTE}UFW:${RESET} $ufw_print | ${NEGRITA}${AZUL_BRILLANTE}SSH activas:${RESET} ${BLANCO}${ssh_sessions}${RESET} | ${NEGRITA}${AZUL_BRILLANTE}Sudos activos:${RESET} ${AMARILLO}${sudo_count}${RESET}"
    echo -e "\e[K   ${NEGRITA}${AZUL_BRILLANTE}Shells Sospechosas:${RESET} $rev_print"
    
    if [ -n "$rev_details" ]; then
        echo -e "\e[K   ${ROJO_BRILLANTE}   └── Detalle:${RESET} ${BLANCO}${rev_details}${RESET}"
    fi

    if [ "$sudo_count" -gt 0 ]; then
        echo -e "\e[K   ${NEGRITA}${AZUL_BRILLANTE}Ejecutando Sudo:${RESET} ${AMARILLO}${sudo_procs}${RESET}"
    fi
    echo -e "\e[K   ${NEGRITA}${AZUL_BRILLANTE}Puertos escuchando:${RESET} ${CIAN}[ $listen_info ]${RESET}"
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

    local svcs_str=""
    if [ "$svcs_failed" -gt 0 ]; then
        svcs_str="${ROJO_BRILLANTE}Fallidos ($svcs_failed): ${AMARILLO}${failed_names}${RESET}"
    else
        svcs_str="${VERDE_BRILLANTE}OK (0 fallidos)${RESET}"
    fi

    local usbs_str=""
    if [ "$usbs" -gt 0 ]; then
        usbs_str="${AMARILLO}$usbs montada(s)${RESET}"
    else
        usbs_str="${BLANCO}Ninguna${RESET}"
    fi

    echo -e "\e[K   ${NEGRITA}${BLANCO}Tiempo activo:${RESET} ${CIAN}${uptime_str}${RESET} | ${NEGRITA}${BLANCO}Carga media:${RESET} ${AMARILLO}${load_avg}${RESET}"
    echo -e "\e[K   ${NEGRITA}${BLANCO}Servicios:${RESET} $svcs_str | ${NEGRITA}${BLANCO}Unidades ext.:${RESET} $usbs_str"
}

monitor_rendimiento() {
    if command -v tput &> /dev/null; then
        tput smcup
        tput civis
    fi

    trap "tput rmcup 2>/dev/null; tput cnorm 2>/dev/null; exit 0" SIGINT SIGTERM

    while true; do

        HORA_ACTUAL=$(date +"%H:%M:%S")
        SEGUNDOS=$(date +"%S")

        ULTIMO_DIGITO="${SEGUNDOS: -1}"
        case "$ULTIMO_DIGITO" in
            1) COLOR_LOGO="$AZUL_BRILLANTE" ;;
            2) COLOR_LOGO="$VERDE_BRILLANTE" ;;
            3) COLOR_LOGO="$AMARILLO_BRILLANTE" ;;
            4) COLOR_LOGO="$CIAN_BRILLANTE" ;;
            5) COLOR_LOGO="$ROJO_BRILLANTE" ;;
            6) COLOR_LOGO="$AZUL_CLARO" ;;
            7) COLOR_LOGO="$VERDE" ;;
            8) COLOR_LOGO="$AMARILLO" ;;
            9) COLOR_LOGO="$CIAN" ;;
            0) COLOR_LOGO="$ROJO" ;;
            *) COLOR_LOGO="$BLANCO_NEGRITA" ;;
        esac

        DIGITO_VER=$(( (10#$SEGUNDOS + 5) % 10 ))
        case "$DIGITO_VER" in
            1) COLOR_VER="$ROJO_BRILLANTE" ;;
            2) COLOR_VER="$CIAN" ;;
            3) COLOR_VER="$VERDE" ;;
            4) COLOR_VER="$AMARILLO" ;;
            5) COLOR_VER="$AZUL_BRILLANTE" ;;
            6) COLOR_VER="$VERDE_BRILLANTE" ;;
            7) COLOR_VER="$AMARILLO_BRILLANTE" ;;
            8) COLOR_VER="$CIAN_BRILLANTE" ;;
            9) COLOR_VER="$AZUL_CLARO" ;;
            0) COLOR_VER="$BLANCO_NEGRITA" ;;
            *) COLOR_VER="$CIAN" ;;
        esac
        
        DIGITO_DASH=$(( (10#$SEGUNDOS + 2) % 10 ))
        case "$DIGITO_DASH" in
            1) COLOR_DASH="$VERDE_BRILLANTE" ;;
            2) COLOR_DASH="$AMARILLO_BRILLANTE" ;;
            3) COLOR_DASH="$CIAN_BRILLANTE" ;;
            4) COLOR_DASH="$ROJO_BRILLANTE" ;;
            5) COLOR_DASH="$AZUL_CLARO" ;;
            6) COLOR_DASH="$VERDE" ;;
            7) COLOR_DASH="$AMARILLO" ;;
            8) COLOR_DASH="$CIAN" ;;
            9) COLOR_DASH="$ROJO" ;;
            0) COLOR_DASH="$BLANCO_NEGRITA" ;;
            *) COLOR_DASH="$GRIS_CLARO" ;;
        esac

        OUTPUT=$(
            echo -ne "\e[H"
            echo -e "\e[K ${AZUL_BRILLANTE}--- ⚡ ${COLOR_LOGO}DASH4ME${RESET} ${AZUL_OSCURO}| ${COLOR_DASH}LITE DASHBOARD GPU${RESET} ${AZUL_OSCURO}| ${COLOR_VER}${VER}${RESET} ${BLANCO}:${HORA_ACTUAL}: ${AZUL_BRILLANTE}⚡---\e[0m"
            echo -e "\e[K ${AZUL_BRILLANTE} - ${RESET}AUTO-REFRESCO: ${CIAN}3s${RESET} | ENTER=${CIAN}Actualizar ${RESET}| CTRL+C=${CIAN}Salir${RESET}${AZUL_BRILLANTE} - "

            # Carga CPU
            CPU_STATS=$(grep 'cpu ' /proc/stat)
            IDLE_1=$(echo $CPU_STATS | awk '{print $5}')
            TOTAL_1=$(echo $CPU_STATS | awk '{print $2+$3+$4+$5+$6+$7+$8}')
            sleep 0.1
            CPU_STATS=$(grep 'cpu ' /proc/stat)
            IDLE_2=$(echo $CPU_STATS | awk '{print $5}')
            TOTAL_2=$(echo $CPU_STATS | awk '{print $2+$3+$4+$5+$6+$7+$8}')
            
            DIFF_TOTAL=$((TOTAL_2 - TOTAL_1))
            DIFF_IDLE=$((IDLE_2 - IDLE_1))
            
            if [ "$DIFF_TOTAL" -gt 0 ]; then
                CPU_PERC=$((100 * (DIFF_TOTAL - DIFF_IDLE) / DIFF_TOTAL))
            else
                CPU_PERC=0
            fi

            # RAM
            RAM_INFO=$(free -m | grep -i "mem:")
            RAM_TOTAL_MB=$(echo $RAM_INFO | awk '{print $2}')
            RAM_USED_MB=$(echo $RAM_INFO | awk '{print $3}')
            RAM_DISP_MB=$(echo $RAM_INFO | awk '{print $7}')
            
            RAM_TOTAL_MB=${RAM_TOTAL_MB:-1}
            RAM_USED_MB=${RAM_USED_MB:-0}
            RAM_DISP_MB=${RAM_DISP_MB:-0}

            RAM_PERC=$(( RAM_USED_MB * 100 / RAM_TOTAL_MB ))

            # SWAP
            SWAP_INFO=$(free -m | grep -i "swap:")
            SWAP_TOTAL=$(echo $SWAP_INFO | awk '{print $2}')
            SWAP_USED=$(echo $SWAP_INFO | awk '{print $3}')
            
            SWAP_TOTAL=$(echo "${SWAP_TOTAL:-0}" | tr -dc '0-9')
            SWAP_USED=$(echo "${SWAP_USED:-0}" | tr -dc '0-9')
            : "${SWAP_TOTAL:=0}"
            : "${SWAP_USED:=0}"

            SWAP_PERC=0
            if [ "$SWAP_TOTAL" -gt 0 ]; then
                SWAP_PERC=$(( SWAP_USED * 100 / SWAP_TOTAL ))
            fi

            # Disco
            DISCO_DATA=$(df -h / | awk 'NR==2 {print $2, $3, $4, $5}')
            D_PERC=$(echo $DISCO_DATA | awk '{print $4}' | tr -d '%')
            D_PERC=${D_PERC:-0}

            # Obtener datos de GPU previamente para dibujarlos
            LAST_GPU_TEMP=0
            LAST_GPU_VRAM_PCT=0
            LAST_GPU_UTIL=0
            
            echo -e "\e[K${AZUL_CLARO}- 📊 RENDIMIENTO EN TIEMPO REAL -${RESET}"
            echo -ne "\e[K${NEGRITA}${VERDE_BRILLANTE}    *** CARGA CPU: ${RESET}"; dibujar_barra $CPU_PERC "uso"; echo -e " -> $(interpretar $CPU_PERC 'cpu')"
            echo -ne "\e[K${NEGRITA}${AZUL_BRILLANTE}    +++ USO RAM:   ${RESET}"; dibujar_barra $RAM_PERC "uso"; echo -e " -> $(interpretar $RAM_PERC 'ram')"
            
            # Barras GPU (si la herramienta nvidia-smi está disponible)
            if command -v nvidia-smi &>/dev/null; then
                # Ejecutamos la consulta para poblar las variables
                obtener_info_gpu_silent() {
                    local data=$(nvidia-smi --query-gpu=temperature.gpu,memory.used,memory.total --format=csv,noheader,nounits 2>/dev/null | head -n 1)
                    if [ -n "$data" ]; then
                        IFS=',' read -r t u tot <<< "$data"
                        LAST_GPU_TEMP=$(echo "$t" | tr -dc '0-9')
                        u=$(echo "$u" | tr -dc '0-9')
                        tot=$(echo "$tot" | tr -dc '0-9')
                        if [ "${tot:-0}" -gt 0 ]; then
                            LAST_GPU_VRAM_PCT=$(( u * 100 / tot ))
                        fi
                    fi
                }
                obtener_info_gpu_silent

                echo -ne "\e[K${NEGRITA}${VERDE_GPU}    🎮 USO VRAM:   ${RESET}"; dibujar_barra $LAST_GPU_VRAM_PCT "uso"; echo -e " -> $(interpretar $LAST_GPU_VRAM_PCT 'vram')"
                echo -ne "\e[K${NEGRITA}${ROJO_GPU}    🔥 TEMP GPU:   ${RESET}"; dibujar_barra $LAST_GPU_TEMP "temp"; echo -e " -> $(interpretar $LAST_GPU_TEMP 'gpu_temp')"
            fi

            if [ "$SWAP_TOTAL" -gt 0 ]; then
                echo -ne "\e[K${NEGRITA}${CIAN_BRILLANTE}    --- USO SWAP:  ${RESET}"; dibujar_barra $SWAP_PERC "uso"; echo -e " -> $(interpretar $SWAP_PERC 'swap')"
            fi

            echo -ne "\e[K${NEGRITA}${CIAN_BRILLANTE}    *** USO DISCO: ${RESET}"; dibujar_barra $D_PERC "uso"; echo -e " -> $(interpretar $D_PERC 'disco')"
            
            obtener_resumen_inicio
            obtener_info_gpu
            obtener_info_red
            obtener_info_seguridad

            echo -ne "\e[J"
        )
        
        echo -e "$OUTPUT"
        read -t 2.9 -n 1 -s key
    done
}

monitor_rendimiento
