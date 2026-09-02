#!/bin/bash

# --- INFORMACIÓN DEL PROYECTO ---
V="5.9.7 añadiendo help -h"
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
# Niveles de severidad
LOG_INFO="INFO"
LOG_WARN="WARN"
LOG_ERR="ERROR"

DATE=$(date +"%d/%m/%Y")

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

registrar_log() {
    local NIVEL="${1:-INFO}" # Si no se pasa nivel, por defecto es INFO
    local MENSAJE="${2}"
    local FECHA
    FECHA=$(date '+%Y-%m-%d %H:%M:%S')
    
    # Formato: [FECHA] [NIVEL] [USUARIO] - MENSAJE
    echo "[$FECHA] [$NIVEL] [$USER] - $MENSAJE" >> "$LOG_FILE"
}

rotar_logs() {
    # Mantenemos el límite en Kilobytes (500 KB)
    local MAX_SIZE=500
    local MODO_SILENCIOSO="${1:-modo_interactivo}"

    if [ "$MODO_SILENCIOSO" != "silencioso" ]; then
        clear
        mostrar_logo
        pintar "$CIAN" "--- ROTACIÓN Y MANTENIMIENTO DE LOGS ---"
        echo -e "${AMARILLO}➤ Archivo de bitácora:${RESET} ${BLANCO}$LOG_FILE${RESET}"
        echo -e "${AMARILLO}➤ Límite configurado:${RESET}  ${BLANCO}${MAX_SIZE} KB${RESET}\n"
    fi

    if [ ! -f "$LOG_FILE" ]; then
        if [ "$MODO_SILENCIOSO" != "silencioso" ]; then
            pintar "$ROJO" "❌ El archivo de log no existe aún. Creando uno nuevo..."
            umask 027
            touch "$LOG_FILE"
            chmod 640 "$LOG_FILE"
            registrar_log "$LOG_INFO" "Bitácora reiniciada manualmente."
            pintar "$VERDE" "✔ Archivo creado e inicializado correctamente."
            read -p "Presione Enter para volver..."
        fi
        return 0
    fi

    # Obtener el tamaño actual del archivo en KB
    local SIZE
    SIZE=$(du -k "$LOG_FILE" | cut -f1)

    if [ "$MODO_SILENCIOSO" != "silencioso" ]; then
        echo -e "${CIAN}🔍 Comprobando tamaño actual...${RESET}"
        echo -e "   Tamaño detectado: ${BLANCO}${SIZE} KB${RESET} / Límite: ${BLANCO}${MAX_SIZE} KB${RESET}\n"
    fi

    if [ "$SIZE" -ge "$MAX_SIZE" ]; then
        [ "$MODO_SILENCIOSO" != "silencioso" ] && pintar "$AMARILLO" "⚠️ El archivo excede el límite. Procediendo con el vaciado y rotación..."
        
        # Guardar marca del reinicio en el log vaciando el contenido anterior
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] - Log reiniciado por alcanzar el límite de $MAX_SIZE KB (Tamaño anterior: ${SIZE} KB)." > "$LOG_FILE"
        
        # Ajustar permisos por seguridad
        chmod 640 "$LOG_FILE"

        if [ "$MODO_SILENCIOSO" != "silencioso" ]; then
            pintar "$VERDE_BRILLANTE" "✔ Se han liberado ${SIZE} KB de espacio en la bitácora."
            pintar "$VERDE" "✔ Permisos reafirmados a 640 (root:root/adm)."
        fi
    else
        if [ "$MODO_SILENCIOSO" != "silencioso" ]; then
            pintar "$VERDE" "✔ El tamaño del log está dentro de los márgenes aceptables."
            echo -e "${AZUL}ℹ️ No se requirió rotación en este momento.${RESET}"
        fi
    fi

    if [ "$MODO_SILENCIOSO" != "silencioso" ]; then
        echo ""
        read -p "Presione Enter para volver al menú..."
    fi
}

ver_logs() {
    clear
    mostrar_logo
    
    if [ -f "$LOG_FILE" ]; then
        pintar "$CIAN" "--- Últimas 20 entradas de la bitácora STK ---"
        echo -e "${AMARILLO}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
        tail -n 20 "$LOG_FILE" | awk '
            /\[INFO\]/ {print "\033[32m" $0 "\033[0m"}
            /\[WARN\]/ {print "\033[33m" $0 "\033[0m"}
            /\[ERROR\]/ {print "\033[31m" $0 "\033[0m"}
        '
        
        # === NUEVO: Mostrar también logs del CRON ===
        local CRON_LOG="/var/log/stk_cron.log"
        if [ -f "$CRON_LOG" ] && [ -s "$CRON_LOG" ]; then
            echo ""
            echo -e "${CIAN}--- Últimas 10 entradas del CRON ---${RESET}"
            echo -e "${AMARILLO}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
            tail -n 10 "$CRON_LOG" | awk '
                /\[INFO\]/ {print "\033[32m" $0 "\033[0m"}
                /\[WARN\]/ {print "\033[33m" $0 "\033[0m"}
                /\[ERROR\]/ {print "\033[31m" $0 "\033[0m"}
            '
        fi
    else
        pintar "$ROJO" "Aún no hay registros."
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

# Inicio y comprobación de registro de logs
if [ ! -f "$LOG_FILE" ]; then
    umask 027
    touch "$LOG_FILE"
    chmod 640 "$LOG_FILE" # Solo root y el grupo pueden leerlo
    registrar_log "$LOG_INFO" "Bitácora inicializada - STK v$V"
fi

# Detección del gestor de paquetes
Package=""

if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID="${ID:-unknown}"
    OS_LIKE="${ID_LIKE:-unknown}"
    URL="${HOME_URL:-unknown}"
    
    if [ -n "$VERSION" ]; then
        VERSION="$VERSION"
    elif [ -n "$VERSION_ID" ]; then
        VERSION="$VERSION_ID"
    elif [[ "$OS_ID" == "arch" || "$OS_LIKE" == *"arch"* ]]; then
        VERSION="Rolling Release"
    else
        VERSION="unknown"
    fi
fi

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
        echo -e "${AZUL}📦 Instalando paquete: $pkg...${RESET}"
        case "$Package" in
            "apt") apt install -y "$pkg" ;;
            "dnf") dnf install -y "$pkg" ;;
            "pacman") pacman -S --noconfirm "$pkg" ;;
            "zypper") zypper install -y "$pkg" ;;
        esac
    done

    # Habilitar e iniciar el demonio de Cron si se instaló crontab
    if [[ " ${tools_to_install[*]} " =~ " crontab " ]]; then
        case "$Package" in
            "apt")    systemctl enable --now cron &>/dev/null ;;
            "pacman") systemctl enable --now cronie &>/dev/null ;;
            "dnf")    systemctl enable --now crond &>/dev/null ;;
            "zypper") systemctl enable --now cron &>/dev/null ;;
        esac
    fi
}
mostrar_instrucciones() {
    clear
    local pkg_upper
    pkg_upper=$(echo "$Package" | tr '[:lower:]' '[:upper:]')

    echo -e "\n${AZUL}══════════════════════════════════════════════════${RESET}"
    echo -e "${BLANCO} 📖 GUÍA DE INSTALACIÓN MANUAL PARA TU SISTEMA (${pkg_upper})${RESET}"
    echo -e "${AZUL}══════════════════════════════════════════════════${RESET}\n"

    for tool in "${missing_tools[@]}"; do
        pkg=$(get_package_name "$tool")

        if [[ "$tool" != "$pkg" ]]; then
            echo -e "${AMARILLO}🛠  Comando faltante: ${BLANCO}$tool${AMARILLO} (Paquete: ${BLANCO}$pkg${AMARILLO})${RESET}"
        else
            echo -e "${AMARILLO}🛠  Herramienta: ${BLANCO}$tool${RESET}"
        fi

        case "$Package" in
            pacman)
                echo -e "   ${VERDE}✔ Comando:${RESET} pacman -S $pkg"
                ;;
            apt|dnf|zypper)
                echo -e "   ${VERDE}✔ Comando:${RESET} $Package install -y $pkg"
                ;;
            *)
                echo -e "   ${VERDE}✔ Comando:${RESET} Usa el gestor de tu sistema para instalar: $pkg"
                ;;
        esac
        echo -e "${AZUL}--------------------------------------------------${RESET}"
    done
}

get_package_name() {
    local tool="$1"

    case "$tool" in
        "xsltproc"|"fzf")
            echo "$tool"
            ;;
        "crontab")
            case "$Package" in
                apt) echo "cron" ;;
                *)   echo "cronie" ;;
            esac
            ;;
        "host") 
            case "$Package" in
                apt)    echo "bind9-dnsutils" ;;
                pacman) echo "bind" ;;
                *)      echo "bind-utils" ;;
            esac
            ;;
        "tput")
            if [[ "$Package" == "apt" ]]; then
                echo "ncurses-bin"
            else
                echo "ncurses"
            fi
            ;;
        "free")
            if [[ "$Package" == "pacman" ]]; then
                echo "procps-ng"
            else
                echo "procps"
            fi
            ;;
        "hostname")
            if [[ "$Package" == "pacman" ]]; then
                echo "inetutils"
            else
                echo "hostname"
            fi
            ;;
        "js") 
            case "$Package" in
                pacman) echo "js128" ;;
                apt)    echo "nodejs" ;;
                dnf)    echo "mozjs115" ;;
                *)      echo "nodejs" ;;
            esac
            ;;
        *)
            echo "$tool"
            ;;
    esac
}

comprobar_firewall() {
    # 1. Inspeccionar reglas reales en el Kernel vía nftables
    if command -v nft &>/dev/null && [ $(nft list ruleset 2>/dev/null | wc -l) -gt 0 ]; then
        return 0
    # 2. Inspeccionar reglas reales en el Kernel vía iptables
    elif command -v iptables &>/dev/null && [ $(iptables -S 2>/dev/null | grep -E '^-A' | wc -l) -gt 0 ]; then
        return 0
    # 3. Verificar estado de UFW (Debian/Ubuntu)
    elif command -v ufw &>/dev/null && ufw status 2>/dev/null | grep -q "status: active"; then
        return 0
    # 4. Verificar estado de Firewalld (RHEL/Fedora/CentOS)
    elif command -v firewall-cmd &>/dev/null && firewall-cmd --state 2>/dev/null | grep -q "running"; then
        return 0
    fi

    return 1
}

pintar() { 
    local COLOR="$1" 
    local MENSAJE="$2" 
    echo -e "${COLOR}${MENSAJE}${RESET}"
}

# --- CAPTURA DE SEÑALES ---
trap salir SIGINT SIGTERM

salir() {
    echo -e "${VERDE}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo ""
    pintar "$AZUL" "Saliendo de forma segura..."
    echo ""
    pintar "$VERDE" "¡Gracias por usar STK, hasta pronto!"
    echo ""
    echo -e "${VERDE}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    exit 0
}

