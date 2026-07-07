#!/bin/bash

# --- INFORMACIÓN DEL PROYECTO ---
V="5.8 Restaurar Backups"
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
BLANCO='\e[97m'
# --- CONFIGURACIÓN DE LOGS ---
LOG_FILE="/var/log/stk_mantenimiento.log"
# niveles de severidad
LOG_INFO="INFO"
LOG_WARN="WARN"
LOG_ERR="ERROR"

DATE=$(date +"%d/%m/%Y")

registrar_log() {
    local NIVEL="${1:-INFO}" # Si no se pasa nivel, por defecto es INFO
    local MENSAJE="${2}"
    local FECHA=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Formato: [FECHA] [NIVEL] [USUARIO] - MENSAJE
    echo "[$FECHA] [$NIVEL] [$USER] - $MENSAJE" >> "$LOG_FILE"
}
rotar_logs() {
    # Definimos el límite en Kilobytes (ejemplo: 500 KB)
    local MAX_SIZE=500
    
    if [ -f "$LOG_FILE" ]; then
        # Obtenemos el tamaño actual en KB
        local SIZE=$(du -k "$LOG_FILE" | cut -f1)
        
        if [ "$SIZE" -ge "$MAX_SIZE" ]; then
            # El comando > vacía el archivo instantáneamente sin cambiar el nombre
            echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] - Log reiniciado por alcanzar el límite de $MAX_SIZE KB." > "$LOG_FILE"
            
            # Aseguramos que los permisos sigan siendo correctos
            chmod 640 "$LOG_FILE"
        fi
    fi
}
ver_logs() {
    clear
    mostrar_logo
    if [ -f "$LOG_FILE" ]; then
        pintar $CIAN "--- Últimas 20 entradas de la bitácora ---"
        # Colorear INFO en verde, WARN en amarillo y ERROR en rojo al mostrar
        tail -n 20 "$LOG_FILE" | awk '
            /\[INFO\]/ {print "\033[32m" $0 "\033[0m"}
            /\[WARN\]/ {print "\033[33m" $0 "\033[0m"}
            /\[ERROR\]/ {print "\033[31m" $0 "\033[0m"}
        '
    else
        pintar $ROJO "Aún no hay registros."
    fi
    echo ""
    read -p "Presione Enter para volver..."
}
# --- COMPROBACIÓN DE SUDO ---
if [ "$EUID" -ne 0 ]; then
    echo -e "${ROJO_BRILLANTE}⚠️ Error: Este script requiere privilegios de root.${RESET}"
    echo -e "${AMARILLO}Prueba con: sudo $0${RESET}"
    exit 1
fi
# Inicio y comprobación de resgristo de logs
if [ ! -f "$LOG_FILE" ]; then
    umask 027
    touch "$LOG_FILE"
    chmod 640 "$LOG_FILE" # Solo root y el grupo pueden leerlo
    registrar_log "$LOG_INFO" "Bitácora inicializada - STK v$V"
fi
    # 1. Identificación del Package de paquetes, usamos variable Package vacia
Package=""

if [ -f /etc/os-release ]; then
        . /etc/os-release
        OS_ID="${ID:-unknown}"
        OS_LIKE="${ID_LIKE:-unknown}"
        VERSION="${VERSION:-unknown}"
        URL="${HOME_URL:-unknown}"
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

install_tools() {
    local tools_to_install=("$@")
    
    echo -e "\n${AZUL}🔄 Actualizando repositorios ($Package)...${RESET}"
    case "$Package" in
        "apt") apt update -y ;;
        "dnf") dnf makecache ;;
        "pacman") pacman -Sy ;;
        "zypper") zypper refresh ;;
    esac

    for tool in "${tools_to_install[@]}"; do
        pkg=$(get_package_name "$tool")

        if [[ "$pkg" == "GEM_REQUIRED" ]]; then
            echo -e "\n${AZUL}💎 Instalando $tool y dependencias de compilación para $Package...${RESET}"
            
            case "$Package" in
                "apt")
                    apt update -y
                    apt install -y ruby-full build-essential zlib1g-dev libcurl4-openssl-dev libcurl4
                    ;;
                "dnf")
                    # Equivalentes exactos para Fedora
                    dnf install -y ruby ruby-devel gcc gcc-c++ make zlib-devel libcurl-devel openssl-devel
                    ;;
                *)
                    echo -e "${ROJO}⚠️ $Package no soportado para dependencias Ruby. Intenta instalarlas manualmente.${RESET}"
                    ;;
            esac
    
            ldconfig 2>/dev/null
            echo -e "${AZUL}⚙️ Instalando gema WPScan...${RESET}"
            gem install wpscan
            continue
        fi

        if [[ "$pkg" == "SNAP_REQUIRED" ]]; then

            if ! command -v snap &> /dev/null; then
                echo -e "\n${AMARILLO}⚠️ $tool requiere Snap, pero no está instalado.${RESET}"
                echo -ne "${AMARILLO}¿Desea instalar snapd ahora? (s/n): ${RESET}"
                read -r snap_pref
                if [[ "$snap_pref" == "s" ]]; then
                    echo -e "\n${AZUL}📦 Instalando motor de Snap...${RESET}"
                    case "$Package" in
                        "apt") 
                            apt install -y snapd
                            systemctl enable --now snapd.socket
                            # Enlace simbólico vital en Debian para rutas estándar
                            ln -s /var/lib/snapd/snap /snap 2>/dev/null 
                            ;;
                        "dnf") dnf install -y snapd && systemctl enable --now snapd.socket ;;
                    esac
                    export PATH="$PATH:/snap/bin:/var/lib/snapd/snap/bin"
                    
                else
                    echo -e "${ROJO}❌ No se puede instalar $tool por falta de Snap.${RESET}"
                    continue
                fi
            fi


            echo -e "${AZUL}📦 Instalando $tool vía Snap...${RESET}"
            local classic=""
            [[ "$tool" == "feroxbuster" || "$tool" == "fzf" ]] && classic="--classic"
            snap install "$tool" $classic
            export PATH=$PATH:/var/lib/snapd/snap/bin
            
        else
            echo -e "${AZUL}📦 Instalando paquete: $pkg...${RESET}"
            case "$Package" in
                "apt") apt install -y "$pkg" ;;
                "dnf") dnf install -y "$pkg" ;;
                "pacman") pacman -S --noconfirm "$pkg" ;;
                "zypper") zypper install -y "$pkg" ;;
            esac
        fi
    done
}

