#!/usr/bin/env bash

# --- INFORMACIÓN DEL PROYECTO ---
V="2.5.0"
DESCRIPCION="Herramienta de instalación de programas por categorías y fuentes híbridas"
AUTOR="DanSanMar"

# --- BIBLIOTECA DE CABECERAS STK (paleta, menús FZF y salida) ---
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SELF_PATH="$SCRIPT_DIR/$(basename "${BASH_SOURCE[0]}")"
source "$SCRIPT_DIR/stk_header.sh"

# Uso interno: FZF puede pedir la cabecera en caliente con bg-transform-header
if [[ "${BASH_SOURCE[0]}" == "$0" ]] && [ "${1:-}" = "--stk-header" ]; then
    stk_init "INSTALL4ME" "$V" "SOFTWARE INSTALLER"
    stk_header
    exit 0
fi

# --- CONFIGURACIÓN DE LOGS ---
# Log centralizado del proyecto (estilo STK / PROC4ME / STOP4ME / JOBS4ME)
LOG_FILE="/var/log/stk_mantenimiento.log"
LOG_INFO="INFO"
LOG_WARN="WARN"
LOG_ERR="ERROR"

DATE=$(date +"%d/%m/%Y")

registrar_log() {
    local NIVEL="${1:-INFO}"
    local MENSAJE="${2}"
    local FECHA
    FECHA=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$FECHA] [$NIVEL] [${SUDO_USER:-$USER}] - [INSTALL4ME] $MENSAJE" >> "$LOG_FILE"
}

pintar() { 
    local COLOR="$1" 
    local MENSAJE="$2" 
    echo -e "${COLOR}${MENSAJE}${RESET}"
}

# --- COMPROBACIÓN DE SUDO ---
if [ "$EUID" -ne 0 ]; then
    echo -e "${ROJO_BRILLANTE}⚠️ Error: Este script requiere privilegios de root.${RESET}"
    echo -e "${AMARILLO}Prueba con: sudo $0${RESET}"
    exit 1
fi

if [ ! -f "$LOG_FILE" ]; then
    umask 027
    touch "$LOG_FILE" 2>/dev/null
    chmod 640 "$LOG_FILE" 2>/dev/null
    registrar_log "$LOG_INFO" "Bitácora inicializada - install4me v$V"
fi

# Detección del gestor de paquetes
Package=""

if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID="${ID:-unknown}"
    OS_LIKE="${ID_LIKE:-unknown}"
    
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

# --- DETECCIÓN DE SISTEMAS INMUTABLES (OSTREE / RPM-OSTREE) ---
# Fedora Silverblue, Kinoite, COSMIC Atomic, Bazzite, Bluefin, CoreOS y derivados.
INMUTABLE=false
REINICIO_REQUERIDO=false

if [ -f /run/ostree-booted ] && command -v rpm-ostree &>/dev/null; then
    INMUTABLE=true
    # rpm-ostree usa repositorios RPM de Fedora/RHEL: conservamos los mapeos de dnf.
    [ "$Package" = "unknown" ] && Package="dnf"
fi

# Configuración de la cabecera responsive (se conserva la línea OS/Pkg/User)
stk_init "INSTALL4ME" "$V" "SOFTWARE INSTALLER"

mostrar_logo() {
    local pkg_mostrar="${Package:-N/A}"
    [ "$INMUTABLE" = true ] && pkg_mostrar="rpm-ostree"
    STK_EXTRA="${VERDE_BRILLANTE}OS:${RESET} ${AZUL}${OS_ID:-N/A}${RESET} | ${AMARILLO}Pkg:${RESET} ${AZUL}${pkg_mostrar}${RESET} | ${CIAN}User:${RESET} ${BLANCO}${SUDO_USER:-$USER}${RESET}"
    echo ""
    stk_header
    echo ""
}

# --- DEFINICIÓN DE PAQUETES ---
declare -A CATEGORIAS

# Apps que se instalan vía Flatpak (Flathub) por no estar en los repos oficiales
# de todas las distribuciones soportadas.
declare -A FLATPAK_APPS
FLATPAK_APPS["librewolf"]="io.gitlab.librewolf-community"
FLATPAK_APPS["google-chrome"]="com.google.Chrome"
FLATPAK_APPS["brave-browser"]="com.brave.Browser"
FLATPAK_APPS["telegram"]="org.telegram.desktop"
FLATPAK_APPS["vscode"]="com.visualstudio.code"
FLATPAK_APPS["vscodium"]="com.vscodium.codium"
FLATPAK_APPS["zed"]="dev.zed.Zed"
FLATPAK_APPS["podman-desktop"]="io.podman_desktop.PodmanDesktop"
FLATPAK_APPS["obsidian"]="md.obsidian.Obsidian"
FLATPAK_APPS["onlyoffice"]="org.onlyoffice.desktopeditors"
FLATPAK_APPS["wps-office"]="com.wps.Office"

# Herramientas que no se pueden instalar en sistemas inmutables basados en rpm-ostree.
# Se ocultan del menú para no ofrecer instalaciones que van a fallar.
declare -A INCOMPATIBLES_INMUTABLE
INCOMPATIBLES_INMUTABLE["metasploit-framework"]="No está en los repositorios de Fedora"

CATEGORIAS["escritorio_navegadores"]="
firefox|Navegador web de código abierto rápido y privado
chromium|Navegador web código abierto base de Chrome
librewolf|Navegador privado basado en Firefox, sin telemetría (Flatpak)
google-chrome|Navegador web oficial de Google (Flatpak)
brave-browser|Navegador enfocado en privacidad y bloqueo de publicidad (Flatpak)
"

CATEGORIAS["escritorio_ofimatica"]="
libreoffice|Suite ofimática completa (procesador, tablas, presentaciones)
onlyoffice|Suite ofimática compatible con formatos de Microsoft Office (Flatpak)
wps-office|Suite ofimática propietaria de Kingsoft (Flatpak)
"

