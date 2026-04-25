#!/bin/bash

# --- INFORMACIÓN DEL PROYECTO ---
V="3.5"
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

# --- COMPROBACIÓN DE SUDO ---
# Corregido: Usaba variables RED/NC que no existían
if [ "$EUID" -ne 0 ]; then
    echo -e "${ROJO_BRILLANTE}⚠️ Error: Este script requiere privilegios de root.${RESET}"
    echo -e "${AMARILLO}Prueba con: sudo $0${RESET}"
    exit 1
fi

    # 1. Identificación del Package de paquetes, usamos variable Package vacia
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
install_tools() {
    local tools_to_install=("$@")
    
    echo -e "\n${AZUL}🔄 Actualizando repositorios ($Package)...${RESET}"
    case "$Package" in
        "apt") sudo apt update -y ;;
        "dnf") sudo dnf makecache ;;
        "pacman") sudo pacman -Sy ;;
        "zypper") sudo zypper refresh ;;
    esac

    for tool in "${tools_to_install[@]}"; do
        pkg=$(get_package_name "$tool")

        if [[ "$pkg" == "GEM_REQUIRED" ]]; then
            echo -e "\n${AZUL}💎 Instalando $tool y dependencias de compilación para $Package...${RESET}"
            
            case "$Package" in
                "apt")
                    sudo apt update -y
                    sudo apt install -y ruby-full build-essential zlib1g-dev libcurl4-openssl-dev libcurl4
                    ;;
                "dnf")
                    # Equivalentes exactos para Fedora
                    sudo dnf install -y ruby ruby-devel gcc gcc-c++ make zlib-devel libcurl-devel openssl-devel
                    ;;
                *)
                    echo -e "${ROJO}⚠️ $Package no soportado para dependencias Ruby. Intenta instalarlas manualmente.${RESET}"
                    ;;
            esac
    
            sudo ldconfig 2>/dev/null
            echo -e "${AZUL}⚙️ Instalando gema WPScan...${RESET}"
            sudo gem install wpscan
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
                            sudo apt install -y snapd
                            sudo systemctl enable --now snapd.socket
                            # Enlace simbólico vital en Debian para rutas estándar
                            sudo ln -s /var/lib/snapd/snap /snap 2>/dev/null 
                            ;;
                        "dnf") sudo dnf install -y snapd && sudo systemctl enable --now snapd.socket ;;
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
            sudo snap install "$tool" $classic
            export PATH=$PATH:/var/lib/snapd/snap/bin
            
        else
            echo -e "${AZUL}📦 Instalando paquete: $pkg...${RESET}"
            case "$Package" in
                "apt") sudo apt install -y "$pkg" ;;
                "dnf") sudo dnf install -y "$pkg" ;;
                "pacman") sudo pacman -S --noconfirm "$pkg" ;;
                "zypper") sudo zypper install -y "$pkg" ;;
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
get_package_name() {
    local tool=$1
    case "$tool" in
        "xsltproc") echo "xsltproc" ;;
        "host") [[ "$Package" == "apt" ]] && echo "dnsutils" || echo "bind-utils" ;;
        "feroxbuster") echo "SNAP_REQUIRED" ;;
        "wpscan") echo "GEM_REQUIRED" ;; # Cambiamos Snap por Ruby Gems
        "fzf") echo "fzf" ;; # No forzar SNAP_REQUIRED
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
dependencies=(fzf xsltproc host)

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
            exit 1
        fi
        
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
    echo -e "${AMARILLO}➤ Package de paquetes:${RESET} ${AZUL}${Package:-"Desconocido"}${RESET}"
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
            6) monitor_rendimiento ;;
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
            pintar $ROJO "❌ Package no compatible."
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

listar_usuarios() {
    echo ""
    pintar $AZUL_BRILLANTE "--- Usuarios Humanos (UID >= 1000) ---"
    cut -d: -f1,3 /etc/passwd | awk -F: '$2 >= 1000 {print "  • " $1}'
    echo ""
    read -p "Presione Enter para continuar..."
}

pedir_nombre() {
    local nombre=""
    while [ -z "$nombre" ]; do
        read -p "Ingrese nombre de usuario: " nombre
        if [ -z "$nombre" ]; then
                # Usar >&2 para enviar el aviso a stderr y no contaminar la salida
                echo -e "${AMARILLO}⚠️ El nombre no puede estar vacío. Inténtelo de nuevo.${RESET}" >&2
        fi
    done
    echo "$nombre"  # ← Este echo SÍ es necesario
}

gestionar_usuarios() {
    
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
                    # Lógica según el Package detectado
                    if [[ "$Package" == "apt" ]]; then
                        sudo adduser "$user"
                    else
                        # Para Fedora, Arch, etc., usamos useradd (estándar universal)
                        sudo useradd -m -s /bin/bash "$user"
                        pintar $AMARILLO "Establezca la contraseña para $user:"
                        sudo passwd "$user"
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
                        sudo deluser --remove-home "$user"
                    else
                        # userdel -r es el equivalente universal
                        sudo userdel -r "$user"
                    fi
                fi
                echo ""
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
        CPU_DETAIL=$(top -bn1 | grep "Cpu(s)" | awk '{printf "Usuario: %.1f%% | System: %.1f%%", $2, $4}')

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

mostrar_spinner() {
    local caracteres="/-\|"
    while true; do
        for (( i=0; i<${#caracteres}; i++ )); do
            printf "\r${AZUL_BRILLANTE}[%c]${RESET} Procesando..." "${caracteres:$i:1}"
            sleep 0.1
        done
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