mostrar_instrucciones() {
    clear
    echo -e "\n${AZUL}══════════════════════════════════════════════════${RESET}"
    echo -e "${BLANCO} 📖 GUÍA DE INSTALACIÓN MANUAL PARA TU SISTEMA (${Package^^})${RESET}"
    echo -e "${AZUL}══════════════════════════════════════════════════${RESET}\n"

    for tool in "${missing_tools[@]}"; do
        echo -e "${AMARILLO}🛠  Herramienta: ${BLANCO}$tool${RESET}"
        case "$tool" in
            "fzf"|"zenity"|"xsltproc"|"host")
                pkg=$(get_package_name "$tool")
                echo -e "   ${VERDE}✔ Estándar:${RESET} sudo $Package install -y $pkg"
                ;;
            "feroxbuster")
                echo -e "   ${VERDE}✔ Snap:${RESET}      sudo snap install feroxbuster"
                echo -e "   ${VERDE}✔ Manual:${RESET}    curl -sL https://raw.githubusercontent.com/epi052/feroxbuster/master/install-nix.sh | bash"
                ;;
            "wpscan")
                echo -e "   ${VERDE}✔ RubyGem:${RESET}   sudo gem install wpscan"
                echo -e "   ${VERDE}✔ Snap:${RESET}      sudo snap install wpscan"
                ;;
        esac
        echo -e "${AZUL}--------------------------------------------------${RESET}"
    done
    
}
#opciones especificas para instalación automática
get_package_name() {
    local tool=$1
    case "$tool" in
        "xsltproc") echo "xsltproc" ;;
        "host") [[ "$Package" == "apt" ]] && echo "dnsutils" || echo "bind-utils" ;;
        "tput") [[ "$Package" == "apt" ]] && echo "ncurses-bin" || echo "ncurses" ;;
        "free") echo "procps" ;;
        "feroxbuster") echo "SNAP_REQUIRED" ;;
        "wpscan") echo "GEM_REQUIRED" ;; 
        "fzf") echo "fzf" ;;
        *) echo "$tool" ;;
    esac
}

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
    echo ""
    pintar $VERDE "¡Gracias por usar STK, hasta pronto!"
    echo ""
    echo -e "${VERDE}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    exit 0
}

# --- DEFINICIÓN DE DEPENDENCIAS ---
# fzf: Menú interactivo
# xsltproc/host: Herramientas de red/procesamiento
# ncurses-bin/ncurses-utils: Para el manejo del cursor (tput)
# procps: Para comandos de sistema como 'free' o 'top'
dependencies=(fzf xsltproc host tput free curl wget tar hostname)
# --- LÓGICA DE RE-VERIFICACIÓN ---
check_dependencies() {
    missing_tools=()
    for tool in "${dependencies[@]}"; do
        # Intenta encontrarlo de forma normal, y si no, busca en la ruta de Snap
        if ! command -v "$tool" &> /dev/null && [ ! -f "/snap/bin/$tool" ] && [ ! -f "/var/lib/snapd/snap/bin/$tool" ]; then
            missing_tools+=("$tool")
        fi
    done
}

# --- FLUJO PRINCIPAL DE DEPENDENCIAS ---
if ! ping -c 1 8.8.8.8 &>/dev/null; then
    pintar $ROJO "❌ No hay conexión a internet. Algunas funciones fallarán."