CATEGORIAS["escritorio_multimedia"]="
gimp|Editor de imágenes y manipulación fotográfica avanzado
inkscape|Editor de gráficos vectoriales SVG
telegram|Cliente oficial de la mensajería Telegram (Flatpak)
vlc|Reproductor multimedia universal para audio y vídeo
mpv|Reproductor de medios ligero pero potente por línea de comandos
krita|Pintura digital, ilustración y animación 2D
audacity|Grabación y edición de audio multipista
kdenlive|Editor de vídeo no lineal
obs-studio|Grabación de pantalla y emisión en directo
yt-dlp|Descarga de vídeo y audio desde múltiples sitios web
"

CATEGORIAS["desarrollo_editores"]="
vscode|Editor Visual Studio Code (Flatpak)
vscodium|VS Code sin telemetría ni marcas de Microsoft (Flatpak)
zed|Editor moderno, rápido y colaborativo (Flatpak)
micro|Editor de texto moderno para terminal con atajos intuitivos
neovim|Editor de texto extensible basado en Vim
vim|Editor de texto clásico interactivo para terminal
kate|Editor gráfico avanzado con LSP y terminal integrada
geany|Editor ligero con funciones básicas de IDE
emacs|Editor extensible y configurable con miles de paquetes
"

CATEGORIAS["desarrollo_versiones"]="
git|Sistema de control de versiones distribuido
gh|Herramienta oficial de línea de comandos para GitHub
"

CATEGORIAS["desarrollo_contenedores"]="
docker|Plataforma de despliegue de contenedores de software
docker-compose|Herramienta para definir y ejecutar aplicaciones Docker multicontenedor
podman|Motor de contenedores sin demonio compatible con Docker
podman-compose|Alternativa a docker-compose basada en Podman
podman-desktop|Interfaz gráfica para gestionar contenedores y Podman (Flatpak)
buildah|Construcción de imágenes de contenedor OCI sin demonio
skopeo|Copia e inspección de imágenes entre registros sin demonio
distrobox|Ejecuta distribuciones GNU/Linux dentro de contenedores integrados
"

CATEGORIAS["desarrollo_lenguajes"]="
nodejs|Entorno de ejecución para JavaScript en el servidor
npm|Gestor de paquetes predeterminado para Node.js
python3|Lenguaje de programación interpretado de propósito general
python3-pip|Gestor de paquetes y librerías para Python
openjdk-jdk|Entorno de desarrollo de Java LTS (21; en Fedora 25)
golang|Lenguaje de programación de código abierto compilado y eficiente
rustc|Compilador del lenguaje de programación Rust
ruby|Lenguaje de programación dinámico y orientado a objetos
"

CATEGORIAS["sistemas_monitoreo"]="
htop|Visualizador interactivo de procesos en tiempo real
btop|Monitor de recursos del sistema en terminal con interfaz moderna
glances|Herramienta de monitorización completa en terminal
iotop-c|Monitor de uso de disco e I/O por proceso (comando iotop)
"

CATEGORIAS["sistemas_discos"]="
ncdu|Analizador de uso de disco en terminal con interfaz ncurses
duf|Utilidad mejorada para ver el espacio y uso de disco
gparted|Editor gráfico de particiones de disco
"

CATEGORIAS["sistemas_informacion"]="
inxi|Script de información completa del hardware y sistema
lshw|Listador detallado del hardware de la máquina
"

CATEGORIAS["sistemas_virtualizacion"]="
qemu|Emulador y virtualizador completo con aceleración KVM
libvirt|Demonio y herramientas de gestión de máquinas virtuales
virt-manager|Interfaz gráfica para crear y administrar máquinas virtuales
virt-install|Creación de máquinas virtuales desde la línea de comandos
virt-viewer|Visor gráfico ligero para máquinas virtuales
gnome-boxes|Máquinas virtuales sencillas con interfaz de GNOME
incus|Gestor de contenedores de sistema y máquinas virtuales (sucesor de LXD)
"

CATEGORIAS["seguridad"]="
nmap|Escáner de redes y auditoría de seguridad de puertos
masscan|Escáner masivo de puertos IP a alta velocidad (no disponible en openSUSE)
wireshark|Analizador de tráfico y protocolos de red
tcpdump|Capturador y analizador de paquetes por línea de comandos
aircrack-ng|Suite de auditoría para redes inalámbricas Wi-Fi
hashcat|Herramienta avanzada de recuperación y cracking de contraseñas
john|Cracker de contraseñas rápido y multisistema
hydra|Herramienta de ataque por fuerza bruta a servicios de red
sqlmap|Herramienta automatizada de detección y explotación de SQLi
nikto|Escáner de vulnerabilidades en servidores web
metasploit-framework|Framework para pruebas de penetración y explotación (solo Arch en repos oficiales)
clamav|Motor antivirus de código abierto para Linux
fail2ban|Prevención de intrusiones mediante bloqueo de IPs
"

CATEGORIAS["utilidades"]="
fzf|Buscador difuso interactivo por línea de comandos
ripgrep|Buscador de texto ultra rápido en archivos
fd-find|Alternativa simple, rápida y amigable al comando find (binario fdfind en Debian/Ubuntu)
bat|Clon de cat con resaltado de sintaxis y manejo de git (binario batcat en Debian/Ubuntu)
eza|Reemplazo moderno para el comando ls con colores y árbol
zoxide|Navegación rápida entre directorios frecuentes (cd mejorado)
tmux|Multiplexor de terminales para sesiones persistentes
screen|Multiplexor de terminal clásico
ranger|Gestor de archivos para terminal con atajos tipo Vim
mc|Gestor de archivos en consola de doble panel
nano|Editor de texto sencillo y directo en consola
"

