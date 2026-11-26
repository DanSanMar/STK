#!/bin/bash

# ==============================================================================
# 1. CONFIGURACIÓN Y CONSTANTES
# ==============================================================================

# --- INFORMACIÓN DEL PROYECTO ---
# La versión se toma de stk_ui_lib.sh (STK_VERSION), fuente única del ecosistema.
DESCRIPCION="Herramienta integral de mantenimiento para Linux"
AUTOR="DanSanMar"

# --- CONFIGURACIÓN DE COLORES (Normalizados) ---
RESET='\e[0m'
NEGRITA='\e[1m'
VERDE_BRILLANTE='\e[92m'
VERDE='\e[32m'
AMARILLO='\e[33m'
AMARILLO_BRILLANTE='\e[93m'
AZUL='\e[34m'
AZUL_BRILLANTE='\e[94m'
AZUL_OSCURO='\e[0;34m'
AZUL_CLARO='\e[38;5;117m'
CIAN='\e[36m'
CIAN_BRILLANTE='\e[96m'
MAGENTA='\e[35m'
ROJO='\e[31m'
ROJO_BRILLANTE='\e[91m'
BLANCO='\e[97m'

# Paleta común para todos los menús FZF de STK (estilo PROC4ME)
FZF_COLORES="border:#ff5555,pointer:#92ff92,header:#5fb2ff,label:#5fb2ff,prompt:#5fb2ff,marker:#92ff92"

# --- CONFIGURACIÓN DE LOGS ---
LOG_FILE="/var/log/stk_mantenimiento.log"
# Niveles de severidad
LOG_INFO="INFO"
LOG_WARN="WARN"
LOG_ERR="ERROR"

DATE=$(date +"%d/%m/%Y")

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Biblioteca compartida: estética + capa de compatibilidad (terminfo/fzf/TTY).
if [ -r "$SCRIPT_DIR/stk_header.sh" ]; then
    # shellcheck source=stk_header.sh
    source "$SCRIPT_DIR/stk_header.sh"
fi

# Librerías compartidas: se cargan después de stk_header.sh para que
# las versiones de STK sobreescriban pintar() y stk_fzf_menu().
if [ -r "$SCRIPT_DIR/stk_ui_lib.sh" ]; then
    source "$SCRIPT_DIR/stk_ui_lib.sh"
fi
if [ -r "$SCRIPT_DIR/stk_menu_lib.sh" ]; then
    source "$SCRIPT_DIR/stk_menu_lib.sh"
fi

V="${STK_VERSION:-7.0.0}"

# Directorio temporal privado (700) para caché y sockets de esta ejecución.
# stk_elegir_tmp prueba TMPDIR, XDG_RUNTIME_DIR, /run/user, /dev/shm y /tmp.
stk_elegir_tmp >/dev/null
STK_TMP_DIR="$STK_TMP_DIR_ELEGIDO"
if [ -d "$STK_TMP_DIR" ]; then
    trap 'rm -rf "$STK_TMP_DIR"' EXIT
else
    STK_TMP_DIR="${TMPDIR:-/tmp}"
fi

# Sanitiza TERM y sondea fzf/curl/TTY antes de cualquier stk_limpiar o menú.
stk_caps_init

# ==============================================================================
# 2. CAPA DE UI & HELPERS
# ==============================================================================

# ------------------------------------------------------------------------------
# CONTRATO DE UI DE STK (aplicar a todo el script y a futuros módulos)
# ------------------------------------------------------------------------------
# Colores: usar siempre las variables declaradas en el Bloque 1. No escribir
#          secuencias ANSI nuevas. Para imprimir: pintar "$COLOR" "mensaje".
# Separador: línea de "━" con el color AMARILLO y RESET al final.
# Logo: mostrar_logo() al entrar en un módulo; logo_texto() dentro de fzf.
# Menús: opciones con formato "N. Texto"; la última es siempre "↩ Volver".
#         La selección se parsea con ${seleccion%%.*} o ${seleccion:0:1}.
# Selector: un único wrapper de fzf (stk_fzf) con tres estilos definidos:
#           "marco" (menú principal), "preview" (submenús) y "simple" (listas).
#           fzf_estilo() y stk_fzf_menu() son los wrappers públicos actuales.
# Cancelación: si fzf devuelve $? != 0, o la selección está vacía o contiene
#              "Volver", se vuelve al nivel anterior. Nunca se usa exit salvo
#              en los flags -m/-v y en salir().
# Pausas: usar stk_volver_menu() con el texto exacto de la pausa; evitar
#         read -p suelto en código nuevo.
# Arranque de módulo: stk_iniciar_modulo() agrupa trap + stk_limpiar + logo.
# Bitácora: registrar_log con LOG_INFO / LOG_WARN / LOG_ERR para toda acción
#           que modifique el sistema.
# ------------------------------------------------------------------------------
# CONTRATO DE ARQUITECTURA Y MÓDULOS (stk.sh)
# ------------------------------------------------------------------------------
# Modelo híbrido: stk.sh es el orquestador; *4me.sh/stk_cron.sh son herramientas
# independientes; stk_*_lib.sh es infra compartida estable (pocas, con contrato).
# No crear micro-archivos por estética: dividir solo con frontera clara.
#
# Lanzamiento de módulos externos: usar SIEMPRE stk_ejecutar_modulo/wrappers.
#   - Resolución estricta: $SCRIPT_DIR/${nombre}.sh (sin fallback PATH).
#   - Ejecución local: bash "$dir/${nombre}.sh" "$@" (no depende de +x).
#   - Modo normal: menús/secuenciales; no toca traps del padre.
#   - Modo tui: monitores/alt-screen; padre absorbe SIGINT/SIGTERM con trap ':'
#     y restaura trap salir SIGINT SIGTERM al volver. El hijo hereda SIG_DFL.
#   - No pasar nombres de módulo construidos desde input de usuario; wrappers
#     con literales fijos.
#
# Traps: el handler global de STK es `trap salir SIGINT SIGTERM`. No usar trap -
# para restaurarlo. Las funciones con trap temporal deben restaurar el handler
# correcto antes de salir/return.
#
# Retornos: funciones internas usan return 0/1; exit solo en entrada/salir/flags.
# Errores: mensaje visible, registrar_log LOG_ERR cuando proceda, no silenciar.
# Globales: minimizar dependencia implícita; en fronteras usar ${VAR:-default}.
# ------------------------------------------------------------------------------

_metrica_color() {
    local valor="$1" sufijo="$2" aviso="$3" critico="$4"
    local color icono

    if [[ ! "$valor" =~ ^[0-9]+$ ]]; then
        printf '%sN/D%s' "${AZUL}" "${RESET}"
        return
    fi

    if [ "$valor" -gt "$critico" ]; then
        color="${ROJO_BRILLANTE}"
        icono="${ROJO_BRILLANTE}⚠${RESET}"
    elif [ "$valor" -gt "$aviso" ]; then
        color="${AMARILLO_BRILLANTE}"
        icono="${AMARILLO_BRILLANTE}⚠${RESET}"
    else
        color="${VERDE_BRILLANTE}"
        icono="${VERDE_BRILLANTE}✔${RESET}"
    fi

    printf '%s%s%s %s' "$color" "$valor" "$sufijo" "$icono"
}

uptime_legible() {
    local seg
    read -r seg _ < /proc/uptime 2>/dev/null
    [[ "$seg" =~ ^[0-9]+ ]] || { echo "N/D"; return; }
    seg=${seg%.*}
    local d=$((seg / 86400)) h=$(((seg % 86400) / 3600)) m=$(((seg % 3600) / 60))
    if [ "$d" -gt 0 ]; then
        echo "${d}d ${h}h"
    elif [ "$h" -gt 0 ]; then
        echo "${h}h ${m}m"
    else
        echo "${m}m"
    fi
}

mostrar_dashboard_rapido() {
    local carga ram_txt ram_pct disco temp

    carga=$(carga_sistema)
    ram_txt=$(memoria_ram)
    disco=$(uso_disco_raiz)
    temp=$(temperatura_maxima)

    # memoria_ram devuelve "X.Y/Z.Y GB (P%)"; nos quedamos con el porcentaje.
    ram_pct=$(printf '%s' "$ram_txt" | sed -n 's/.*(\([0-9][0-9]*\)%).*/\1/p')
    [[ "$ram_pct" =~ ^[0-9]+$ ]] || ram_pct="N/D"

    # Umbrales tipo dash4me:
    #   CPU/disco: verde <=60, naranja 61-85, rojo >85
    #   RAM:       verde <=65, naranja 66-85, rojo >85
    #   Temp:      verde <=75, naranja 76-85, rojo >85
    echo -e " ${AMARILLO}Carga:${RESET} $(_metrica_color "$carga" '%' 60 85)   ${AMARILLO}RAM:${RESET} $(_metrica_color "$ram_pct" '%' 65 85)   ${AMARILLO}Disco /:${RESET} $(_metrica_color "$disco" '%' 60 85)   ${AMARILLO}Temp:${RESET} $(_metrica_color "$temp" '°C' 75 85)"
}

# ==============================================================================
# 3. CAPA DE UTILIDADES (CORE)
# ==============================================================================

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
        stk_limpiar
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
            stk_mostrar_exito "✔ Archivo creado e inicializado correctamente." "Presione Enter para volver..."
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
        [ "$MODO_SILENCIOSO" != "silencioso" ] && pintar "$AMARILLO" "⚠️ El archivo excede el límite. Procediendo con la rotación..."

        # La bitácora es el único registro persistente del modo auto: se
        # conserva el historial anterior en .1 en lugar de descartarlo.
        mv -f "$LOG_FILE" "${LOG_FILE}.1" 2>/dev/null
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] [INFO] - Bitácora rotada al superar ${MAX_SIZE} KB (tamaño anterior: ${SIZE} KB). Historial previo: ${LOG_FILE}.1." > "$LOG_FILE"
        chmod 640 "$LOG_FILE" "${LOG_FILE}.1" 2>/dev/null

        if [ "$MODO_SILENCIOSO" != "silencioso" ]; then
            pintar "$VERDE_BRILLANTE" "✔ Bitácora rotada; historial conservado en ${LOG_FILE}.1"
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
    stk_limpiar
    mostrar_logo

    if [ -f "$LOG_FILE" ]; then
        pintar "$CIAN" "--- BITÁCORA GENERAL (últimas 20 entradas) ---"
        pintar "$AZUL" "Incluye todos los eventos registrados por STK."
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

ver_logs_actualizaciones() {
    stk_limpiar
    mostrar_logo

    if [ -f "$LOG_FILE" ]; then
        pintar "$CIAN" "--- LOGS DE ACTUALIZACIONES (últimas 20 coincidencias) ---"
        pintar "$AZUL" "Vista filtrada: solo entradas relacionadas con actualizaciones de paquetes/sistema."
        echo -e "${AMARILLO}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
        local coincidencias
        # Filtramos por "actualizaci" para capturar Actualización, actualización y ACTUALIZACIÓN
        coincidencias=$(grep -i 'actualizaci' "$LOG_FILE" | tail -n 20)
        if [ -n "$coincidencias" ]; then
            echo "$coincidencias" | awk '
                /\[INFO\]/ {print "\033[32m" $0 "\033[0m"}
                /\[WARN\]/ {print "\033[33m" $0 "\033[0m"}
                /\[ERROR\]/ {print "\033[31m" $0 "\033[0m"}
            '
        else
            pintar "$AMARILLO" "No hay registros de actualizaciones en la bitácora."
        fi
    else
        pintar "$ROJO" "Aún no hay registros."
    fi
    echo ""
    read -p "Presione Enter para volver..."
}