fi
#llamada para comprobar los programas necesarios
check_dependencies
#Herramientas no instaladas
if [ ${#missing_tools[@]} -gt 0 ]; then
    echo -e "${ROJO}❌ No se han podido encontrar estas herramientas: ${missing_tools[*]}${RESET}"
    echo -e "${CIAN}¿Qué deseas hacer?${RESET}"
    echo -e "   ${BLANCO}s) Intento de instalación automática (Sudo)${RESET}"
    echo -e "   ${BLANCO}i) Mostrar instrucciones de instalación manual${RESET}"
    echo -e "   ${BLANCO}n) Continuar de todos modos (Puede fallar)${RESET}"
    echo -ne "\n${AMARILLO}Selecciona una opción: ${RESET}"
    read -r confirm

    if [[ "$confirm" == "s" ]]; then
        # 1. Intentar instalar
        install_tools "${missing_tools[@]}"
        
        # 2. Verificación crítica: ¿Realmente se instaló fzf?
        if ! command -v fzf &> /dev/null; then
            echo -e "${ROJO}❌ Error crítico: fzf no se pudo instalar o no está en el PATH.${RESET}"
            echo -e "${AMARILLO}Por favor, instálalo manualmente y reinicia.${RESET}"
            registrar_log "$LOG_ERR" "Error crítico: fzf no pudo ser instalado."
            exit 1
        fi
        registrar_log "$LOG_INFO" "Dependencias instaladas con exito: ${missing_tools[*]}"
        # 3. Re-verificar si quedan otras herramientas pendientes
        check_dependencies
        if [ ${#missing_tools[@]} -gt 0 ]; then
            echo -e "${ROJO}⚠️ Advertencia: Aún faltan herramientas: ${missing_tools[*]}. El script podría fallar.${RESET}"
            read -p "Presiona Enter para continuar de todos modos..."
        fi

    elif [[ "$confirm" == "i" ]]; then
        mostrar_instrucciones
        echo -e "\n${CIAN}Una vez instaladas, vuelve a ejecutar el script.${RESET}"
        exit 0

    elif [[ "$confirm" == "n" ]]; then
        echo -e "${AMARILLO}Continuando sin las dependencias... (Puede fallar)${RESET}"
        # No hacemos nada, el script sigue su curso

    else
        echo -e "${ROJO}❌ Opción no válida. Abortando.${RESET}"
        exit 1
    fi
fi
restaurar_backup() {
    local DESTINO_DEF="/var/backups/stk_backups"
    clear
    mostrar_logo
    pintar $CIAN "--- RESTAURAR COPIA DE SEGURIDAD ---"

    if [ ! -d "$DESTINO_DEF" ] || [ -z "$(find "$DESTINO_DEF" -name "*.tar.gz")" ]; then
        pintar $ROJO "No hay backups disponibles para restaurar."
        read -p "Presione Enter..."
        return
    fi

    local seleccion=$(find "$DESTINO_DEF" -type f -name "*.tar.gz" | fzf_estilo "Seleccione backup para RESTAURAR" "R E S T A U R A C I Ó N")

    if [ -n "$seleccion" ]; then
        echo -e "\n${AMARILLO}¿Dónde desea restaurar el backup?${RESET}"
        echo -e "1. En su ruta original (¡Peligro: Puede sobrescribir archivos!)"
        echo -e "2. En una ruta temporal (/tmp/stk_restaurado)"
        echo -ne "\nSeleccione una opción (1/2): "
        read -r opt_restaurar

        local ruta_extraccion="/"
        if [[ "$opt_restaurar" == "2" ]]; then
            ruta_extraccion="/tmp/stk_restaurado"
            mkdir -p "$ruta_extraccion"
        fi

        echo -ne "\n${ROJO_BRILLANTE}⚠️ ¿Confirmar restauración de $(basename "$seleccion")? (s/N): ${RESET}"
        read -r confirmar

        if [[ "$confirmar" == "s" || "$confirmar" == "S" ]]; then
            echo -e "\n${AZUL}🔄 Extrayendo archivos...${RESET}"
            mostrar_spinner & SPINNER_PID=$!
            
            tar -xzpf "$seleccion" -C "$ruta_extraccion" > /tmp/stk_restore_err 2>&1
            local EXIT_CODE=$?

            kill "$SPINNER_PID" 2>/dev/null; wait "$SPINNER_PID" 2>/dev/null
            printf "\r\e[K"

            if [ $EXIT_CODE -eq 0 ]; then
                pintar $VERDE_BRILLANTE "✔ Backup restaurado con éxito en: $ruta_extraccion"
                registrar_log "$LOG_INFO" "Backup restaurado: $seleccion en $ruta_extraccion"
            else
                pintar $ROJO "❌ Error al restaurar:"
                cat /tmp/stk_restore_err
                registrar_log "$LOG_ERR" "Error al restaurar backup: $seleccion"
            fi
        else
            pintar $AZUL "Operación cancelada."
        fi
        read -p "Presione Enter..."
    fi
}

mostrar_logo() {
    # He re-alineado los bloques de ASCII para que encajen perfectamente
    echo -e "${CIAN}  ██████  ████████ ██   ██${RESET}"
    echo -e "${AZUL_BRILLANTE}  ██         ██    ██  ██ ${RESET}"
    echo -e "${AZUL}  ██████     ██    █████  ${RESET}"
    echo -e "${AZUL}       ██    ██    ██  ██ ${RESET}"
    echo -e "${AZUL_BRILLANTE}  ██████     ██    ██   ██${RESET}"
    echo -e "${VERDE_BRILLANTE}  SYSTEM TOOL KIT-ALL4ME    ${RESET}\n${AZUL_BRILLANTE}  v${V}${RESET}"
    echo -e "${AZUL}  By: ${AUTOR}${RESET}"
    echo -e "${CIAN}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    #OS_ID:-"Desconocido" Forma sencilla de decir: si no tiene valor imprime: "Desconocido"
    echo -e "${AMARILLO}➤ Sistema detectado:${RESET} ${AZUL}${OS_ID:-"Desconocido"}${RESET}"
    echo -e "${AMARILLO}➤ Package de paquetes:${RESET} ${AZUL}${Package:-"Desconocido"}${RESET}"
    echo -e "${AMARILLO}➤ Versión:${RESET} ${AZUL}${VERSION:-"Desconocido"}${RESET}"
    echo -e "${AMARILLO}➤ Web oficial:${RESET} ${AZUL}${URL:-"Desconocido"}${RESET}"
    echo -e "${CIAN}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
}
#Lógica fzf de estilo
fzf_estilo() {
    local prompt_text="$1"
    local header_text="$2"
    fzf --ansi \
        --height=15 \
        --reverse \
        --border=rounded \
        --prompt="➤ $prompt_text: " \
        --header="$header_text" \
        --color="border:#00ffff,pointer:#92ff92,header:#5fb2ff"
}

# LÓGICA FZF menú principal
fzf_menu_principal() {
    fzf --ansi \
        --height=15 \
        --layout=reverse \
        --border=rounded \
        --prompt=" Selecione Menú-❯ " \
        --header="--- P A N E L  D E  C O N T R O L ---" \
        --header-lines=1 \
        --color="border:#5fafd7,header:#af87ff,prompt:#5fb2ff,pointer:#afff00" \
        --preview-window="up:25%:border-bottom" \
        --preview="echo -e '
\033[1;36mINFORMACIÓN\033[0m | \033[1;33m Fecha:\033[0m $DATE | \033[1;33m Host:\033[0m $(hostname) | \033[1;33m Kernel:\033[0m $(uname -r | cut -d- -f1)'"
}
#función del menú principal
menu() {
    while true; do
        clear
        mostrar_logo
        
        # El encabezado es la primera línea que fzf ignorará gracias a --header-lines=1
opciones="ICONO | CATEGORÍA       | DESCRIPCIÓN
1. 📊 | MONITORIZACIÓN  | Estado de red y rendimiento
2. 📦 | SOFTWARE        | Gestión de paquetes y actualizaciones
3. ⚙️ | ADMINISTRACIÓN  | Usuarios, servicios y backups
4. 🧹 | MANTENIMIENTO   | Limpieza de sistema y logs
5. ❌ | SALIR           | Control+C"

        # Capturamos la selección
        seleccion=$(echo -e "$opciones" | fzf_menu_principal)

        # Salida si se cancela con ESC o si está vacío
        if [ $? -ne 0 ] || [ -z "$seleccion" ]; then salir; fi

        # Extraemos solo el número antes del punto para el case
        case ${seleccion%%.*} in
            1) # --- SUBMENÚ MONITORIZACIÓN ---
                while true; do
                    clear
                    mostrar_logo
                    accion=$(echo -e "1. Rendimiento del Sistema\n2. Información de Red \n3. ↩ Volver" | fzf_estilo "Seleccione" "MONITORIZACIÓN")
                    if [[ $? -ne 0 || "$accion" == *"Volver"* ]]; then break; fi
                    case ${accion%%.*} in
                        1) monitor_rendimiento ;;
                        2) mostrar_info_red ;;
                    esac
                done
                ;;

            2) # --- SUBMENÚ SOFTWARE ---
                while true; do
                    clear
                    mostrar_logo
                    accion=$(echo -e "1. Actualización del Sistema\n2. Instalar programa\n3. Desinstalar programa\n4. ↩ Volver" | fzf_estilo "Seleccione" "SOFTWARE")
                    if [[ $? -ne 0 || "$accion" == *"Volver"* ]]; then break; fi
                    case ${accion%%.*} in
                        1) Actualizar_sistema ;;
                        2) instalar_programa ;;
                        3) desinstalar_programa ;;
                    esac
                done
                ;;

            3) # --- SUBMENÚ ADMINISTRACIÓN ---
                while true; do
                    clear
                    mostrar_logo
                    accion=$(echo -e "1. Gestión de Usuarios\n2. Gestión de Servicios\n3. Gestión de Backups\n4. ↩ Volver" | fzf_estilo "Seleccione" "ADMINISTRACIÓN")
                    if [[ $? -ne 0 || "$accion" == *"Volver"* ]]; then break; fi
                    case ${accion%%.*} in
                        1) gestionar_usuarios ;;
                        2) gestionar_servicios ;;
                        3) hacer_backup;;  
                        4) restaurar_backup ;;                   
                    esac
                done
                ;;

            4) # --- SUBMENÚ MANTENIMIENTO ---
                while true; do
                    clear
                    mostrar_logo
                    accion=$(echo -e "1. Limpieza de Archivos\n2. Ver Bitácora (Logs)\n3. Limpiar archivos de log\n4. ↩ Volver" | fzf_estilo "Seleccione" "MANTENIMIENTO")
                    if [[ $? -ne 0 || "$accion" == *"Volver"* ]]; then break; fi
                    case ${accion%%.*} in
                        1) super_limpieza ;;
                        2) ver_logs ;;
                        3) rotar_logs ;;
                    esac                   
                done
                ;;

            5) salir ;;
        esac
    done
}