CATEGORIAS["scan4me"]="
masscan|Escáner masivo de puertos IP a alta velocidad
nmap|Escáner de redes y puertos de alto rendimiento
gobuster|Bruteforce de URLs, directorios y subdominios DNS
feroxbuster|Herramienta rápida de descubrimiento recursivo de contenido web
nikto|Escáner de vulnerabilidades de servidores web
wpscan|Escáner de seguridad especializado en WordPress
sublist3r|Enumeración de subdominios mediante OSINT
subfinder|Descubrimiento pasivo de subdominios rápido
nuclei|Escáner de vulnerabilidades basado en plantillas YAML
whatweb|Reconocimiento de tecnologías web e identificación de CMS
dnsrecon|Herramienta de enumeración y reconocimiento DNS
enum4linux|Herramienta de extracción de datos de equipos SMB/Windows
smbclient|Cliente de consola para acceso a recursos compartidos SMB
snmp|Consultas y extracción de datos vía protocolo SNMP
"

CATEGORIAS["admin4me"]="
fzf|Buscador difuso interactivo
xsltproc|Procesador de hojas de estilo XSLT
host|Utilidad de búsqueda de nombres de dominio DNS
tput|Herramienta de inicialización y control de terminal
free|Visualizador del uso de memoria RAM y Swap
curl|Cliente de transferencia de datos con sintaxis URL
wget|Descargador de archivos no interactivo desde la web
tar|Utilidad para empaquetar y desempaquetar archivos
hostname|Muestra o configura el nombre del sistema
js|Intérprete de motor JavaScript
jq|Procesador y filtrador de datos JSON por terminal
rsync|Sincronización rápida y eficiente de archivos locales o remotos
crontab|Gestor de tareas programadas en tiempo real
"

CATEGORIAS["stop4me"]="
fzf|Buscador difuso interactivo para la gestión y menús
ufw|Cortafuegos simple y gestor de reglas de red
host|Utilidad para resolución DNS inversa de IPs atacantes
awk|Procesador de texto y analizador de métricas en logs
grep|Filtrador de patrones de texto para trazas de tráfico
journalctl|Consultor de registros y eventos del sistema systemd
"

CATEGORIAS["note4me"]="
obsidian|Nota y gestión de conocimiento personal (Flatpak)
ghostwriter|Editor Markdown con vista previa en vivo
"

CATEGORIAS["docker4me"]="
docker|Plataforma de contenedores
docker-compose|Herramienta de orquestación multicontenedor
"

CATEGORIAS["move4me"]="
rsync|Sincronización y transferencia de archivos
rclone|Herramienta de sincronización con almacenamiento en la nube
"

get_package_name() {
    local tool="$1"
    case "$tool" in
        "gh") [[ "$Package" == "pacman" ]] && echo "github-cli" || echo "gh" ;;
        "docker")
            case "$Package" in
                apt) echo "docker.io" ;;
                dnf) echo "moby-engine" ;;
                *) echo "docker" ;;
            esac
            ;;
        "docker-compose")
            if [[ "$Package" == "apt" && "$OS_ID" == "ubuntu" ]]; then
                echo "docker-compose-v2"
            else
                echo "docker-compose"
            fi
            ;;
        # Fedora empaqueta Node.js y npm por versión (nodejs22, nodejs22-npm...)
        "nodejs") [[ "$Package" == "zypper" ]] && echo "nodejs-default" || { [[ "$Package" == "dnf" ]] && echo "nodejs22" || echo "nodejs"; } ;;
        "npm")
            case "$Package" in
                dnf) echo "nodejs22-npm" ;;
                zypper) echo "npm-default" ;;
                *) echo "npm" ;;
            esac
            ;;
        "python3-pip") [[ "$Package" == "pacman" ]] && echo "python-pip" || echo "python3-pip" ;;
        "openjdk-jdk")
            case "$Package" in
                apt) echo "openjdk-21-jdk" ;;
                dnf) echo "java-25-openjdk-devel" ;;
                pacman) echo "jdk21-openjdk" ;;
                zypper) echo "java-21-openjdk-devel" ;;
                *) echo "openjdk-21-jdk" ;;
            esac
            ;;
        "golang") [[ "$Package" == "apt" ]] && echo "golang-go" || echo "go" ;;
        "rustc") [[ "$Package" == "apt" ]] && echo "rustc" || echo "rust" ;;
        "fd-find") [[ "$Package" == "pacman" ]] && echo "fd" || echo "fd-find" ;;
        "awk") echo "gawk" ;;
        "micro") [[ "$Package" == "zypper" ]] && echo "micro-editor" || echo "micro" ;;
        "qemu")
            case "$Package" in
                apt) echo "qemu-system-x86" ;;
                dnf) echo "qemu-kvm" ;;
                pacman) echo "qemu-full" ;;
                *) echo "qemu" ;;
            esac
            ;;
        "libvirt")
            case "$Package" in
                apt) echo "libvirt-daemon-system" ;;
                dnf) echo "libvirt-daemon-kvm" ;;
                *) echo "libvirt" ;;
            esac
            ;;
        "virt-install") [[ "$Package" == "apt" ]] && echo "virtinst" || echo "virt-install" ;;
        "journalctl") echo "systemd" ;;
        "xsltproc")
            case "$Package" in
                apt) echo "xsltproc" ;;
                zypper) echo "libxslt-tools" ;;
                *) echo "libxslt" ;;
            esac
            ;;
        "crontab") [[ "$Package" == "apt" ]] && echo "cron" || echo "cronie" ;;
        "host")
            case "$Package" in
                apt) echo "bind9-dnsutils" ;;
                pacman) echo "bind" ;;
                *) echo "bind-utils" ;;
            esac
            ;;
        "tput")
            case "$Package" in
                apt) echo "ncurses-bin" ;;
                zypper) echo "ncurses-utils" ;;
                *) echo "ncurses" ;;
            esac
            ;;
        "free") [[ "$Package" == "pacman" || "$Package" == "dnf" ]] && echo "procps-ng" || echo "procps" ;;
        "hostname") [[ "$Package" == "pacman" ]] && echo "inetutils" || echo "hostname" ;;
        "js")
            case "$Package" in
                pacman) echo "js128" ;;
                zypper) echo "nodejs-default" ;;
                *) echo "nodejs" ;;
            esac
            ;;
        "snmp") [[ "$Package" == "apt" ]] && echo "snmp" || echo "net-snmp" ;;
        "smbclient")
            case "$Package" in
                apt|pacman) echo "smbclient" ;;
                *) echo "samba-client" ;;
            esac
            ;;
        "wireshark")
            case "$Package" in
                pacman) echo "wireshark-qt" ;;
                zypper) echo "wireshark-ui-qt" ;;
                *) echo "wireshark" ;;
            esac
            ;;
        *) echo "$tool" ;;
    esac
}