get_package_name() {
    local tool="$1"

    case "$tool" in
        "fzf")
            echo "$tool"
            ;;
        "xsltproc")
            case "$Package" in
                apt)    echo "xsltproc" ;;
                pacman) echo "libxslt" ;;
                dnf)    echo "libxslt" ;;
                zypper) echo "libxslt-tools" ;;
                *)      echo "$tool" ;;
            esac
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
            case "$Package" in
                apt)    echo "ncurses-bin" ;;
                zypper) echo "ncurses-utils" ;;
                *)      echo "ncurses" ;;
            esac
            ;;
        "free")
            case "$Package" in
                apt)    echo "procps" ;;
                pacman) echo "procps-ng" ;;
                dnf)    echo "procps-ng" ;;
                zypper) echo "procps" ;;
                *)      echo "$tool" ;;
            esac
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
                dnf)    echo "nodejs" ;; # Cambiado de mozjs115 a nodejs, pero mantenemos la lógica por si cambia
                *)      echo "nodejs" ;;
            esac
            ;;
        *)
            echo "$tool"
            ;;
    esac
}

crear_enlace_js() {
    command -v js &>/dev/null && return 0

    local candidatos=(js128 js115 qjs gjs node nodejs)
    local target target_path
    for target in "${candidatos[@]}"; do
        target_path=$(command -v "$target" 2>/dev/null) || continue
        echo -e "${AMARILLO}🔗 Creando enlace de compatibilidad para 'js' -> $target_path${RESET}"

        if [ -d /usr/local/bin ] && [ -w /usr/local/bin ]; then
            ln -sf "$target_path" /usr/local/bin/js
        fi
        # En sistemas inmutables /usr/bin es de solo lectura: se omite.
        if [ "$IMMUTABLE" != true ] && [ -w /usr/bin ]; then
            ln -sf "$target_path" /usr/bin/js 2>/dev/null
        fi

        hash -r 2>/dev/null
        return 0
    done

    return 1
}

install_tools() {
    local tools_to_install=("$@")
    local tool pkg
    local paquetes=()

    # Traducir herramientas a paquetes y evitar duplicados
    for tool in "${tools_to_install[@]}"; do
        pkg=$(get_package_name "$tool")
        [[ " ${paquetes[*]} " == *" $pkg "* ]] || paquetes+=("$pkg")
    done

    # --- SISTEMAS INMUTABLES (Fedora Silverblue/Kinoite/COSMIC, CoreOS...) ---
    if [ "$IMMUTABLE" = true ]; then
        echo -e "\n${AZUL}🔄 Actualizando metadatos de rpm-ostree...${RESET}"
        rpm-ostree refresh-md &>/dev/null || true

        echo -e "${AZUL}📦 Instalando en una capa inmutable: ${paquetes[*]}...${RESET}"
        if rpm-ostree install --idempotent --allow-inactive --apply-live "${paquetes[@]}"; then
            echo -e "${VERDE_BRILLANTE}✔ Paquetes aplicados en la sesión actual.${RESET}"
        else
            echo -e "${AMARILLO}⚠️ No se pudo aplicar en vivo. Preparando la capa para el próximo arranque...${RESET}"
            if rpm-ostree install --idempotent --allow-inactive "${paquetes[@]}"; then
                REINICIO_REQUERIDO=true
                echo -e "${AMARILLO}🔄 Reinicia el sistema para usar las herramientas instaladas.${RESET}"
                if [[ " ${tools_to_install[*]} " =~ " crontab " ]]; then
                    echo -e "${AMARILLO}📅 Tras reiniciar, habilita cron: sudo systemctl enable --now crond${RESET}"
                fi
            else
                pintar "$ROJO" "❌ No se pudieron instalar los paquetes con rpm-ostree."
                registrar_log "$LOG_ERR" "Fallo al instalar dependencias con rpm-ostree: ${paquetes[*]}"
                return 1
            fi
        fi

        if [[ " ${tools_to_install[*]} " =~ " crontab " ]]; then
            systemctl enable --now crond &>/dev/null || true
        fi
        return 0
    fi

    # --- SISTEMAS TRADICIONALES ---
    echo -e "\n${AZUL}🔄 Actualizando repositorios ($Package)...${RESET}"
    case "$Package" in
        "apt") apt update -y ;;
        "dnf") dnf makecache ;;
        "pacman") pacman -Sy ;;
        "zypper") zypper refresh ;;
    esac

    for pkg in "${paquetes[@]}"; do
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
    stk_limpiar
    local pkg_upper
    pkg_upper=$(echo "$Package" | tr '[:lower:]' '[:upper:]')

    if [ "$IMMUTABLE" = true ]; then
        pkg_upper="RPM-OSTREE / SISTEMA INMUTABLE"
    fi

    echo -e "\n${AZUL}══════════════════════════════════════════════════${RESET}"
    echo -e "${BLANCO} 📖 GUÍA DE INSTALACIÓN MANUAL PARA TU SISTEMA (${pkg_upper})${RESET}"
    echo -e "${AZUL}══════════════════════════════════════════════════${RESET}\n"

    if [ "$IMMUTABLE" = true ]; then
        local tool pkg
        local paquetes=()
        for tool in "${missing_tools[@]}"; do
            pkg=$(get_package_name "$tool")
            [[ " ${paquetes[*]} " == *" $pkg "* ]] || paquetes+=("$pkg")

            if [[ "$tool" != "$pkg" ]]; then
                echo -e "${AMARILLO}🛠  Comando faltante: ${BLANCO}$tool${AMARILLO} (Paquete: ${BLANCO}$pkg${AMARILLO})${RESET}"
            else
                echo -e "${AMARILLO}🛠  Herramienta: ${BLANCO}$tool${RESET}"
            fi
        done
        echo -e "${AZUL}--------------------------------------------------${RESET}"
        echo -e "${AMARILLO}📦 Instala todo en una sola capa:${RESET}"
        echo -e "   ${VERDE}sudo rpm-ostree install --idempotent --allow-inactive ${paquetes[*]}${RESET}"
        echo -e "   ${VERDE}sudo systemctl reboot${RESET}"
        echo ""
        echo -e "${AMARILLO}⚡ O aplica en vivo (si tu rpm-ostree lo soporta):${RESET}"
        echo -e "   ${VERDE}sudo rpm-ostree install --idempotent --allow-inactive --apply-live ${paquetes[*]}${RESET}"
        echo ""
        echo -e "${CIAN}💡 Alternativa: ejecuta STK dentro de un Toolbox/Distrobox de Fedora.${RESET}"
        if [[ " ${missing_tools[*]} " =~ " crontab " ]]; then
            echo -e "${AMARILLO}📅 Tras reiniciar, habilita cron:${RESET} ${VERDE}sudo systemctl enable --now crond${RESET}"
        fi
        echo -e "${AZUL}--------------------------------------------------${RESET}"
        return
    fi

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

comprobar_salida_internet() {
    SALIDA_RED=""
    SALIDA_RED_LATENCIA=""

    # 1. TCP al puerto DNS de Cloudflare (útil si ICMP está filtrado)
    if command -v nc &>/dev/null && nc -zw1 1.1.1.1 53 &>/dev/null; then
        SALIDA_RED="1.1.1.1:53"
        return 0
    fi

    # 2. ICMP a Google (más fiable que 1.1.1.1 en muchas redes)
    if command -v ping &>/dev/null; then
        local ping_out
        ping_out=$(LC_ALL=C ping -c 1 -w 2 -n 8.8.8.8 2>/dev/null)
        if [ $? -eq 0 ]; then
            SALIDA_RED="8.8.8.8"
            SALIDA_RED_LATENCIA=$(printf '%s\n' "$ping_out" | sed -n 's/.*time=\([0-9.]*\).*/\1/p' | head -n1)
            return 0
        fi
    fi

    # 3. HTTP como último recurso
    if command -v curl &>/dev/null && curl -sI --connect-timeout 2 --max-time 5 http://www.google.com &>/dev/null; then
        SALIDA_RED="HTTP"
        return 0
    fi

    return 1
}

formato_bytes() {
    local b="${1:-0}"
    [[ "$b" =~ ^[0-9]+$ ]] || b=0
    if [ "$b" -ge 1073741824 ]; then
        LC_ALL=C awk -v b="$b" 'BEGIN { printf "%.2f GB", b / 1073741824 }'
    elif [ "$b" -ge 1048576 ]; then
        LC_ALL=C awk -v b="$b" 'BEGIN { printf "%.1f MB", b / 1048576 }'
    elif [ "$b" -ge 1024 ]; then
        LC_ALL=C awk -v b="$b" 'BEGIN { printf "%.1f KB", b / 1024 }'
    else
        printf '%s B' "$b"
    fi
}

tipo_interfaz() {
    local iface="$1"
    case "$iface" in
        lo) echo "Loopback" ;;
        wl*) echo "Wi-Fi" ;;
        en*|eth*) echo "Ethernet" ;;
        virbr*|docker*|br-*|veth*|vmnet*|vboxnet*) echo "Virtual" ;;
        tun*|tap*|wg*|tailscale*|zt*) echo "VPN" ;;
        *)
            if [ -d "/sys/class/net/$iface/wireless" ]; then
                echo "Wi-Fi"
            else
                echo "Red"
            fi
            ;;
    esac
}

prioridad_interfaz() {
    case "$(tipo_interfaz "$1")" in
        Ethernet|Wi-Fi) echo 0 ;;
        VPN) echo 1 ;;
        Red) echo 2 ;;
        Virtual) echo 3 ;;
        *) echo 4 ;;
    esac
}

campo_red() {
    printf ' %b➤ %-17s%b %b\n' "$AMARILLO" "$1" "$RESET" "$2"
}

# ==============================================================================
# 4. MÓDULOS DE ACCIÓN
# ==============================================================================