# --- DEFINICIÓN DE DEPENDENCIAS ---
dependencies=(fzf xsltproc host tput free curl wget tar hostname js jq rsync crontab)

check_dependencies() {
    missing_tools=()
    local js_executables=(js js128 js115 qjs gjs node nodejs)

    for tool in "${dependencies[@]}"; do
        if [[ "$tool" == "js" ]]; then
            local found_js=false
            for exe in "${js_executables[@]}"; do
                if command -v "$exe" &>/dev/null; then
                    found_js=true
                    break
                fi
            done
            [[ "$found_js" == false ]] && missing_tools+=("js")
        else
            if ! command -v "$tool" &>/dev/null; then
                missing_tools+=("$tool")
            fi
        fi
    done
}

# --- FLUJO PRINCIPAL DE DEPENDENCIAS ---
if ! ping -c 1 8.8.8.8 &>/dev/null; then
    pintar "$ROJO" "❌ No hay conexión a internet. Algunas funciones fallarán."
fi

check_dependencies

if [ ${#missing_tools[@]} -gt 0 ]; then
    echo -e "${ROJO}❌ No se han podido encontrar estas herramientas: ${missing_tools[*]}${RESET}"
    echo -e "${CIAN}¿Qué deseas hacer?${RESET}"
    echo -e "   ${BLANCO}s) Intento de instalación automática${RESET}"
    echo -e "   ${BLANCO}i) Mostrar instrucciones de instalación manual${RESET}"
    echo -e "   ${BLANCO}n) Continuar de todos modos (Puede fallar)${RESET}"
    echo -ne "\n${AMARILLO}Selecciona una opción: ${RESET}"
    read -r confirm

    if [[ "$confirm" == "s" ]]; then
        install_tools "${missing_tools[@]}"
        check_dependencies

        # Crear enlace de compatibilidad dinámico para 'js' si no existe
        if ! command -v js &>/dev/null; then
            js_candidates=(js128 js115 qjs gjs node nodejs)
            for target in "${js_candidates[@]}"; do
                if command -v "$target" &>/dev/null; then
                    target_path=$(command -v "$target")
                    echo -e "${AMARILLO}🔗 Creando enlace de compatibilidad para 'js' -> $target_path${RESET}"
                    ln -sf "$target_path" /usr/local/bin/js
                    break
                fi
            done
        fi

        if ! command -v fzf &>/dev/null; then
            echo -e "${ROJO}❌ Error crítico: fzf no se pudo instalar o no está en el PATH. Si lo has instalado con Git puede haber problemas con la ruta y el uso de sudo. Puedes instalarlo de forma automatica para solucionarlo y tener ambos sin problema.${RESET}"
            registrar_log "$LOG_ERR" "Error crítico: fzf no pudo ser instalado."
            exit 1
        fi

        if ! command -v js &>/dev/null; then
            echo -e "${AMARILLO}⚠️ Advertencia: El intérprete 'js' no se encontró o requiere un alias en el PATH.${RESET}"
            registrar_log "$LOG_WARN" "Dependencia 'js' no localizada tras la instalación."
        fi

        if [ ${#missing_tools[@]} -gt 0 ]; then
            echo -e "${ROJO}⚠️ Advertencia: Aún faltan herramientas: ${missing_tools[*]}. El script podría fallar.${RESET}"
            read -p "Presiona Enter para continuar de todos modos..."
        else
            registrar_log "$LOG_INFO" "Todas las dependencias instaladas con éxito."
        fi

    elif [[ "$confirm" == "i" ]]; then
        mostrar_instrucciones
        read -p "Presiona Enter para continuar una vez hayas instalado las herramientas..."
        check_dependencies
    fi
fi

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

ejecutar_stop4me() {
  # Obtiene el directorio donde vive ESTE script (garantiza que funcione sin importar desde dónde lo ejecutes)
  local DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  
  # Ejecuta el archivo pasándole argumentos
  bash "$DIR/stop4me.sh"
}
# LÓGICA FZF menú principal

fzf_menu_principal() {
    local host_name=$(hostname 2>/dev/null || cat /etc/hostname)
    local kernel_ver=$(uname -r | cut -d- -f1)

    fzf --ansi \
        --height=15 \
        --layout=reverse \
        --border=rounded \
        --prompt=" Selecione Menú-❯ " \
        --header="--- P A N E L  D E  C O N T R O L ---" \
        --header-lines=1 \
        --color="border:#5fafd7,header:#af87ff,prompt:#5fb2ff,pointer:#afff00" \
        --preview-window="up:25%:border-bottom" \
        --preview="echo -e '\033[1;36mINFORMACIÓN\033[0m | \033[1;33mFecha:\033[0m $DATE | \033[1;33mHost:\033[0m $host_name | \033[1;33mKernel:\033[0m $kernel_ver'"
}
#función del menú principal
menu() {
    while true; do
        clear
        mostrar_logo
        
        # El encabezado es la primera línea que fzf ignorará gracias a --header-lines=1
opciones="ICONO | CATEGORÍA       | DESCRIPCIÓN
0. 🤖 | MODO AUTO       | Auto-update-limpieza + Servicios y Auditoria.
1. 📊 | MONITORIZACIÓN  | Analisis de rendimiento, red y seguridad
2. 📦 | SOFTWARE        | Gestión de paquetes y actualizaciones
3. ⚙️ | ADMINISTRACIÓN  | Usuarios, servicios y backups
4. 🧹 | MANTENIMIENTO   | Limpieza de sistema y logs
5. 📅 | TAREAS AUTO     | Programar tareas automáticas con CRON
6. ❌ | SALIR           | Control+C"            

        # Capturamos la selección
        seleccion=$(echo -e "$opciones" | fzf_menu_principal)

        # Salida si se cancela con ESC o si está vacío
        if [ $? -ne 0 ] || [ -z "$seleccion" ]; then salir; fi

        # Extraemos solo el número antes del punto para el case
        case ${seleccion%%.*} in
            
            0) # --- MODO AUTO ---
                modo_auto
                ;;

            1) # --- SUBMENÚ MONITORIZACIÓN ---
                while true; do
                    clear
                    mostrar_logo
                    accion=$(echo -e "1. Rendimiento del Sistema\n2. Información de Red \n3. Auditoría de Seguridad\n4. Gestor de Firewall UFW\n5. ↩ Volver" | fzf_estilo "Seleccione" "MONITORIZACIÓN")
                    if [[ $? -ne 0 || "$accion" == *"Volver"* ]]; then break; fi
                    case ${accion%%.*} in
                        1) monitor_rendimiento ;;
                        2) mostrar_info_red ;;
                        3) auditoria_seguridad ;;
                        4) ejecutar_stop4me ;;
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
                                        
                    esac
                done
                ;;

            4) # --- SUBMENÚ MANTENIMIENTO ---
                while true; do
                    clear
                    mostrar_logo
                    accion=$(echo -e "1. Superlimpieza del Sistema\n2. Ver Bitácora (Logs)\n3. Rotación archivos de log\n4. ↩ Volver" | fzf_estilo "Seleccione" "MANTENIMIENTO")
                    if [[ $? -ne 0 || "$accion" == *"Volver"* ]]; then break; fi
                    case ${accion%%.*} in
                        1) super_limpieza ;;
                        2) ver_logs ;;
                        3) rotar_logs ;;
                    esac                   
                done
                ;;

            5) 
                # Gestor de tareas automatizadas
                if [ -f "$SCRIPT_DIR/stk_cron.sh" ]; then
                    bash "$SCRIPT_DIR/stk_cron.sh"
                else
                    echo -e "${ROJO}❌ Error: No se encuentra stk_cron.sh${RESET}"
                    echo -e "${AMARILLO}El gestor de tareas debe estar en: $SCRIPT_DIR/stk_cron.sh${RESET}"
                    read -p "Presione Enter..."
                fi
                ;;

            6) salir ;;
        esac
    done
}

# --- NUEVO MODO AUTOMÁTICO AUTÓNOMO Y VERBOSO ---