instalar_github_release() {
    local repo=$1
    local binary_name=$2
    local asset_pattern=$3
    local is_tgz=${4:-false}

    echo -e "${AZUL}📥 Descargando $binary_name desde GitHub ($repo)...${RESET}"
    local download_url
    download_url=$(curl -s "https://api.github.com/repos/$repo/releases/latest" \
        | grep "browser_download_url" \
        | grep -iE "$asset_pattern" \
        | head -n 1 \
        | cut -d '"' -f 4)

    if [[ -z "$download_url" ]]; then
        echo -e "${ROJO}❌ Error al resolver release de GitHub para $binary_name.${RESET}"
        return 1
    fi

    local tmp_file="/tmp/${binary_name}_tmp"
    wget -qO "$tmp_file" "$download_url"

    if [ "$is_tgz" = true ]; then
        tar -xzf "$tmp_file" -C /usr/local/bin/ "$binary_name" 2>/dev/null || tar -xzf "$tmp_file" -C /usr/local/bin/
    else
        unzip -o -q "$tmp_file" -d /tmp/
        mv /tmp/"$binary_name" /usr/local/bin/ 2>/dev/null || true
    fi

    chmod +x "/usr/local/bin/$binary_name"
    rm -f "$tmp_file"
    echo -e "${VERDE}✅ $binary_name instalado en /usr/local/bin/${RESET}"
}

# Instala fzf como binario estático en /usr/local/bin (respaldo para inmutables sin reinicio).
instalar_fzf_binario() {
    local archivo_arch
    case "$(uname -m)" in
        x86_64) archivo_arch="linux_amd64" ;;
        aarch64|arm64) archivo_arch="linux_arm64" ;;
        *) return 1 ;;
    esac

    local url
    url=$(curl -fsSL "https://api.github.com/repos/junegunn/fzf/releases/latest" \
        | grep "browser_download_url" \
        | grep -i "${archivo_arch}.tar.gz" \
        | head -n 1 \
        | cut -d '"' -f 4)

    [ -z "$url" ] && return 1

    local tmp_dir
    tmp_dir=$(mktemp -d) || return 1

    if curl -fsSL "$url" -o "$tmp_dir/fzf.tar.gz" \
        && tar -xzf "$tmp_dir/fzf.tar.gz" -C "$tmp_dir" fzf; then
        install -m 0755 "$tmp_dir/fzf" /usr/local/bin/fzf
        rm -rf "$tmp_dir"
        return 0
    fi

    rm -rf "$tmp_dir"
    return 1
}

instalar_flatpak_base() {
    if ! command -v flatpak &>/dev/null; then
        echo -e "${AZUL}📦 Instalando Flatpak...${RESET}"
        if [ "$INMUTABLE" = true ]; then
            instalar_paquetes_inmutables flatpak || return 1
        else
            case "$Package" in
                apt) apt update -y -qq && apt install -y flatpak ;;
                dnf) dnf install -y flatpak ;;
                pacman) pacman -S --noconfirm flatpak ;;
                zypper) zypper install -y flatpak ;;
                *)
                    echo -e "${ROJO}❌ No hay un gestor compatible para instalar Flatpak.${RESET}"
                    return 1
                    ;;
            esac
        fi
    fi

    if ! command -v flatpak &>/dev/null; then
        registrar_log "$LOG_ERR" "No se pudo instalar Flatpak"
        return 1
    fi

    if ! flatpak remote-add --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo; then
        registrar_log "$LOG_ERR" "No se pudo configurar el repositorio Flathub"
        return 1
    fi

    return 0
}

instalar_flatpak_app() {
    local tool="$1"
    local app_id="${FLATPAK_APPS[$tool]}"

    if [ -z "$app_id" ]; then
        registrar_log "$LOG_ERR" "Sin ID de Flatpak para: $tool"
        return 1
    fi

    instalar_flatpak_base || return 1

    echo -e "${AZUL}   ➜ Instalando $tool desde Flathub ($app_id)...${RESET}"
    if flatpak install -y flathub "$app_id"; then
        registrar_log "$LOG_INFO" "Flatpak instalado: $tool ($app_id)"
        return 0
    else
        registrar_log "$LOG_ERR" "Error al instalar Flatpak: $tool ($app_id)"
        return 1
    fi
}