Actualizar_sistema() {
    trap "clear; return" SIGINT
    clear
    mostrar_logo
    pintar $AZUL_BRILLANTE "➤ Iniciando actualización automática del sistema..."
    echo ""
        # 2. Ejecución de comandos según el Package
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
            pintar $ROJO "❌ Error: No se pudo identificar un Package compatible."
            read -p "Presione Enter para volver..."
            return 1
            ;;
    esac

    # 3. Resultado final
    if [ $? -eq 0 ]; then
        echo ""
        pintar $VERDE_BRILLANTE "✔ ¡El sistema se ha actualizado correctamente!"
        registrar_log "$LOG_INFO" "Actualización del sistema completada con éxito ($Package)."
    else
        echo ""
        pintar $ROJO "✘ Hubo un error durante la actualización."
        registrar_log "$LOG_ERR" "Fallo en la actualización del sistema usando $Package."
    fi

    echo ""
    read -p "Presione Enter para volver al menú..."
}

instalar_programa() {
    trap "clear; return" SIGINT
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
    if [[ ! "$programa" =~ ^[a-zA-Z0-9_.-]+$ ]]; then
            pintar $ROJO "⚠️ El nombre contiene caracteres no válidos."
            sleep 2
            return 1
    fi
  
    echo ""
    echo -e "${AMARILLO}➤ Package de paquetes para la instalación:${RESET} ${AZUL}$Package${RESET}"
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
            pintar $ROJO "❌ Error: No se pudo identificar un Package compatible."
            read -p "Presione Enter para volver..."
            return 1
            ;;
    esac

    # 3. Resultado final
    if [ $? -eq 0 ]; then
        pintar $VERDE_BRILLANTE "✔ ¡$programa se ha instalado/actualizado correctamente!"
        registrar_log "$LOG_INFO" "Programa instalado: $programa"
    else
        pintar $ROJO "✘ Hubo un error..."
        registrar_log "$LOG_ERR" "Error al intentar instalar: $programa"
    fi

    echo ""
    read -p "Presione Enter para volver al menú..."
}

desinstalar_programa() {
    trap "clear; return" SIGINT
    clear
    mostrar_logo 
    echo ""
    read -p "Escriba el nombre del programa que desea desinstalar: " programa
    
    if [[ -z "$programa" ]]; then
        pintar $ROJO "⚠️ No escribió ningún nombre."
        sleep 2
        return 1
    fi
    if [[ ! "$programa" =~ ^[a-zA-Z0-9_.-]+$ ]]; then
        pintar $ROJO "⚠️ El nombre contiene caracteres no válidos."
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
            pintar $ROJO "❌ Package no compatible."
            return 1
            ;;
    esac

    if [ $? -eq 0 ]; then
        registrar_log "$LOG_WARN" "Programa eliminado: $programa"
        pintar $VERDE_BRILLANTE "✔ ¡$programa ha sido eliminado correctamente!"
    else
        pintar $ROJO "✘ Error al intentar desinstalar $programa."
    fi
    read -p "Presione Enter para volver..."
}

listar_usuarios() {
    echo ""
    pintar $AZUL_BRILLANTE "--- Usuarios Humanos (UID >= 1000) ---"
    cut -d: -f1,3 /etc/passwd | awk -F: '$2 >= 1000 && $2 < 60000 {print "  • " $1}'
    echo ""
    read -p "Presione Enter para continuar..."
}

pedir_nombre() {
    
    local nombre=""
    while [ -z "$nombre" ]; do
        read -p "Ingrese nombre de usuario: " nombre
        
        if [ -z "$nombre" ]; then
            echo -e "${AMARILLO}⚠️ El nombre no puede estar vacío. Inténtelo de nuevo.${RESET}" >&2
            continue
        fi
        
        
        if [[ ! "$nombre" =~ ^[a-zA-Z0-9_.-]+$ ]]; then
            echo -e "${ROJO}⚠️ El nombre contiene caracteres no válidos.${RESET}" >&2
            sleep 2
            nombre="" # Vaciamos para que el bucle vuelva a pedirlo
        fi
    done
    echo "$nombre"  
}