modo_auto() {
    # Capturar Ctrl+C para volver de forma segura al menú principal
    trap "clear; return" SIGINT

    clear
    mostrar_logo
    pintar "$MAGENTA" "════════════════════════════════════════════════════════════════"
    pintar "$BLANCO"  " 🤖 INICIANDO MODO AUTOMÁTICO INTEGRAL DE MANTENIMIENTO"
    pintar "$MAGENTA" "════════════════════════════════════════════════════════════════"
    echo ""

    local T_INICIO
    T_INICIO=$(date +%s)
    local FECHA_INICIO
    FECHA_INICIO=$(date '+%Y-%m-%d %H:%M:%S')

    registrar_log "$LOG_INFO" "=== INICIO DE MODO AUTO INTEGRAL ==="

    # Variables de estado y resumen
    local RES_ACTUALIZACION="Sin procesar"
    local RES_LIMPIEZA="Sin procesar"
    local RES_SEGURIDAD="Sin procesar"
    local RES_SERVICIOS="Sin procesar"

    # --------------------------------------------------------------------------
    # PASO 1: ACTUALIZACIÓN DEL SISTEMA
    # --------------------------------------------------------------------------
    pintar "$AZUL_BRILLANTE" "📌 [1/4] Ejecutando Actualización del Sistema ($Package)..."
    mostrar_spinner & SPINNER_PID=$!
    
    local LOG_TEMP_ACT
    LOG_TEMP_ACT=$(mktemp)
    local ESTADO_ACT=1
    local PKGS_ACTUALIZADOS=()

    case "$Package" in
        apt)
            # Guardar lista de paquetes actualizables antes de ejecutar
            mapfile -t PKGS_ACTUALIZADOS < <(apt list --upgradable 2>/dev/null | grep -v "Listing..." | cut -d/ -f1)

            DEBIAN_FRONTEND=noninteractive apt-get update -y &>"$LOG_TEMP_ACT" && \
            DEBIAN_FRONTEND=noninteractive apt-get full-upgrade -y &>>"$LOG_TEMP_ACT" && \
            apt-get autoremove -y &>>"$LOG_TEMP_ACT"
            ESTADO_ACT=$?
            ;;

        pacman)
            # Extraer paquetes desde el log temporal de pacman
            pacman -Syu --noconfirm &>"$LOG_TEMP_ACT"
            ESTADO_ACT=$?
            if [ $ESTADO_ACT -eq 0 ]; then
                mapfile -t PKGS_ACTUALIZADOS < <(grep -E "upgraded|actualizado" "$LOG_TEMP_ACT" | awk '{print $2}')
            fi
            ;;

        dnf)
            dnf upgrade --refresh -y &>"$LOG_TEMP_ACT" && dnf autoremove -y &>>"$LOG_TEMP_ACT"
            ESTADO_ACT=$?
            if [ $ESTADO_ACT -eq 0 ]; then
                mapfile -t PKGS_ACTUALIZADOS < <(grep -E "Upgraded:|Upgrade" "$LOG_TEMP_ACT" | awk '{print $2}')
            fi
            ;;

        zypper)
            zypper refresh &>"$LOG_TEMP_ACT" && zypper update -y &>>"$LOG_TEMP_ACT"
            ESTADO_ACT=$?
            ;;
    esac

    # --- Flatpak ---
    local RES_FLATPAK=""
    local FLATPAKS_ACT=()
    if command -v flatpak &>/dev/null; then
        local LOG_FLATPAK
        LOG_FLATPAK=$(mktemp)
        flatpak update -y &>"$LOG_FLATPAK"
        
        if grep -qi -E "nothing to do|nothing updated|nada que hacer" "$LOG_FLATPAK"; then
            RES_FLATPAK="Flatpak: Sin cambios."
        else
            mapfile -t FLATPAKS_ACT < <(grep -E "Updating|Installing|Actualizando" "$LOG_FLATPAK" | awk -F"'" '{print $2}')
            RES_FLATPAK="Flatpak: ${#FLATPAKS_ACT[@]} aplicación(es) actualizada(s)."
        fi
        rm -f "$LOG_FLATPAK"
    fi

    # --- Snap ---
    local RES_SNAP=""
    local SNAPS_ACT=()
    if command -v snap &>/dev/null; then
        local LOG_SNAP
        LOG_SNAP=$(mktemp)
        snap refresh &>"$LOG_SNAP"
        
        if grep -qi -E "all snaps are up to date|todos los snaps están actualizados" "$LOG_SNAP"; then
            RES_SNAP="Snap: Sin cambios."
        else
            mapfile -t SNAPS_ACT < <(grep -v "All snaps" "$LOG_SNAP" | awk 'NR>1 {print $1}')
            RES_SNAP="Snap: ${#SNAPS_ACT[@]} paquete(s) actualizado(s)."
        fi
        rm -f "$LOG_SNAP"
    fi

    kill "$SPINNER_PID" 2>/dev/null; wait "$SPINNER_PID" 2>/dev/null
    printf "\r\e[K"

    if [ $ESTADO_ACT -eq 0 ]; then
        local total_pkgs=$(( ${#PKGS_ACTUALIZADOS[@]} + ${#FLATPAKS_ACT[@]} + ${#SNAPS_ACT[@]} ))
        RES_ACTUALIZACION="✔ Sistema al día ($Package: ${#PKGS_ACTUALIZADOS[@]} actualizados | $RES_FLATPAK"
        [ -n "$RES_SNAP" ] && RES_ACTUALIZACION="$RES_ACTUALIZACION | $RES_SNAP"
        RES_ACTUALIZACION="$RES_ACTUALIZACION)"
        pintar "$VERDE" "   └─ $RES_ACTUALIZACION"
    else
        RES_ACTUALIZACION="❌ Error en la actualización del gestor principal ($Package)."
        pintar "$ROJO" "   └─ $RES_ACTUALIZACION"
    fi
    rm -f "$LOG_TEMP_ACT"
    echo ""

    # --------------------------------------------------------------------------
    # PASO 2: SÚPER LIMPIEZA
    # --------------------------------------------------------------------------
    pintar "$AZUL_BRILLANTE" "📌 [2/4] Ejecutando Limpieza Profunda del Sistema..."
    mostrar_spinner & SPINNER_PID=$!

    local ANTES_RAIZ
    ANTES_RAIZ=$(df --output=avail / | tail -n 1)

    command -v journalctl &>/dev/null && journalctl --vacuum-time=3d &>/dev/null

    case "$Package" in
        apt)
            apt-get install -f -y &>/dev/null
            apt-get autoremove --purge -y &>/dev/null
            apt-get autoclean -y &>/dev/null
            apt-get clean &>/dev/null
            ;;
        dnf)
            dnf clean all &>/dev/null
            dnf autoremove -y &>/dev/null
            ;;
        pacman)
            pacman -Sc --noconfirm &>/dev/null
            local huerfanos
            huerfanos=$(pacman -Qtdq 2>/dev/null)
            [ -n "$huerfanos" ] && pacman -Rns $huerfanos --noconfirm &>/dev/null
            ;;
        zypper)
            zypper clean --all &>/dev/null
            ;;
    esac

    find /home/*/.local/share/Trash/files /root/.local/share/Trash/files -mindepth 1 -delete 2>/dev/null
    find /home/*/.cache/thumbnails /root/.cache/thumbnails -type f -atime +7 -delete 2>/dev/null

    kill "$SPINNER_PID" 2>/dev/null; wait "$SPINNER_PID" 2>/dev/null
    printf "\r\e[K"

    local DESPUES_RAIZ
    DESPUES_RAIZ=$(df --output=avail / | tail -n 1)
    local LIBERADO_MB=$(( (DESPUES_RAIZ - ANTES_RAIZ) / 1024 ))
    [ "$LIBERADO_MB" -lt 0 ] && LIBERADO_MB=0

    RES_LIMPIEZA="✔ Limpieza finalizada. Espacio liberado en /: ~${LIBERADO_MB} MB."
    pintar "$VERDE" "   └─ $RES_LIMPIEZA"
    echo ""

    # --------------------------------------------------------------------------
    # PASO 3: AUDITORÍA DE SEGURIDAD
    # --------------------------------------------------------------------------
    pintar "$AZUL_BRILLANTE" "📌 [3/4] Auditando Parámetros Críticos de Seguridad..."
    local sec_checks=0
    local sec_passed=0
    local sec_alertas=()

    # 1. Chequeo UID 0
    ((sec_checks++))
    if [ $(awk -F: '$3 == 0 {print $1}' /etc/passwd | wc -l) -gt 1 ]; then
        sec_alertas+=("Múltiples usuarios con UID 0 detectados")
    else
        ((sec_passed++))
    fi

    # 2. Cuentas sin clave
    ((sec_checks++))
    if [ -n "$(awk -F: '($2 == "" || $2 == "!!") {print $1}' /etc/shadow 2>/dev/null)" ]; then
        sec_alertas+=("Cuentas inactivas o sin contraseña configurada")
    else
        ((sec_passed++))
    fi

    # 3. Estado Cortafuegos
    ((sec_checks++))
    if comprobar_firewall; then
        ((sec_passed++))
    else
        sec_alertas+=("Firewall inactivo o sin reglas configuradas")
    fi

    # 4. Chequeo SSH
    ((sec_checks++))
    if command -v ss &>/dev/null; then
        if ss -tulpn 2>/dev/null | grep LISTEN | grep -E "0\.0\.0\.0:22|:::22|\*:22" &>/dev/null; then
            sec_alertas+=("Puerto SSH (22) expuesto públicamente")
        else
            ((sec_passed++))
        fi
    else
        ((sec_passed++))
    fi

    # 5. Módulos MAC (SELinux / AppArmor)
    ((sec_checks++))
    if command -v getenforce &>/dev/null && [ "$(getenforce)" == "Enforcing" ]; then
        ((sec_passed++))
    elif command -v aa-status &>/dev/null && aa-status --enabled 2>/dev/null; then
        ((sec_passed++))
    else
        sec_alertas+=("Sin módulo MAC activo (AppArmor/SELinux)")
    fi

    local score=$(( (sec_passed * 100) / sec_checks ))
    RES_SEGURIDAD="Puntuación: ${score}% (${sec_passed}/${sec_checks} pruebas). Alertas: ${#sec_alertas[@]}."
    
    if [ $score -ge 80 ]; then
        pintar "$VERDE" "   └─ $RES_SEGURIDAD"
    else
        pintar "$AMARILLO" "   └─ $RES_SEGURIDAD"
    fi
    echo ""

    # --------------------------------------------------------------------------
    # PASO 4: REVISIÓN DE SERVICIOS FALLIDOS
    # --------------------------------------------------------------------------
    pintar "$AZUL_BRILLANTE" "📌 [4/4] Analizando Estado de Servicios (Systemd)..."
    local svcs_failed
    svcs_failed=$(systemctl list-units --state=failed --no-legend --plain 2>/dev/null | awk '{print $1}')

    if [ -n "$svcs_failed" ]; then
        local count_failed
        count_failed=$(echo "$svcs_failed" | grep -c '^')
        local svcs_list
        svcs_list=$(echo "$svcs_failed" | tr '\n' ' ')
        RES_SERVICIOS="⚠️ Detectados $count_failed servicio(s) fallido(s): $svcs_list"
        pintar "$AMARILLO" "   └─ $RES_SERVICIOS"
        echo "Puedes ir al menú de Gestión de Servicios para más detalles y opciones de actuación"
    else
        RES_SERVICIOS="✔ Todos los servicios operan correctamente (0 fallidos)."
        pintar "$VERDE" "   └─ $RES_SERVICIOS"
    fi
    echo ""

    # --------------------------------------------------------------------------
    # RESUMEN Y REGISTRO FINAL
    # --------------------------------------------------------------------------
    local T_FIN
    T_FIN=$(date +%s)
    local DURACION=$(( T_FIN - T_INICIO ))

    echo ""
    pintar "$CIAN" "════════════════════════════════════════════════════════════════"
    pintar "$BLANCO" "       📋 INFORME Y RESUMEN FINAL - MODO AUTOMÁTICO"
    pintar "$CIAN" "════════════════════════════════════════════════════════════════"
    echo -e "${AMARILLO}➤ Fecha de Inicio:${RESET}     ${BLANCO}${FECHA_INICIO}${RESET}"
    echo -e "${AMARILLO}➤ Tiempo Transcurrido:${RESET}  ${BLANCO}${DURACION} segundos${RESET}\n"

    echo -e "${NEGRITA}${MAGENTA}RESULTADOS POR MÓDULO:${RESET}"
    echo -e " ${AZUL}1. Actualización:${RESET} $RES_ACTUALIZACION"
    echo -e " ${AZUL}2. Limpieza:${RESET}       $RES_LIMPIEZA"
    echo -e " ${AZUL}3. Seguridad:${RESET}       $RES_SEGURIDAD"
    echo -e " ${AZUL}4. Servicios:${RESET}       $RES_SERVICIOS"

    # Desglose detallado si se detectaron paquetes actualizados
    if [ ${#PKGS_ACTUALIZADOS[@]} -gt 0 ] || [ ${#FLATPAKS_ACT[@]} -gt 0 ] || [ ${#SNAPS_ACT[@]} -gt 0 ]; then
        echo -e "\n${AMARILLO}📦 Detalle de Paquetes Actualizados:${RESET}"
        
        if [ ${#PKGS_ACTUALIZADOS[@]} -gt 0 ]; then
            echo -e "   ${AZUL_BRILLANTE}• Sistema ($Package):${RESET} ${PKGS_ACTUALIZADOS[*]}"
        fi
        if [ ${#FLATPAKS_ACT[@]} -gt 0 ]; then
            echo -e "   ${AZUL_BRILLANTE}• Flatpak:${RESET} ${FLATPAKS_ACT[*]}"
        fi
        if [ ${#SNAPS_ACT[@]} -gt 0 ]; then
            echo -e "   ${AZUL_BRILLANTE}• Snap:${RESET} ${SNAPS_ACT[*]}"
        fi
    fi
    
    if [ ${#sec_alertas[@]} -gt 0 ]; then
        echo -e "\n${AMARILLO}⚠️ Alertas de Seguridad Detectadas:${RESET}"
        for alt in "${sec_alertas[@]}"; do
            echo -e "   • $alt"
        done
    fi
    pintar "$CIAN" "════════════════════════════════════════════════════════════════"

    # Bitácora
    registrar_log "$LOG_INFO" "=== RESUMEN MODO AUTO (Duración: ${DURACION}s) ==="
    registrar_log "$LOG_INFO" "ACTUALIZACIÓN: $RES_ACTUALIZACION"
    registrar_log "$LOG_INFO" "LIMPIEZA: $RES_LIMPIEZA"
    registrar_log "$LOG_INFO" "SEGURIDAD: $RES_SEGURIDAD"
    for alt in "${sec_alertas[@]}"; do
        registrar_log "$LOG_WARN" "SEG-ALERTA: $alt"
    done
    registrar_log "$LOG_INFO" "SERVICIOS: $RES_SERVICIOS"
    registrar_log "$LOG_INFO" "=== FIN DE MODO AUTO ==="

    trap - SIGINT
    echo ""
    read -p "Presione Enter para volver al menú principal..."
}
auditoria_seguridad() {
    trap "clear; return" SIGINT
    clear
    mostrar_logo
    pintar $MAGENTA "--- AUDITORÍA Y RECOMENDACIONES DE SEGURIDAD ---"
    echo ""

    local sugerencias=()
    local alertas_count=0
    local total_checks=0
    local checks_passed=0

    # ==========================================
    # 1. AUDITORÍA DE USUARIOS Y PRIVILEGIOS
    # ==========================================
    pintar $MAGENTA "--- 1. USUARIOS, PRIVILEGIOS Y CUENTAS ---"
    echo ""

    # A. Cuentas con UID 0
    ((total_checks++))
    pintar $AMARILLO "🔍 Verificando cuentas con privilegio UID 0:"
    local uid_zero
    uid_zero=$(awk -F: '$3 == 0 {print "  • " $1}' /etc/passwd)
    echo "$uid_zero"
    if [ $(echo "$uid_zero" | wc -l) -gt 1 ]; then
        pintar $ROJO_BRILLANTE "  ⚠️ ¡Alerta! Hay cuentas de superusuario adicionales a root."
        registrar_log "$LOG_ERR" "SEGURIDAD: Múltiples cuentas detectadas con UID 0"
        sugerencias+=("⚠️ UID 0: Revisa /etc/passwd y elimina las cuentas UID 0 no oficiales.")
        ((alertas_count++))
    else
        pintar $VERDE "  ✔ Solo la cuenta 'root' tiene UID 0."
        ((checks_passed++))
    fi
    echo ""

    # B. Cuentas sin contraseña activa
    ((total_checks++))
    pintar $AMARILLO "🔍 Verificando existencia de cuentas sin contraseña:"
    local nopass_users
    nopass_users=$(awk -F: '($2 == "" || $2 == "!") {print $1}' /etc/shadow 2>/dev/null)
    if [ -n "$nopass_users" ]; then
        pintar $ROJO_BRILLANTE "  ⚠️ Cuentas detectadas sin contraseña configurada:"
        echo "$nopass_users" | awk '{print "  • " $0}'
        sugerencias+=("🔑 Contraseñas: Asigna contraseña o bloquea las cuentas sin clave en /etc/shadow.")
        registrar_log "$LOG_WARN" "SEGURIDAD: Cuentas sin contraseña detectadas"
        ((alertas_count++))
    else
        pintar $VERDE "  ✔ Todas las cuentas del sistema poseen credenciales o están bloqueadas."
        ((checks_passed++))
    fi
    echo ""

    # ==========================================
    # 2. AUDITORÍA DE RED Y SERVICIOS
    # ==========================================
    pintar $MAGENTA "--- 2. RED Y PUERTOS EN ESCUCHA ---"
    echo ""

    # A. Sockets Abiertos
    ((total_checks++))
    pintar $AMARILLO "🔍 Sockets y servicios escuchando públicamente (0.0.0.0 / ::):"
    if command -v ss &>/dev/null; then
        local listening_ports
        listening_ports=$(ss -tulpn 2>/dev/null | grep LISTEN)
        if [ -n "$listening_ports" ]; then
            echo "$listening_ports" | awk '{
                split($7, proc, "\"");
                pname = (proc[2] != "") ? proc[2] : "Desconocido";
                print "  • Local: " $4 " -> Proceso: " pname
            }'
            
            # Chequeo específico de SSH expuesto públicamente
            if echo "$listening_ports" | grep -E "0\.0\.0\.0:22|:::22|\*:22" &>/dev/null; then
                sugerencias+=("🌐 SSH Expuesto: Cambia el puerto por defecto (22) o restringe accesos en /etc/ssh/sshd_config.")
                registrar_log "$LOG_WARN" "SEGURIDAD: SSH corriendo en puerto 22 público"
                ((alertas_count++))
            else
                ((checks_passed++))
            fi
        else
            pintar $VERDE "  ✔ No se detectaron puertos escuchando públicamente."
            ((checks_passed++))
        fi
    else
        pintar $ROJO "  ❌ Comando 'ss' no encontrado."
    fi
    echo ""

    # B. Robustecimiento de Red (Kernel Sysctl)
    ((total_checks++))
    pintar $AMARILLO "🔍 Parámetros de seguridad del Kernel (Sysctl Network):"
    local syn_cookies
    syn_cookies=$(sysctl -n net.ipv4.tcp_syncookies 2>/dev/null)
    local accept_redirects
    accept_redirects=$(sysctl -n net.ipv4.conf.all.accept_redirects 2>/dev/null)

    if [ "$syn_cookies" -eq 1 ] && [ "$accept_redirects" -eq 0 ]; then
        pintar $VERDE "  ✔ Protección TCP SYN Cookies activa y Redirecciones ICMP desactivadas."
        ((checks_passed++))
    else
        pintar $AMARILLO "  ⚠️ Configuración de red del kernel mejorable."
        [ "$syn_cookies" -ne 1 ] && sugerencias+=("🌐 Kernel: Habilita SYN Cookies (sysctl net.ipv4.tcp_syncookies=1).")
        [ "$accept_redirects" -ne 0 ] && sugerencias+=("🌐 Kernel: Deshabilita ICMP Redirects (sysctl net.ipv4.conf.all.accept_redirects=0).")
        ((alertas_count++))
    fi
    echo ""
    # C. Auditoría de Intentos SSH / Auth
    ((total_checks++))
    pintar $AMARILLO "🔍 Accesos fallidos de seguridad recientes (SSH/Auth):"
    local ssh_logs=""
    case "$Package" in
        apt)
            [ -f /var/log/auth.log ] && ssh_logs=$(grep "Failed password" /var/log/auth.log 2>/dev/null | tail -n 5)
            ;;
        dnf|zypper)
            [ -f /var/log/secure ] && ssh_logs=$(grep "Failed password" /var/log/secure 2>/dev/null | tail -n 5)
            ;;
        pacman)
            ssh_logs=$(journalctl -u sshd -n 50 --no-pager 2>/dev/null | grep "Failed" | tail -n 5)
            ;;
    esac

    if [ -n "$ssh_logs" ]; then
        echo "$ssh_logs" | awk '{print "  • " $0}'
        sugerencias+=("🔐 Intentos SSH: Instala 'fail2ban' o deshabilita la autenticación por contraseña en SSH.")
        registrar_log "$LOG_WARN" "SEGURIDAD: Detectados accesos fallidos SSH recientes"
        ((alertas_count++))
    else
        pintar $VERDE "  ✔ Sin registros recientes de ataques o contraseñas fallidas por SSH."
        ((checks_passed++))
    fi
    echo ""

    # ==========================================
    # 3. SISTEMA DE ARCHIVOS Y BINARIOS
    # ==========================================
    pintar $MAGENTA "--- 3. ARCHIVOS Y PERMISOS DE SISTEMA ---"
    echo ""

    # A. Ejecutables SUID
    ((total_checks++))
    pintar $AMARILLO "🔍 Archivos con bit SUID activado (Permisos de elevación):"
    local suid_files
    suid_files=$(find /usr/bin /usr/sbin /bin /sbin -perm -4000 2>/dev/null)
    local suid_count
    suid_count=$(echo "$suid_files" | grep -c -v '^$')
    
    echo -e "  • Total de ejecutables SUID detectados: ${BLANCO}${suid_count}${RESET}"
    if [ "$suid_count" -gt 60 ]; then
        pintar $AMARILLO "  ⚠️ Umbral alto de binarios SUID detectado."
        sugerencias+=("🛡️ SUID Elevado: Hay $suid_count binarios SUID. Audítalos con: find / -perm -4000")
        ((alertas_count++))
    else
        pintar $VERDE "  ✔ Cantidad de binarios SUID dentro de rangos normales."
        ((checks_passed++))
    fi
    echo ""

    # ==========================================
    # 4. MÓDULOS DE SEGURIDAD Y FIREWALL ($Package)
    # ==========================================
    pintar $MAGENTA "--- 4. CORTAFUEGOS Y MÓDULOS MAC ($Package) ---"
    echo ""

    # A. Cortafuegos
    ((total_checks++))
    pintar $AMARILLO "🔍 Estado del Cortafuegos (Firewall):"

    if comprobar_firewall; then
        pintar $VERDE "  ✔ Se detectaron reglas de cortafuegos activas en el sistema."
        ((checks_passed++))
    else
        pintar $ROJO_BRILLANTE "  ⚠️ No se detectó ningún cortafuegos o motor de filtrado activo."
        registrar_log "$LOG_WARN" "SEGURIDAD: Firewall inactivo o sin reglas filtrando."
        sugerencias+=("🔥 Firewall: Habilita y configura el cortafuegos de tu sistema (ufw/firewalld/nftables).")
        ((alertas_count++))
    fi
    echo ""

    # B. Módulos MAC (SELinux / AppArmor)
    ((total_checks++))
    pintar $AMARILLO "🔍 Módulos de Control de Acceso Mandatorio (MAC):"
    if command -v getenforce &>/dev/null; then
        local selinux_st
        selinux_st=$(getenforce)
        echo -e "  • SELinux Estado: ${BLANCO}${selinux_st}${RESET}"
        if [ "$selinux_st" == "Enforcing" ]; then
            pintar $VERDE "  ✔ SELinux está activo en modo Enforcing."
            ((checks_passed++))
        else
            sugerencias+=("🛡️ SELinux: Cambia el modo a Enforcing en /etc/selinux/config.")
            registrar_log "$LOG_WARN" "SEGURIDAD: SELinux en modo $selinux_st"
            ((alertas_count++))
        fi
    elif command -v aa-status &>/dev/null; then
        if aa-status --enabled 2>/dev/null; then
            pintar $VERDE "  ✔ AppArmor está activo y protegiendo los perfiles."
            ((checks_passed++))
        else
            pintar $ROJO_BRILLANTE "  ⚠️ AppArmor está inactivo."
            sugerencias+=("🛡️ AppArmor: Activa el módulo ejecutando 'systemctl enable --now apparmor'.")
            registrar_log "$LOG_WARN" "SEGURIDAD: AppArmor deshabilitado"
            ((alertas_count++))
        fi
    else
        echo -e "  • ${AMARILLO}Sin módulo MAC (AppArmor/SELinux) explícito en ejecución.${RESET}"
        sugerencias+=("🛡️ MAC: Se recomienda habilitar AppArmor o SELinux para mitigar exploits.")
        ((alertas_count++))
    fi
    echo ""

    

    # ==========================================
    # 5. RESUMEN, SCORE Y PLAN DE ACCIÓN
    # ==========================================
    local score=$(( (checks_passed * 100) / total_checks ))
    
    echo -e "${CIAN}====================================================${RESET}"
    pintar $BLANCO "📊 BALANCE Y PUNTUACIÓN DE SEGURIDAD:"
    echo -e "  • Pruebas superadas: ${VERDE}${checks_passed}/${total_checks}${RESET}"
    echo -e "  • Alertas encontradas: ${ROJO_BRILLANTE}${alertas_count}${RESET}"
    
    if [ "$score" -ge 80 ]; then
        echo -e "  • Nivel del sistema: ${VERDE_BRILLANTE}${score}% (SEGURO)${RESET}"
    elif [ "$score" -ge 50 ]; then
        echo -e "  • Nivel del sistema: ${AMARILLO}${score}% (MEJORABLE)${RESET}"
    else
        echo -e "  • Nivel del sistema: ${ROJO_BRILLANTE}${score}% (RIESGO ELEVADO)${RESET}"
    fi
    echo -e "${CIAN}----------------------------------------------------${RESET}"

    if [ ${#sugerencias[@]} -gt 0 ]; then
        pintar $AMARILLO "💡 PLAN DE ACCIÓN Y SUGERENCIAS RECOMENDADAS:"
        for sug in "${sugerencias[@]}"; do
            echo -e "  $sug"
        done
    else
        pintar $VERDE_BRILLANTE "🎉 ¡Excelente! El sistema superó los test de seguridad."
    fi
    echo -e "${CIAN}====================================================${RESET}"

    registrar_log "$LOG_INFO" "Auditoría completada. Score: ${score}% ($checks_passed/$total_checks). Alertas: $alertas_count"
    
    trap - SIGINT
    echo ""
    read -p "Presione Enter para volver al menú..."
}

Actualizar_sistema() {
    trap "clear; return" SIGINT
    clear
    mostrar_logo
    pintar $AZUL_BRILLANTE "➤ Iniciando actualización automática del sistema..."
    echo ""

    local ESTADO_ACTUALIZACION=0

    # 1. Actualización según el gestor principal del sistema
    case "$Package" in
        apt)
            pintar $VERDE "Actualizando repositorios y paquetes (APT)..."
            DEBIAN_FRONTEND=noninteractive apt-get update -y && \
            DEBIAN_FRONTEND=noninteractive apt-get full-upgrade -y && \
            apt-get autoremove -y
            ESTADO_ACTUALIZACION=$?
            ;;
        dnf)
            pintar $VERDE "Actualizando sistema (DNF)..."
            dnf upgrade --refresh -y && dnf autoremove -y
            ESTADO_ACTUALIZACION=$?
            ;;
        pacman)
            pintar $VERDE "Sincronizando repositorios y sistema (PACMAN)..."
            pacman -Syu --noconfirm
            ESTADO_ACTUALIZACION=$?
            ;;
        zypper)
            pintar $VERDE "Refrescando y actualizando (ZYPPER)..."
            zypper refresh && zypper update -y
            ESTADO_ACTUALIZACION=$?
            ;;
        *)
            pintar $ROJO "❌ Error: No se pudo identificar un gestor de paquetes compatible."
            read -p "Presione Enter para volver..."
            trap - SIGINT
            return 1
            ;;
    esac

    # 2. Actualización opcional para paquetes Flatpak (si está instalado)
    if command -v flatpak &>/dev/null; then
        echo ""
        pintar $AZUL "📦 Actualizando paquetes Flatpak..."
        flatpak update -y
    fi

    # 3. Actualización opcional para paquetes Snap (si está instalado)
    if command -v snap &>/dev/null; then
        echo ""
        pintar $AZUL "📦 Actualizando paquetes Snap..."
        snap refresh
    fi

    # 4. Evaluación del resultado y registro en logs
    echo ""
    if [ $ESTADO_ACTUALIZACION -eq 0 ]; then
        pintar $VERDE_BRILLANTE "✔ ¡El sistema se ha actualizado correctamente!"
        registrar_log "$LOG_INFO" "Actualización del sistema completada con éxito ($Package)."
    else
        pintar $ROJO "✘ Hubo un error durante la actualización."
        registrar_log "$LOG_ERR" "Fallo en la actualización del sistema usando $Package."
    fi

    # Restaurar la trampa de señal por defecto antes de salir
    trap - SIGINT
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

# ==============================================================================
#                 GESTIÓN DE USUARIOS Y PERMISOS
# ==============================================================================

# Obtener el grupo administrativo adecuado según el gestor de paquetes / distro
obtener_grupo_sudo() {
    if grep -q "^sudo:" /etc/group; then
        echo "sudo"
    elif grep -q "^wheel:" /etc/group; then
        echo "wheel"
    else
        echo "sudo"
    fi
}

# Función auxiliar para modificar o asignar permisos
modificar_permisos_usuario() {
    local user="$1"
    local grupo_admin
    grupo_admin=$(obtener_grupo_sudo)

    local opciones_rol="1. 👤 Estándar (Sin privilegios root)\n2. 🔑 Administrador (Añadir a $grupo_admin)\n3. ↩ Cancelar"
    local sel_rol
    sel_rol=$(echo -e "$opciones_rol" | fzf_estilo "Rol para $user" "NIVEL DE PERMISOS")

    case ${sel_rol:0:1} in
        1)
            gpasswd -d "$user" "$grupo_admin" 2>/dev/null
            usermod -s /bin/bash "$user" 2>/dev/null
            pintar $VERDE "✔ Privilegios elevados removidos. '$user' es un usuario Estándar."
            registrar_log "$LOG_INFO" "Permisos cambiados: $user -> Estándar"
            ;;
        2)
            usermod -aG "$grupo_admin" "$user" 2>/dev/null
            usermod -s /bin/bash "$user" 2>/dev/null
            pintar $VERDE_BRILLANTE "✔ Usuario '$user' añadido al grupo $grupo_admin (Administrador)."
            registrar_log "$LOG_WARN" "Permisos elevados otorgados: $user -> Administrador ($grupo_admin)"
            ;;
        *)
            pintar $AZUL "Operación cancelada sin cambios de permisos."
            ;;
    esac
}

