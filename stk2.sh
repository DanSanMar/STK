#!/bin/bash

# --- INFORMACIÓN DEL PROYECTO ---
V="2.5"
DESCRIPCION="Herramienta integral de mantenimiento para Linux"
AUTOR="DanSanMar"

# --- CONFIGURACIÓN DE COLORES (Normalizados) ---
RESET='\e[0m'
NEGRITA='\e[1m'
VERDE_BRILLANTE='\e[92m'
VERDE='\e[32m'
AMARILLO='\e[33m'
AZUL='\e[34m'
AZUL_BRILLANTE='\e[94m'
CIAN='\e[36m'
MAGENTA='\e[35m'
ROJO='\e[31m'
ROJO_BRILLANTE='\e[91m'

# --- COMPROBACIÓN DE SUDO ---
# Corregido: Usaba variables RED/NC que no existían
if [ "$EUID" -ne 0 ]; then
    echo -e "${ROJO_BRILLANTE}⚠️ Error: Este script requiere privilegios de root.${RESET}"
    echo -e "${AMARILLO}Prueba con: sudo $0${RESET}"
    exit 1
fi

    # 1. Identificación del gestor de paquetes, usamos variable Package vacia
Package=""

if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID=$ID
        OS_LIKE=$ID_LIKE
        VERSION=$VERSION
        URL=$HOME_URL
fi

        # Lógica de detección 
    case "$OS_ID" in
        debian|ubuntu|linuxmint|pop|kali|raspbian) Package="apt" ;;
        fedora|rhel|centos|rocky|almalinux)        Package="dnf" ;;
        arch|manjaro|endeavouros|garuda)           Package="pacman" ;;
        opensuse*|suse)                            Package="zypper" ;;
        *)
            if [[ "$OS_LIKE" == *"debian"* ]]; then Package="apt"
            elif [[ "$OS_LIKE" == *"fedora"* ]] || [[ "$OS_LIKE" == *"rhel"* ]]; then Package="dnf"
            elif [[ "$OS_LIKE" == *"arch"* ]]; then Package="pacman"
            elif [[ "$OS_LIKE" == *"suse"* ]]; then Package="zypper"
            elif command -v apt &>/dev/null;    then Package="apt"
            elif command -v dnf &>/dev/null;    then Package="dnf"
            elif command -v pacman &>/dev/null; then Package="pacman"
            elif command -v zypper &>/dev/null; then Package="zypper"
            else Package="unknown"; fi
            ;;
    esac
# --- FUNCIONES AUXILIARES ---
pintar() { 
    local COLOR="$1" 
    local MENSAJE="$2" 
    echo -e "${COLOR}${MENSAJE}${RESET}"
}
# --- CAPTURA DE SEÑALES (Salida limpia con Ctrl+C) ---
trap salir SIGINT SIGTERM

salir() {
    
    echo -e "${VERDE}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo ""
    pintar $AZUL "Saliendo de forma segura..."
    pintar $VERDE "¡Gracias por usar STK, hasta pronto!"
    echo ""
    echo -e "${VERDE}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    exit 0
}

mostrar_logo() {
    # He re-alineado los bloques de ASCII para que encajen perfectamente
    echo -e "${CIAN}  ██████  ████████ ██   ██${RESET}"
    echo -e "${AZUL_BRILLANTE}  ██         ██    ██  ██ ${RESET}"
    echo -e "${AZUL}  ██████     ██    █████  ${RESET}"
    echo -e "${AZUL}       ██    ██    ██  ██ ${RESET}"
    echo -e "${AZUL_BRILLANTE}  ██████     ██    ██   ██${RESET}"
    echo -e "${VERDE_BRILLANTE}  SYSTEM TOOL KIT-ALL4ME    v${V}${RESET}"
    echo -e "${AZUL}  By: ${AUTOR}${RESET}"
    echo -e "${CIAN}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    #OS_ID:-"Desconocido" Forma sencilla de decir: si no tiene valor imprime: "Desconocido"
    echo -e "${AMARILLO}➤ Sistema detectado:${RESET} ${AZUL}${OS_ID:-"Desconocido"}${RESET}"
    echo -e "${AMARILLO}➤ Gestor de paquetes:${RESET} ${AZUL}${Package:-"Desconocido"}${RESET}"
    echo -e "${AMARILLO}➤ Versión:${RESET} ${AZUL}${VERSION:-"Desconocido"}${RESET}"
    echo -e "${AMARILLO}➤ Web oficial:${RESET} ${AZUL}${URL:-"Desconocido"}${RESET}"
    echo -e "${CIAN}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo ""
}