# Instala paquetes RPM en una capa de rpm-ostree (sistemas inmutables).
instalar_paquetes_inmutables() {
    local paquetes=("$@")
    [ ${#paquetes[@]} -eq 0 ] && return 0

    echo -e "\n${AZUL}🔄 Actualizando metadatos de rpm-ostree...${RESET}"
    rpm-ostree refresh-md &>/dev/null || true

    echo -e "${AZUL}📦 Instalando en una capa inmutable: ${paquetes[*]}...${RESET}"
    if rpm-ostree install --idempotent --allow-inactive --apply-live "${paquetes[@]}"; then
        echo -e "${VERDE}✅ Paquetes aplicados en la sesión actual.${RESET}"
        registrar_log "$LOG_INFO" "Paquetes instalados con rpm-ostree: ${paquetes[*]}"
        return 0
    fi

    echo -e "${AMARILLO}⚠️ No se pudo aplicar en vivo. Preparando la capa para el próximo arranque...${RESET}"
    if rpm-ostree install --idempotent --allow-inactive "${paquetes[@]}"; then
        REINICIO_REQUERIDO=true
        echo -e "${AMARILLO}🔄 Reinicia el sistema para usar los paquetes instalados.${RESET}"
        registrar_log "$LOG_INFO" "Paquetes preparados con rpm-ostree (reinicio pendiente): ${paquetes[*]}"
        return 0
    fi

    echo -e "${ROJO}❌ No se pudieron instalar los paquetes con rpm-ostree.${RESET}"
    registrar_log "$LOG_ERR" "Fallo al instalar con rpm-ostree: ${paquetes[*]}"
    return 1
}

# Asegura las herramientas que usan los instaladores externos.
preparar_dependencias_externas() {
    local herramientas=("$@")
    local dependencias=()
    local dep tool
    local necesita_gem=false
    local necesita_pip=false

    for dep in git wget curl unzip tar; do
        command -v "$dep" &>/dev/null || dependencias+=("$dep")
    done

    for tool in "${herramientas[@]}"; do
        case "$tool" in
            wpscan) necesita_gem=true ;;
            sublist3r|dnsrecon) necesita_pip=true ;;
        esac
    done

    if [ "$necesita_gem" = true ] && ! command -v gem &>/dev/null; then
        dependencias+=("$(get_package_name "ruby")")
    fi
    if [ "$necesita_pip" = true ] && ! command -v pip &>/dev/null; then
        dependencias+=("$(get_package_name "python3-pip")")
    fi

    [ ${#dependencias[@]} -eq 0 ] && return 0

    if [ "$INMUTABLE" = true ]; then
        instalar_paquetes_inmutables "${dependencias[@]}" || true
        return 0
    fi

    echo -e "${AZUL}📦 Instalando dependencias externas: ${dependencias[*]}...${RESET}"
    case "$Package" in
        "apt") apt install -y "${dependencias[@]}" ;;
        "dnf") dnf install -y "${dependencias[@]}" ;;
        "pacman") pacman -S --noconfirm "${dependencias[@]}" ;;
        "zypper") zypper install -y "${dependencias[@]}" ;;
    esac
}

