#!/bin/bash

# --- INFORMACIÓN DEL PROYECTO ---
VERSION="1.2"
DESCRIPCION="Herramienta integral de mantenimiento para Linux"
AUTOR="DanSanMar"

# --- CONFIGURACIÓN DE COLORES ---
RESET='\e[0m'
NEGRITA='\e[1m'
ROJO_BRILLANTE='\e[91m'
VERDE_BRILLANTE='\e[92m'
VERDE='\e[32m'
AMARILLO='\e[33m'
AZUL='\e[34m'
AZUL_BRILLANTE='\e[94m'
CIAN='\e[36m'
MAGENTA='\e[35m'
ROJO='\e[31m'

# --- FUNCIONES AUXILIARES ---
pintar() { 
    local COLOR="$1" 
    local MENSAJE="$2" 
    echo -e "${COLOR}${MENSAJE}${RESET}"
}

mostrar_logo() {
    echo -e "${CIAN}  ██████  ████████ ██   ██"
    echo -e "${AZUL_BRILLANTE}  ██         ██    ██  ██ "
    echo -e "${AZUL}  ██████     ██    █████  "
    echo -e "${AZUL}       ██    ██    ██  ██ "
    echo -e "${AZUL_BRILLANTE}  ██████     ██    ██   ██"
    echo -e "${VERDE_BRILLANTE}  SYSTEM TOOL KIT       v${VERSION} ${RESET}"
    echo -e "${CIAN}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
}

obtener_rendimiento() {
    echo ""
    pintar $AZUL_BRILLANTE "  ESTADO DEL HARDWARE:"
    
    # CPU
    CPU_IDLE=$(top -bn1 | grep "Cpu(s)" | awk '{print $8}' | cut -d. -f1 | cut -d, -f1)
    CPU_LOAD=$(( 100 - CPU_IDLE ))
    echo -ne "  CPU:  [ "
    for i in {1..20}; do
        if [ $CPU_LOAD -ge $((i*5)) ]; then echo -ne "${VERDE}#${RESET}"; else echo -ne "."; fi
    done
    echo -e " ] ${CPU_LOAD}%"

    # RAM
    MEM_TOTAL=$(free -m | awk '/Mem:/ { print $2 }')
    MEM_USED=$(free -m | awk '/Mem:/ { print $3 }')
    MEM_PERC=$(( MEM_USED * 100 / MEM_TOTAL ))
    echo -ne "  RAM:  [ "
    for i in {1..20}; do
        if [ $MEM_PERC -ge $((i*5)) ]; then echo -ne "${AZUL}#${RESET}"; else echo -ne "."; fi
    done
    echo -e " ] ${MEM_PERC}% (${MEM_USED}MB / ${MEM_TOTAL}MB)"

    # TEMPERATURA
    TEMP_VAL=$(sensors 2>/dev/null | grep -m 1 "temp1\|Core 0\|Package id 0" | awk '{print $2}' | tr -d '+°C')
    if [ -z "$TEMP_VAL" ] && [ -f /sys/class/thermal/thermal_zone0/temp ]; then
        TEMP_RAW=$(cat /sys/class/thermal/thermal_zone0/temp)
        TEMP_VAL=$(( TEMP_RAW / 1000 ))
    fi
    if [ ! -z "$TEMP_VAL" ] && [ "$TEMP_VAL" != "0" ]; then
        echo -e "  TEMP: ${AMARILLO}${TEMP_VAL}°C${RESET}"
    else
        echo -e "  TEMP: ${ROJO}No detectada${RESET}"
    fi
    
    # DISCO
    DISCO=$(df -h / | awk 'NR==2 {print $5}')
    echo -e "  DISCO: ${CIAN}${DISCO} ocupado${RESET}"
}