# LÓGICA FZF
fzf_menu() {
    # Definimos las opciones que verá FZF
    local opciones="1. Actualizar sistema\n2. Instalar programa\n3. Desinstalar programa\n4. Gestión de usuarios\n5. Súper Limpieza\n6. Rendimiento del Sistema\n7. Copia de seguridad\n8. Salir (Control C)"
    
    # Ejecutamos fzf capturando la salida
    # --reverse lo pone arriba, --height para no tapar el logo, --border para la "ventana"
    echo -e "$opciones" | fzf --ansi \
        --height=15 \
        --reverse \
        --border=rounded \
        --prompt="➤ Seleccione acción: " \
        --header="P A N E L   D E   C O N T R O L" \
        --color="border:#00ffff,pointer:#92ff92,header:#5fb2ff"
}

menu() {
    while true; do
        clear
        mostrar_logo
        # Llamamos a fzf_menu y guardamos el resultado
        seleccion=$(fzf_menu)
        # --- ESTA ES LA LÓGICA QUE DETIENE EL BUCLE ---
        # Si fzf devuelve un error (130 es Ctrl+C) o la selección está vacía
        if [ $? -ne 0 ] || [ -z "$seleccion" ]; then
            salir
        fi
        # Extraemos el primer carácter (el número) de la selección de fzf
        case ${seleccion:0:1} in
            1) Actualizar_sistema ;;
            2) instalar_programa ;;
            3) desinstalar_programa ;; 
            4) gestionar_usuarios ;;
            5) super_limpieza ;;
            6) mostrar_rendimiento ;;
            7) hacer_backup ;;
            8) salir ;;
        esac
    done
}

Actualizar_sistema() {
    clear
    mostrar_logo
    pintar $AZUL_BRILLANTE "➤ Iniciando actualización automática del sistema..."
    echo ""

    # 2. Ejecución de comandos según el gestor
    case "$Package" in
        apt)
            pintar $VERDE "Actualizando repositorios y paquetes (APT)..."
            apt update && apt full-upgrade -y && apt autoremove -y
            ;;
        dnf)
            pintar $VERDE "Actualizando sistema (DNF)..."
            dnf upgrade -y && dnf autoremove -y
            ;;
        pacman)
            pintar $VERDE "Sincronizando repositorios y sistema (PACMAN)..."
            pacman -Syu --noconfirm
            ;;
        zypper)
            pintar $VERDE "Refrescando y actualizando (ZYPPER)..."
            zypper refresh && zypper update -y
            ;;
        *)
            pintar $ROJO "❌ Error: No se pudo identificar un gestor compatible."
            read -p "Presione Enter para volver..."
            return 1
            ;;
    esac

    # 3. Resultado final
    if [ $? -eq 0 ]; then
        echo ""
        pintar $VERDE_BRILLANTE "✔ ¡El sistema se ha actualizado correctamente!"
    else
        echo ""
        pintar $ROJO "✘ Hubo un error durante la actualización."
    fi

    echo ""
    read -p "Presione Enter para volver al menú..."
}