temperatura_maxima() {
    local max=0 z t
    for z in /sys/class/thermal/thermal_zone*/temp; do
        [ -r "$z" ] || continue
        t=$(cat "$z" 2>/dev/null)
        [[ "$t" =~ ^[0-9]+$ ]] || continue
        # Descartar valores irreales de sensores sin calibrar
        [ "$t" -ge 1000 ] && [ "$t" -le 120000 ] || continue
        [ "$t" -gt "$max" ] && max="$t"
    done

    if [ "$max" -gt 0 ]; then
        echo $((max / 1000))
        return
    fi

    if command -v sensors &>/dev/null; then
        local salida
        salida=$(sensors 2>/dev/null | awk '
            /°C/ {
                for (i = 1; i <= NF; i++) {
                    if ($i ~ /^\+[0-9.,]+°C$/) {
                        v = $i
                        gsub(/[+°C]/, "", v)
                        gsub(/,/, ".", v)
                        if (v + 0 > max && v + 0 < 120) max = v + 0
                        break
                    }
                }
            }
            END { if (max > 0) printf "%.0f", max; else print "N/D" }
        ')
        echo "${salida:-N/D}"
    else
        echo "N/D"
    fi
}

carga_sistema() {
    # Uso de CPU en % calculado con dos lecturas de /proc/stat (estilo dash4me).
    # Barato: 0.1 s y solo lecturas de /proc; el dashboard lo cachea 15 s.
    local campos f total1 total2 idle1 idle2 dt di pct
    read -r campos < /proc/stat 2>/dev/null || { echo "N/D"; return; }
    read -r -a f <<< "$campos"
    idle1=${f[4]:-0}
    total1=$(( ${f[1]:-0} + ${f[2]:-0} + ${f[3]:-0} + ${f[4]:-0} + ${f[5]:-0} + ${f[6]:-0} + ${f[7]:-0} + ${f[8]:-0} ))

    sleep 0.1

    read -r campos < /proc/stat 2>/dev/null || { echo "N/D"; return; }
    read -r -a f <<< "$campos"
    idle2=${f[4]:-0}
    total2=$(( ${f[1]:-0} + ${f[2]:-0} + ${f[3]:-0} + ${f[4]:-0} + ${f[5]:-0} + ${f[6]:-0} + ${f[7]:-0} + ${f[8]:-0} ))

    dt=$((total2 - total1))
    di=$((idle2 - idle1))
    if [ "$dt" -gt 0 ]; then
        pct=$(( (dt - di) * 100 / dt ))
    else
        pct=0
    fi
    [ "$pct" -lt 0 ] && pct=0
    echo "$pct"
}

memoria_ram() {
    local clave valor total=0 disponible=0 memfree=0 buffers=0 cached=0
    while read -r clave valor _; do
        case "$clave" in
            MemTotal:)     total=$valor ;;
            MemAvailable:) disponible=$valor ;;
            MemFree:)      memfree=$valor ;;
            Buffers:)      buffers=$valor ;;
            Cached:)       cached=$valor ;;
        esac
    done < /proc/meminfo 2>/dev/null

    # Kernels antiguos sin MemAvailable: aproximación con MemFree + Buffers + Cached.
    [ "$disponible" -gt 0 ] || disponible=$((memfree + buffers + cached))

    if [ "${total:-0}" -le 0 ]; then
        echo "N/D"
        return
    fi

    local usada=$((total - disponible))
    local pct=$((usada * 100 / total))
    local u_ent=$((usada / 1048576)) u_dec=$(((usada % 1048576) * 10 / 1048576))
    local t_ent=$((total / 1048576)) t_dec=$(((total % 1048576) * 10 / 1048576))
    printf '%d.%d/%d.%d GB (%d%%)' "$u_ent" "$u_dec" "$t_ent" "$t_dec" "$pct"
}

uso_disco_raiz() {
    local uso
    uso=$(df -P / 2>/dev/null | awk 'NR == 2 {gsub(/%/, "", $5); print $5}')
    [[ "$uso" =~ ^[0-9]+$ ]] && echo "$uso" || echo "N/D"
}

reverse_shell_alerta() {
    # Busca intérpretes con sockets establecidos: patrón típico de reverse shell.
    local procesos total

    if ! command -v ss &>/dev/null; then
        echo "N/D"
        return
    fi

    procesos=$(ss -tupn state established 2>/dev/null \
        | sed -n 's/.*users:(("\([^"]*\)".*/\1/p' \
        | grep -Eix 'bash|sh|dash|zsh|ksh|python|python[0-9.]*|perl|php|ruby|nc|ncat|socat')

    total=$(printf '%s\n' "$procesos" | awk 'NF {n++} END {print n+0}')

    if [ "$total" -gt 0 ]; then
        echo "⚠ ${total} sospechosa(s)"
    else
        echo "ok"
    fi
}

mostrar_dashboard_seguridad() {
    local ok="${VERDE_BRILLANTE}" bad="${ROJO_BRILLANTE}" nd="${AZUL}"
    local fallos fw ssh red

    # Servicios fallidos: solo ✔ en verde si están todos bien, ⚠ en rojo si no.
    if command -v systemctl &>/dev/null; then
        local salida_fallos n_fallos
        if salida_fallos=$(systemctl list-units --state=failed --no-legend --plain 2>/dev/null); then
            n_fallos=$(printf '%s\n' "$salida_fallos" | awk 'NF {n++} END {print n+0}')
            if [ "$n_fallos" -eq 0 ]; then
                fallos="${ok}✔${RESET}"
            else
                fallos="${bad}⚠ ${n_fallos} fallidos${RESET}"
            fi
        else
            fallos="${nd}N/D${RESET}"
        fi
    else
        fallos="${nd}N/D${RESET}"
    fi

    # Firewall: UFW, firewalld, nftables o iptables
    if comprobar_firewall; then
        fw="${ok}✔${RESET}"
    elif command -v ufw &>/dev/null || command -v firewall-cmd &>/dev/null \
        || command -v nft &>/dev/null || command -v iptables &>/dev/null; then
        fw="${bad}⚠${RESET}"
    else
        fw="${nd}N/D${RESET}"
    fi

    # SSH
    local ssh_activo=false
    if command -v systemctl &>/dev/null; then
        systemctl is-active --quiet ssh 2>/dev/null && ssh_activo=true
        systemctl is-active --quiet sshd 2>/dev/null && ssh_activo=true
    fi
    [ "$ssh_activo" = false ] && pgrep -x sshd >/dev/null 2>&1 && ssh_activo=true
    if [ "$ssh_activo" = true ]; then
        ssh="${ok}✔${RESET}"
    else
        ssh="${bad}⚠${RESET}"
    fi

    # Conexión: ruta por defecto + salida a Internet (misma comprobación que el menú de red)
    local hay_ruta=false
    if command -v ip &>/dev/null; then
        ip route 2>/dev/null | grep -q '^default' && hay_ruta=true
    elif command -v route &>/dev/null; then
        route -n 2>/dev/null | grep -q '^0\.0\.0\.0' && hay_ruta=true
    else
        hay_ruta=true
    fi

    if [ "$hay_ruta" = true ] && comprobar_salida_internet; then
        red="${ok}✔${RESET}"
    else
        red="${bad}⚠ sin red${RESET}"
    fi

    echo -e " ${AMARILLO}Servicios:${RESET} ${fallos}  ${AMARILLO}Firewall:${RESET} ${fw}  ${AMARILLO}SSH:${RESET} ${ssh}  ${AMARILLO}Red:${RESET} ${red}"
}

_cache_vigente() {
    local cache="$1" stamp="$2" ttl="$3"
    local ahora mtime=0
    ahora=$(date +%s 2>/dev/null)
    [[ "$ahora" =~ ^[0-9]+$ ]] || return 1
    [ -f "$stamp" ] && read -r mtime < "$stamp" 2>/dev/null
    [[ "$mtime" =~ ^[0-9]+$ ]] || mtime=0
    [ -f "$cache" ] && [ $((ahora - mtime)) -lt "$ttl" ]
}

_cache_guardar() {
    local cache="$1" stamp="$2" contenido="$3"
    printf '%s\n' "$contenido" > "${cache}.tmp" 2>/dev/null &&
        mv -f "${cache}.tmp" "$cache" 2>/dev/null
    date +%s > "$stamp" 2>/dev/null
}

_cache_seguridad_refrescar() {
    (
        local nueva
        nueva=$(mostrar_dashboard_seguridad)
        printf '%s\n' "$nueva" > "${LOGO_SEG_CACHE}.tmp" 2>/dev/null &&
            mv -f "${LOGO_SEG_CACHE}.tmp" "$LOGO_SEG_CACHE" 2>/dev/null
        date +%s > "${LOGO_SEG_CACHE}.stamp" 2>/dev/null
    ) </dev/null >/dev/null 2>&1 &
}

dashboard_cacheado() {
    local rapido seguridad

    # Métricas dinámicas: baratas, se recalculan cada DASH_REFRESCO segundos.
    if _cache_vigente "$LOGO_DASH_CACHE" "${LOGO_DASH_CACHE}.stamp" "$DASH_REFRESCO"; then
        rapido=$(cat "$LOGO_DASH_CACHE" 2>/dev/null)
    else
        rapido=$(mostrar_dashboard_rapido)
        _cache_guardar "$LOGO_DASH_CACHE" "${LOGO_DASH_CACHE}.stamp" "$rapido"
    fi

    # Seguridad: cara. Se muestra la última copia y se refresca aparte.
    if [ -f "$LOGO_SEG_CACHE" ]; then
        seguridad=$(cat "$LOGO_SEG_CACHE" 2>/dev/null)
        if ! _cache_vigente "$LOGO_SEG_CACHE" "${LOGO_SEG_CACHE}.stamp" "$DASH_SEG_REFRESCO"; then
            _cache_seguridad_refrescar
        fi
    else
        seguridad=$(mostrar_dashboard_seguridad)
        _cache_guardar "$LOGO_SEG_CACHE" "${LOGO_SEG_CACHE}.stamp" "$seguridad"
    fi

    # El uptime se calcula en vivo: no depende de la caché de seguridad (180 s).
    local uptime_txt="${AMARILLO}Uptime:${RESET} ${AZUL}$(uptime_legible)${RESET}"
    printf '%s\n%s  %b\n' "$rapido" "$seguridad" "$uptime_txt"
}

stk_limpieza_manual_menu() {
    local pasos_sel
    pasos_sel=$(printf '%s\n' \
        "journal|🗞️  Logs del journal (>${AUTO_LIMPIEZA_LOG_DIAS} días)" \
        "cache|📦  Caché del gestor de paquetes" \
        "thumbnails|🖼️  Miniaturas antiguas (>7 días)" \
        "orphans|🧩  Paquetes huérfanos/dependencias" \
        "trash|🗑️  Papelera de usuarios (con confirmación)" | \
        stk_fzf_ejecutar "Seleccione pasos" "Marca con TAB los pasos a ejecutar." "LIMPIEZA MANUAL" \
        --ansi \
        --multi \
        --delimiter='|' \
        --with-nth=2 \
        --height=~60% \
        --layout=reverse \
        --no-sort \
        --border=rounded \
        --border-label=" LIMPIEZA MANUAL " \
        --prompt="➤ TAB marca/desmarca · ENTER confirma: " \
        --header="Marca con TAB los pasos a ejecutar." \
        --bind 'start:select-all' \
        --color="$FZF_COLORES")

    if [ $? -ne 0 ] || [ -z "$pasos_sel" ]; then
        pintar "$AMARILLO" "Limpieza manual cancelada."
        sleep 1
        return 0
    fi

    local pasos_csv="" linea_p
    while IFS= read -r linea_p; do
        [ -n "$linea_p" ] && pasos_csv+="${pasos_csv:+,}${linea_p%%|*}"
    done <<< "$pasos_sel"

    stk_limpiar
    mostrar_logo
    stk_limpieza manual "$pasos_csv"
    echo ""
    read -p "Presione Enter para volver al menú..."
}