instalar_paquetes() {
    local lista_raw="$1"
    local paquetes_a_instalar=()
    local paquetes_especiales=()
    local paquetes_flatpak=()

    while IFS= read -r line; do
        [ -z "$line" ] && continue
        local nombre_paquete="${line%%|*}"

        if [[ -n "${FLATPAK_APPS[$nombre_paquete]:-}" ]]; then
            paquetes_flatpak+=("$nombre_paquete")
            continue
        fi

        case "$nombre_paquete" in
            wpscan|feroxbuster|subfinder|nuclei|gobuster|whatweb|sublist3r|enum4linux|dnsrecon|nikto|sqlmap)
                paquetes_especiales+=("$nombre_paquete")
                ;;
            *)
                local pkg_real
                pkg_real=$(get_package_name "$nombre_paquete")
                paquetes_a_instalar+=("$pkg_real")
                ;;
        esac
    done <<< "$lista_raw"

    if [ ${#paquetes_a_instalar[@]} -gt 0 ]; then
        local -A vistos=()
        local paquetes_limpios=()
        local pkg
        for pkg in "${paquetes_a_instalar[@]}"; do
            [[ -n "${vistos[$pkg]:-}" ]] && continue
            vistos[$pkg]=1
            paquetes_limpios+=("$pkg")
        done
        paquetes_a_instalar=("${paquetes_limpios[@]}")
    fi

    if [ "$INMUTABLE" = true ] && grep -qE '^(docker|docker-compose)\|' <<< "$lista_raw"; then
        echo -e "\n${AMARILLO}⚠️ Docker no está soportado oficialmente en sistemas inmutables.${RESET}"
        echo -e "${CIAN}💡 Se recomienda Podman o Distrobox. Se intentará instalar en una capa rpm-ostree.${RESET}"
    fi

    if [ ${#paquetes_a_instalar[@]} -gt 0 ]; then
        if [ "$INMUTABLE" = true ]; then
            instalar_paquetes_inmutables "${paquetes_a_instalar[@]}"
        else
            echo -e "\n${AZUL}🔄 Actualizando repositorios ($Package)...${RESET}"
            case "$Package" in
                "apt") apt update -y -qq ;;
                "dnf") dnf makecache ;;
                "pacman") pacman -Sy --noconfirm ;;
                "zypper") zypper refresh ;;
            esac

            echo -e "\n${AZUL}📦 Instalando paquetes nativos...${RESET}"
            for pkg in "${paquetes_a_instalar[@]}"; do
                echo -e "${AZUL}   ➜ Instalando $pkg...${RESET}"
                local status=0
                case "$Package" in
                    "apt") apt install -y "$pkg" || status=1 ;;
                    "dnf") dnf install -y "$pkg" || status=1 ;;
                    "pacman") pacman -S --noconfirm "$pkg" || status=1 ;;
                    "zypper") zypper install -y "$pkg" || status=1 ;;
                esac

                if [ $status -eq 0 ]; then
                    registrar_log "$LOG_INFO" "Paquete instalado nativo: $pkg"
                else
                    registrar_log "$LOG_ERR" "Error al instalar nativo: $pkg"
                fi
            done
        fi
    fi

    if [ ${#paquetes_especiales[@]} -gt 0 ]; then
        echo -e "\n${MAGENTA}⚙️ Instalando herramientas especializadas/externas...${RESET}"
        preparar_dependencias_externas "${paquetes_especiales[@]}"

        for tool in "${paquetes_especiales[@]}"; do
            case "$tool" in
                "wpscan")
                    echo -e "${AZUL}💎 Instalando WPScan vía RubyGems...${RESET}"
                    gem install wpscan --no-document && registrar_log "$LOG_INFO" "wpscan instalado por gem"
                    ;;
                "feroxbuster")
                    instalar_github_release "epi052/feroxbuster" "feroxbuster" "x86_64-linux-feroxbuster.zip" false
                    ;;
                "nuclei")
                    instalar_github_release "projectdiscovery/nuclei" "nuclei" "linux_amd64.zip" false
                    ;;
                "subfinder")
                    instalar_github_release "projectdiscovery/subfinder" "subfinder" "linux_amd64.zip" false
                    ;;
                "gobuster")
                    instalar_github_release "OJ/gobuster" "gobuster" "Linux_x86_64.tar.gz" true
                    ;;
                "whatweb")
                    rm -rf /opt/whatweb
                    git clone --depth 1 https://github.com/urbanadventurer/WhatWeb.git /opt/whatweb
                    ln -sf /opt/whatweb/whatweb /usr/local/bin/whatweb
                    chmod +x /usr/local/bin/whatweb
                    ;;
                "sublist3r")
                    rm -rf /opt/sublist3r
                    git clone --depth 1 https://github.com/aboul3la/Sublist3r.git /opt/sublist3r
                    pip install --break-system-packages -r /opt/sublist3r/requirements.txt 2>/dev/null || pip install -r /opt/sublist3r/requirements.txt
                    ln -sf /opt/sublist3r/sublist3r.py /usr/local/bin/sublist3r
                    chmod +x /usr/local/bin/sublist3r
                    ;;
                "enum4linux")
                    rm -rf /opt/enum4linux
                    git clone --depth 1 https://github.com/CiscoCXSecurity/enum4linux.git /opt/enum4linux
                    ln -sf /opt/enum4linux/enum4linux.pl /usr/local/bin/enum4linux
                    chmod +x /usr/local/bin/enum4linux
                    ;;
                "dnsrecon")
                    rm -rf /opt/dnsrecon
                    git clone --depth 1 https://github.com/darkoperator/dnsrecon.git /opt/dnsrecon
                    pip install --break-system-packages -r /opt/dnsrecon/requirements.txt 2>/dev/null || pip install -r /opt/dnsrecon/requirements.txt
                    ln -sf /opt/dnsrecon/dnsrecon.py /usr/local/bin/dnsrecon
                    chmod +x /usr/local/bin/dnsrecon
                    ;;
                "nikto")
                    rm -rf /opt/nikto
                    git clone --depth 1 https://github.com/sullo/nikto.git /opt/nikto
                    ln -sf /opt/nikto/program/nikto.pl /usr/local/bin/nikto
                    chmod +x /opt/nikto/program/nikto.pl
                    registrar_log "$LOG_INFO" "nikto instalado desde git"
                    ;;
                "sqlmap")
                    rm -rf /opt/sqlmap
                    git clone --depth 1 https://github.com/sqlmapproject/sqlmap.git /opt/sqlmap
                    ln -sf /opt/sqlmap/sqlmap.py /usr/local/bin/sqlmap
                    chmod +x /opt/sqlmap/sqlmap.py
                    registrar_log "$LOG_INFO" "sqlmap instalado desde git"
                    ;;
            esac
        done
    fi

    if [ ${#paquetes_flatpak[@]} -gt 0 ]; then
        echo -e "\n${MAGENTA}🌐 Instalando aplicaciones Flatpak desde Flathub...${RESET}"
        for tool in "${paquetes_flatpak[@]}"; do
            instalar_flatpak_app "$tool" || true
        done
    fi

    if [[ " ${paquetes_a_instalar[*]} " =~ "cron" ]] || [[ " ${paquetes_a_instalar[*]} " =~ "cronie" ]]; then
        if ! systemctl enable --now cron 2>/dev/null \
            && ! systemctl enable --now cronie 2>/dev/null \
            && ! systemctl enable --now crond 2>/dev/null; then
            [ "$INMUTABLE" = true ] && \
                echo -e "${AMARILLO}⚠️ Si acabas de instalar cronie, reinicia y ejecuta: sudo systemctl enable --now crond${RESET}"
        fi
    fi

    pintar "$VERDE_BRILLANTE" "\n✔ Proceso de instalación finalizado."
}

# --- NUEVA FUNCIÓN: INSTALAR GESTORES ADICIONALES ---
menu_gestores_paquetes() {
    while true; do
        clear
        mostrar_logo
        local opciones="1. 🧊 Flatpak + Flathub  - Sistema de paquetes sandbox universal
2. 📦 Snapcraft           - Gestor de paquetes canónico (Ubuntu/Debian/Fedora)
3. 🚀 AppImage Runtime    - Soporte Fuse para ejecutables portátiles
4. 🏹 AUR Helper (yay)    - Para distros basadas en Arch Linux
0. ⬅️ Volver al menú principal"

        local seleccion
        seleccion=$(echo -e "$opciones" | stk_fzf_menu "Seleccione Gestor" "GESTORES DE PAQUETES" "15")
        [ -z "$seleccion" ] && return

        local opcion_num
        opcion_num=$(echo "$seleccion" | grep -oE '^[0-9]+')

        case "$opcion_num" in
            1)
                if instalar_flatpak_base; then
                    echo -e "${VERDE}✅ Flatpak configurado con Flathub.${RESET}"
                fi
                sleep 2
                ;;
            2)
                if [ "$INMUTABLE" = true ]; then
                    echo -e "${AMARILLO}⚠️ Snap no es compatible con sistemas inmutables basados en rpm-ostree.${RESET}"
                    echo -e "${CIAN}💡 Usa Flatpak o un contenedor Distrobox/Toolbox en su lugar.${RESET}"
                else
                    echo -e "${AZUL}📦 Instalando Snap...${RESET}"
                    case "$Package" in
                        apt) apt update && apt install -y snapd ;;
                        dnf) dnf install -y snapd && systemctl enable --now snapd.socket ;;
                        pacman) pacman -S --noconfirm snapd && systemctl enable --now snapd.socket ;;
                        zypper) zypper install -y snapd && systemctl enable --now snapd ;;
                    esac
                    ln -sf /var/lib/snapd/snap /snap 2>/dev/null || true
                    echo -e "${VERDE}✅ Snapd instalado correctamente.${RESET}"
                fi
                sleep 2
                ;;
            3)
                echo -e "${AZUL}📦 Instalando soporte FUSE para AppImage...${RESET}"
                if [ "$INMUTABLE" = true ]; then
                    if ! instalar_paquetes_inmutables fuse fuse3; then
                        sleep 2
                        continue
                    fi
                else
                    case "$Package" in
                        apt) apt update && apt install -y libfuse2 fuse3 ;;
                        dnf) dnf install -y fuse fuse3 ;;
                        pacman) pacman -S --noconfirm fuse2 fuse3 ;;
                        zypper) zypper install -y fuse fuse3 ;;
                    esac
                fi
                echo -e "${VERDE}✅ Soporte AppImage instalado.${RESET}"
                sleep 2
                ;;
            4)
                if [[ "$Package" != "pacman" ]]; then
                    echo -e "${ROJO}⚠️ 'yay' solo se puede instalar en distribuciones basadas en Arch Linux.${RESET}"
                else
                    echo -e "${AZUL}📦 Instalando dependencias e instalando yay...${RESET}"
                    pacman -S --needed --noconfirm git base-devel
                    local target_user="${SUDO_USER:-$USER}"
                    su - "$target_user" -c "cd /tmp && git clone https://aur.archlinux.org/yay.git && cd yay && makepkg -si --noconfirm"
                    echo -e "${VERDE}✅ Helper AUR 'yay' instalado correctamente.${RESET}"
                fi
                sleep 2
                ;;
            0) return ;;
        esac
    done
}

