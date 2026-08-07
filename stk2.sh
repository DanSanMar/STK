#!/bin/bash

# --- INFORMACIÓN DEL PROYECTO ---
V="5.8.2 Testeando en Arch"
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
    # Mantenemos el límite en Kilobytes (500 KB)
    local MAX_SIZE=500
    local MODO_SILENCIOSO="${1:-modo_interactivo}"

    if [ "$MODO_SILENCIOSO" != "silencioso" ]; then
        clear
        mostrar_logo
        pintar $CIAN "--- ROTACIÓN Y MANTENIMIENTO DE LOGS ---"
        echo -e "${AMARILLO}➤ Archivo de bitácora:${RESET} ${BLANCO}$LOG_FILE${RESET}"
        echo -e "${AMARILLO}➤ Límite configurado:${RESET}  ${BLANCO}${MAX_SIZE} KB${RESET}\n"
    fi

    if [ ! -f "$LOG_FILE" ]; then
        if [ "$MODO_SILENCIOSO" != "silencioso" ]; then
            pintar $ROJO "❌ El archivo de log no existe aún. Creando uno nuevo..."
            umask 027
            touch "$LOG_FILE"
            chmod 640 "$LOG_FILE"
            registrar_log "$LOG_INFO" "Bitácora reiniciada manualmente."[cite: 1]
            pintar $VERDE "✔ Archivo creado e inicializado correctamente."
            read -p "Presione Enter para volver..."
        fi
        return 0
    fi

    # Obtener el tamaño actual del archivo en KB
    local SIZE=$(du -k "$LOG_FILE" | cut -f1)

    if [ "$MODO_SILENCIOSO" != "silencioso" ]; then
        echo -e "${CIAN}🔍 Comprobando tamaño actual...${RESET}"
        echo -e "   Tamaño detectado: ${BLANCO}${SIZE} KB${RESET} / Límite: ${BLANCO}${MAX_SIZE} KB${RESET}\n"
    fi

    if [ "$SIZE" -ge "$MAX_SIZE" ]; then
        [ "$MODO_SILENCIOSO" != "silencioso" ] && pintar $AMARILLO "⚠️ El archivo excede el límite. Procediendo con el vaciado y rotación..."
        
        # Guardar marca del reinicio en el log vaciando el contenido anterior
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] - Log reiniciado por alcanzar el límite de $MAX_SIZE KB (Tamaño anterior: ${SIZE} KB)." > "$LOG_FILE"
        
        # Ajustar permisos por seguridad
        chmod 640 "$LOG_FILE"

        if [ "$MODO_SILENCIOSO" != "silencioso" ]; then
            pintar $VERDE_BRILLANTE "✔ Se han liberado $((SIZE)) KB de espacio en la bitácora."
            pintar $VERDE "✔ Permisos reafirmados a 640 (root:root/adm)."
        fi
    else
        if [ "$MODO_SILENCIOSO" != "silencioso" ]; then
            pintar $VERDE "✔ El tamaño del log está dentro de los márgenes aceptables."
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
        URL="${HOME_URL:-unknown}"
        
        # Asignación inteligente de versión respetando Rolling Release
        if [ -n "$VERSION" ]; then
            VERSION="$VERSION"
        elif [ -n "$VERSION_ID" ]; then
            VERSION="$VERSION_ID"
        elif [[ "$OS_ID" == "arch" || "$OS_LIKE" == *"arch"* ]]; then
            # Si es Arch/derivada y no hay versión, se indica que es Rolling Release
            VERSION="Rolling Release"
        else
            VERSION="unknown"
        fi
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
        echo -e "${AZUL}📦 Instalando paquete: $pkg...${RESET}"
        case "$Package" in
            "apt") apt install -y "$pkg" ;;
            "dnf") dnf install -y "$pkg" ;;
            "pacman") pacman -S --noconfirm "$pkg" ;;
            "zypper") zypper install -y "$pkg" ;;
        esac
    done
}