mostrar_info_red() {
    trap "stk_limpiar; return" SIGINT
    stk_limpiar
    mostrar_logo

    local ok="${VERDE_BRILLANTE}"
    local warn="${AMARILLO}"
    local bad="${ROJO_BRILLANTE}"
    local sep="${CIAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    local ruta iface_activa gw ip_local ip_local_txt ip_publica ip_publica_txt
    local dns_servers internet dns_ok=true

    echo -e " ${CIAN}${NEGRITA}INFORMACIÓN DE RED${RESET}"
    echo -e " ${sep}"

    # --- Interfaz de salida, IP local y puerta de enlace ---
    ruta=$(ip route get 1.1.1.1 2>/dev/null | head -n1)
    iface_activa=$(printf '%s\n' "$ruta" | awk '{ for (i = 1; i <= NF; i++) if ($i == "dev") { print $(i + 1); exit } }')
    ip_local=$(printf '%s\n' "$ruta" | sed -n 's/.* src \([^ ]*\).*/\1/p')
    gw=$(ip route 2>/dev/null | awk '$1 == "default" { print $3; exit }')

    [ -z "$ip_local" ] && ip_local=$(hostname -I 2>/dev/null | awk '{ print $1 }')
    if [ -n "$iface_activa" ]; then
        ip_local_txt=$(ip -o -4 addr show dev "$iface_activa" 2>/dev/null | awk '{ print $4; exit }')
    fi
    [ -z "$ip_local_txt" ] && ip_local_txt="$ip_local"

    # --- IP pública (con alternativas y diagnóstico de DNS) ---
    echo -ne "\r\033[K ${AMARILLO}➤ Consultando IP pública...${RESET}"
    if command -v host &>/dev/null; then
        host ifconfig.me &>/dev/null || dns_ok=false
    elif command -v getent &>/dev/null; then
        getent hosts ifconfig.me &>/dev/null || dns_ok=false
    fi

    if [ "$dns_ok" = false ]; then
        ip_publica="Error DNS (revisa /etc/resolv.conf)"
        ip_publica_txt="${bad}${ip_publica}${RESET}"
    elif ! command -v curl &>/dev/null && ! command -v wget &>/dev/null; then
        ip_publica="falta curl/wget"
        ip_publica_txt="${warn}${ip_publica}${RESET}"
    else
        local url valor
        ip_publica=""
        for url in "https://ifconfig.me" "https://api.ipify.org" "https://icanhazip.com"; do
            if command -v curl &>/dev/null; then
                valor=$(curl -sL --connect-timeout 3 --max-time 5 "$url" 2>/dev/null)
            else
                valor=$(wget -qO- --timeout=3 --tries=1 "$url" 2>/dev/null)
            fi
            valor=$(printf '%s' "$valor" | tr -d '[:space:]')
            if [ -n "$valor" ] && [[ "$valor" =~ ^[0-9a-fA-F:.]+$ ]]; then
                ip_publica="$valor"
                break
            fi
        done
        if [ -n "$ip_publica" ]; then
            ip_publica_txt="$ip_publica"
        else
            ip_publica="no disponible"
            ip_publica_txt="${warn}${ip_publica}${RESET}"
        fi
    fi
    printf '\r\033[K'

    # --- Servidores DNS configurados ---
    dns_servers=$(awk '$1 == "nameserver" { printf "%s%s", sep, $2; sep = ", " } END { print "" }' /etc/resolv.conf 2>/dev/null)
    [ -z "$dns_servers" ] && dns_servers="—"

    # --- Estado de Internet y latencia (misma comprobación que el dashboard) ---
    if comprobar_salida_internet; then
        internet="${ok}✔ conectado${RESET}"
        [ -n "$SALIDA_RED" ] && internet+=" ${AZUL}(${SALIDA_RED}${SALIDA_RED_LATENCIA:+, ${SALIDA_RED_LATENCIA} ms})${RESET}"
    else
        internet="${warn}⚠ sin salida${RESET}"
    fi

    campo_red "Interfaz activa:" "${iface_activa:-—}${iface_activa:+ ${AZUL}[$(tipo_interfaz "$iface_activa")]${RESET}}"
    campo_red "IP local:" "${ip_local_txt:-—}"
    campo_red "IP pública:" "$ip_publica_txt"
    campo_red "Puerta de enlace:" "${gw:-—}"
    campo_red "DNS:" "$dns_servers"
    campo_red "Internet:" "$internet"

    # --- Detalle de cada interfaz ---
    echo ""
    echo -e " ${sep}"
    echo -e " ${CIAN}${NEGRITA}ESTADO DE LAS INTERFACES${RESET}  ${AZUL}(RX/TX acumulado desde el arranque)${RESET}"
    echo ""
    local encontrados=0 base iface lista total_ifaces tecla
    lista=$(for base in /sys/class/net/*; do
        [ -e "$base" ] || continue
        iface=$(basename "$base")
        [ "$iface" = "lo" ] && continue
        printf '%s %s\n' "$(prioridad_interfaz "$iface")" "$iface"
    done | sort -k1,1n -k2,2)
    total_ifaces=$(printf '%s\n' "$lista" | awk 'NF >= 2 { n++ } END { print n + 0 }')
    while read -r _ iface; do
        [ -n "$iface" ] || continue
        mostrar_interfaz_red "$iface"
        echo ""
        encontrados=$((encontrados + 1))
        # Con varias interfaces, parar tras la primera para no desplazar la
        # información principal (IP pública, DNS, Internet) fuera de pantalla.
        if [ "$encontrados" -eq 1 ] && [ "$total_ifaces" -gt 1 ]; then
            echo -e "      ${AMARILLO_BRILLANTE}➤ Pulse cualquier tecla para continuar (${total_ifaces} interfaces en total)...${RESET}"
            read -r -n 1 -s tecla </dev/tty 2>/dev/null || true
            echo ""
        fi
    done <<< "$lista"
    if [ "$encontrados" -eq 0 ]; then
        echo -e "  ${AZUL}Sin interfaces de red detectadas${RESET}"
    fi

    registrar_log "$LOG_INFO" "Consulta de red realizada (Interfaz: ${iface_activa:-?} | Local: ${ip_local:-?} | Pública: ${ip_publica})"
    read -p "Presione Enter para volver..."
}

wifi_detalle() {
    local iface="$1" ssid="" senal="" calidad="" freq="" salida

    if command -v iw &>/dev/null; then
        salida=$(iw dev "$iface" link 2>/dev/null)
        if [ -n "$salida" ]; then
            ssid=$(printf '%s\n' "$salida" | sed -n 's/^[[:space:]]*SSID:[[:space:]]*//p' | head -n1)
            senal=$(printf '%s\n' "$salida" | sed -n 's/^[[:space:]]*signal:[[:space:]]*//p' | head -n1)
            freq=$(printf '%s\n' "$salida" | sed -n 's/^[[:space:]]*freq:[[:space:]]*//p' | head -n1)
        fi
    fi

    if [ -z "$ssid" ] && command -v nmcli &>/dev/null; then
        ssid=$(LC_ALL=C nmcli -t -f GENERAL.CONNECTION dev show "$iface" 2>/dev/null \
            | sed -n 's/^GENERAL.CONNECTION://p' | head -n1)
        [ "$ssid" = "--" ] && ssid=""
    fi

    if [ -z "$senal" ] && [ -r /proc/net/wireless ]; then
        senal=$(awk -v i="${iface}:" '$1==i { gsub(/\./,"",$4); print $4 " dBm" }' /proc/net/wireless 2>/dev/null)
        calidad=$(awk -v i="${iface}:" '$1==i { gsub(/\./,"",$3); print $3 "/70" }' /proc/net/wireless 2>/dev/null)
    fi

    [ -z "$ssid$senal$calidad$freq" ] && return

    [ -n "$ssid" ] && printf '%s' "$ssid"
    [ -n "$senal" ] && printf ' · Señal %s' "$senal"
    [ -n "$calidad" ] && printf ' · Calidad %s' "$calidad"
    [ -n "$freq" ] && printf ' · %s MHz' "$freq"
}

mostrar_interfaz_red() {
    local iface="$1"
    local base="/sys/class/net/$iface"
    local estado estado_txt mac ipv4 ipv6 rx tx tipo wifi_info
    local ok="${VERDE_BRILLANTE}"
    local bad="${ROJO_BRILLANTE}"
    local warn="${AMARILLO}"

    estado=$(cat "$base/operstate" 2>/dev/null)
    mac=$(cat "$base/address" 2>/dev/null)
    ipv4=$(ip -o -4 addr show dev "$iface" 2>/dev/null | awk '{print $4}' | paste -sd, - | sed 's/,/, /g')
    ipv6=$(ip -o -6 addr show dev "$iface" scope global 2>/dev/null | awk '{print $4}' | paste -sd, - | sed 's/,/, /g')
    rx=$(formato_bytes "$(cat "$base/statistics/rx_bytes" 2>/dev/null)")
    tx=$(formato_bytes "$(cat "$base/statistics/tx_bytes" 2>/dev/null)")
    tipo=$(tipo_interfaz "$iface")

    case "$estado" in
        up)   estado_txt="${ok}● UP${RESET}" ;;
        down) estado_txt="${bad}● DOWN${RESET}" ;;
        *)    estado_txt="${warn}● ${estado:-?}${RESET}" ;;
    esac

    echo -e "  ${estado_txt}  ${NEGRITA}${BLANCO}${iface}${RESET}  ${AZUL}[${tipo}]${RESET}"
    echo -e "      ${AMARILLO}IPv4${RESET} ${ipv4:-—}    ${AMARILLO}MAC${RESET} ${mac:-—}"
    if [ -n "$ipv6" ]; then
        echo -e "      ${AMARILLO}IPv6${RESET} ${ipv6}"
    fi
    echo -e "      ${AMARILLO}RX${RESET} ${rx}    ${AMARILLO}TX${RESET} ${tx}"

    wifi_info=""
    if [ "$tipo" = "Wi-Fi" ]; then
        wifi_info=$(wifi_detalle "$iface")
    fi
    if [ -n "$wifi_info" ]; then
        echo -e "      ${AMARILLO}Wi-Fi${RESET} ${wifi_info}"
    fi
}

auto_checklist() {
    local -a pasos=(
        "actualizacion|🔄  Actualización del sistema"
        "limpieza|🧹  Limpieza y espacio"
        "auditoria|🔍  Auditoría de seguridad"
        "servicios|📊  Servicios y reinicio"
    )

    # Sin terminal interactiva se ejecutan todos los pasos.
    # Nota: solo miramos stdin, porque la salida se captura por command substitution.
    if [ ! -t 0 ]; then
        printf '%s\n' "${pasos[@]}"
        return 0
    fi

    local seleccion
    seleccion=$(printf '%s\n' "${pasos[@]}" | stk_fzf_ejecutar "Seleccione pasos" "Selecciona los pasos a ejecutar (todos marcados por defecto)." "PASOS DEL MODO AUTO" \
        --ansi \
        --multi \
        --delimiter='|' \
        --with-nth=2 \
        --height=~60% \
        --layout=reverse \
        --no-sort \
        --border=rounded \
        --border-label=" PASOS DEL MODO AUTO " \
        --prompt="➤ TAB marca/desmarca · ENTER confirma: " \
        --header="Selecciona los pasos a ejecutar (todos marcados por defecto)." \
        --bind 'start:select-all' \
        --color="$FZF_COLORES")

    local rc=$?
    [ $rc -ne 0 ] && return 1
    [ -z "$seleccion" ] && return 1
    printf '%s\n' "$seleccion"
}