seleccionar_programas() {
    local cat_key="$1"
    local nombre_cat="$2"
    local raw_data="${CATEGORIAS[$cat_key]}"

    if [ -z "$raw_data" ]; then
        echo -e "\033[31mError: No hay datos para la categoría '$cat_key'\033[0m" >&2
        return 1
    fi

    local ocultos=0
    local nombres_ocultos=""
    if [ "$INMUTABLE" = true ]; then
        local filtrado="" linea tool
        while IFS= read -r linea; do
            [ -z "$linea" ] && continue
            tool="${linea%%|*}"
            if [[ -n "${INCOMPATIBLES_INMUTABLE[$tool]:-}" ]]; then
                ocultos=$((ocultos + 1))
                nombres_ocultos+="$tool "
                continue
            fi
            filtrado+="$linea"$'\n'
        done <<< "$raw_data"
        raw_data="$filtrado"
    fi

    if ! printf '%s\n' "$raw_data" | grep -q '[^[:space:]]'; then
        echo -e "\033[33m⚠️ No hay programas compatibles con este sistema en '$cat_key'.\033[0m" >&2
        sleep 2
        return 1
    fi

    local nota_ocultos=""
    [ "$ocultos" -gt 0 ] && nota_ocultos=" | ⚠️ No disponible(s): ${nombres_ocultos% }"

    local seleccionados
    seleccionados=$(printf '%s\n0. ⬅️ Volver|Volver al menú anterior\n' "$raw_data" \
        | sed '/^[[:space:]]*$/d' | fzf --ansi \
        --multi \
        --height=18 \
        --reverse \
        --border=rounded \
        --delimiter="|" \
        --with-nth=1 \
        --prompt="➤ Seleccione programas: " \
        --header="PROGRAMAS - $nombre_cat (TAB: Marcar | Esc/0: Volver)${nota_ocultos}" \
        --border-label=" PROGRAMAS - $nombre_cat " \
        --color="$FZF_COLORES" \
        --preview-window="right:50%:wrap" \
        --preview='
            echo -e "\033[1;36mDETALLES DEL PROGRAMA\033[0m\n"
            echo -e "\033[1;33m➜\033[0m {2..}"
        ')

    # Quitamos la opción "Volver" de la lista de programas a instalar
    seleccionados=$(printf '%s\n' "$seleccionados" | grep -v '^0\.' | sed '/^[[:space:]]*$/d')

    if [ -n "$seleccionados" ]; then
        echo "$seleccionados"
    fi
}

menu_categoria() {
    local cat_key="$1"
    local nombre_categoria="$2"
    
    clear
    mostrar_logo
    
    local seleccionados
    seleccionados=$(seleccionar_programas "$cat_key" "$nombre_categoria")
    
    if [ -n "$seleccionados" ]; then
        instalar_paquetes "$seleccionados"
        echo ""
        read -p "Presione Enter para continuar..."
    fi
}

menu_escritorio() {
    while true; do
        clear
        mostrar_logo
        local opciones="1. 🌐 NAVEGADORES  - Navegadores web
2. 📄 OFIMÁTICA     - Suite ofimática
3. 🎬 MULTIMEDIA    - Imagen, vídeo, audio y mensajería
0. ⬅️ VOLVER        - Volver al menú principal"

        local seleccion
        seleccion=$(echo -e "$opciones" | stk_fzf_menu "Seleccione Categoría" "CATEGORÍAS INSTALL4ME")

        [ -z "$seleccion" ] && return

        local opcion_num
        opcion_num=$(echo "$seleccion" | grep -oE '^[0-9]+')

        case "$opcion_num" in
            1) menu_categoria "escritorio_navegadores" "Navegadores" ;;
            2) menu_categoria "escritorio_ofimatica" "Ofimática" ;;
            3) menu_categoria "escritorio_multimedia" "Multimedia" ;;
            0) return ;;
            *) echo "Opción no válida"; sleep 1 ;;
        esac
    done
}

menu_desarrollo() {
    while true; do
        clear
        mostrar_logo
        local opciones="1. 📝 EDITORES      - Editores de código y terminal
2. 🔀 VERSIONES     - Git y GitHub CLI
3. 🐳 CONTENEDORES  - Docker y Docker Compose
4. 💻 LENGUAJES     - Runtimes, compiladores y gestores
0. ⬅️ VOLVER        - Volver al menú principal"

        local seleccion
        seleccion=$(echo -e "$opciones" | stk_fzf_menu "Seleccione Categoría" "CATEGORÍAS INSTALL4ME")

        [ -z "$seleccion" ] && return

        local opcion_num
        opcion_num=$(echo "$seleccion" | grep -oE '^[0-9]+')

        case "$opcion_num" in
            1) menu_categoria "desarrollo_editores" "Editores" ;;
            2) menu_categoria "desarrollo_versiones" "Versiones" ;;
            3) menu_categoria "desarrollo_contenedores" "Contenedores" ;;
            4) menu_categoria "desarrollo_lenguajes" "Lenguajes" ;;
            0) return ;;
            *) echo "Opción no válida"; sleep 1 ;;
        esac
    done
}