mostrar_instrucciones() {
    clear
    echo -e "\n${AZUL}══════════════════════════════════════════════════${RESET}"
    echo -e "${BLANCO} 📖 GUÍA DE INSTALACIÓN MANUAL PARA TU SISTEMA (${Package^^})${RESET}"
    echo -e "${AZUL}══════════════════════════════════════════════════${RESET}\n"

    for tool in "${missing_tools[@]}"; do
        echo -e "${AMARILLO}🛠  Herramienta: ${BLANCO}$tool${RESET}"
        pkg=$(get_package_name "$tool")

        case "$Package" in
            "pacman")
                echo -e "   ${VERDE}✔ Comando:${RESET} sudo pacman -S $pkg"
                ;;
            "apt"|"dnf"|"zypper")
                echo -e "   ${VERDE}✔ Comando:${RESET} sudo $Package install -y $pkg"
                ;;
            *)
                echo -e "   ${VERDE}✔ Comando:${RESET} Usa el gestor de paquetes de tu sistema para instalar: $pkg"
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
        "hostname") [[ "$Package" == "pacman" ]] && echo "inetutils" || echo "hostname" ;;
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
1. 📊 | MONITORIZACIÓN  | Analisis de rendimiento, red y seguridad
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
                    accion=$(echo -e "1. Rendimiento del Sistema\n2. Información de Red \n3. Auditoría de Seguridad\n4. ↩ Volver" | fzf_estilo "Seleccione" "MONITORIZACIÓN")
                    if [[ $? -ne 0 || "$accion" == *"Volver"* ]]; then break; fi
                    case ${accion%%.*} in
                        1) monitor_rendimiento ;;
                        2) mostrar_info_red ;;
                        3) auditoria_seguridad ;;
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

            5) salir ;;
        esac
    done
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
    local fw_active=false

    case "$Package" in
        apt)
            if command -v ufw &>/dev/null; then
                local ufw_st
                ufw_st=$(ufw status 2>/dev/null | head -n 1)
                echo -e "  • UFW: ${BLANCO}${ufw_st}${RESET}"
                if [[ "$ufw_st" == *"active"* ]] && [[ "$ufw_st" != *"inactive"* ]]; then
                    fw_active=true
                fi
            fi
            ;;
        dnf)
            if command -v firewall-cmd &>/dev/null; then
                local fwd_st
                fwd_st=$(systemctl is-active firewalld 2>/dev/null)
                echo -e "  • Firewalld: ${BLANCO}${fwd_st}${RESET}"
                [ "$fwd_st" == "active" ] && fw_active=true
            fi
            ;;
        pacman|zypper|*)
            if systemctl is-active nftables &>/dev/null || systemctl is-active iptables &>/dev/null; then
                echo -e "  • Servidor con motor de reglas activo (nftables/iptables)."
                fw_active=true
            fi
            ;;
    esac

    if [ "$fw_active" = true ]; then
        pintar $VERDE "  ✔ El cortafuegos está activo y protegiendo el sistema."
        ((checks_passed++))
    else
        pintar $ROJO_BRILLANTE "  ⚠️ No se detectó ningún cortafuegos activo."
        registrar_log "$LOG_WARN" "SEGURIDAD: Firewall inactivo en $Package"
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
        registrar_log "$LOG_INFO" "Actualización del sistema completada con éxito ($Package)."[cite: 1]
    else
        pintar $ROJO "✘ Hubo un error durante la actualización."
        registrar_log "$LOG_ERR" "Fallo en la actualización del sistema usando $Package."[cite: 1]
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
        local opciones="1. 📁 Sistema (/etc)\n2. 👤 Usuario Actual\n3. 🌐 Web (/var/www)\n4. ✍️ Ruta Personalizada\n5. 📜 VER BACKUPS REALIZADOS\n6. 🗑️ ELIMINAR BACKUPS\n7. 🔄 RESTAURAR BACKUPS\n8. ↩ Volver"
        local seleccion=$(echo -e "$opciones" | fzf_estilo "Seleccione acción" "C O P I A  D E  S E G U R I D A D")

        if [ $? -ne 0 ] || [ -z "$seleccion" ]; then break; fi
        
        # Lógica de saltos según selección
        if [[ "${seleccion:0:1}" == "5" ]]; then ver_backups_existentes; continue; fi
        if [[ "${seleccion:0:1}" == "6" ]]; then eliminar_backups; continue; fi
        if [[ "${seleccion:0:1}" == "7" ]]; then restaurar_backup; continue; fi
        if [[ "${seleccion:0:1}" == "8" ]]; then break; fi
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
rotar_logs "silencioso"
menu