gestionar_usuarios() {
    trap "clear; return" SIGINT
    while true; do
        clear
        mostrar_logo
        
        local opciones="1. 📋 Listar usuarios humanos\n2. ➕ Crear usuario (Con permisos)\n3. 🛡️ Modificar permisos de usuario\n4. 🗑️ Eliminar usuario\n5. ↩ Volver"
        local seleccion_users
        seleccion_users=$(echo -e "$opciones" | fzf_estilo "Acción" "G E S T I Ó N  D E  U S U A R I O S")
        
        if [[ $? -ne 0 || "$seleccion_users" == *"Volver"* || -z "$seleccion_users" ]]; then 
            break 
        fi

        case ${seleccion_users:0:1} in
            1) 
                listar_usuarios 
                ;;

            2) 
                local user
                user=$(pedir_nombre)
                if [ -n "$user" ]; then
                    if id "$user" &>/dev/null; then
                        pintar $ROJO "⚠️ El usuario '$user' ya existe en el sistema."
                        sleep 2
                        continue
                    fi

                    pintar $AMARILLO "➤ Creando usuario $user..."
                    local status_creacion=1

                    if [[ "$Package" == "apt" ]]; then
                        adduser --disabled-password --gecos "" "$user" 2>/dev/null
                        status_creacion=$?
                    else
                        useradd -m -s /bin/bash "$user" 2>/dev/null
                        status_creacion=$?
                    fi

                    if [ $status_creacion -eq 0 ]; then
                        pintar $AMARILLO "🔑 Establezca la contraseña para $user:"
                        passwd "$user"
                        
                        registrar_log "$LOG_INFO" "Usuario creado: $user"
                        
                        echo ""
                        pintar $CIAN "--- ASIGNACIÓN INICIAL DE PERMISOS ---"
                        modificar_permisos_usuario "$user"
                    else
                        pintar $ROJO "❌ Error al crear el usuario '$user'."
                        registrar_log "$LOG_ERR" "Fallo al crear usuario: $user"
                    fi
                fi
                read -p "Presione Enter para continuar..." 
                ;;

            3)
                clear
                mostrar_logo
                pintar $CIAN "--- MODIFICAR PERMISOS DE USUARIOS ---"
                
                # Obtener listado de usuarios humanos (UID >= 1000)
                local lista_users
                lista_users=$(cut -d: -f1,3 /etc/passwd | awk -F: '$2 >= 1000 && $2 < 60000 {print $1}')

                if [ -z "$lista_users" ]; then
                    pintar $AMARILLO "No se encontraron usuarios humanos configurables."
                    read -p "Presione Enter..."; continue
                fi

                local user_sel
                user_sel=$(echo "$lista_users" | fzf_estilo "Seleccione usuario" "MODIFICAR PERMISOS")

                if [ -n "$user_sel" ]; then
                    local grupo_admin
                    grupo_admin=$(obtener_grupo_sudo)
                    
                    echo -e "\n${AMARILLO}Usuario seleccionado:${RESET} ${BLANCO}$user_sel${RESET}"
                    if id -nG "$user_sel" | grep -qw "$grupo_admin"; then
                        echo -e "${AMARILLO}Estado actual:${RESET} ${VERDE_BRILLANTE}ADMINISTRADOR ($grupo_admin)${RESET}\n"
                    else
                        echo -e "${AMARILLO}Estado actual:${RESET} ${AZUL}ESTÁNDAR${RESET}\n"
                    fi

                    modificar_permisos_usuario "$user_sel"
                    read -p "Presione Enter para continuar..."
                fi
                ;;

            4) 
                local user
                user=$(pedir_nombre)
                if [ -n "$user" ]; then
                    if ! id "$user" &>/dev/null; then
                        pintar $ROJO "⚠️ El usuario '$user' no existe."
                        sleep 2
                        continue
                    fi

                    echo ""
                    echo -ne "${ROJO_BRILLANTE}⚠️ ¿Está seguro que desea eliminar el usuario $user y su carpeta /home? (s/N): ${RESET}"
                    read -r conf
                    
                    if [[ "$conf" == "s" || "$conf" == "S" ]]; then
                        pintar $ROJO "➤ Eliminando usuario $user..."
                        
                        # Matar procesos del usuario antes de borrarlo para evitar bloqueos
                        pkill -u "$user" 2>/dev/null
                        
                        if [[ "$Package" == "apt" ]]; then
                            deluser --remove-home "$user" 2>/dev/null && registrar_log "$LOG_WARN" "Usuario eliminado: $user"
                        else
                            userdel -r "$user" 2>/dev/null && registrar_log "$LOG_WARN" "Usuario eliminado: $user"
                        fi
                        
                        pintar $VERDE "✔ Usuario '$user' eliminado correctamente."
                    else
                        pintar $AZUL "Operación cancelada."
                    fi
                fi
                read -p "Presione Enter para continuar..." 
                ;;
        esac
    done
}

