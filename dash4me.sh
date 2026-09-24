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

VER="V 1.6.2" #estable


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
    # Obtener interfaz por defecto y su IP local en un solo comando sin grep -P
    read -r iface ip_local <<< "$(ip route get 1.1.1.1 2>/dev/null | awk '{print $5, $7; exit}')"
    
    local rx_gb="0.00"
    local tx_gb="0.00"

    if [ -n "$iface" ] && [ "$iface" != "lo" ]; then
        local rx_bytes=$(cat /sys/class/net/"$iface"/statistics/rx_bytes 2>/dev/null || echo 0)
        local tx_bytes=$(cat /sys/class/net/"$iface"/statistics/tx_bytes 2>/dev/null || echo 0)
        
        # Un solo proceso awk para procesar ambos valores a GB (Base 1024)
        read -r rx_gb tx_gb <<< "$(awk -v rx="$rx_bytes" -v tx="$tx_bytes" 'BEGIN {printf "%.2f %.2f", rx/1073741824, tx/1073741824}')"
    else
        iface="N/A"
        ip_local="Sin IP"
    fi

    # Comprobación de conectividad optimizada en paralelo
    local status_ping="${ROJO_BRILLANTE}Desconectado${RESET}"
    
    # 1. Chequeo rápido por TCP directo a Cloudflare (puerto 53) en 1 segundo máximo
    if nc -zw1 1.1.1.1 53 &>/dev/null; then
        status_ping="${VERDE_BRILLANTE}OK (1.1.1.1:53)${RESET}"
    # 2. Fallback ICMP ping a Google DNS (solo 1 paquete, timeout estricto)
    elif ping -c 1 -w 1 8.8.8.8 &>/dev/null; then
        status_ping="${VERDE_BRILLANTE}OK (8.8.8.8)${RESET}"
    # 3. Última opción HTTP
    elif curl -sI --connect-timeout 1 http://www.google.com &>/dev/null; then
        status_ping="${VERDE_BRILLANTE}OK (HTTP)${RESET}"
    fi

    echo -e "\e[K${AZUL_CLARO}- 🌐 TELEMETRÍA Y RED -${RESET}"
    echo -e "\e[K   ${NEGRITA}${BLANCO}Interfaz:${RESET} ${AZUL_BRILLANTE}${iface}${RESET} (${CIAN_BRILLANTE}${ip_local}${RESET})${NEGRITA}${BLANCO} Ping: $status_ping"
    echo -e "\e[K   ${NEGRITA}${BLANCO}Tráfico I/O:${RESET} RX: ${VERDE_BRILLANTE}${rx_gb} GB${RESET} | TX: ${AMARILLO_BRILLANTE}${tx_gb} GB${RESET}"
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

        # Color Logo (basado en el último dígito)
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

        # Color Versión (desfasado 5 segundos para ser asíncrono)
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
            echo -e "\e[K ${AZUL_BRILLANTE}--- ⚡ ${COLOR_LOGO}DASH4ME${RESET} ${AZUL_OSCURO}| ${COLOR_DASH}LITE DASHBOARD${RESET} ${AZUL_OSCURO}| ${COLOR_VER}${VER}${RESET} ${BLANCO}:${HORA_ACTUAL}: ${AZUL_BRILLANTE}⚡---\e[0m"
            echo -e "\e[K ${AZUL_BRILLANTE} - ${RESET}AUTO-REFRESCO: ${CIAN}3s${RESET} | ENTER=${CIAN}Actualizar ${RESET}| CTRL+C=${CIAN}Salir${RESET}${AZUL_BRILLANTE} - "

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

            echo -e "\e[K${AZUL_CLARO}- 📊 RENDIMIENTO EN TIEMPO REAL -${RESET}"
            echo -ne "\e[K${NEGRITA}${VERDE_BRILLANTE}    *** CARGA CPU: ${RESET}"; dibujar_barra $CPU_PERC; echo -e " -> $(interpretar $CPU_PERC 'cpu')"
            echo -ne "\e[K${NEGRITA}${AZUL_BRILLANTE}    +++ USO RAM:   ${RESET}"; dibujar_barra $RAM_PERC; echo -e " -> $(interpretar $RAM_PERC 'ram')"
            
            if [ "$SWAP_TOTAL" -gt 0 ]; then
                echo -ne "\e[K${NEGRITA}${CIAN_BRILLANTE} --- USO SWAP:  ${RESET}"; dibujar_barra $SWAP_PERC; echo -e " -> $(interpretar $SWAP_PERC 'swap')"
            fi

            echo -ne "\e[K${NEGRITA}${CIAN_BRILLANTE}    *** USO DISCO: ${RESET}"; dibujar_barra $D_PERC; echo -e " -> $(interpretar $D_PERC 'disco')"
            echo -e "\e[K${AZUL_CLARO}- 💻 SISTEMA -${RESET}"
            echo -e "\e[K   ${NEGRITA}${AMARILLO}CPU:${RESET} ${BLANCO}${CPU_MODEL} ${RESET}${CIAN_BRILLANTE}${CPU_CORES}${RESET} hilos ${RESET}"
            echo -e "\e[K   ${BLANCO}Now:${RESET} ${CIAN_BRILLANTE}${CPU_GHZ}${RESET} GHz${NEGRITA}${BLANCO} | ${RESET}${CIAN_BRILLANTE}${CPU_DETAIL}${RESET}"
            echo -e "\e[K   ${NEGRITA}${AMARILLO}RAM:${RESET}   ${VERDE_BRILLANTE}${G_USED}GB${RESET} usados / ${BLANCO}${G_TOTAL}GB${RESET} total (Disp: ${AZUL_BRILLANTE}${G_DISP}GB${RESET})"
            echo -e "\e[K   ${NEGRITA}${AMARILLO}DISCO:${RESET} ${VERDE_BRILLANTE}${D_USADO}${RESET} usados / ${BLANCO}${D_TOTAL}${RESET} total (Libre: ${AZUL_BRILLANTE}${D_LIBRE}${RESET})"
            
            obtener_resumen_inicio
            obtener_info_arranque
            obtener_info_red
            obtener_info_seguridad

            

            echo -ne "\e[J"
        )
        
        echo -e "$OUTPUT"
        read -t 1.9 -n 1 -s key
    done
}