instalar_programa() {
    clear
    mostrar_logo 
    echo ""
    read -p "Escriba el nombre del programa que desea instalar/actualizar: " programa
    
    # Validar que el usuario no dejó el nombre vacío
    if [[ -z "$programa" ]]; then
        pintar $ROJO "⚠️ No escribió ningún nombre. Intenteló otra vez."
        sleep 2
        return 1
    fi
  
    echo ""
    echo -e "${AMARILLO}➤ Gestor de paquetes para la instalación:${RESET} ${AZUL}$Package${RESET}"
    echo ""

    # 2. Ejecución de comandos (CORREGIDOS)
    case "$Package" in
        apt)
            pintar $VERDE "Actualizando índices e instalando/actualizando $programa..."
            apt update
            apt install "$programa" -y  # Corregido "insall" por "install"
            ;;
        dnf)
            pintar $VERDE "Instalando/actualizando $programa..."
            dnf install "$programa" -y
            ;;
        pacman)
            pintar $VERDE "Instalando/actualizando $programa..."
            # CORRECCIÓN: pacman no usa "install", usa "-S"
            pacman -S --noconfirm "$programa" 
            ;;
        zypper)
            pintar $VERDE "Instalando/actualizando $programa..."
            zypper install -y "$programa"
            ;;
        *)
            pintar $ROJO "❌ Error: No se pudo identificar un gestor compatible."
            read -p "Presione Enter para volver..."
            return 1
            ;;
    esac

    # 3. Resultado final
    if [ $? -eq 0 ]; then
        echo ""
        pintar $VERDE_BRILLANTE "✔ ¡$programa se ha instalado/actualizado correctamente!"
    else
        echo ""
        pintar $ROJO "✘ Hubo un error durante el proceso de instalación/actualización de $programa."
    fi

    echo ""
    read -p "Presione Enter para volver al menú..."
}

desinstalar_programa() {
    clear
    mostrar_logo 
    echo ""
    read -p "Escriba el nombre del programa que desea desinstalar: " programa
    
    if [[ -z "$programa" ]]; then
        pintar $ROJO "⚠️ No escribió ningún nombre."
        sleep 2
        return 1
    fi
  
    echo -e "${ROJO}➤ Preparando para eliminar:${RESET} ${AZUL}$programa${RESET}"
    echo ""

    case "$Package" in
        apt)
            pintar $VERDE "Eliminando y limpiando configuraciones (APT)..."
            apt purge "$programa" -y && apt autoremove -y
            ;;
        dnf)
            pintar $VERDE "Eliminando paquete (DNF)..."
            dnf remove "$programa" -y
            ;;
        pacman)
            pintar $VERDE "Eliminando paquete y dependencias no usadas (PACMAN)..."
            pacman -Rs --noconfirm "$programa"
            ;;
        zypper)
            pintar $VERDE "Eliminando paquete (ZYPPER)..."
            zypper remove -y "$programa"
            ;;
        *)
            pintar $ROJO "❌ Gestor no compatible."
            return 1
            ;;
    esac

    if [ $? -eq 0 ]; then
        pintar $VERDE_BRILLANTE "✔ ¡$programa ha sido eliminado correctamente!"
    else
        pintar $ROJO "✘ Error al intentar desinstalar $programa."
    fi
    read -p "Presione Enter para volver..."
}

gestionar_usuarios() {
    
    listar_usuarios() {
        echo ""
        pintar $AZUL_BRILLANTE "--- Usuarios Humanos (UID >= 1000) ---"
        cut -d: -f1,3 /etc/passwd | awk -F: '$2 >= 1000 {print "  • " $1}'
        echo ""
        read -p "Presione Enter para continuar..."
    }

    pedir_nombre() {
        local nombre
        nombre=$(zenity --entry --text="Ingrese nombre de usuario" --title="Gestión" 2>/dev/null)
        if [ $? -ne 0 ] || [ -z "$nombre" ]; then
            read -p "Nombre de usuario: " nombre
        fi
        echo "$nombre"
    }

    while true; do
        clear
        mostrar_logo
        seleccion_users=$(fzf_menu_users)
        
        # Capturamos escape o Ctrl+C para volver al menú principal
        if [ $? -ne 0 ] || [ -z "$seleccion_users" ]; then
            break
        fi

        case ${seleccion_users:0:1} in
            1) listar_usuarios ;;
            2) 
                user=$(pedir_nombre)
                if [ -n "$user" ]; then
                    pintar $AMARILLO "➤ Creando usuario $user..."
                    # Lógica según el gestor detectado
                    if [[ "$Package" == "apt" ]]; then
                        sudo adduser "$user"
                    else
                        # Para Fedora, Arch, etc., usamos useradd (estándar universal)
                        sudo useradd -m -s /bin/bash "$user"
                        pintar $AMARILLO "Establezca la contraseña para $user:"
                        sudo passwd "$user"
                    fi
                fi
                read -p "Proceso finalizado. Presione Enter..." ;;
            3) 
                user=$(pedir_nombre)
                if [ -n "$user" ]; then
                    pintar $ROJO "➤ Eliminando usuario $user..."
                    if [[ "$Package" == "apt" ]]; then
                        sudo deluser --remove-home "$user"
                    else
                        # userdel -r es el equivalente universal
                        sudo userdel -r "$user"
                    fi
                fi
                read -p "Proceso finalizado. Presione Enter..." ;;
            4) break ;;
            5) salir ;;
        esac
    done
}