gestionar_usuarios() {
    trap "clear; return" SIGINT
    while true; do
        
        clear
        mostrar_logo
        # Usamos fzf_estilo 
        local opciones="1. Listar usuarios humanos\n2. Crear usuario\n3. Eliminar usuario\n4. ↩ Volver"
        seleccion_users=$(echo -e "$opciones" | fzf_estilo "Acción" "G E S T I Ó N  DE  U S U A R I O S")
        
       
        if [[ $? -ne 0 || "$seleccion_users" == *"Volver"* ]]; then 
            break 
        fi

        case ${seleccion_users:0:1} in
            1) listar_usuarios ;;
            2) 
                user=$(pedir_nombre)
                if [ -n "$user" ]; then
                    pintar $AMARILLO "➤ Creando usuario $user..."
                    # Lógica según el Package detectado
                    if [[ "$Package" == "apt" ]]; then
                        adduser "$user" && registrar_log "$LOG_INFO" "Usuario creado: $user"
                    else
                        # Para Fedora, Arch, etc., usamos useradd (estándar universal)
                        useradd -m -s /bin/bash "$user"
                        pintar $AMARILLO "Establezca la contraseña para $user:"
                        passwd "$user"
                        registrar_log "$LOG_INFO" "Usuario creado (useradd): $user"
                    fi
                fi
                read -p "Proceso finalizado. Presione Enter para continuar..." ;;
            3) 
                user=$(pedir_nombre)
                if [ -n "$user" ]; then
                    echo ""
                    echo -ne "${ROJO}➤ ¿Está seguro que desea eliminar el usuario $user? ${RESET}"
                    read
                    echo ""
                    pintar $ROJO "➤ Eliminando usuario $user..."
                    if [[ "$Package" == "apt" ]]; then
                        deluser --remove-home "$user" && registrar_log "$LOG_WARN" "Usuario eliminado: $user"
                    else
                        # userdel -r es el equivalente universal
                        userdel -r "$user" && registrar_log "$LOG_WARN" "Usuario eliminado: $user"
                    fi
                fi
                echo ""
                read -p "Proceso finalizado. Presione Enter..." ;;
                      
        esac
    done
}
super_limpieza() {
    echo ""
    pintar $MAGENTA "Iniciando Súper Limpieza..."
    ANTES=$(df / | awk 'NR==2 {print $3}')
    
    case "$Package" in
        apt)
            apt-get install -f -y > /dev/null 2>&1
            apt-get autoremove -y > /dev/null 2>&1
            apt-get autoclean -y > /dev/null 2>&1
            apt-get clean > /dev/null 2>&1
            ;;
        dnf)
            dnf clean all > /dev/null 2>&1
            dnf autoremove -y > /dev/null 2>&1
            ;;
        pacman)
            pacman -Sc --noconfirm > /dev/null 2>&1
            ;;
        zypper)
            zypper clean --all > /dev/null 2>&1
            zypper clean --packages > /dev/null 2>&1
            ;;
        *)
            pintar $ROJO "❌ Limpieza automática no soportada para $Package"
            return 1
            ;;
    esac
    
    # Limpieza de papelera (común a todos)
    find /home -maxdepth 2 -path "*/.local/share/Trash/*" -delete 2>/dev/null
    
    DESPUES=$(df / | awk 'NR==2 {print $3}')
    
    if [ "$ANTES" -gt "$DESPUES" ] 2>/dev/null; then
        LIBERADO=$(( (ANTES - DESPUES) / 1024 ))
        pintar $VERDE_BRILLANTE "¡Sistema limpio! ✨"
        [[ $LIBERADO -gt 0 ]] && echo "Se han liberado aprox. ${LIBERADO} MB."
        registrar_log "$LOG_INFO" "LIMPIEZA: Se liberaron aprox. ${LIBERADO:-0} MB"
    else
        pintar $VERDE "Limpieza completada (sin cambios significativos de espacio)."
    fi
    read -p "Pulse Enter..."
}
mostrar_logo_monitor() {
    # Definimos el logo con limpieza de línea \e[K al principio de cada fila
    echo -e "\e[K${CIAN}  _____ _______ _  __  __  __                _ _             "
    echo -e "\e[K / ____|__   __| |/ / |  \/  |              (_) |            "
    echo -e "\e[K| (___    | |  | ' /  | \  / | ___  _ __  _ _| |_ ___  _ __  "
    echo -e "\e[K \___ \   | |  |  <   | |\/| |/ _ \| '_ \| | | __/ _ \| '__| "
    echo -e "\e[K ____) |  | |  | . \  | |  | | (_) | | | | | | |_ (_) | |    "
    echo -e "\e[K|_____/   |_|  |_|\_\ |_|  |_|\___/|_| |_|_|_|\__\___/|_|    ${RESET}"
    echo -e "\e[K${AZUL}------------------------------------------------------${RESET}"
}
monitor_rendimiento() {
    # Verificar si tput está disponible antes de usarlo
    if ! command -v tput &> /dev/null; then
        pintar $AMARILLO "⚠️ tput no encontrado. La interfaz podría verse desordenada."
    else
        tput civis
    fi

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

    # Configuración inicial
    trap "tput cnorm; clear; return" SIGINT
    tput civis 
    clear # Limpia la pantalla solo UNA vez al empezar

    while true; do
        # Retornar cursor a la esquina superior izquierda sin borrar
        echo -ne "\e[H"
        
        mostrar_logo_monitor
       
        echo -e "\e[K${NEGRITA}-------- MONITOR DE SISTEMA (Ctrl+C para volver) --------${RESET}"
        echo -e "\e[K${CIAN}Tasa Auto-refresco: 5s | Pulsa ENTER para actualizar antes${RESET}\n"

        # --- OBTENCIÓN DE DATOS ---
        CPU_MODEL=$(grep -m1 "model name" /proc/cpuinfo | cut -d: -f2 | sed -e 's/^[ \t]*//' -e 's/(R)//g' -e 's/(TM)//g' -e 's/  */ /g')
        CPU_CORES=$(nproc)
        CPU_MHZ=$(grep -m1 "cpu MHz" /proc/cpuinfo | awk '{print int($4)}')
        CPU_GHZ=$(awk "BEGIN {printf \"%.2f\", $CPU_MHZ/1000}")

        # Cálculo CPU
        CPU_STATS=$(grep 'cpu ' /proc/stat)
        IDLE_1=$(echo $CPU_STATS | awk '{print $5}')
        TOTAL_1=$(echo $CPU_STATS | awk '{print $2+$3+$4+$5+$6+$7+$8}')
        sleep 0.1
        CPU_STATS=$(grep 'cpu ' /proc/stat)
        IDLE_2=$(echo $CPU_STATS | awk '{print $5}')
        TOTAL_2=$(echo $CPU_STATS | awk '{print $2+$3+$4+$5+$6+$7+$8}')
        CPU_PERC=$((100 * ((TOTAL_2-TOTAL_1)-(IDLE_2-IDLE_1)) / (TOTAL_2-TOTAL_1) ))
        CPU_DETAIL=$(top -bn1 | grep "Cpu(s)" | awk '{printf "User: %.1f%% | System: %.1f%%", $2, $4}')

        # RAM y DISCO
        RAM_INFO=$(free -m | grep "Mem:")
        RAM_TOTAL_MB=$(echo $RAM_INFO | awk '{print $2}')
        RAM_USED_MB=$(echo $RAM_INFO | awk '{print $3}')
        RAM_DISP_MB=$(echo $RAM_INFO | awk '{print $7}')
        RAM_PERC=$(( RAM_USED_MB * 100 / RAM_TOTAL_MB ))
        G_TOTAL=$(awk "BEGIN {printf \"%.1f\", $RAM_TOTAL_MB/1024}"); G_USED=$(awk "BEGIN {printf \"%.1f\", $RAM_USED_MB/1024}"); G_DISP=$(awk "BEGIN {printf \"%.1f\", $RAM_DISP_MB/1024}")

        DISCO_DATA=$(df -h / | awk 'NR==2 {print $2, $3, $4, $5}')
        D_TOTAL=$(echo $DISCO_DATA | awk '{print $1}'); D_USADO=$(echo $DISCO_DATA | awk '{print $2}'); D_LIBRE=$(echo $DISCO_DATA | awk '{print $3}'); D_PERC=$(echo $DISCO_DATA | awk '{print $4}' | tr -d '%')

        # --- RENDERIZADO 
        echo -e "\e[K${AMARILLO}PROCESADOR:${RESET} ${BLANCO}${CPU_MODEL}${RESET}"
        echo -e "\e[K${AMARILLO}NÚCLEOS:${RESET}    ${BLANCO}${CPU_CORES} hilos${RESET} | ${AMARILLO}FREQ:${RESET} ${BLANCO}${CPU_GHZ} GHz${RESET}\n"

        echo -ne "\e[K${VERDE}CARGA CPU: ${RESET}"; dibujar_barra $CPU_PERC; echo -e " -> $(interpretar $CPU_PERC 'cpu')"
        echo -ne "\e[K${AZUL}USO RAM:   ${RESET}"; dibujar_barra $RAM_PERC; echo -e " -> $(interpretar $RAM_PERC 'ram')"
        echo -ne "\e[K${CIAN}USO DISCO: ${RESET}"; dibujar_barra $D_PERC; echo -e " -> $(interpretar $D_PERC 'disco')"

        echo -e "\e[K\n${CIAN}------------- INFO MÁS DETALLADA -----------${RESET}"
        echo -e "\e[K   ${BLANCO}CPU:${RESET}   ${CPU_DETAIL} | ${BLANCO}Hilos:${RESET} ${CPU_CORES}"
        echo -e "\e[K   ${BLANCO}RAM:${RESET}   ${G_USED}GB usados / ${G_TOTAL}GB total (Disp: ${G_DISP}GB)"
        echo -e "\e[K   ${BLANCO}DISCO:${RESET} ${D_USADO} usados / ${D_TOTAL} total (Libre: ${D_LIBRE})"
        echo -e "\e[K${CIAN}--------------------------------------------${RESET}"
        echo -e "\e[K\n${BLANCO}Presione Ctrl+C para volver al menú principal${RESET}"
        echo -ne "\e[K" # Línea extra de seguridad
        # Rellenar con líneas vacías limpias para evitar que texto viejo suba
        for i in {1..2}; do echo -e "\e[K"; done
        read -t 5 -n 1 -s key
    done
}
#Gestión de servicios   
gestionar_servicios() {
    trap "clear; return" SIGINT
    while true; do
        
        clear
        mostrar_logo
        pintar $MAGENTA "--- PANEL DE CONTROL DE SERVICIOS (Systemd) ---"
        echo -e "${BLANCO}Seleccione un estado para filtrar servicios:${RESET}"
        
        # Menú de filtro usando fzf
        local filtro=$(echo -e "1. Ver servicios FALLIDOS (Error)\n2. Ver todos los servicios ACTIVOS\n3. Buscar un servicio específico\n4. ↩ Volver" | fzf_estilo "Filtrar por" "F I L T R O  D E  S E R V I C I O S")
        
        case ${filtro:0:1} in
            1) listado=$(systemctl list-units --state=failed --no-legend --plain | awk '{print $1}') ;;
            2) listado=$(systemctl list-units --type=service --state=running --no-legend --plain | awk '{print $1}') ;;
            3) listado=$(systemctl list-unit-files --type=service --no-legend | awk '{print $1}') ;;
            *) break ;;
        esac

        if [ -z "$listado" ]; then
            pintar $VERDE "✔ No se encontraron servicios en este estado."
            read -p "Presione Enter..."
            continue
        fi

        # Selección del servicio específico para operar
        local svc_seleccionado=$(echo "$listado" | fzf_estilo "Servicio" "S E L E C C I O N E  S E R V I C I O")

        if [ -n "$svc_seleccionado" ]; then
            menu_operaciones_servicio "$svc_seleccionado"
        fi
    done
}