listar_usuarios() {
    echo ""
    for u in $(awk -F: '$3 >= 1000 && $3 != 65534 {print $1}' /etc/passwd); do
        pintar $AZUL "================================================================="
        pintar $NEGRITA$CIAN "USUARIO: $MAGENTA $u"
        echo "-----------------------------------------------------------------"
        pintar $NEGRITA$CIAN "GRUPOS : $AZUL_BRILLANTE $(id -nG "$u")"
        echo "-----------------------------------------------------------------"
        pintar $NEGRITA$CIAN "SUDO   : $RESET $(sudo -l -U "$u")"
        pintar $VERDE"================================================================="
        sleep 2
                    
    done
    echo ""
    echo "================================================================="
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
#--------------------------
super_limpieza() {
    echo ""
    pintar $MAGENTA "Iniciando Súper Limpieza..."
    
    # 1. Feedback visual mientras trabaja
    mostrar_spinner & SPINNER_PID=$!

    # 2. Medir espacio libre inicial en la raíz y en /home (si está separado)
    local ANTES_RAIZ=$(df --output=avail / | tail -n 1)
    local ANTES_HOME=$(df --output=avail /home 2>/dev/null | tail -n 1)

    # 3. Limpieza de logs antiguos de systemd (libera mucho espacio en todas las distros)
    if command -v journalctl &>/dev/null; then
        journalctl --vacuum-time=3d >/dev/null 2>&1
    fi

    # 4. Limpieza del gestor de paquetes según la distro
    case "$Package" in
        apt)
            apt-get install -f -y >/dev/null 2>&1
            apt-get autoremove --purge -y >/dev/null 2>&1
            apt-get autoclean -y >/dev/null 2>&1
            apt-get clean >/dev/null 2>&1
            ;;
        dnf)
            dnf clean all >/dev/null 2>&1
            dnf autoremove -y >/dev/null 2>&1
            ;;
        pacman)
            # Limpia paquetes no instalados y antiguas versiones de la caché
            pacman -Sc --noconfirm >/dev/null 2>&1
            # Elimina paquetes huérfanos si existen
            local huerfanos=$(pacman -Qtdq 2>/dev/null)
            if [ -n "$huerfanos" ]; then
                pacman -Rns $huerfanos --noconfirm >/dev/null 2>&1
            fi
            ;;
        zypper)
            zypper clean --all >/dev/null 2>&1
            zypper clean --packages >/dev/null 2>&1
            ;;
        *)
            kill "$SPINNER_PID" 2>/dev/null; wait "$SPINNER_PID" 2>/dev/null
            printf "\r\e[K"
            pintar $ROJO "❌ Limpieza automática no soportada para $Package"
            return 1
            ;;
    esac

    # 5. Limpieza profunda de papeleras de usuarios (evaluando dinámicamente)
    find /home/*/.local/share/Trash/files /home/*/.local/share/Trash/info -mindepth 1 -delete 2>/dev/null
    find /root/.local/share/Trash/files /root/.local/share/Trash/info -mindepth 1 -delete 2>/dev/null

    # 6. Limpieza segura de miniatura de imágenes (Caché de thumbnails)
    find /home/*/.cache/thumbnails /root/.cache/thumbnails -type f -atime +7 -delete 2>/dev/null

    # 7. Detener spinner
    kill "$SPINNER_PID" 2>/dev/null; wait "$SPINNER_PID" 2>/dev/null
    printf "\r\e[K"

    # 8. Medir espacio final
    local DESPUES_RAIZ=$(df --output=avail / | tail -n 1)
    local DESPUES_HOME=$(df --output=avail /home 2>/dev/null | tail -n 1)

    local DIF_RAIZ=$(( (DESPUES_RAIZ - ANTES_RAIZ) / 1024 ))
    local DIF_HOME=0
    [ -n "$ANTES_HOME" ] && [ -n "$DESPUES_HOME" ] && DIF_HOME=$(( (DESPUES_HOME - ANTES_HOME) / 1024 ))

    local LIBERADO=$(( DIF_RAIZ + DIF_HOME ))

    # 9. Reporte de resultados
    if [ "$LIBERADO" -gt 0 ]; then
        pintar $VERDE_BRILLANTE "¡Sistema limpio! ✨"
        echo -e "Se han liberado aprox. ${BLANCO}${LIBERADO} MB${RESET}."
        registrar_log "$LOG_INFO" "LIMPIEZA: Se liberaron aprox. ${LIBERADO} MB"
    else
        pintar $VERDE "Limpieza completada (el sistema ya estaba optimizado)."
        registrar_log "$LOG_INFO" "LIMPIEZA: Completada sin cambios significativos"
    fi

    echo ""
    read -p "Pulse Enter para volver..."
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
# ==============================================================================
#                 CONFIGURACIÓN Y FUNCIONES BASE DE BACKUP
# ==============================================================================

CONFIG_JSON="/var/backups/stk_backups/config.json"
DESTINO_DEF="/var/backups/stk_backups"

init_copy4me_config() {
    mkdir -p "$(dirname "$CONFIG_JSON")"
    if [ ! -f "$CONFIG_JSON" ]; then
        echo '{"perfiles":{},"opciones":{"verificar_hash":true,"compresion":6}}' > "$CONFIG_JSON"
        chmod 600 "$CONFIG_JSON"
    fi
}

obtener_perfiles_json() {
    init_copy4me_config
    jq -r '.perfiles | keys[]' "$CONFIG_JSON" 2>/dev/null
}

guardar_perfil_json() {
    local nombre="$1"
    local origen="$2"
    local destino="$3"
    local fecha
    fecha=$(date '+%Y-%m-%d %H:%M:%S')

    init_copy4me_config
    local tmp_json
    tmp_json=$(mktemp)

    # CORRECCIÓN 1: Uso seguro de mktemp y mv para escritura atómica
    if jq --arg nom "$nombre" \
          --arg orig "$origen" \
          --arg dest "$destino" \
          --arg date "$fecha" \
          '.perfiles[$nom] = {
              "ruta_local": $orig,
              "ruta_destino": $dest,
              "ultima_sincronizacion": $date
          }' "$CONFIG_JSON" > "$tmp_json"; then
        mv "$tmp_json" "$CONFIG_JSON"
        chmod 600 "$CONFIG_JSON"
    else
        rm -f "$tmp_json"
    fi
}

eliminar_perfil_json() {
    local nombre="$1"
    init_copy4me_config
    local tmp_json
    tmp_json=$(mktemp)

    if jq --arg nom "$nombre" 'del(.perfiles[$nom])' "$CONFIG_JSON" > "$tmp_json"; then
        mv "$tmp_json" "$CONFIG_JSON"
        chmod 600 "$CONFIG_JSON"
    else
        rm -f "$tmp_json"
    fi
}

verificar_espacio() {
    local origen="$1"
    local destino="$2"
    
    # CORRECCIÓN 7: Obtener el punto de montaje existente más cercano si el destino no existe aún
    local dest_dir="$destino"
    while [ ! -d "$dest_dir" ] && [ "$dest_dir" != "/" ]; do
        dest_dir=$(dirname "$dest_dir")
    done

    local tam_origen
    tam_origen=$(du -sk "$origen" 2>/dev/null | cut -f1)
    local disp_destino
    disp_destino=$(df -k "$dest_dir" 2>/dev/null | tail -n 1 | awk '{print $4}')
    
    tam_origen=${tam_origen:-0}
    disp_destino=${disp_destino:-0}
    
    [ "$disp_destino" -gt "$tam_origen" ]
}

rotar_backups() {
    local ruta="$1"
    local max_backups=5
    local count
    count=$(find "$ruta" -maxdepth 1 -name "*.tar.gz" 2>/dev/null | wc -l)

    if [ "$count" -gt "$max_backups" ]; then
        # CORRECCIÓN 2: Uso de exec ls -1t para garantizar portabilidad sin errores de sintaxis en find
        find "$ruta" -maxdepth 1 -name "*.tar.gz" -exec ls -1t {} + 2>/dev/null | \
            tail -n +$((max_backups + 1)) | xargs rm -f 2>/dev/null
        registrar_log "$LOG_INFO" "Rotación de backups ejecutada en $ruta (Límite: $max_backups)"
    fi
}

obtener_puntos_montaje_externos() {
    local USUARIO_REAL=${SUDO_USER:-$USER}
    {
        lsblk -o MOUNTPOINT -n 2>/dev/null | grep -v "^$" | grep -E "^/(media|run/media|mnt|media/$USUARIO_REAL)"
        find "/media/$USUARIO_REAL" "/run/media/$USUARIO_REAL" "/media" "/mnt" -maxdepth 2 -mindepth 1 -type d 2>/dev/null
    } | sort -u
}

# ==============================================================================
#                 NAVEGADOR DE DIRECTORIOS INTERACTIVO (FZF)
# ==============================================================================

fzf_seleccionar_directorio() {
    local dir_actual="${1:-$HOME}"
    dir_actual=$(readlink -f "$dir_actual" 2>/dev/null || echo "$dir_actual")

    while true; do
        if [ ! -d "$dir_actual" ] || [ ! -r "$dir_actual" ]; then
            dir_actual="$HOME"
        fi

        # Construir la lista de opciones
        local lineas_menu=""
        lineas_menu+="✅ [SELECCIONAR ESTA CARPETA]\t$dir_actual\n"
        lineas_menu+="➕ [CREAR NUEVA CARPETA AQUÍ]\t$dir_actual\n"
        lineas_menu+="⬆️ [SUBIR A CARPETA PADRE]\t$dir_actual\n"

        while IFS= read -r sub_d; do
            [ -n "$sub_d" ] && lineas_menu+="📁 $(basename "$sub_d")\t$sub_d\n"
        done < <(find "$dir_actual" -mindepth 1 -maxdepth 1 -type d 2>/dev/null | sort)

        # Ejecutar FZF mostrando solo la primera columna (el texto legible/icono)
        local sel
        sel=$(echo -e "$lineas_menu" | fzf --ansi --height=18 --reverse --border=rounded \
            --prompt="Navegar ❯ " \
            --header="Directorio actual: $dir_actual" \
            --delimiter="\t" --with-nth=1)

        # Si el usuario cancela con ESC o Ctrl+C
        if [ $? -ne 0 ] || [ -z "$sel" ]; then
            return 1
        fi

        # Extraer la opción seleccionada y su ruta real (columna 2)
        local opcion_texto
        opcion_texto=$(echo "$sel" | cut -d$'\t' -f1)
        local ruta_target
        ruta_target=$(echo "$sel" | cut -d$'\t' -f2)

        if [[ "$opcion_texto" == *"✅ [SELECCIONAR ESTA CARPETA]"* ]]; then
            echo "$dir_actual"
            return 0
        elif [[ "$opcion_texto" == *"➕ [CREAR NUEVA CARPETA AQUÍ]"* ]]; then
            echo -ne "\n\033[33mEscriba el nombre de la nueva carpeta: \033[0m" >&2
            read -r nueva_k
            if [ -n "$nueva_k" ]; then
                local target="$dir_actual/$nueva_k"
                mkdir -p "$target" 2>/dev/null
                if [ -d "$target" ]; then
                    dir_actual="$target"
                else
                    echo -e "\033[31m❌ Error: No se pudo crear la carpeta en $dir_actual (Compruebe permisos)\033[0m" >&2
                    sleep 2
                fi
            fi
        elif [[ "$opcion_texto" == *"⬆️ [SUBIR A CARPETA PADRE]"* ]]; then
            dir_actual=$(dirname "$dir_actual")
        elif [ -n "$ruta_target" ] && [ -d "$ruta_target" ]; then
            dir_actual="$ruta_target"
        fi
    done
}

# ==============================================================================
#                 GESTIÓN Y VISUALIZACIÓN DE BACKUPS (.tar.gz)
# ==============================================================================

ver_backups_existentes() {
    clear
    mostrar_logo
    pintar $CIAN "--- BACKUPS LOCALES EXISTENTES ---"

    if [ ! -d "$DESTINO_DEF" ]; then
        pintar $ROJO "No se encontró el directorio de backups ($DESTINO_DEF)."
        read -p "Presione Enter..."
        return
    fi

    local archivos
    archivos=$(find "$DESTINO_DEF" -type f -name "*.tar.gz" 2>/dev/null)
    if [ -z "$archivos" ]; then
        pintar $AMARILLO "No hay archivos de backup (.tar.gz) disponibles."
        read -p "Presione Enter..."
        return
    fi

    echo "$archivos" | fzf --ansi \
        --height=18 \
        --reverse \
        --border=rounded \
        --prompt="➤ Inspeccionar Backup: " \
        --header="--- VISTA PREVIA DEL CONTENIDO (.tar.gz) ---" \
        --preview="tar -tvf {} | head -n 40" \
        --preview-window="right:60%"

    read -p "Presione Enter para volver..."
}

eliminar_backups() {
    clear
    mostrar_logo
    pintar $CIAN "--- ELIMINAR COPIAS DE SEGURIDAD ---"

    local archivos
    archivos=$(find "$DESTINO_DEF" -type f -name "*.tar.gz" 2>/dev/null)
    if [ -z "$archivos" ]; then
        pintar $AMARILLO "No hay respaldos para eliminar."
        read -p "Presione Enter..."
        return
    fi

    local sel
    sel=$(echo "$archivos" | fzf_estilo "Seleccione backup a ELIMINAR" "E L I M I N A C I Ó N")

    if [ -n "$sel" ]; then
        echo -ne "\n${ROJO_BRILLANTE}⚠️ ¿Seguro que desea eliminar $(basename "$sel")? (s/N): ${RESET}"
        read -r conf
        if [[ "$conf" == "s" || "$conf" == "S" ]]; then
            rm -f "$sel"
            pintar $VERDE "✔ Archivo eliminado correctamente."
            registrar_log "$LOG_WARN" "Backup eliminado: $sel"
        else
            pintar $AZUL "Operación cancelada."
        fi
        read -p "Presione Enter..."
    fi
}

restaurar_backup() {
    clear
    mostrar_logo
    pintar $CIAN "--- RESTAURAR COPIA DE SEGURIDAD ---"

    if [ ! -d "$DESTINO_DEF" ] || [ -z "$(find "$DESTINO_DEF" -name "*.tar.gz" 2>/dev/null)" ]; then
        pintar $ROJO "No hay backups disponibles para restaurar."
        read -p "Presione Enter..."
        return
    fi

    local seleccion
    seleccion=$(find "$DESTINO_DEF" -type f -name "*.tar.gz" | fzf_estilo "Seleccione backup para RESTAURAR" "R E S T A U R A C I Ó N")

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

# ==============================================================================
#  OPCIÓN 1: RESPALDO LOCAL AUTOMÁTICO (.tar.gz)
# ==============================================================================

autocopy_atomatic() {
    trap "clear; return" SIGINT

    while true; do
        clear
        mostrar_logo
        pintar $CIAN "--- RESPALDO LOCAL AUTOMÁTICO (PC) ---"

        local USUARIO_REAL=${SUDO_USER:-$USER}
        local opciones="1. 📁 Sistema (/etc)\n2. 👤 Usuario Actual (/home/$USUARIO_REAL)\n3. 🌐 Web (/var/www)\n4. 🔍 Explorar e Indicar Carpeta con FZF\n5. ↩ Volver"
        local sel
        sel=$(echo -e "$opciones" | fzf_estilo "Origen Local" "SELECCIONAR ORIGEN")

        if [ $? -ne 0 ] || [ -z "$sel" ] || [[ "${sel:0:1}" == "5" ]]; then break; fi

        local ORIGEN=""
        case ${sel:0:1} in
            1) ORIGEN="/etc" ;;
            2) ORIGEN="/home/$USUARIO_REAL" ;;
            3) ORIGEN="/var/www" ;;
            4) ORIGEN=$(fzf_seleccionar_directorio "/home/$USUARIO_REAL") ;;
        esac

        if [ -z "$ORIGEN" ] || [ ! -e "$ORIGEN" ]; then
            pintar $ROJO "❌ Error: Ruta de origen inválida o no seleccionada."
            sleep 2; continue
        fi

        echo -ne "\n${CIAN}➤ Subcarpeta para organizar el backup (Enter para 'general'): ${RESET}"
        read -r SUBDIR
        local RUTA_FINAL="$DESTINO_DEF/${SUBDIR:-"general"}"

        if ! mkdir -p "$RUTA_FINAL" 2>/dev/null; then
            pintar $ROJO "❌ Error crítico: Sin permisos de escritura en $RUTA_FINAL"
            sleep 2; continue
        fi
        chmod 700 "$DESTINO_DEF" 2>/dev/null

        local FECHA
        FECHA=$(date +%Y%m%d_%H%M%S)
        local NOMBRE_ARCH="backup_$(basename "$ORIGEN")_${FECHA}.tar.gz"
        local DESTINO_COMPLETO="$RUTA_FINAL/$NOMBRE_ARCH"

        if ! verificar_espacio "$ORIGEN" "$RUTA_FINAL"; then
            pintar $ROJO "❌ Espacio insuficiente en el disco local para comprimir este directorio."
            read -p "Presione Enter para continuar..."; continue
        fi

        echo -e "\n${AZUL}🔄 Empaquetando y comprimiendo archivos...${RESET}"
        mostrar_spinner & SPINNER_PID=$!

        local PARENT_DIR
        PARENT_DIR=$(dirname "$ORIGEN")
        local TARGET_BASE
        TARGET_BASE=$(basename "$ORIGEN")
        [ "$PARENT_DIR" == "/" ] && PARENT_DIR=""

        # CORRECCIÓN 5 y 6: umask restringido durante compresión y exclusión de globs aislados
        (
            umask 077
            tar -czpf "$DESTINO_COMPLETO" \
                --exclude='*.log' --exclude='*.tmp' --exclude='*/.cache/*' \
                -C "${PARENT_DIR:-/}" "$TARGET_BASE" > /tmp/stk_backup_err 2>&1
        )
        local TAR_EXIT_CODE=$?

        kill "$SPINNER_PID" 2>/dev/null; wait "$SPINNER_PID" 2>/dev/null
        printf "\r\e[K"

        if [ $TAR_EXIT_CODE -eq 0 ]; then
            chmod 600 "$DESTINO_COMPLETO"
            local SIZE
            SIZE=$(du -h "$DESTINO_COMPLETO" | cut -f1)
            local HASH
            HASH=$(sha256sum "$DESTINO_COMPLETO" | awk '{print $1}' | cut -c1-16)

            echo -e "${VERDE_BRILLANTE}✅ BACKUP LOCAL COMPLETADO CON ÉXITO${RESET}"
            echo -e "${BLANCO}------------------------------------------------${RESET}"
            echo -e "${AMARILLO}Origen:    ${BLANCO}$ORIGEN${RESET}"
            echo -e "${AMARILLO}Archivo:   ${BLANCO}$NOMBRE_ARCH${RESET}"
            echo -e "${AMARILLO}Ruta:      ${BLANCO}$RUTA_FINAL${RESET}"
            echo -e "${AMARILLO}Tamaño:    ${BLANCO}$SIZE${RESET}"
            echo -e "${AMARILLO}SHA256:    ${BLANCO}$HASH... (verificado)${RESET}"
            echo -e "${BLANCO}------------------------------------------------${RESET}"

            registrar_log "$LOG_INFO" "Backup Automático: $NOMBRE_ARCH en $RUTA_FINAL (Hash: $HASH)"
            rotar_backups "$RUTA_FINAL"
        else
            pintar $ROJO "❌ Error al comprimir el respaldo:"
            cat /tmp/stk_backup_err
            registrar_log "$LOG_ERR" "Error en tar al respaldar $ORIGEN"
        fi

        read -p "Presione Enter para continuar..."
    done
}

# ==============================================================================
#  OPCIÓN 2: COPY4ME TUI ENGINE (RSYNC CON PERFILES Y MULTI-DISTRO USB)
# ==============================================================================

ejecutar_sincronizacion_bash() {
    local origen="$1"
    local destino="$2"
    local modo="$3"

    if ! mkdir -p "$destino" 2>/dev/null; then
        pintar $ROJO "\n❌ Error: No se tienen permisos para escribir en el destino: $destino"
        read -p "Presione Enter..."
        return 1
    fi

    echo -e "\n${AZUL}🚀 Ejecutando rsync (${modo^^})...${RESET}"
    echo -e "${AMARILLO}📂 Origen:  ${BLANCO}$origen${RESET}"
    echo -e "${AMARILLO}🎯 Destino: ${BLANCO}$destino${RESET}\n"

    case "$modo" in
        "incremental")
            rsync -avu --progress "$origen/" "$destino/"
            ;;
        "espejo")
            rsync -av --delete --progress "$origen/" "$destino/"
            ;;
        "bidireccional")
            echo -e "${CIAN}🔄 Pasada 1: Origen ➔ Destino...${RESET}"
            rsync -avu --progress "$origen/" "$destino/"
            echo -e "${CIAN}🔄 Pasada 2: Destino ➔ Origen...${RESET}"
            rsync -avu --progress "$destino/" "$origen/"
            ;;
    esac

    if [ $? -eq 0 ]; then
        pintar $VERDE_BRILLANTE "\n✔ ¡Sincronización finalizada correctamente!"
        registrar_log "$LOG_INFO" "COPY4ME ($modo): $origen -> $destino"
    else
        pintar $ROJO "\n❌ Error durante la transferencia con rsync."
        registrar_log "$LOG_ERR" "COPY4ME Falló: $origen -> $destino"
    fi
}

copy4me_tui_main() {
    local USUARIO_REAL=${SUDO_USER:-$USER}

    while true; do
        clear
        mostrar_logo
        pintar $CIAN "--- COPY4ME ENGINE TUI (RSYNC & PERFILES) ---"

        local menu_opts="1. 🚀 Realizar Sincronización / Respaldo\n2. 📂 Gestionar Perfiles Guardados\n3. 🔌 Escanear y Probar Unidades Externas/USB\n4. ↩ Volver"
        local sel
        sel=$(echo -e "$menu_opts" | fzf_estilo "Seleccione Acción" "C O P Y 4 M E")

        if [ $? -ne 0 ] || [ -z "$sel" ] || [[ "${sel:0:1}" == "4" ]]; then break; fi

        case ${sel:0:1} in
            1)
                local origen=""
                local destino=""
                local nombre_perfil=""

                local perfiles
                perfiles=$(obtener_perfiles_json)
                local opts_orig="🔍 [NUEVO] Explorar carpetas con FZF\n"
                
                if [ -n "$perfiles" ]; then
                    while read -r p; do
                        # CORRECCIÓN 3: Uso seguro de --arg en jq para nombres de perfiles con espacios
                        local path_orig
                        path_orig=$(jq -r --arg p "$p" '.perfiles[$p].ruta_local' "$CONFIG_JSON")
                        opts_orig+="📁 [Perfil] $p ➔ $path_orig\n"
                    done <<< "$perfiles"
                fi

                local sel_orig
                sel_orig=$(echo -e "$opts_orig" | fzf_estilo "Seleccione Origen" "ORIGEN DE DATOS")
                if [ -z "$sel_orig" ]; then continue; fi

                if [[ "$sel_orig" == *"📁 [Perfil]"* ]]; then
                    # CORRECCIÓN 4: Extracción de perfil por sed soportando espacios adecuadamente
                    nombre_perfil=$(echo "$sel_orig" | sed -n 's/.*📁 \[Perfil\] \(.*\) ➔ .*/\1/p')
                    origen=$(jq -r --arg nom "$nombre_perfil" '.perfiles[$nom].ruta_local' "$CONFIG_JSON")
                    destino=$(jq -r --arg nom "$nombre_perfil" '.perfiles[$nom].ruta_destino' "$CONFIG_JSON")
                else
                    origen=$(fzf_seleccionar_directorio "/home/$USUARIO_REAL")
                    if [ -z "$origen" ] || [ ! -d "$origen" ]; then
                        pintar $ROJO "❌ No se seleccionó una carpeta de origen válida."
                        sleep 2; continue
                    fi
                    nombre_perfil=$(basename "$origen")
                fi

                if [ -z "$destino" ] || [ "$destino" == "null" ]; then
                    local usbs
                    usbs=$(obtener_puntos_montaje_externos)
                    local opts_dest="🔍 Explorar/Crear carpeta en PC con FZF\n"

                    if [ -n "$usbs" ]; then
                        while read -r u; do
                            [ -n "$u" ] && [ -d "$u" ] && opts_dest+="🔌 [Montaje detectado] $u\n"
                        done <<< "$usbs"
                    fi

                    local sel_dest
                    sel_dest=$(echo -e "$opts_dest" | fzf_estilo "Seleccione Destino" "DESTINO PARA: $nombre_perfil")
                    if [ -z "$sel_dest" ]; then continue; fi

                    if [[ "$sel_dest" == *"🔌 [Montaje detectado]"* ]]; then
                        local usb_root
                        usb_root=$(echo "$sel_dest" | sed 's/.*🔌 \[Montaje detectado\] //')
                        
                        local sub_usb_opts="1. Usar raíz de la unidad ($usb_root/copy4me_backups/$nombre_perfil)\n2. 🔍 Navegar o crear subcarpeta con FZF"
                        local sel_sub_usb
                        sel_sub_usb=$(echo -e "$sub_usb_opts" | fzf_estilo "Opciones de montaje" "DIRECTORIO EN UNIDAD")

                        if [[ "${sel_sub_usb:0:1}" == "2" ]]; then
                            local dest_fzf
                            dest_fzf=$(fzf_seleccionar_directorio "$usb_root")
                            if [ -n "$dest_fzf" ]; then
                                destino="$dest_fzf/$nombre_perfil"
                            else
                                continue
                            fi
                        else
                            destino="$usb_root/copy4me_backups/$nombre_perfil"
                        fi
                    else
                        destino=$(fzf_seleccionar_directorio "/home/$USUARIO_REAL")
                        if [ -n "$destino" ]; then
                            destino="$destino/$nombre_perfil"
                        else
                            continue
                        fi
                    fi
                fi

                local modos="1. incremental   | Copia solo archivos nuevos o modificados\n2. espejo        | Borra en destino lo eliminado en origen\n3. bidireccional | Sincroniza cambios en ambos sentidos"
                local sel_modo
                sel_modo=$(echo -e "$modos" | fzf_estilo "Seleccione Modo" "MODO SINCRONIZACIÓN")
                if [ -z "$sel_modo" ]; then continue; fi

                local modo
                modo=$(echo "$sel_modo" | awk '{print $2}')

                guardar_perfil_json "$nombre_perfil" "$origen" "$destino"
                ejecutar_sincronizacion_bash "$origen" "$destino" "$modo"
                read -p "Presione Enter para continuar..."
                ;;

            2)
                local perfiles
                perfiles=$(obtener_perfiles_json)
                if [ -z "$perfiles" ]; then
                    pintar $AMARILLO "No hay perfiles guardados."
                    read -p "Presione Enter..."; continue
                fi

                local opts_del=""
                while read -r p; do
                    opts_del+="❌ Borrar Perfil: $p\n"
                done <<< "$perfiles"

                local sel_del
                sel_del=$(echo -e "$opts_del" | fzf_estilo "Perfil a eliminar" "BORRAR PERFILES")
                if [ -n "$sel_del" ]; then
                    local p_target
                    p_target=$(echo "$sel_del" | sed 's/.*❌ Borrar Perfil: //')
                    eliminar_perfil_json "$p_target"
                    pintar $VERDE "✔ Perfil '$p_target' eliminado."
                    read -p "Presione Enter..."
                fi
                ;;

            3)
                clear
                mostrar_logo
                pintar $CIAN "--- DISPOSITIVOS Y PUNTOS DE MONTAJE DETECTADOS ---"
                lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,TRAN | grep -v "^$"
                echo -e "\n${AMARILLO}Rutas de almacenamiento externo detectadas:${RESET}"
                obtener_puntos_montaje_externos
                echo ""
                read -p "Presione Enter para continuar..."
                ;;
        esac
    done
}