fzf_menu_users() {
    local opciones="1. Listar usuarios humanos\n2. Crear usuario\n3. Eliminar usuario\n4. Volver al menú principal\n5. Salir"
    
    echo -e "$opciones" | fzf --ansi \
        --height=15 \
        --reverse \
        --border=rounded \
        --prompt="➤ Seleccione acción: " \
        --header="--- GESTIÓN DE USUARIOS ---" \
        --color="border:#00ffff,pointer:#92ff92,header:#5fb2ff"
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

super_limpieza() {
    echo ""
    pintar $MAGENTA "Iniciando Súper Limpieza..."
    ANTES=$(df / | awk 'NR==2 {print $3}')
    apt-get install -f -y > /dev/null 2>&1
    apt-get autoremove -y > /dev/null 2>&1
    apt-get autoclean -y > /dev/null 2>&1
    rm -rf /home/*/.local/share/Trash/*
    DESPUES=$(df / | awk 'NR==2 {print $3}')
    LIBERADO=$(( (ANTES - DESPUES) / 1024 ))
    pintar $VERDE_BRILLANTE "¡Sistema limpio! ✨"
    [[ $LIBERADO -gt 0 ]] && echo "Se han liberado aprox. ${LIBERADO} MB."
    read -p "Pulse Enter..."
}

mostrar_rendimiento() {
    while true; do
        clear
        mostrar_logo
        obtener_rendimiento
        # Usamos zenity si está disponible, si no, un read simple para no romper el bucle
        if command -v zenity &>/dev/null; then
            seleccion=$(zenity --list --title="Rendimiento" --column="Opciones" "Refrescar" "Volver al menú" 2>/dev/null)
        else
            read -p "1. Refrescar / 2. Volver: " res
            [[ $res == "2" ]] && seleccion="Volver al menú" || seleccion="Refrescar"
        fi
        [[ "$seleccion" == "Volver al menú" ]] && break
    done
}

hacer_backup() {
    USUARIO_REAL=${SUDO_USER:-$USER}
    ORIGEN=$(sudo -u $USUARIO_REAL xdg-user-dir DOCUMENTS 2>/dev/null || echo "/home/$USUARIO_REAL/Documents")
    DESTINO_BASE=$(sudo -u $USUARIO_REAL xdg-user-dir DESKTOP 2>/dev/null || echo "/home/$USUARIO_REAL/Desktop")
    CARPETA_BACKUP="$DESTINO_BASE/Backup"
    ARCHIVO="backup_$(date +%d-%m-%y).zip"

    mkdir -p "$CARPETA_BACKUP"
    cd "$ORIGEN" && zip -rq "$CARPETA_BACKUP/$ARCHIVO" . > /dev/null 2>&1
    chown "$USUARIO_REAL:$USUARIO_REAL" "$CARPETA_BACKUP/$ARCHIVO"
    pintar $VERDE "Backup guardado en: $CARPETA_BACKUP/$ARCHIVO"
    read -p "Pulse Enter..."
}


# --- EJECUCIÓN ---
menu