menu_operaciones_servicio() {
    local svc=$1
    trap "clear; return" SIGINT
    while true; do
        
        clear
        pintar $CIAN "⚙️ Gestionando: $svc"
        echo "------------------------------------------------"
        # Mostramos el estado actual muy brevemente para tener contexto
        systemctl status "$svc" --no-pager | grep -E "Active:|Main PID:|Tasks:"
        echo "------------------------------------------------"
        
        local accion=$(echo -e "1. Reiniciar (Restart)\n2. Detener (Stop)\n3. Ver Logs (Journalctl -u)\n4. Ver Estado Completo (Status)\n5. Habilitar/Deshabilitar (Enable/Disable)\n6. Volver" | fzf_estilo "Acción" "O P E R A C I O N E S :  $svc")

        case ${accion:0:1} in
            1) 
                echo -ne "${AMARILLO}🔄 Reiniciando $svc...${RESET}"
                if systemctl restart "$svc"; then
                    registrar_log "$LOG_WARN" "Servicio REINICIADO: $svc"
                    echo -e " ${VERDE_BRILLANTE}[OK]${RESET}"
                    sleep 1.5 # Tiempo para que el usuario vea el [OK]
                else
                    pintar $ROJO " [ERROR]"
                    registrar_log "$LOG_ERR" "Fallo al reiniciar: $svc"
                    sleep 2
                fi
                ;;
            2) 
                echo -ne "${ROJO}🛑 Deteniendo $svc...${RESET}"
                if systemctl stop "$svc"; then
                    registrar_log "$LOG_WARN" "Servicio DETENIDO: $svc"
                    echo -e " ${VERDE_BRILLANTE}[OK]${RESET}"
                    sleep 1.5
                else
                    pintar $ROJO " [ERROR]"
                    sleep 2
                fi
                ;;
            3) 
                pintar $AZUL "📄 Mostrando últimas 50 líneas de log (Journal)..."
                echo "------------------------------------------------"
                journalctl -u "$svc" -n 50 --no-pager
                echo "------------------------------------------------"
                read -p "Presione Enter para volver a la gestión de $svc..."
                ;;
            4) 
                pintar $AZUL "📋 Estado completo de $svc:"
                echo "------------------------------------------------"
                # Forzamos --no-pager para que no se bloquee y no necesite Ctrl+C
                systemctl status "$svc" --no-pager
                echo "------------------------------------------------"
                read -p "Presione Enter para volver a la gestión de $svc..."
                ;;
            5)
                if systemctl is-enabled "$svc" &>/dev/null; then
                    systemctl disable "$svc" && pintar $ROJO "✔ Deshabilitado en el arranque."
                else
                    systemctl enable "$svc" && pintar $VERDE "✔ Habilitado en el arranque."
                fi
                sleep 2
                ;;
            *) break ;;
        esac
    done
}
#Info de REd
mostrar_info_red() {
    trap "clear; return" SIGINT
    clear
    mostrar_logo
    pintar $CIAN "--- INFORMACIÓN DE RED ---"

    # 1. Obtener IP Local (Método universal usando la ruta por defecto)
    # Buscamos la interfaz que tiene la ruta de salida (default) y extraemos su IP
    IP_LOCAL=$(ip route get 1.1.1.1 2>/dev/null | grep -oP 'src \K\S+')
    
    # Si el método anterior falla, probamos filtrando loopback
    if [ -z "$IP_LOCAL" ]; then
        IP_LOCAL=$(hostname -I | awk '{print $1}')
    fi

    # 2. Obtener IP Pública (Con manejo de errores y alternativa)
    echo -ne "${AMARILLO}Obteniendo IP pública (espere un momento...)${RESET}"
    
    # --- NUEVA MEJORA DE DIAGNÓSTICO ---
    # Comprobamos primero si el sistema puede resolver nombres (DNS)
    if ! host ifconfig.me &>/dev/null; then
        IP_PUBLICA="Error DNS (Revisa /etc/resolv.conf)"
    else
        # Si el DNS funciona, procedemos con curl o wget
        if command -v curl &>/dev/null; then
            # Usamos -L por si hay redirecciones y un timeout de conexión corto
            IP_PUBLICA=$(curl -sL --connect-timeout 3 --max-time 5 ifconfig.me || echo "Error de conexión")
        elif command -v wget &>/dev/null; then
            IP_PUBLICA=$(wget -qO- --timeout=3 --tries=1 ifconfig.me || echo "Error de conexión")
        else
            IP_PUBLICA="Falta curl/wget para consultar"
        fi
    fi

    # Limpiamos la línea de "Obteniendo..." y mostramos resultados
    echo -e "\r\033[K" 
    echo -e "${AMARILLO}➤ IP Local:${RESET}    ${BLANCO}${IP_LOCAL:-"No detectada"}${RESET}"
    echo -e "${AMARILLO}➤ IP Pública:${RESET}  ${BLANCO}${IP_PUBLICA}${RESET}"
    echo -e "${AMARILLO}➤ Interfaz:${RESET}    ${BLANCO}$(ip route | grep default | awk '{print $5}')${RESET}"
    echo -e "${AMARILLO}➤ Puerta Enlace:${RESET} ${BLANCO}$(ip route | grep default | awk '{print $3}')${RESET}"
    echo ""
    
    pintar $AZUL "Estado de interfaces:"
    ip -brief addr show | grep -v "127.0.0.1"
    
    echo ""
    registrar_log "$LOG_INFO" "Consulta de red realizada (Local: $IP_LOCAL | Pública: $IP_PUBLICA)"
    read -p "Presione Enter para volver..."
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
#Funciones auxiliares para backups
eliminar_backups() {
    local DESTINO_DEF="/var/backups/stk_backups"
    clear
    mostrar_logo
    pintar $CIAN "--- ELIMINAR COPIAS DE SEGURIDAD ---"

    if [ ! -d "$DESTINO_DEF" ] || [ -z "$(find "$DESTINO_DEF" -name "*.tar.gz")" ]; then
        pintar $ROJO "No hay backups para eliminar."
        read -p "Presione Enter..."
        return
    fi

    # Listamos los archivos para que fzf permita seleccionar
    # Usamos find para obtener rutas completas pero mostramos solo el nombre en la lista
    local seleccion=$(find "$DESTINO_DEF" -type f -name "*.tar.gz" | fzf_estilo "Seleccione backup para BORRAR" "B O R R A D O  D E  A R C H I V O S")

    if [ -n "$seleccion" ]; then
        echo -e "\n${ROJO_BRILLANTE}⚠️ ADVERTENCIA: Vas a eliminar permanentemente:${RESET}"
        pintar $BLANCO "$(basename "$seleccion")"
        echo -ne "\n${AMARILLO}¿Estás seguro? (s/N): ${RESET}"
        read -r confirmar

        if [[ "$confirmar" == "s" || "$confirmar" == "S" ]]; then
            if rm "$seleccion"; then
                pintar $VERDE "✔ Archivo eliminado correctamente."
                registrar_log "$LOG_WARN" "Backup eliminado manualmente: $seleccion"
            else
                pintar $ROJO "❌ Error al intentar eliminar el archivo."
            fi
        else
            pintar $AZUL "Operación cancelada."
        fi
        sleep 1.5
    fi
}
ver_backups_existentes() {
    local DESTINO_DEF="/var/backups/stk_backups"
    clear
    mostrar_logo
    pintar $CIAN "--- EXPLORADOR DE COPIAS DE SEGURIDAD ---"
    echo -e "${AMARILLO}Directorio: ${BLANCO}$DESTINO_DEF${RESET}\n"

    if [ ! -d "$DESTINO_DEF" ] || [ -z "$(ls -A "$DESTINO_DEF")" ]; then
        pintar $ROJO "No se encontraron copias de seguridad en la ruta predeterminada."
    else
        # Listado detallado: Tamaño, Fecha de modificación y Nombre
        printf "${AZUL}%-12s %-20s %-s${RESET}\n" "TAMAÑO" "FECHA" "ARCHIVO"
        echo "--------------------------------------------------------------------------"
        find "$DESTINO_DEF" -type f -name "*.tar.gz" -printf "%-12s %TY-%Tm-%Td %TH:%TM:%TS %p\n" | sed "s|$DESTINO_DEF/||g" | sort -r
    fi
    echo ""
    read -p "Presione Enter para volver..."
}
verificar_espacio() {
    local ORIGEN="$1"
    local DESTINO="$2"
    
    # Tamaño estimado del origen en KB
    local TAM_ORIGEN=$(du -s "$ORIGEN" | awk '{print $1}')
    # Espacio disponible en destino en KB
    local ESPACIO_DISP=$(df -Pk "$DESTINO" | tail -1 | awk '{print $4}')
    
    # Margen de seguridad: El backup comprimido suele ser menor, 
    # pero necesitamos espacio para maniobrar.
    if [ "$ESPACIO_DISP" -lt "$TAM_ORIGEN" ]; then
        return 1 # No hay espacio suficiente
    fi
    return 0
}
rotar_backups() {
    local DESTINO="$1"
    local DIAS_RETENCION=15 # Valor para ajustar según preferencia
    
    # Comprobar si hay archivos más antiguos que los días definidos y eliminarlos
    local ELIMINADOS=$(find "$DESTINO" -name "backup_*.tar.gz" -type f -mtime +$DIAS_RETENCION -print -delete)
    
    if [ -n "$ELIMINADOS" ]; then
        local CANTIDAD=$(echo "$ELIMINADOS" | wc -l)
        pintar $AMARILLO "♻️ Se han eliminado $CANTIDAD copias antiguas (más de $DIAS_RETENCION días)."
        registrar_log "$LOG_INFO" "Rotación automática: $CANTIDAD backups antiguos eliminados en $DESTINO"
    fi
}

hacer_backup() {
    trap "clear; return" SIGINT
    local DESTINO_DEF="/var/backups/stk_backups"

    while true; do
        clear
        mostrar_logo
        pintar $CIAN "--- GESTIÓN DE COPIAS DE SEGURIDAD ---"
        
        # Añadimos la opción 6 para eliminar y movemos Volver al 7
        local opciones="1. 📁 Sistema (/etc)\n2. 👤 Usuario Actual\n3. 🌐 Web (/var/www)\n4. ✍️ Ruta Personalizada\n5. 📜 VER BACKUPS REALIZADOS\n6. 🗑️ ELIMINAR BACKUPS\n7. ↩ Volver"
        local seleccion=$(echo -e "$opciones" | fzf_estilo "Seleccione acción" "C O P I A  D E  S E G U R I D A D")

        if [ $? -ne 0 ] || [ -z "$seleccion" ]; then break; fi
        
        # Lógica de saltos según selección
        if [[ "${seleccion:0:1}" == "5" ]]; then ver_backups_existentes; continue; fi
        if [[ "${seleccion:0:1}" == "6" ]]; then eliminar_backups; continue; fi
        if [[ "${seleccion:0:1}" == "7" ]]; then break; fi
        local ORIGEN=""
        local USUARIO_REAL=${SUDO_USER:-$USER}

        case ${seleccion:0:1} in
            1) ORIGEN="/etc" ;;
            2) ORIGEN="/home/$USUARIO_REAL" ;;
            3) ORIGEN="/var/www" ;;
            4) 
                echo -ne "\n${AMARILLO}➤ Ingrese ruta absoluta: ${RESET}"
                read ORIGEN
                ;;
        esac

        # 1. Validación de Origen
        if [ ! -e "$ORIGEN" ]; then
            pintar $ROJO "❌ Error: La ruta '$ORIGEN' no existe."
            sleep 2; continue
        fi

        # 2. Organización: Nombre de subcarpeta específica
        echo -ne "${CIAN}➤ Nombre para la subcarpeta de este backup (Enter para omitir): ${RESET}"
        read SUBDIR
        local RUTA_FINAL="$DESTINO_DEF/${SUBDIR:-"general"}"

        # 3. Creación segura de directorio
        if ! mkdir -p "$RUTA_FINAL" 2>/dev/null; then
            pintar $ROJO "❌ Error crítico: No se puede escribir en $RUTA_FINAL"
            sleep 2; continue
        fi
        chmod 700 "$DESTINO_DEF"

        # 4. Preparación del archivo
        local FECHA=$(date +%Y%m%d_%H%M%S)
        local NOMBRE_ARCH="backup_$(basename "$ORIGEN")_${FECHA}.tar.gz"
        local DESTINO_COMPLETO="$RUTA_FINAL/$NOMBRE_ARCH"

        # 5. Verificación de espacio
        if ! verificar_espacio "$ORIGEN" "$RUTA_FINAL"; then
            pintar $ROJO "❌ Espacio insuficiente en destino."
            read -p "Enter..."; continue
        fi

        # 6. Ejecución con Spinner y Seguridad
        echo -e "\n${AZUL}🔄 Iniciando respaldo...${RESET}"
        
        # --- LANZAR SPINNER ---
        mostrar_spinner & 
        SPINNER_PID=$!

        # --- EJECUTAR TAR ---
        tar -czpf "$DESTINO_COMPLETO" \
            --exclude='*.log' --exclude='*.tmp' --exclude='*/.cache/*' \
            -C "$(dirname "$ORIGEN")" "$(basename "$ORIGEN")" > /tmp/stk_backup_err 2>&1
        TAR_EXIT_CODE=$?

        # --- DETENER SPINNER ---
        kill "$SPINNER_PID" 2>/dev/null
        wait "$SPINNER_PID" 2>/dev/null
        printf "\r\e[K" # Borra la línea del spinner

        if [ $TAR_EXIT_CODE -eq 0 ]; then
            # 7. Integridad y Reporte Final
            chmod 600 "$DESTINO_COMPLETO"
            local SIZE=$(du -h "$DESTINO_COMPLETO" | cut -f1)
            local HASH=$(sha256sum "$DESTINO_COMPLETO" | awk '{print $1}' | cut -c1-16)

            echo -e "${VERDE_BRILLANTE}✅ BACKUP COMPLETADO CON ÉXITO${RESET}"
            echo -e "${BLANCO}------------------------------------------------${RESET}"
            echo -e "${AMARILLO}Archivo:   ${BLANCO}$NOMBRE_ARCH${RESET}"
            echo -e "${AMARILLO}Ruta:      ${BLANCO}$RUTA_FINAL${RESET}"
            echo -e "${AMARILLO}Tamaño:    ${BLANCO}$SIZE${RESET}"
            echo -e "${AMARILLO}SHA256:    ${BLANCO}$HASH... (verificado)${RESET}"
            echo -e "${BLANCO}------------------------------------------------${RESET}"
            
            registrar_log "$LOG_INFO" "Backup exitoso: $NOMBRE_ARCH en $RUTA_FINAL (Hash: $HASH)"
            rotar_backups "$RUTA_FINAL"
        else
            pintar $ROJO "❌ Error durante la compresión:"
            cat /tmp/stk_backup_err
            registrar_log "$LOG_ERR" "Error en tar al respaldar $ORIGEN"
        fi
        
        read -p "Presione Enter para continuar..."
    done
}

# --- EJECUCIÓN ---
rotar_logs
menu
 