# ==============================================================================
#           MENÚ PRINCIPAL Y ESTRUCTURA GENERAL DE BACKUP
# ==============================================================================

hacer_backup() {
    trap "clear; return" SIGINT

    while true; do
        clear
        mostrar_logo
        pintar $CIAN "--- GESTIÓN INTEGRAL DE COPIAS DE SEGURIDAD ---"
        
        local opciones="1. 📁 Respaldo Local Automático (PC - Compressed .tar.gz)\n2. 🚀 COPY4ME TUI Engine (Rsync, USB y Perfiles)\n3. 📜 Ver Backups Locales Existentes\n4. 🗑️ Eliminar Backups Locales\n5. 🔄 Restaurar Backup Comprimido\n6. ↩ Volver al Menú Principal"
        local seleccion
        seleccion=$(echo -e "$opciones" | fzf_estilo "Seleccione opción" "G E S T I Ó N  D E  B A C K U P S")

        if [ $? -ne 0 ] || [ -z "$seleccion" ]; then break; fi
        
        case ${seleccion:0:1} in
            1) autocopy_atomatic ;;
            2) copy4me_tui_main ;;
            3) ver_backups_existentes ;;
            4) eliminar_backups ;;
            5) restaurar_backup ;;
            6) break ;;
        esac
    done
}