menu_sistemas() {
    while true; do
        clear
        mostrar_logo
        local opciones="1. 📊 MONITOREO     - Procesos y recursos en tiempo real
2. 💾 DISCOS        - Análisis, espacio y particiones
3. 🔎 INFORMACIÓN   - Hardware y datos del sistema
4. 🧩 VIRTUALIZACIÓN - Máquinas virtuales y contenedores de sistema
0. ⬅️ VOLVER        - Volver al menú principal"

        local seleccion
        seleccion=$(echo -e "$opciones" | stk_fzf_menu "Seleccione Categoría" "CATEGORÍAS INSTALL4ME")

        [ -z "$seleccion" ] && return

        local opcion_num
        opcion_num=$(echo "$seleccion" | grep -oE '^[0-9]+')

        case "$opcion_num" in
            1) menu_categoria "sistemas_monitoreo" "Monitoreo" ;;
            2) menu_categoria "sistemas_discos" "Discos" ;;
            3) menu_categoria "sistemas_informacion" "Información" ;;
            4) menu_categoria "sistemas_virtualizacion" "Virtualización" ;;
            0) return ;;
            *) echo "Opción no válida"; sleep 1 ;;
        esac
    done
}

menu_all4me() {
    while true; do
        clear
        mostrar_logo
        local opciones="1. 🔍 SCAN4ME    - Herramientas de escaneo y auditoría
2. ⚙️  ADMIN4ME   - Herramientas de administración de sistemas
3. 🛑 STOP4ME    - Herramientas de seguridad y bloqueo
4. 📝 NOTE4ME    - Notas y documentación
5. 🐳 DOCKER4ME  - Contenedores y orquestación
6. 🔄 MOVE4ME    - Transferencia y sincronización
0. ⬅️ VOLVER     - Volver al menú principal"

        local seleccion
        seleccion=$(echo -e "$opciones" | stk_fzf_menu "Seleccione Opción" "INSTALL4ME")

        [ -z "$seleccion" ] && return

        local opcion_num
        opcion_num=$(echo "$seleccion" | grep -oE '^[0-9]+')

        case "$opcion_num" in
            1) menu_categoria "scan4me" "Scan4Me" ;;
            2) menu_categoria "admin4me" "Admin4Me" ;;
            3) menu_categoria "stop4me" "Stop4Me" ;;
            4) menu_categoria "note4me" "Note4Me" ;;
            5) menu_categoria "docker4me" "Docker4Me" ;;
            6) menu_categoria "move4me" "Move4Me" ;;
            0) return ;;
            *) echo "Opción no válida"; sleep 1 ;;
        esac
    done
}

menu_principal() {
    while true; do
        clear
        mostrar_logo
        
        local opciones="1. 🖥️  ESCRITORIO      - Navegadores, ofimática, multimedia
2. 🔧  DESARROLLO      - Editores, compiladores, lenguajes
3. 🛠️  SISTEMAS        - Monitoreo, administración, diagnóstico
4. 🔒  SEGURIDAD       - Herramientas de seguridad y auditoría
5. 📦  UTILIDADES      - Herramientas generales del sistema
6. 🚀  ALL4ME          - Paquetes necesarios incluidos en cada programa personal
7. 🍱  GESTORES PKG    - Instalar Flatpak, Snap, AppImage o AUR (yay)
0. ❌  SALIR           - Salir del script"

        local seleccion
        seleccion=$(echo -e "$opciones" | stk_fzf_menu "Seleccione Opción" "INSTALL4ME")

        [ -z "$seleccion" ] && salir

        local opcion_num
        opcion_num=$(echo "$seleccion" | grep -oE '^[0-9]+')

        case "$opcion_num" in
            1) menu_escritorio ;;
            2) menu_desarrollo ;;
            3) menu_sistemas ;;
            4) menu_categoria "seguridad" "Seguridad" ;;
            5) menu_categoria "utilidades" "Utilidades" ;;
            6) menu_all4me ;;
            7) menu_gestores_paquetes ;;
            0) salir ;;
            *) echo "Opción no válida"; sleep 1 ;;
        esac
    done
}

salir() {
    echo ""
    if [ "$REINICIO_REQUERIDO" = true ]; then
        pintar "$AMARILLO_BRILLANTE" "  ⚠️ Hay cambios de rpm-ostree pendientes. Reinicia el sistema."
        echo ""
    fi
    stk_salir "INSTALL4ME" "Saliendo de Install4Me..."
}
trap salir SIGINT SIGTERM

if ! command -v fzf &>/dev/null; then
    echo -e "${AMARILLO}⚠️  fzf no está instalado. Instalando...${RESET}"
    if [ "$INMUTABLE" = true ]; then
        instalar_paquetes_inmutables fzf || true
        if ! command -v fzf &>/dev/null; then
            echo -e "${AMARILLO}⚠️ fzf aún no está disponible; instalando binario estático en /usr/local/bin...${RESET}"
            instalar_fzf_binario || true
            hash -r 2>/dev/null
        fi
    else
        case "$Package" in
            "apt") apt update -y && apt install -y fzf ;;
            "dnf") dnf install -y fzf ;;
            "pacman") pacman -Sy --noconfirm fzf ;;
            "zypper") zypper install -y fzf ;;
        esac
    fi
    if ! command -v fzf &>/dev/null; then
        echo -e "${ROJO}❌ No se pudo instalar fzf. El script requiere fzf para funcionar correctamente.${RESET}"
        exit 1
    fi
fi

menu_principal "$@"