obtener_info_arranque() {
    local boot_time="N/A"
    local kernel_time="N/A"
    local user_time="N/A"
    local slowest_service="N/A"
    local boot_sec=0
    local last_boot=$(uptime -s 2>/dev/null || who -b 2>/dev/null | awk '{print $3,$4}')

    # 1. Ruta global en /var/log
    local data_dir="/var/log/dash4me"
    local log_file="$data_dir/boot_history.log"

    # Intentar crear el directorio si hay permisos
    if [ ! -d "$data_dir" ] && [ -w "/var/log" ]; then
        mkdir -p "$data_dir" 2>/dev/null
        chmod 755 "$data_dir" 2>/dev/null
    fi

    # 2. Obtener tiempos del arranque actual
    if command -v systemd-analyze &>/dev/null; then
        local sa_output
        sa_output=$(systemd-analyze 2>/dev/null | head -n 1)

        if [ -n "$sa_output" ]; then
            kernel_time=$(echo "$sa_output" | grep -oP '[\d\.]+(ms|s|min)(?=\s+\(kernel\))' || echo "N/A")
            user_time=$(echo "$sa_output" | grep -oP '[\d\.]+(ms|s|min)(?=\s+\(userspace\))' || echo "N/A")
            boot_time=$(echo "$sa_output" | awk -F '=' '{print $2}' | xargs || echo "N/A")

            # Extraer segundos totales de forma limpia
            boot_sec=$(echo "$boot_time" | awk '{
                sec=0;
                for(i=1; i<=NF; i++) {
                    if ($i ~ /min/) { gsub(/[^0-9.]/, "", $i); sec += $i * 60 }
                    else if ($i ~ /ms/) { gsub(/[^0-9.]/, "", $i); sec += $i / 1000 }
                    else if ($i ~ /s/) { gsub(/[^0-9.]/, "", $i); sec += $i }
                }
                print sec
            }')
        fi

        slowest_service=$(systemd-analyze blame 2>/dev/null | head -n 1 | awk '{print $2 " (" $1 ")"}')
    fi

    # 3. Registrar el arranque en el log global si es escribible
    if [ -n "$boot_sec" ] && [ "$(awk -v n="$boot_sec" 'BEGIN {print (n>0)?1:0}')" -eq 1 ]; then
        local boot_id_stamp=$(date -d "$last_boot" "+%Y-%m-%dT%H:%M:%S" 2>/dev/null || echo "$last_boot")
        
        if [ -w "$data_dir" ] || [ -w "$log_file" ]; then
            if [ ! -f "$log_file" ] || ! grep -q "^$boot_id_stamp" "$log_file" 2>/dev/null; then
                echo "$boot_id_stamp,$boot_sec" >> "$log_file" 2>/dev/null
                chmod 644 "$log_file" 2>/dev/null
            fi
        fi
    fi

    # 4. Cálculo de la media histórica (Corrección del error sintáctico)
    local media_str="N/A"
    local comparativa=""

    if [ -f "$log_file" ] && [ -s "$log_file" ]; then
        local stats
        stats=$(awk -F',' -v actual="$boot_sec" '
            BEGIN { suma=0; count=0 }
            $2 ~ /^[0-9]+(\.[0-9]+)?$/ { suma += $2; count++ }
            END {
                if (count > 0) {
                    media = suma / count;
                    diff = actual - media;
                    printf "%.2f %.2f %d", media, diff, count;
                }
            }
        ' "$log_file")

        if [ -n "$stats" ]; then
            read -r media diff count <<< "$stats"
            media_str="${media}s ($count log)"

            local es_mayor=$(awk -v d="$diff" 'BEGIN {print (d > 0.5)?1:0}')
            local es_menor=$(awk -v d="$diff" 'BEGIN {print (d < -0.5)?1:0}')

            if [ "$es_mayor" -eq 1 ]; then
                comparativa=" ${ROJO_BRILLANTE}(+${diff}s)${RESET}"
            elif [ "$es_menor" -eq 1 ]; then
                # Cálculo seguro del valor absoluto usando la función abs() en awk
                local diff_abs=$(awk -v d="$diff" 'BEGIN { printf "%.2f", (d < 0 ? -d : d) }')
                comparativa=" ${VERDE_BRILLANTE}(-${diff_abs}s)${RESET}"
            else
                comparativa=" ${VERDE_BRILLANTE}(=)${RESET}"
            fi
        fi
    fi

    echo -e "\e[K${AZUL_CLARO}- 🚀 ARRANQUE -${RESET}"
    echo -e "\e[K   ${NEGRITA}${AZUL_BRILLANTE}Último:${RESET} ${BLANCO}$last_boot${RESET} ${NEGRITA}${AZUL_BRILLANTE}Tiempo:${RESET} ${BLANCO}${boot_time:-"N/A"}${RESET}${comparativa}"
    echo -e "\e[K   ${CIAN_BRILLANTE}Kernel:${RESET} ${BLANCO}$kernel_time${RESET} | ${CIAN_BRILLANTE}Userspace:${RESET} ${BLANCO}$user_time${RESET} ${NEGRITA}${AZUL_BRILLANTE}Media:${RESET} ${BLANCO}$media_str${RESET}"
    echo -e "\e[K   ${NEGRITA}${AZUL_BRILLANTE}Más lento:${RESET} ${AMARILLO_BRILLANTE}${slowest_service:-"N/A"}${RESET}"
}

obtener_info_seguridad() {
    # 1. Estado del Firewall
    local ufw_print="${AMARILLO_BRILLANTE}No instalado${RESET}"
    if command -v ufw &>/dev/null; then
        local ufw_status=$(ufw status 2>/dev/null | head -n 1 | awk '{print $2}')
        if [ "$ufw_status" = "active" ]; then
            ufw_print="${VERDE_BRILLANTE}Activo${RESET}"
        else
            ufw_print="${ROJO_BRILLANTE}Inactivo${RESET}"
        fi
    fi

    # 2. Conexiones SSH activas
    local ssh_sessions
    ssh_sessions=$(ss -tn state established '( dport = :22 or sport = :22 )' 2>/dev/null | tail -n +2 | wc -l)

    # 3. Conteo y extracción de procesos Sudo activos
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

    # 4. Shells sospechosas (Extracción de proceso y sockets)
    local rev_print="${VERDE_BRILLANTE}Ninguna detectada${RESET}"
    local rev_details=""
    
    local raw_shells
    raw_shells=$(ss -tupn state established 2>/dev/null | grep -E '(bash|sh|zsh|python|perl|nc|socat)')

    if [ -n "$raw_shells" ]; then
        local reverse_shells
        reverse_shells=$(echo "$raw_shells" | wc -l)
        rev_print="${ROJO_BRILLANTE}${NEGRITA}⚠️ ALERTA: $reverse_shells sospechosa(s)${RESET}"

        # Extrae: proceso (puerto_local -> socket_remoto)
        rev_details=$(echo "$raw_shells" | awk '{
            proc="desconocido";
            if (match($0, /users:\(\("([^"]+)"/, m)) proc=m[1];
            local_addr=$5;
            remote_addr=$6;
            print proc " (" local_addr " -> " remote_addr ")"
        }' | tr '\n' '  ' | sed 's/  $//')
    fi

    # 5. Puertos en escucha mapeados con su proceso
    local listen_info
    listen_info=$(ss -tulnp 2>/dev/null | awk 'NR>1 {
        split($5, a, ":"); 
        port=a[length(a)]; 
        proc="desconocido"; 
        if (match($0, /users:\(\("([^"]+)"/, m)) proc=m[1]; 
        if (port ~ /^[0-9]+$/) print port " (" proc ")"
    }' | sort -nu -k1,1 | head -n 6 | tr '\n' '  ' | sed 's/  $//')
    
    [ -z "$listen_info" ] && listen_info="Ninguno"

    # --- IMPRESIÓN DEL MÓDULO ---
    echo -e "\e[K${AZUL_CLARO}- 🛡️ SEGURIDAD -${RESET}"
    echo -e "\e[K   ${NEGRITA}${AZUL_BRILLANTE}UFW:${RESET} $ufw_print | ${NEGRITA}${AZUL_BRILLANTE}SSH activas:${RESET} ${BLANCO}${ssh_sessions}${RESET} | ${NEGRITA}${AZUL_BRILLANTE}Sudos activos:${RESET} ${AMARILLO_BRILLANTE}${sudo_count}${RESET}"
    echo -e "\e[K   ${NEGRITA}${AZUL_BRILLANTE}Shells Sospechosas:${RESET} $rev_print"
    
    # Detalle condicional para alerta de shells
    if [ -n "$rev_details" ]; then
        echo -e "\e[K   ${ROJO_BRILLANTE}   └── Detalle:${RESET} ${BLANCO}${rev_details}${RESET}"
    fi

    if [ "$sudo_count" -gt 0 ]; then
        echo -e "\e[K   ${NEGRITA}${AZUL_BRILLANTE}Ejecutando Sudo:${RESET} ${AMARILLO_BRILLANTE}${sudo_procs}${RESET}"
    fi
    echo -e "\e[K   ${NEGRITA}${AZUL_BRILLANTE}Puertos escuchando:${RESET} ${CIAN_BRILLANTE}[ $listen_info ]${RESET}"
}

monitor_rendimiento