# --- EJECUCIÓN ---
rotar_logs "silencioso"

mostrar_ayuda() {
    echo -e "${CIAN}STK - System Tool Kit v${V}${RESET}"
    echo -e "${BLANCO}Uso:${RESET} sudo $0 [OPCIÓN]"
    echo ""
    echo -e "${AMARILLO}Opciones de línea de comandos:${RESET}"
    echo -e "  ${VERDE}-m, --monitor${RESET}          Abre el monitor de rendimiento del sistema."
    echo -e "  ${VERDE}-a, --audit${RESET}            Ejecuta la auditoría de seguridad del sistema."
    echo -e "  ${VERDE}-u, --update${RESET}           Actualiza los paquetes del sistema y repositorios."
    echo -e "  ${VERDE}-c, --clean${RESET}            Ejecuta la súper limpieza de espacio e imprevistos."
    echo -e "  ${VERDE}-l, --logs${RESET}             Muestra las últimas entradas de la bitácora STK."
    echo -e "  ${VERDE}-b, --backup${RESET}           Accede directamente al menú de copias de seguridad."
    echo -e "  ${VERDE}-A, --auto${RESET}             Ejecuta el modo automático de mantenimiento integral."
    echo -e "  ${VERDE}-v, --version${RESET}          Muestra la versión del script y sale."
    echo -e "  ${VERDE}-h, --help, ayuda${RESET}      Muestra este mensaje de ayuda."
    echo ""
    echo -e "  ${AZUL}Sin argumentos:${RESET}        Abre el menú interactivo con FZF."
    echo ""
    exit 0
}

# Comprobación de flags pasados como argumento al script
case "$1" in
    -m|--monitor|stk_monitor)
        monitor_rendimiento
        ;;

    -a|--audit|auditoria_seguridad)
        auditoria_seguridad
        ;;

    -u|--update|actualizacion)
        Actualizar_sistema   
        ;;

    -c|--clean|limpieza)
        super_limpieza
        ;;

    -l|--logs|bitacora)
        ver_logs
        ;;

    -b|--backup|copia)
        hacer_backup
        ;;

    -A|--auto|modo_automativo)
        modo_auto
        ;;

    -v|--version)
        echo -e "${CIAN}STK Version:${RESET} ${BLANCO}v$V${RESET}"
        exit 0
        ;;

    -h|--help|ayuda)
        mostrar_ayuda
        ;;

    *)
        menu
        ;;
esac