mostrar_spinner() {
    local caracteres="/-\|"
    while true; do
        for (( i=0; i<${#caracteres}; i++ )); do
            printf "\r${AZUL_BRILLANTE}[%c]${RESET} Procesando..." "${caracteres:$i:1}"
            sleep 0.1
        done
    done
}

# --- VALIDACIONES INICIALES ---
if [ "$EUID" -ne 0 ]; then 
  pintar $ROJO_BRILLANTE "Error: Este script debe ejecutarse con sudo."
  exit 1
fi

for pkg in zip xdg-user-utils lm-sensors; do
    if ! command -v $pkg &> /dev/null; then
        apt-get install -y $pkg > /dev/null 2>&1
    fi
done

# --- BUCLE PRINCIPAL ---
while true; do
    clear
    mostrar_logo
    
    echo -e "${NEGRITA}  P A N E L  D E  C O N T R O L${RESET}"
    echo -e "${CIAN}  ▛━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━▜${RESET}"
    pintar $VERDE_BRILLANTE "  ▌ 1) Actualizar sistema"
    pintar $AMARILLO "  ▌ 2) Instalar programa"
    pintar $AZUL_BRILLANTE "  ▌ 3) Gestión de usuarios"
    pintar $MAGENTA "  ▌ 4) Súper Limpieza"
    pintar $CIAN "  ▌ 5) Rendimiento del Sistema"
    pintar $VERDE "  ▌ 6) Copia de seguridad"
    pintar $ROJO_BRILLANTE "  ▌ 7) Salir"
    echo -e "${CIAN}  ▙━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━▟${RESET}"
    echo ""
    read -p "  Seleccione una opción (1-7): " eleccion

    case $eleccion in 
        1)
            echo ""
            pintar $NEGRITA "Actualizando repositorios..."
            mostrar_spinner & PID_SPINNER=$!
            apt-get update -qq > /dev/null 2>&1
            STATUS=$?
            kill $PID_SPINNER > /dev/null 2>&1
            if [ $STATUS -eq 0 ]; then
                printf "\r${VERDE_BRILLANTE}[✔] Repositorios listos!${RESET}               \n"
                pintar $AMARILLO "Instalando actualizaciones..."
                mostrar_spinner & PID_SPINNER=$!
                apt-get upgrade -y -qq > /dev/null 2>&1
                kill $PID_SPINNER > /dev/null 2>&1
                printf "\r${VERDE_BRILLANTE}[✔] Actualizaciones completadas!${RESET}       \n"
            fi
            read -p "Pulse Enter..."
            ;;
        2)
            echo ""
            read -p "Nombre del programa: " programa
            apt-get install -y $programa
            read -p "Pulse Enter..."
            ;;
        3)
            while true; do
                clear
                mostrar_logo
                pintar $AZUL_BRILLANTE "  --- GESTIÓN DE USUARIOS ---"
                echo "  1. Listar usuarios humanos"
                echo "  2. Crear usuario"
                echo "  3. Eliminar usuario"
                echo "  4. Volver"
                read -p "  Opción: " sub_user
                case $sub_user in
                    1) echo ""; cut -d: -f1,3 /etc/passwd | awk -F: '$2 >= 1000 {print "  • " $1}'; echo ""; read -p "  Enter..." ;;
                    2) read -p "  Nombre: " nu; adduser $nu; read -p "Enter..." ;;
                    3) read -p "  Nombre: " bu; deluser --remove-home $bu; read -p "Enter..." ;;
                    4) break ;;
                esac
            done
            ;;
        4)
            echo ""
            pintar $MAGENTA "Iniciando Súper Limpieza..."
            ANTES=$(df / | awk 'NR==2 {print $3}')
            apt-get install -f -y && apt-get autoremove -y && apt-get autoclean -y
            rm -rf /home/*/.local/share/Trash/*
            DESPUES=$(df / | awk 'NR==2 {print $3}')
            LIBERADO=$(( (ANTES - DESPUES) / 1024 ))
            pintar $VERDE_BRILLANTE "¡Sistema limpio! ✨"
            [[ $LIBERADO -gt 0 ]] && echo "Se han liberado aprox. ${LIBERADO} MB."
            read -p "Pulse Enter..."
            ;;
        5)
            while true; do
                clear
                mostrar_logo
                obtener_rendimiento
                echo ""
                pintar $AMARILLO "  (Presione 'r' para refrescar o 'm' para volver al menú)"
                read -n 1 -t 5 accion 
                if [[ $accion == "m" ]]; then break; fi
            done
            ;;
        6)
            echo ""
            pintar $AMARILLO_BRILLANTE "  --- COPIA DE SEGURIDAD ---"
            USUARIO_REAL=${SUDO_USER:-$USER}
            ORIGEN=$(sudo -u $USUARIO_REAL xdg-user-dir DOCUMENTS)
            DESTINO_BASE=$(sudo -u $USUARIO_REAL xdg-user-dir DESKTOP)
            CARPETA_BACKUP="$DESTINO_BASE/Backup"
            ARCHIVO="backup_$(date +%d-%m-%y).zip"
            mkdir -p "$CARPETA_BACKUP"
            if [ -d "$ORIGEN" ]; then
                (cd "$ORIGEN" && zip -rq "$CARPETA_BACKUP/$ARCHIVO" .)
                chown $USUARIO_REAL:$USUARIO_REAL "$CARPETA_BACKUP/$ARCHIVO"
                pintar $VERDE "Backup guardado en: $CARPETA_BACKUP/$ARCHIVO"
            fi
            read -p "Pulse Enter..."
            ;;
        7) echo ""
         pintar $AZUL "Gracias por usar STK, hasta pronto!!"
        exit 0 ;;

        *) pintar $ROJO "Opción no válida"; sleep 1 ;;
    esac
done