modo_auto() {
    if ! declare -F stk_lock_adquirir >/dev/null 2>&1; then
        pintar "$ROJO" "❌ Falta la biblioteca del modo automático (stk_auto_lib.sh)."
        echo ""
        read -p "Presione Enter para volver al menú principal..."
        return 1
    fi

    # Capturar Ctrl+C para liberar el lock y volver de forma segura al menú
    trap '[ -n "${SPINNER_PID:-}" ] && kill "$SPINNER_PID" 2>/dev/null; stk_lock_liberar; stk_limpiar; return' SIGINT

    stk_limpiar
    mostrar_logo
    pintar "$MAGENTA" "════════════════════════════════════════════════════════════════"
    pintar "$BLANCO"  " 🤖 MODO AUTOMÁTICO INTEGRAL DE MANTENIMIENTO"
    pintar "$MAGENTA" "════════════════════════════════════════════════════════════════"
    echo ""

    # --- Checklist de pasos ---
    local seleccion
    seleccion=$(auto_checklist)
    if [ $? -ne 0 ]; then
        pintar "$AMARILLO" "Modo auto cancelado. No se ha ejecutado nada."
        echo ""
        trap - SIGINT
        read -p "Presione Enter para volver al menú principal..."
        return 0
    fi

    local -a PASOS_EJECUTADOS=()
    local linea
    while IFS= read -r linea; do
        [ -n "$linea" ] && PASOS_EJECUTADOS+=("${linea%%|*}")
    done <<< "$seleccion"

    if [ ${#PASOS_EJECUTADOS[@]} -eq 0 ]; then
        pintar "$AMARILLO" "No has seleccionado ningún paso."
        echo ""
        trap - SIGINT
        read -p "Presione Enter para volver al menú principal..."
        return 0
    fi

    # --- Lock: evita ejecuciones simultáneas (también con el cron) ---
    if ! stk_lock_adquirir; then
        pintar "$ROJO" "❌ Ya hay otra ejecución del modo auto en curso."
        echo ""
        trap - SIGINT
        read -p "Presione Enter para volver al menú principal..."
        return 3
    fi

    local T_INICIO FECHA_INICIO
    T_INICIO=$(date +%s)
    FECHA_INICIO=$(date '+%Y-%m-%d %H:%M:%S')

    registrar_log "$LOG_INFO" "=== INICIO DE MODO AUTO INTEGRAL ==="
    registrar_log "$LOG_INFO" "PASOS: ${PASOS_EJECUTADOS[*]}"

    # --- Estado inicial (por si algún paso no se ejecuta) ---
    local RES_ACTUALIZACION="Sin procesar"
    local RES_LIMPIEZA="Sin procesar"
    local RES_SEGURIDAD="Sin procesar"
    local RES_SERVICIOS="Sin procesar"
    local ESPACIO_LIBERADO_MB=0
    local FALLO_CRITICO=false
    local AUDITORIA_EJECUTADA=false
    local -a FLATPAKS_ACT=() SNAPS_ACT=() TIEMPOS=()
    local -a PKGS_ACTUALIZADOS=()
    ACT_INCIDENCIAS=()
    SEC_ALERTAS=()
    SVC_FAILED_ARR=()
    PRE_AVISOS=()
    local SCORE_SEGURIDAD=0
    local PRE_RED="ok" PRE_ESPACIO_MB=0 PRE_ESPACIO_OK=true PRE_GESTOR_LIBRE=true PRE_BATERIA="N/D"
    local SNAPSHOT_METODO="ninguno"
    local REBOOT_REQUIRED=false REBOOT_PKGS="" KERNEL_PENDIENTE=false NEEDRESTART=""
    local ETIQUETA_GESTOR="$Package"
    [ "${IMMUTABLE:-false}" = true ] && ETIQUETA_GESTOR="rpm-ostree"

    # Contadores para la numeración [x/N]
    local N_PASOS=${#PASOS_EJECUTADOS[@]}
    local PASO_IDX=0
    local T_PASO

    # --- Preflight (los avisos ya se registran en bitácora desde la librería) ---
    pintar "$CIAN" "🔎 Preflight del sistema..."
    stk_preflight
    echo ""

    # --- Snapshot previo (solo si se va a actualizar) ---
    if printf '%s\n' "${PASOS_EJECUTADOS[@]}" | grep -qx "actualizacion" \
       && [ "$PRE_RED" = "ok" ] && [ "$PRE_ESPACIO_OK" = true ] && [ "$PRE_GESTOR_LIBRE" = true ]; then
        pintar "$CIAN" "🛟 Creando punto de recuperación previo..."
        stk_snapshot
        case "$SNAPSHOT_METODO" in
            ninguno) pintar "$AMARILLO" "   └─ No se pudo crear ningún punto de recuperación." ;;
            *)       pintar "$VERDE" "   └─ Punto de recuperación: $SNAPSHOT_METODO" ;;
        esac
        echo ""
    fi

    # ======================================================================
    # PASO: ACTUALIZACIÓN
    # ======================================================================
    if printf '%s\n' "${PASOS_EJECUTADOS[@]}" | grep -qx "actualizacion"; then
        ((PASO_IDX++))
        T_PASO=$(date +%s)
        pintar "$AZUL_BRILLANTE" "📌 [${PASO_IDX}/${N_PASOS}] Ejecutando Actualización del Sistema ($ETIQUETA_GESTOR)..."
        echo ""

        if [ "$PRE_RED" != "ok" ] || [ "$PRE_ESPACIO_OK" != true ] || [ "$PRE_GESTOR_LIBRE" != true ]; then
            RES_ACTUALIZACION="⏭ Omitida por el preflight (red/espacio/gestor)."
            pintar "$AMARILLO" "   └─ $RES_ACTUALIZACION"
        else
            stk_actualizar
            local ESTADO_ACT=$?

            case "$ESTADO_ACT" in
                0)   pintar "$VERDE" "   └─ $RES_ACTUALIZACION" ;;
                124) pintar "$ROJO" "   └─ $RES_ACTUALIZACION"; FALLO_CRITICO=true ;;
                *)   pintar "$ROJO" "   └─ $RES_ACTUALIZACION"; FALLO_CRITICO=true ;;
            esac

            # Las incidencias detectadas en la salida del gestor ya están en
            # la bitácora; también se muestran aquí para que no se pierdan.
            if [ ${#ACT_INCIDENCIAS[@]} -gt 0 ]; then
                pintar "$AMARILLO" "   └─ ⚠ ${#ACT_INCIDENCIAS[@]} incidencia(s) registrada(s) en la bitácora:"
                local inc
                for inc in "${ACT_INCIDENCIAS[@]}"; do
                    echo "      • $inc"
                done
            fi
        fi
        TIEMPOS+=("Actualización: $(( $(date +%s) - T_PASO ))s")
        echo ""
    fi

    # ======================================================================
    # PASO: LIMPIEZA (modo seguro: solo cachés y logs)
    # ======================================================================
    if printf '%s\n' "${PASOS_EJECUTADOS[@]}" | grep -qx "limpieza"; then
        ((PASO_IDX++))
        T_PASO=$(date +%s)
        pintar "$AZUL_BRILLANTE" "📌 [${PASO_IDX}/${N_PASOS}] Ejecutando Limpieza Segura del Sistema..."
        stk_limpieza auto
        if [ $? -eq 0 ]; then
            ESPACIO_LIBERADO_MB=${SUPER_LIMPIEZA_LIBERADO:-0}
            [[ "$ESPACIO_LIBERADO_MB" =~ ^[0-9]+$ ]] || ESPACIO_LIBERADO_MB=0
            if [ "$ESPACIO_LIBERADO_MB" -gt 0 ]; then
                RES_LIMPIEZA="✔ Liberados aprox. ${ESPACIO_LIBERADO_MB} MB (cachés y logs; sin paquetes ni papeleras)."
            else
                RES_LIMPIEZA="✔ Limpieza completada (solo cachés y logs; el sistema ya estaba optimizado)."
            fi
        else
            RES_LIMPIEZA="⚠ La limpieza no pudo completarse."
        fi
        TIEMPOS+=("Limpieza: $(( $(date +%s) - T_PASO ))s")
        echo ""
    fi

    # ======================================================================
    # PASO: AUDITORÍA DE SEGURIDAD
    # ======================================================================
    if printf '%s\n' "${PASOS_EJECUTADOS[@]}" | grep -qx "auditoria"; then
        ((PASO_IDX++))
        T_PASO=$(date +%s)
        pintar "$AZUL_BRILLANTE" "📌 [${PASO_IDX}/${N_PASOS}] Auditando Parámetros Críticos de Seguridad..."
        stk_auditoria
        AUDITORIA_EJECUTADA=true
        if [ "$SCORE_SEGURIDAD" -ge 80 ]; then
            pintar "$VERDE" "   └─ $RES_SEGURIDAD"
        else
            pintar "$AMARILLO" "   └─ $RES_SEGURIDAD"
        fi
        TIEMPOS+=("Auditoría: $(( $(date +%s) - T_PASO ))s")
        echo ""
    fi

    # ======================================================================
    # PASO: SERVICIOS Y REINICIO
    # ======================================================================
    if printf '%s\n' "${PASOS_EJECUTADOS[@]}" | grep -qx "servicios"; then
        ((PASO_IDX++))
        T_PASO=$(date +%s)
        pintar "$AZUL_BRILLANTE" "📌 [${PASO_IDX}/${N_PASOS}] Analizando Servicios y Estado de Reinicio..."
        stk_servicios

        if [ ${#SVC_FAILED_ARR[@]} -gt 0 ]; then
            pintar "$AMARILLO" "   └─ $RES_SERVICIOS"
            echo "Puedes ir al menú de Gestión de Servicios para más detalles y opciones de actuación"
        else
            pintar "$VERDE" "   └─ $RES_SERVICIOS"
        fi
        [ "$REBOOT_REQUIRED" = true ] && pintar "$AMARILLO" "   └─ 🔄 Reinicio recomendado${REBOOT_PKGS:+ (paquetes: $REBOOT_PKGS)}"
        [ "$KERNEL_PENDIENTE" = true ] && pintar "$AMARILLO" "   └─ 🧠 Kernel nuevo instalado; se aplicará al reiniciar."
        [ -n "$NEEDRESTART" ] && pintar "$AMARILLO" "   └─ Servicios que necesitan reinicio: $NEEDRESTART"
        TIEMPOS+=("Servicios: $(( $(date +%s) - T_PASO ))s")
        echo ""
    fi

    # ======================================================================
    # RESUMEN FINAL (en pantalla + bitácora; sin ficheros JSON)
    # ======================================================================
    local T_FIN DURACION
    T_FIN=$(date +%s)
    DURACION=$(( T_FIN - T_INICIO ))

    # Resultado global y código de salida
    local resultado="ok" rc=0
    [[ "$SCORE_SEGURIDAD" =~ ^[0-9]+$ ]] || SCORE_SEGURIDAD=0
    if [ "$FALLO_CRITICO" = true ]; then
        resultado="error"; rc=2
    elif [ ${#PRE_AVISOS[@]} -gt 0 ] || [ ${#SEC_ALERTAS[@]} -gt 0 ] \
         || [ ${#SVC_FAILED_ARR[@]} -gt 0 ] || [ "$REBOOT_REQUIRED" = true ] \
         || [ "$KERNEL_PENDIENTE" = true ] \
         || { [ "$AUDITORIA_EJECUTADA" = true ] && [ "$SCORE_SEGURIDAD" -lt 80 ]; }; then
        resultado="avisos"; rc=1
    fi

    echo ""
    pintar "$CIAN" "════════════════════════════════════════════════════════════════"
    pintar "$BLANCO" "       📋 INFORME Y RESUMEN FINAL - MODO AUTOMÁTICO"
    pintar "$CIAN" "════════════════════════════════════════════════════════════════"
    echo -e "${AMARILLO}➤ Fecha de Inicio:${RESET}     ${BLANCO}${FECHA_INICIO}${RESET}"
    echo -e "${AMARILLO}➤ Tiempo Transcurrido:${RESET}  ${BLANCO}${DURACION} segundos${RESET}"
    echo -e "${AMARILLO}➤ Pasos ejecutados:${RESET}    ${BLANCO}${PASOS_EJECUTADOS[*]}${RESET}"
    [ ${#TIEMPOS[@]} -gt 0 ] && { local TIEMPOS_TXT="" t; for t in "${TIEMPOS[@]}"; do TIEMPOS_TXT+="${TIEMPOS_TXT:+ · }$t"; done; echo -e "${AMARILLO}➤ Duración por paso:${RESET}   ${BLANCO}${TIEMPOS_TXT}${RESET}"; }
    echo -e "${AMARILLO}➤ Preflight:${RESET}           ${BLANCO}Red: $PRE_RED · Espacio: ${PRE_ESPACIO_MB} MB · Batería: $PRE_BATERIA${RESET}"
    if [ ${#PRE_AVISOS[@]} -gt 0 ]; then
        local av
        for av in "${PRE_AVISOS[@]}"; do echo -e "   ${AMARILLO}⚠ $av${RESET}"; done
    fi
    echo -e "${AMARILLO}➤ Snapshot previo:${RESET}     ${BLANCO}${SNAPSHOT_METODO}${RESET}"
    echo -e "${AMARILLO}➤ Espacio liberado:${RESET}    ${BLANCO}${ESPACIO_LIBERADO_MB} MB${RESET}"
    echo -e "${AMARILLO}➤ Resultado:${RESET}           ${BLANCO}${resultado}${RESET}\n"

    echo -e "${NEGRITA}${MAGENTA}RESULTADOS POR MÓDULO:${RESET}"
    printf '%s\n' "${PASOS_EJECUTADOS[@]}" | grep -qx "actualizacion" && echo -e " ${AZUL}• Actualización:${RESET} $RES_ACTUALIZACION"
    printf '%s\n' "${PASOS_EJECUTADOS[@]}" | grep -qx "limpieza" && echo -e " ${AZUL}• Limpieza:${RESET}       $RES_LIMPIEZA"
    printf '%s\n' "${PASOS_EJECUTADOS[@]}" | grep -qx "auditoria" && echo -e " ${AZUL}• Seguridad:${RESET}      $RES_SEGURIDAD"
    printf '%s\n' "${PASOS_EJECUTADOS[@]}" | grep -qx "servicios" && echo -e " ${AZUL}• Servicios:${RESET}      $RES_SERVICIOS"

    # Incidencias de la actualización: antes se perdían al borrar el log temporal.
    if [ ${#ACT_INCIDENCIAS[@]} -gt 0 ]; then
        echo -e "\n${AMARILLO}⚠️ Incidencias de actualización (guardadas en la bitácora):${RESET}"
        local inc
        for inc in "${ACT_INCIDENCIAS[@]}"; do echo -e "   • $inc"; done
    fi

    # Desglose detallado si se detectaron paquetes actualizados
    if [ ${#PKGS_ACTUALIZADOS[@]} -gt 0 ] || [ ${#FLATPAKS_ACT[@]} -gt 0 ] || [ ${#SNAPS_ACT[@]} -gt 0 ]; then
        echo -e "\n${AMARILLO}📦 Detalle de Paquetes Actualizados:${RESET}"

        if [ ${#PKGS_ACTUALIZADOS[@]} -gt 0 ]; then
            echo -e "   ${AZUL_BRILLANTE}• Sistema ($ETIQUETA_GESTOR):${RESET} ${PKGS_ACTUALIZADOS[*]}"
        fi
        if [ ${#FLATPAKS_ACT[@]} -gt 0 ]; then
            echo -e "   ${AZUL_BRILLANTE}• Flatpak:${RESET} ${FLATPAKS_ACT[*]}"
        fi
        if [ ${#SNAPS_ACT[@]} -gt 0 ]; then
            echo -e "   ${AZUL_BRILLANTE}• Snap:${RESET} ${SNAPS_ACT[*]}"
        fi
    fi

    if [ ${#SEC_ALERTAS[@]} -gt 0 ]; then
        echo -e "\n${AMARILLO}⚠️ Alertas de Seguridad Detectadas:${RESET}"
        local alt
        for alt in "${SEC_ALERTAS[@]}"; do echo -e "   • $alt"; done
    fi

    if [ "$REBOOT_REQUIRED" = true ] || [ "$KERNEL_PENDIENTE" = true ] || [ -n "$NEEDRESTART" ]; then
        echo -e "\n${AMARILLO}🔄 Reinicio:${RESET}"
        [ "$REBOOT_REQUIRED" = true ] && echo -e "   • Hay un reinicio pendiente${REBOOT_PKGS:+ (paquetes: $REBOOT_PKGS)}"
        [ "$KERNEL_PENDIENTE" = true ] && echo -e "   • Kernel nuevo instalado; se aplicará al reiniciar"
        [ -n "$NEEDRESTART" ] && echo -e "   • Servicios que necesitan reinicio: $NEEDRESTART"
    fi
    pintar "$CIAN" "════════════════════════════════════════════════════════════════"

    # Bitácora: el detalle de cada módulo ya lo registró la biblioteca compartida.
    registrar_log "$LOG_INFO" "=== RESUMEN MODO AUTO (Duración: ${DURACION}s) ==="
    registrar_log "$LOG_INFO" "RESULTADO: $resultado (código $rc) | pasos: ${PASOS_EJECUTADOS[*]}"
    registrar_log "$LOG_INFO" "PREFLIGHT: red=$PRE_RED espacio=${PRE_ESPACIO_MB}MB batería=$PRE_BATERIA"
    registrar_log "$LOG_INFO" "LIMPIEZA: $RES_LIMPIEZA"
    registrar_log "$LOG_INFO" "=== FIN DE MODO AUTO ==="

    echo -e "\n${AMARILLO}➤ Bitácora:${RESET} ${BLANCO}${LOG_FILE}${RESET}"
    echo -e "${AMARILLO}➤ Logs de actualizaciones:${RESET} ${BLANCO}También en Menú Mantenimiento → Logs de actualizaciones${RESET}"
    stk_lock_liberar
    trap - SIGINT
    echo ""
    read -p "Presione Enter para volver al menú principal..."
    return $rc
}

auditoria_seguridad() {
    trap "stk_limpiar; return" SIGINT
    stk_limpiar
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

    # B. Intérpretes con conexiones establecidas (posible reverse shell)
    ((total_checks++))
    pintar $AMARILLO "🔍 Intérpretes con conexiones establecidas (posible reverse shell):"
    local rs_shells
    rs_shells=$(reverse_shell_alerta)
    if [ "$rs_shells" == "ok" ]; then
        pintar $VERDE "  ✔ Ninguna conexión de intérprete sospechosa."
        ((checks_passed++))
    elif [ "$rs_shells" == "N/D" ]; then
        pintar $AZUL "  ℹ️ No se pudo comprobar (falta el comando 'ss')."
    else
        pintar $ROJO_BRILLANTE "  ⚠️ ${rs_shells#⚠ }"
        sugerencias+=("🕵️ Reverse shell: Revisa las conexiones con 'ss -tupn state established' y valida los procesos implicados.")
        registrar_log "$LOG_WARN" "SEGURIDAD: Posible reverse shell detectada"
        ((alertas_count++))
    fi
    echo ""

    # C. Robustecimiento de Red (Kernel Sysctl)
    ((total_checks++))
    pintar $AMARILLO "🔍 Parámetros de seguridad del Kernel (Sysctl Network):"
    local syn_cookies accept_redirects
    syn_cookies=$(sysctl -n net.ipv4.tcp_syncookies 2>/dev/null)
    accept_redirects=$(sysctl -n net.ipv4.conf.all.accept_redirects 2>/dev/null)
    # Valores por defecto seguros: si sysctl no está disponible, se informa
    # de la configuración mejorable en lugar de producir errores aritméticos.
    [[ "$syn_cookies" =~ ^[0-9]+$ ]] || syn_cookies=0
    [[ "$accept_redirects" =~ ^[0-9]+$ ]] || accept_redirects=1

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
    # D. Auditoría de Intentos SSH / Auth
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
    if [ "$suid_count" -gt "$AUTO_LIMITE_SUID" ]; then
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
    local score=0
    [ "$total_checks" -gt 0 ] && score=$(( (checks_passed * 100) / total_checks ))

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
    trap "stk_limpiar; return" SIGINT
    stk_limpiar
    mostrar_logo
    pintar $AZUL_BRILLANTE "➤ Iniciando actualización automática del sistema..."
    echo ""

    local ESTADO_ACTUALIZACION=0
    local ETIQUETA_GESTOR="$Package"
    [ "$IMMUTABLE" = true ] && ETIQUETA_GESTOR="rpm-ostree"

    # 1. Actualización según el gestor principal del sistema
    if [ "$IMMUTABLE" = true ]; then
        pintar $VERDE "Actualizando la imagen del sistema (RPM-OSTREE)..."
        rpm-ostree upgrade
        ESTADO_ACTUALIZACION=$?
        if [ $ESTADO_ACTUALIZACION -eq 0 ]; then
            pintar $AMARILLO "🔄 Reinicia el sistema para aplicar la nueva imagen."
        fi
    else
        case "$Package" in
            apt)
                pintar $VERDE "Actualizando repositorios y paquetes (APT)..."
                local APT_NET_OPTS=(-o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30 -o DPkg::Lock::Timeout=120)

                apt-get update -y "${APT_NET_OPTS[@]}"
                apt-get full-upgrade "${APT_NET_OPTS[@]}"
                ESTADO_ACTUALIZACION=$?

                if [ $ESTADO_ACTUALIZACION -ne 0 ]; then
                    echo ""
                    pintar $AMARILLO "⚠️ La actualización terminó con errores (código $ESTADO_ACTUALIZACION)."
                    read -r -p "¿Deseas intentar reparar el gestor con dpkg --configure -a? (s/N): " reparar
                    if [[ "$reparar" == "s" || "$reparar" == "S" ]]; then
                        local ESTADO_REPARACION
                        dpkg --configure -a
                        ESTADO_REPARACION=$?
                        # La reparación no debe maquillar el fallo de la actualización.
                        if [ "$ESTADO_REPARACION" -ne 0 ]; then
                            pintar $AMARILLO "⚠️ La reparación con dpkg terminó con errores (código $ESTADO_REPARACION)."
                        fi
                    fi
                fi

                echo ""
                pintar $AZUL "🧹 Comprobando paquetes huérfanos..."
                apt-get autoremove
                ;;
            dnf)
                pintar $VERDE "Actualizando sistema (DNF)..."
                dnf upgrade --refresh
                ESTADO_ACTUALIZACION=$?
                if [ $ESTADO_ACTUALIZACION -eq 0 ]; then
                    echo ""
                    pintar $AZUL "🧹 Comprobando paquetes huérfanos..."
                    dnf autoremove
                fi
                ;;
            pacman)
                pintar $VERDE "Sincronizando repositorios y sistema (PACMAN)..."
                pacman -Syu
                ESTADO_ACTUALIZACION=$?
                ;;
            zypper)
                pintar $VERDE "Refrescando y actualizando (ZYPPER)..."
                zypper refresh && zypper update
                ESTADO_ACTUALIZACION=$?
                ;;
            *)
                stk_mostrar_error "❌ Error: No se pudo identificar un gestor de paquetes compatible." "Presione Enter para volver..."
                trap - SIGINT
                return 1
                ;;
        esac
    fi

    # 2. Actualización opcional para paquetes Flatpak (si está instalado)
    if command -v flatpak &>/dev/null; then
        echo ""
        pintar $AZUL "📦 Actualizando paquetes Flatpak..."
        flatpak update
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
        if [ "$IMMUTABLE" = true ]; then
            pintar $VERDE_BRILLANTE "✔ Imagen del sistema preparada. Reinicia para aplicar los cambios."
            registrar_log "$LOG_INFO" "Actualización rpm-ostree preparada; reinicio pendiente."
        else
            pintar $VERDE_BRILLANTE "✔ ¡El sistema se ha actualizado correctamente!"
            registrar_log "$LOG_INFO" "Actualización del sistema completada con éxito ($ETIQUETA_GESTOR)."
        fi
    else
        pintar $ROJO "✘ Hubo un error durante la actualización."
        registrar_log "$LOG_ERR" "Fallo en la actualización del sistema usando $ETIQUETA_GESTOR."
    fi

    # Restaurar la trampa de señal por defecto antes de salir
    trap - SIGINT
    echo ""
    read -p "Presione Enter para volver al menú..."
}

instalar_programa() {
    trap "stk_limpiar; return" SIGINT
    stk_limpiar
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
    local GESTOR_MOSTRAR="$Package"
    [ "$IMMUTABLE" = true ] && GESTOR_MOSTRAR="rpm-ostree (inmutable)"
    echo -e "${AMARILLO}➤ Package de paquetes para la instalación:${RESET} ${AZUL}$GESTOR_MOSTRAR${RESET}"
    echo ""

    local ESTADO_INSTALACION=1

    # 2. Ejecución de comandos (CORREGIDOS)
    if [ "$IMMUTABLE" = true ]; then
        pintar $AMARILLO "💡 En sistemas inmutables, para aplicaciones de escritorio se recomienda Flatpak."
        pintar $VERDE "Instalando/actualizando $programa en una capa rpm-ostree..."
        if rpm-ostree install --idempotent --allow-inactive --apply-live "$programa"; then
            ESTADO_INSTALACION=0
        else
            rpm-ostree install --idempotent --allow-inactive "$programa"
            ESTADO_INSTALACION=$?
            if [ $ESTADO_INSTALACION -eq 0 ]; then
                pintar $AMARILLO "🔄 Reinicia el sistema para usar $programa."
            fi
        fi
    else
        case "$Package" in
            apt)
                pintar $VERDE "Actualizando índices e instalando/actualizando $programa..."
                apt update
                apt install "$programa" -y  # Corregido "insall" por "install"
                ESTADO_INSTALACION=$?
                ;;
            dnf)
                pintar $VERDE "Instalando/actualizando $programa..."
                dnf install "$programa" -y
                ESTADO_INSTALACION=$?
                ;;
            pacman)
                pintar $VERDE "Instalando/actualizando $programa..."
                # CORRECCIÓN: pacman no usa "install", usa "-S"
                pacman -S --noconfirm "$programa"
                ESTADO_INSTALACION=$?
                ;;
            zypper)
                pintar $VERDE "Instalando/actualizando $programa..."
                zypper install -y "$programa"
                ESTADO_INSTALACION=$?
                ;;
            *)
                stk_mostrar_error "❌ Error: No se pudo identificar un Package compatible." "Presione Enter para volver..."
                return 1
                ;;
        esac
    fi

    # 3. Resultado final
    if [ $ESTADO_INSTALACION -eq 0 ]; then
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
    trap "stk_limpiar; return" SIGINT
    stk_limpiar
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

    local ESTADO_DESINSTALACION=1

    if [ "$IMMUTABLE" = true ]; then
        pintar $VERDE "Eliminando $programa de la capa rpm-ostree..."
        rpm-ostree uninstall "$programa"
        ESTADO_DESINSTALACION=$?
        if [ $ESTADO_DESINSTALACION -eq 0 ]; then
            pintar $AMARILLO "🔄 Reinicia el sistema para aplicar la eliminación."
        fi
    else
        case "$Package" in
            apt)
                pintar $VERDE "Eliminando y limpiando configuraciones (APT)..."
                apt purge "$programa" -y && apt autoremove -y
                ESTADO_DESINSTALACION=$?
                ;;
            dnf)
                pintar $VERDE "Eliminando paquete (DNF)..."
                dnf remove "$programa" -y
                ESTADO_DESINSTALACION=$?
                ;;
            pacman)
                pintar $VERDE "Eliminando paquete y dependencias no usadas (PACMAN)..."
                pacman -Rs --noconfirm "$programa"
                ESTADO_DESINSTALACION=$?
                ;;
            zypper)
                pintar $VERDE "Eliminando paquete (ZYPPER)..."
                zypper remove -y "$programa"
                ESTADO_DESINSTALACION=$?
                ;;
            *)
                pintar $ROJO "❌ Package no compatible."
                return 1
                ;;
        esac
    fi

    if [ $ESTADO_DESINSTALACION -eq 0 ]; then
        registrar_log "$LOG_WARN" "Programa eliminado: $programa"
        pintar $VERDE_BRILLANTE "✔ ¡$programa ha sido eliminado correctamente!"
    else
        pintar $ROJO "✘ Error al intentar desinstalar $programa."
    fi
    read -p "Presione Enter para volver..."
}

obtener_grupo_sudo() {
    if grep -q "^sudo:" /etc/group; then
        echo "sudo"
    elif grep -q "^wheel:" /etc/group; then
        echo "wheel"
    else
        echo "sudo"
    fi
}

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
    trap "stk_limpiar; return" SIGINT
    while true; do
        stk_limpiar
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
                stk_limpiar
                mostrar_logo
                pintar $CIAN "--- MODIFICAR PERMISOS DE USUARIOS ---"

                # Obtener listado de usuarios humanos (UID >= 1000)
                local lista_users
                lista_users=$(cut -d: -f1,3 /etc/passwd | awk -F: '$2 >= 1000 && $2 < 60000 {print $1}')

                if [ -z "$lista_users" ]; then
                    stk_mostrar_info "No se encontraron usuarios humanos configurables." "Presione Enter..."
                    continue
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

gestionar_servicios() {
    trap "stk_limpiar; return" SIGINT
    while true; do

        stk_limpiar
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
            stk_mostrar_exito "✔ No se encontraron servicios en este estado." "Presione Enter..."
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
    trap "stk_limpiar; return" SIGINT
    while true; do

        stk_limpiar
        pintar $CIAN "⚙️ Gestionando: $svc"
        echo "------------------------------------------------"
        # Mostramos el estado actual muy brevemente para tener contexto
        systemctl status "$svc" --no-pager | grep -E "Active:|Main PID:|Tasks:"
        echo "------------------------------------------------"

        local accion=$(echo -e "1. Reiniciar (Restart)\n2. Detener (Stop)\n3. Ver Logs (Journalctl -u)\n4. Ver Estado Completo (Status)\n5. Habilitar/Deshabilitar (Enable/Disable)\n6. ↩ Volver" | fzf_estilo "Acción" "O P E R A C I O N E S :  $svc")

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
        sel=$(echo -e "$lineas_menu" | stk_fzf_ejecutar "Navegar" "Directorio actual: $dir_actual" "EXPLORADOR DE DIRECTORIOS" \
            --ansi --height=18 --reverse --border=rounded \
            --prompt="Navegar ❯ " \
            --header="Directorio actual: $dir_actual" \
            --color="$FZF_COLORES" \
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

ver_backups_existentes() {
    stk_limpiar
    mostrar_logo
    pintar $CIAN "--- BACKUPS LOCALES EXISTENTES ---"

    if [ ! -d "$DESTINO_DEF" ]; then
        stk_mostrar_error "No se encontró el directorio de backups ($DESTINO_DEF)." "Presione Enter..."
        return
    fi

    local archivos
    archivos=$(find "$DESTINO_DEF" -type f -name "*.tar.gz" 2>/dev/null)
    if [ -z "$archivos" ]; then
        stk_mostrar_info "No hay archivos de backup (.tar.gz) disponibles." "Presione Enter..."
        return
    fi

    echo "$archivos" | stk_fzf_ejecutar "Inspeccionar Backup" "VISTA PREVIA DEL CONTENIDO (.tar.gz)" "INSPECCIÓN DE BACKUPS" \
        --ansi \
        --height=18 \
        --reverse \
        --border=rounded \
        --prompt="➤ Inspeccionar Backup: " \
        --header="--- VISTA PREVIA DEL CONTENIDO (.tar.gz) ---" \
        --color="$FZF_COLORES" \
        --preview="tar -tvf {} | head -n 40" \
        --preview-window="right:60%"

    read -p "Presione Enter para volver..."
}

eliminar_backups() {
    stk_limpiar
    mostrar_logo
    pintar $CIAN "--- ELIMINAR COPIAS DE SEGURIDAD ---"

    local archivos
    archivos=$(find "$DESTINO_DEF" -type f -name "*.tar.gz" 2>/dev/null)
    if [ -z "$archivos" ]; then
        stk_mostrar_info "No hay respaldos para eliminar." "Presione Enter..."
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
    stk_limpiar
    mostrar_logo
    pintar $CIAN "--- RESTAURAR COPIA DE SEGURIDAD ---"

    if [ ! -d "$DESTINO_DEF" ] || [ -z "$(find "$DESTINO_DEF" -name "*.tar.gz" 2>/dev/null)" ]; then
        stk_mostrar_error "No hay backups disponibles para restaurar." "Presione Enter..."
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

autocopy_atomatic() {
    trap "stk_limpiar; return" SIGINT

    while true; do
        stk_limpiar
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
            stk_mostrar_error "❌ Espacio insuficiente en el disco local para comprimir este directorio." "Presione Enter para continuar..."
            continue
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

ejecutar_sincronizacion_bash() {
    local origen="$1"
    local destino="$2"
    local modo="$3"

    if ! mkdir -p "$destino" 2>/dev/null; then
        stk_mostrar_error "\n❌ Error: No se tienen permisos para escribir en el destino: $destino" "Presione Enter..."
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
        stk_limpiar
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
                    stk_mostrar_info "No hay perfiles guardados." "Presione Enter..."
                    continue
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
                    stk_mostrar_exito "✔ Perfil '$p_target' eliminado." "Presione Enter..."
                fi
                ;;

            3)
                stk_limpiar
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

hacer_backup() {
    trap "stk_limpiar; return" SIGINT

    while true; do
        stk_limpiar
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

# Helper unificado para lanzar módulos STK.
# Uso: stk_ejecutar_modulo <nombre> <modo> [args...]
#   nombre: nombre base del módulo, sin extensión (ej: "dash4me")
#   modo:   normal | tui
#     normal - lanzamiento estándar
#     tui    - absorbe SIGINT/SIGTERM en STK para que el hijo gestione Ctrl+C
stk_ejecutar_modulo() {
    local nombre="${1:-}"
    local modo="${2:-normal}"
    shift 2 2>/dev/null || shift $# 2>/dev/null || true

    local dir="${SCRIPT_DIR:-$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)}"
    local target="" rc=0

    if [ -z "$nombre" ]; then
        echo -e "${ROJO:-}❌ Error: nombre de módulo vacío${RESET:-}" >&2
        return 1
    fi

    # Resolución estricta: solo módulos junto a STK
    if [ -f "$dir/${nombre}.sh" ]; then
        target="bash:$dir/${nombre}.sh"
    else
        echo -e "${ROJO:-}❌ Error: No se encuentra ${nombre}.sh en ${dir}${RESET:-}" >&2
        registrar_log "${LOG_ERR:-ERROR}" "Módulo no encontrado: ${nombre}" 2>/dev/null || true
        read -r -p "Presione Enter para continuar..."
        return 1
    fi

    # TUI/monitor: el padre absorbe la señal; el hijo hereda SIG_DFL y puede
    # instalar su propio trap (restaurar alt-screen/cursor, etc.).
    if [ "$modo" = "tui" ]; then
        trap ':' SIGINT SIGTERM
    fi

    if [[ "$target" == bash:* ]]; then
        bash "${target#bash:}" "$@"
        rc=$?
    else
        "$target" "$@"
        rc=$?
    fi

    if [ "$modo" = "tui" ]; then
        trap salir SIGINT SIGTERM
    fi

    return "$rc"
}

ejecutar_dash4me() { stk_ejecutar_modulo "dash4me" "tui" "$@"; }

# ==============================================================================
# 5. ORQUESTACIÓN
# ==============================================================================

salir() {
    echo -e "${VERDE}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo ""
    pintar "$AZUL" "Saliendo de forma segura..."
    echo ""
    pintar "$VERDE" "¡Gracias por usar STK, hasta pronto!"
    echo ""
    echo -e "${VERDE}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    stk_resumen_avisos
    exit 0
}

ejecutar_stop4me()      { stk_ejecutar_modulo "stop4me"      "normal" "$@"; }
ejecutar_proc4me()      { stk_ejecutar_modulo "proc4me"      "normal" "$@"; }
ejecutar_jobs4me()      { stk_ejecutar_modulo "jobs4me"      "tui"    "$@"; }
ejecutar_hard4me()      { stk_ejecutar_modulo "hard4me"      "tui"    "$@"; }
ejecutar_install4me()   { stk_ejecutar_modulo "install4me"   "normal" "$@"; }
ejecutar_localscan4me() { stk_ejecutar_modulo "localscan4me" "normal" "$@"; }
ejecutar_stk_cron()     { stk_ejecutar_modulo "stk_cron"     "normal" "$@"; }

menu() {
    # Precalienta el dashboard mientras el usuario lee el menú (sin bloquear).
    dashboard_cacheado </dev/null >/dev/null 2>&1 &
    while true; do
        stk_limpiar

opciones="0. 🤖 | MODO AUTO       | Update + Servicios + Auditoria + Limpieza
1. 📊 | MONITORIZACIÓN  | Rendimiento, red, disco y servicios
2. 🛡️ | SEGURIDAD       | Auditoria de red, procesos y firewall
3. 📦 | SOFTWARE        | Actualización e instalación
4. ⚙️ | ADMINISTRACIÓN  | Usuarios, servicios y backups
5. 🧹 | MANTENIMIENTO   | Limpieza de sistema y logs
6. 📅 | TAREAS AUTO     | Programar tareas automáticas
7. ❌ | SALIR           | Control+C"

        # Capturamos la selección
        seleccion=$(echo -e "$opciones" | stk_fzf_menu "Seleccione" "System Tool Kit")

        # Salida si se cancela con ESC o si está vacío
        if [ $? -ne 0 ] || [ -z "$seleccion" ]; then salir; fi

        # Extraemos solo el número antes del punto para el case
        case ${seleccion%%.*} in

            0) # --- MODO AUTO ---
                modo_auto
                ;;

            1) menu_monitoreo ;;

            2) menu_seguridad ;;

            3) menu_software ;;

            4) menu_administracion ;;

            5) menu_mantenimiento ;;

            6)
                # Gestor de tareas automatizadas
                ejecutar_stk_cron
                ;;

            7) salir ;;
        esac
    done
}


# 5.4 Arranque (inicialización y despacho CLI)

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
# Fedora Silverblue, Kinoite, COSMIC Atomic, CoreOS y derivados.
IMMUTABLE=false
REINICIO_REQUERIDO=false
INSTALACION_OK=false
if [ -f /run/ostree-booted ] && command -v rpm-ostree &>/dev/null; then
    IMMUTABLE=true
    # rpm-ostree implica un sistema basado en RPM; usa los mapeos de Fedora/RHEL.
    [ "$Package" = "unknown" ] && Package="dnf"
fi

# --- CAPTURA DE SEÑALES ---
trap salir SIGINT SIGTERM

# --- DEFINICIÓN DE DEPENDENCIAS ---
dependencies=(fzf xsltproc host tput free curl wget tar hostname js jq rsync crontab)

# --- FLUJO PRINCIPAL DE DEPENDENCIAS ---
if ! ping -c 1 -W 1 -n 8.8.8.8 &>/dev/null; then
    # ICMP suele estar bloqueado en servidores: es un aviso, no un error fatal.
    stk_avisar warn sin_red \
        "No se pudo verificar Internet con ping (puede estar bloqueado o faltar ping). Algunas funciones podrían fallar."
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
        if install_tools "${missing_tools[@]}"; then
            INSTALACION_OK=true
        else
            pintar "$AMARILLO" "⚠️ La instalación automática no terminó correctamente."
        fi
        check_dependencies

        crear_enlace_js

        if ! command -v fzf &>/dev/null; then
            if [ "$IMMUTABLE" = true ] && [ "$INSTALACION_OK" = true ]; then
                if [ "$REINICIO_REQUERIDO" = true ]; then
                    echo -e "${AMARILLO}⚠️ fzf quedó preparado en una nueva capa de rpm-ostree.${RESET}"
                else
                    echo -e "${AMARILLO}⚠️ fzf no está disponible en esta sesión.${RESET}"
                fi
                echo -e "${AMARILLO}🔄 Reinicia el sistema y vuelve a ejecutar STK.${RESET}"
                registrar_log "$LOG_INFO" "Dependencias preparadas con rpm-ostree; reinicio pendiente."
                read -p "Presiona Enter para salir..."
                exit 0
            fi
            echo -e "${ROJO}❌ Error crítico: fzf no se pudo instalar o no está en el PATH. Si lo has instalado con Git puede haber problemas con la ruta y el uso de sudo. Puedes instalarlo de forma automatica para solucionarlo y tener ambos sin problema.${RESET}"
            registrar_log "$LOG_ERR" "Error crítico: fzf no pudo ser instalado."
            exit 1
        fi

        if [ ${#missing_tools[@]} -gt 0 ]; then
            if [ "$IMMUTABLE" = true ] && [ "$INSTALACION_OK" = true ]; then
                echo -e "${AMARILLO}⚠️ Aún faltan herramientas: ${missing_tools[*]}.${RESET}"
                echo -e "${AMARILLO}🔄 Si se han preparado con rpm-ostree, reinicia el sistema para aplicarlas.${RESET}"
            else
                echo -e "${ROJO}⚠️ Advertencia: Aún faltan herramientas: ${missing_tools[*]}. El script podría fallar.${RESET}"
            fi
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

# --- LOGO Y DASHBOARD DE ESTADO (estilo PROC4ME) ---
DASH_REFRESCO=15      # Caché de métricas dinámicas (carga, RAM, disco, temperatura)
DASH_SEG_REFRESCO=180 # Caché del bloque de seguridad (servicios, firewall, SSH, red)
LOGO_DASH_CACHE="$STK_TMP_DIR/dashboard_${UID:-0}"
LOGO_SEG_CACHE="$STK_TMP_DIR/seguridad_${UID:-0}"

# Datos que no cambian durante la ejecución: se leen una sola vez.
KERNEL_STK=$(uname -r 2>/dev/null || echo "N/D")
HOST_STK=$(hostname 2>/dev/null || cat /etc/hostname 2>/dev/null || echo "Desconocido")
SO_STK="${PRETTY_NAME:-${OS_ID:-Desconocido}}"

# --- CONFIGURACIÓN DEL MODO AUTOMÁTICO ---
AUTO_MIN_ESPACIO_MB=1024          # Espacio libre mínimo en / para actualizar
AUTO_TIMEOUT_ACTUALIZACION=3600   # 60 min para el bloque de actualización
AUTO_TIMEOUT_LIMPIEZA=600         # 10 min por comando de limpieza
AUTO_LIMPIEZA_LOG_DIAS=7          # Retención de logs del journal (limpieza segura)
AUTO_LIMITE_SUID=60               # Umbral de binarios SUID considerados anormales en auditoria
STK_ESTADO_DIR="/var/lib/stk"     # snapshots lógicos (sin informes JSON)

# --- BIBLIOTECA COMPARTIDA DEL MODO AUTOMÁTICO ---
# Una sola implementación de lock, preflight, snapshot, actualización,
# limpieza, auditoría y servicios para stk2.sh y para el cron.
STK_AUTO_LIB="$SCRIPT_DIR/stk_auto_lib.sh"
if [ ! -f "$STK_AUTO_LIB" ]; then
    STK_AUTO_LIB=$(find /home /root /usr/local -maxdepth 5 -name "stk_auto_lib.sh" 2>/dev/null | head -n 1)
fi
if [ -f "$STK_AUTO_LIB" ]; then
    # shellcheck source=stk_auto_lib.sh
    source "$STK_AUTO_LIB"
else
    pintar "$ROJO" "❌ No se encuentra $STK_AUTO_LIB. El modo automático no está disponible."
fi

# --- CONFIGURACIÓN DE BACKUPS ---

CONFIG_JSON="/var/backups/stk_backups/config.json"
DESTINO_DEF="/var/backups/stk_backups"

# --- EJECUCIÓN ---
rotar_logs "silencioso"

# Comprobación de flags pasados como argumento al script
case "$1" in
    -m|--monitor|stk_monitor)
        ejecutar_dash4me
        exit 0
        ;;

    -a|--audit|auditoria_seguridad)
        auditoria_seguridad
        ;;

    -u|--update|actualizacion)
        Actualizar_sistema
        ;;

    -c|--clean|limpieza)
        stk_limpieza completa
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

    -D|--disk|hard4me)
        ejecutar_hard4me
        ;;

    -d|--diagnostico)
        stk_caps_init
        stk_diagnostico
        exit 0
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