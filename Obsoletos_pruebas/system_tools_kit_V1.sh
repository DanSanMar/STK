#!/bin/bash

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
    # Fuente de bloque sólido para máxima legibilidad
    echo -e "${CIAN}  ██████  ████████ ██   ██"
    echo -e "${AZUL_BRILLANTE}  ██         ██    ██  ██ "
    echo -e "${AZUL}  ██████     ██    █████  "
    echo -e "${AZUL}       ██    ██    ██  ██ "
    echo -e "${AZUL_BRILLANTE}  ██████     ██    ██   ██"
    echo -e "${VERDE_BRILLANTE}  SYSTEM TOOL KIT       v1.0 ${RESET}"
    echo -e "${CIAN}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
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

# Verificando dependencias en silencio
for pkg in nmap zip xdg-user-utils; do
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
    pintar $CIAN "  ▌ 5) Escaneo de red local"
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
                
                read -p "¿Deseas realizar limpieza de paquetes? (s/n): " confirmar
                if [[ $confirmar =~ ^[sS] ]]; then
                    apt-get autoremove -y > /dev/null
                    pintar $VERDE "Limpieza realizada."
                fi
            else
                pintar $ROJO "Error al conectar con los servidores."
            fi
            read -p "Pulse Enter para continuar..."
            ;;
        
        2)
            echo ""
            read -p "Nombre del programa: " programa
            read -p "¿Instalar $programa? (s/n): " confirmar
            if [[ $confirmar =~ ^[sS] ]]; then
                apt-get install -y $programa
                [[ $? -eq 0 ]] && pintar $VERDE "Éxito" || pintar $ROJO "Error"
            fi
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
                echo "  4. Volver al menú principal"
                echo "  ─────────────────────────────────────"
                read -p "  Opción: " sub_user
                case $sub_user in
                    1) echo ""; cut -d: -f1,3 /etc/passwd | awk -F: '$2 >= 1000 {print "  • " $1}'; echo ""; read -p "  Presione Enter..." ;;
                    2) read -p "  Nombre del nuevo usuario: " nu; adduser $nu; read -p "  Enter..." ;;
                    3) read -p "  Nombre del usuario a borrar: " bu; deluser --remove-home $bu; read -p "  Enter..." ;;
                    4) break ;;
                esac
            done
            ;;

        4)
            echo ""
            pintar $MAGENTA "Iniciando Súper Limpieza..."
            # Guardamos espacio antes
            ANTES=$(df / | awk 'NR==2 {print $3}')
            apt-get install -f -y && apt-get autoremove -y && apt-get autoclean -y
            rm -rf /home/*/.local/share/Trash/*
            # Espacio después
            DESPUES=$(df / | awk 'NR==2 {print $3}')
            LIBERADO=$(( (ANTES - DESPUES) / 1024 ))
            
            pintar $VERDE_BRILLANTE "¡Sistema limpio! ✨"
            [[ $LIBERADO -gt 0 ]] && echo "Se han liberado aprox. ${LIBERADO} MB."
            read -p "Pulse Enter..."
            ;;

        5)
            echo ""
            pintar $CIAN "Buscando dispositivos activos..."
            MI_IP=$(hostname -I | awk '{print $1}' | cut -d. -f1-3)
            if [ -z "$MI_IP" ]; then
                pintar $ROJO "Error: Sin conexión de red."
            else
                mostrar_spinner & PID_SPINNER=$!
                MAPA=$(nmap -sn $MI_IP.0/24 | grep "Nmap scan report")
                kill $PID_SPINNER > /dev/null 2>&1
                printf "\r${VERDE_BRILLANTE}[✔] Dispositivos encontrados:${RESET}          \n"
                echo "$MAPA" | sed 's/Nmap scan report for /  → /'
            fi
            echo ""
            read -p "Pulse Enter para continuar..."
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
            chown $USUARIO_REAL:$USUARIO_REAL "$CARPETA_BACKUP"

            if [ -d "$ORIGEN" ]; then
                pintar $CIAN "Comprimiendo Documentos..."
                (cd "$ORIGEN" && zip -rq "$CARPETA_BACKUP/$ARCHIVO" .)
                chown $USUARIO_REAL:$USUARIO_REAL "$CARPETA_BACKUP/$ARCHIVO"
                pintar $VERDE "Backup guardado en: $CARPETA_BACKUP/$ARCHIVO"
            else
                pintar $ROJO "No se encontró la carpeta Documentos en $ORIGEN"
            fi
            read -p "Pulse Enter..."
            ;;

        7)
            echo ""
            pintar $VERDE_BRILLANTE "  ¡Gracias por usar System Tool Kit!"
            exit 0
            ;;
        *)
            pintar $ROJO "  Opción no válida"
            sleep 1
            ;;
    esac
done