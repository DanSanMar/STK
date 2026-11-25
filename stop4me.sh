#!/bin/bash

# --- INFORMACIÓN DEL MÓDULO ---
DESCRIPCION="Instalación, Gestión y Configuración de Cortafuegos UFW para Linux"
AUTOR="DanSanMar"

# --- CAPA DE COMPATIBILIDAD STK (TERM / fzf / TTY / rutas) ---
STK_COMPAT_HEADER="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)/stk_header.sh"
if [ -r "$STK_COMPAT_HEADER" ]; then
    # shellcheck source=stk_header.sh
    source "$STK_COMPAT_HEADER"
fi

# --- CAPA DE UI COMPARTIDA DE STK ---
# Se carga antes de las definiciones propias: fzf_estilo() y el dashboard
# delegan en stk_fzf modulo para conservar el marco STK.
STK_UI_LIB="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)/stk_ui_lib.sh"
if [ -r "$STK_UI_LIB" ]; then
    # shellcheck source=stk_ui_lib.sh
    source "$STK_UI_LIB"
fi

V="${STK_VERSION:-7.0.0}"
ver="v ${STK_VERSION:-7.0.0} · STOP4ME"
STK_MODULO="STOP4ME"

# --- CONFIGURACIÓN DE COLORES (Estilo STK / dash4me) ---
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
GRIS_CLARO='\e[37m'

# --- CONFIGURACIÓN DE LOGS DE GESTIÓN ---
LOG_FILE="/var/log/stk_mantenimiento.log"
LOG_INFO="INFO"
LOG_WARN="WARN"
LOG_ERR="ERROR"


registrar_log() {
    local NIVEL="${1:-INFO}"
    local MENSAJE="${2}"
    local FECHA
    FECHA=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$FECHA] [$NIVEL] [$USER] - [STOP4ME] $MENSAJE" >> "$LOG_FILE"
}

# --- COMPROBACIÓN DE PRIVILEGIOS DE ROOT ---
if [ "$EUID" -ne 0 ]; then
    echo -e "${ROJO_BRILLANTE}⚠️ Error: Este script requiere privilegios de root.${RESET}"
    echo -e "${AMARILLO}Prueba con: sudo $0${RESET}"
    exit 1
fi

if [ ! -f "$LOG_FILE" ]; then
    umask 027
    touch "$LOG_FILE"
    chmod 640 "$LOG_FILE"
    registrar_log "$LOG_INFO" "Bitácora inicializada desde $ver"
fi

# --- DETECCIÓN DEL GESTOR DE PAQUETES ---
Package=""
if [ -f /etc/os-release ]; then
    . /etc/os-release
    OS_ID="${ID:-unknown}"
    OS_LIKE="${ID_LIKE:-unknown}"
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
        elif command -v apt &>/dev/null;    then Package="apt"
        elif command -v dnf &>/dev/null;    then Package="dnf"
        elif command -v pacman &>/dev/null; then Package="pacman"
        else Package="unknown"; fi
        ;;
esac

# --- DETECCIÓN DE SISTEMAS INMUTABLES (OSTREE / RPM-OSTREE) ---
IMMUTABLE=false
if [ -f /run/ostree-booted ] && command -v rpm-ostree &>/dev/null; then
    IMMUTABLE=true
    [ "$Package" = "unknown" ] && Package="dnf"
fi

# --- DASHBOARD Y PREVIEW DE MÓDULO (patrón cron4me) ---
stk_dash_stop4me() {
    local iface="N/A" ip_addr="N/A"
    iface=$(ip route 2>/dev/null | awk '/default/ {print $5; exit}')
    if [ -n "$iface" ]; then
        ip_addr=$(ip -4 addr show "$iface" 2>/dev/null | awk '/inet / {print $2; exit}' | cut -d/ -f1)
    else
        iface="Ninguna"
        ip_addr="Desconectado"
    fi

    local ufw_status="NO INSTALADO" ufw_policies="N/A" ufw_rules="0" ufw_log="N/A"
    if command -v ufw &>/dev/null; then
        local st_ufw
        st_ufw=$(ufw status verbose 2>/dev/null)
        if echo "$st_ufw" | grep -iq "Status: active"; then
            ufw_status="ACTIVO"
            local in_pol out_pol
            in_pol=$(echo "$st_ufw" | grep -i "Default:" | grep -o "deny (incoming)\|allow (incoming)\|reject (incoming)" | cut -d' ' -f1 | tr 'a-z' 'A-Z')
            out_pol=$(echo "$st_ufw" | grep -i "Default:" | grep -o "deny (outgoing)\|allow (outgoing)\|reject (outgoing)" | cut -d' ' -f1 | tr 'a-z' 'A-Z')
            ufw_policies="IN:${in_pol:-DENY} OUT:${out_pol:-ALLOW}"
            ufw_rules=$(ufw status numbered 2>/dev/null | grep -cE '^\[ *[0-9]+\]')
            ufw_log=$(echo "$st_ufw" | grep -i "Logging:" | awk '{print $2; exit}' | tr 'a-z' 'A-Z')
        else
            ufw_status="INACTIVO"
            ufw_policies="N/A"
        fi
    fi

    echo "  ┃ STOP4ME · UFW:$ufw_status · reglas:$ufw_rules · $ufw_policies · log:${ufw_log:-N/A} · $iface($ip_addr)"
}

stk_preview_stop4me() {
    local sel="$1"
    case "${sel%%.*}" in
        1) echo "Activar, desactivar o recargar UFW." ;;
        2) echo "Gestionar reglas por puerto, servicio o IP." ;;
        3) echo "Analizar tráfico, escaneos y auditoría de eventos." ;;
        4) echo "Restablecer UFW a la configuración de fábrica." ;;
        5) echo "Volver al menú anterior." ;;
        *) echo "Seleccione una opción del gestor de cortafuegos." ;;
    esac
}
PREVIEW_STOP4ME="$(declare -f stk_preview_stop4me); stk_preview_stop4me \"\$1\""

fzf_estilo() {
    stk_fzf modulo "$1" "${2:-}" "$PREVIEW_STOP4ME"
}

mostrar_logo_stop4me() {
    mostrar_logo
}

# Wrapper de compatibilidad: los menús usan el marco STK con dashboard/preview.
stop4me_fzf_menu() {
    local prompt_text="$1"
    fzf_estilo "$prompt_text"
}

salir_stop4me() {
    echo -e "\n${VERDE}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    pintar "$AZUL" "Saliendo de Stop4me..."
    pintar "$VERDE" "¡Gracias por usar UFW con All4me!"
    echo -e "${VERDE}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"
    if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
        exit 0
    fi
}

# --- VERIFICACIÓN DE DEPENDENCIAS ---
verificar_e_instalar_ufw() {
    if ! command -v ufw &>/dev/null; then
        stk_limpiar
        mostrar_logo_stop4me
        pintar "$AMARILLO" "⚠️ No se detectó el cortafuegos 'ufw' instalado en el sistema."

        local gestor_mostrar="$Package"
        [ "$IMMUTABLE" = true ] && gestor_mostrar="rpm-ostree (inmutable)"
        echo -ne "${CIAN}¿Desea instalar UFW automáticamente usando $gestor_mostrar? (s/N): ${RESET}"
        read -r inst_conf

        if [[ "$inst_conf" =~ ^[sS]$ ]]; then
            if [ "$IMMUTABLE" = true ]; then
                echo -e "\n${AZUL}🔄 Instalando UFW en una capa rpm-ostree...${RESET}"
                if rpm-ostree install --idempotent --allow-inactive --apply-live ufw && command -v ufw &>/dev/null; then
                    pintar "$VERDE_BRILLANTE" "✔ UFW aplicado en la sesión actual."
                else
                    echo -e "${AMARILLO}⚠️ No se pudo aplicar en vivo. Preparando la capa para el próximo arranque...${RESET}"
                    if ! rpm-ostree install --idempotent --allow-inactive ufw; then
                        pintar "$ROJO" "❌ Error instalando UFW con rpm-ostree."
                        registrar_log "$LOG_ERR" "Fallo al preparar UFW con rpm-ostree."
                        read -p "Presione Enter para volver..."
                        return 1
                    fi
                    if ! command -v ufw &>/dev/null; then
                        pintar "$AMARILLO" "🔄 Reinicia el sistema y vuelve a ejecutar STOP4ME."
                        registrar_log "$LOG_INFO" "UFW preparado con rpm-ostree; reinicio pendiente."
                        read -p "Presione Enter para volver..."
                        return 1
                    fi
                fi
            else
                echo -e "\n${AZUL}🔄 Instalando UFW...${RESET}"
                case "$Package" in
                    apt) apt update -y && apt install -y ufw ;;
                    dnf) dnf install -y ufw ;;
                    pacman) pacman -S --noconfirm ufw ;;
                    zypper) zypper install -y ufw ;;
                    *) pintar "$ROJO" "❌ No se puede instalar UFW automáticamente." ; return 1 ;;
                esac
            fi

            if command -v ufw &>/dev/null; then
                pintar "$VERDE_BRILLANTE" "✔ UFW instalado con éxito."
                registrar_log "$LOG_INFO" "UFW instalado correctamente."
            else
                pintar "$ROJO" "❌ Error instalando UFW."
                read -p "Presione Enter para volver..."
                return 1
            fi
        else
            return 1
        fi
    fi
    return 0
}

# --- FUNCIONES DE CONTROL UFW ---

gestionar_reglas_menu() {
    while true; do
        stk_limpiar
        mostrar_logo_stop4me
        pintar "$MAGENTA" "--- 🔒 GESTIÓN INTERACTIVA DE REGLAS UFW ---"

        local raw_rules
        raw_rules=$(ufw status numbered 2>/dev/null | grep -E '^\[ *[0-9]+\]')

        local fzf_input="[+] ➕ AÑADIR NUEVA REGLA (Puerto / IP / Servicio)\n"
        if [ -n "$raw_rules" ]; then
            fzf_input+="$raw_rules"
        else
            fzf_input+="    (No hay reglas activas registradas)"
        fi

        local sel_regla
        sel_regla=$(echo -e "$fzf_input" | stop4me_fzf_menu "Seleccione regla o acción" "REGLAS ACTIVAS EN UFW" "~80%")

        [ -z "$sel_regla" ] && break

        if [[ "$sel_regla" == *"[+] ➕"* ]]; then
            agregar_regla_unificada
        elif [[ "$sel_regla" =~ \[[[:space:]]*([0-9]+)\] ]]; then
            local num_regla="${BASH_REMATCH[1]}"
            gestionar_regla_existente "$num_regla" "$sel_regla"
        fi
    done
}

agregar_regla_unificada() {
    stk_limpiar
    mostrar_logo_stop4me
    pintar "$CIAN" "--- ➕ CREAR NUEVA REGLA DE FILTRADO ---"

    local opt_accion="1. 🟢 ALLOW (Permitir)\n2. 🔴 DENY (Bloquear/Denegar)\n3. 🚫 REJECT (Rechazar con respuesta)"
    local sel_acc
    sel_acc=$(echo -e "$opt_accion" | stop4me_fzf_menu "Acción" "TIPO DE POLÍTICA" "~70%")
    [ -z "$sel_acc" ] && return

    local accion=""
    case ${sel_acc:0:1} in
        1) accion="allow" ;;
        2) accion="deny" ;;
        3) accion="reject" ;;
        *) return ;;
    esac

    local opt_tipo="1. 🔌 Por Puerto / Servicio (ej: 80, 443/tcp, ssh)\n2. 🌐 Por Dirección IP / Subred (ej: 192.168.1.50, 10.0.0.0/24)\n3. 🎯 Por IP Y Puerto Específico"
    local sel_tipo
    sel_tipo=$(echo -e "$opt_tipo" | stop4me_fzf_menu "Criterio" "APLICAR REGLA POR" "~70%")
    [ -z "$sel_tipo" ] && return

    local cmd_args=()
    local log_msg=""

    case ${sel_tipo:0:1} in
        1)
            echo -ne "\n${AMARILLO}Ingrese el puerto/servicio (ej: 80, 443/tcp, ssh): ${RESET}"
            read -r target
            [ -z "$target" ] && { pintar "$ROJO" "⚠️ Valor vacío. Cancelado."; sleep 1.5; return; }
            cmd_args=("$accion" "$target")
            log_msg="Regla UFW añadida: $accion puerto/servicio $target"
            ;;
        2)
            echo -ne "\n${AMARILLO}Ingrese IP o Subred (ej: 192.168.1.50 o 10.0.0.0/24): ${RESET}"
            read -r target
            [ -z "$target" ] && { pintar "$ROJO" "⚠️ Valor vacío. Cancelado."; sleep 1.5; return; }
            cmd_args=("$accion" "from" "$target")
            log_msg="Regla UFW añadida: $accion origen $target"
            ;;
        3)
            echo -ne "\n${AMARILLO}Ingrese la IP de Origen: ${RESET}"
            read -r ip_src
            echo -ne "${AMARILLO}Ingrese el Puerto de Destino: ${RESET}"
            read -r port_dst
            if [ -z "$ip_src" ] || [ -z "$port_dst" ]; then
                pintar "$ROJO" "⚠️ Se requieren ambos datos. Cancelado."
                sleep 1.5; return
            fi
            cmd_args=("$accion" "from" "$ip_src" "to" "any" "port" "$port_dst")
            log_msg="Regla UFW añadida: $accion IP $ip_src hacia puerto $port_dst"
            ;;
        *) return ;;
    esac

    echo -e "\n${AZUL}🔄 Aplicando: ${AMARILLO}ufw ${cmd_args[*]}${RESET}"
    if ufw "${cmd_args[@]}"; then
        pintar "$VERDE_BRILLANTE" "✔ Regla aplicada con éxito."
        registrar_log "$LOG_INFO" "$log_msg"
    else
        pintar "$ROJO" "❌ Error al intentar aplicar la regla en UFW."
        registrar_log "$LOG_ERR" "Error ejecutando: ufw ${cmd_args[*]}"
    fi
    read -p "Presione Enter para continuar..."
}

gestionar_regla_existente() {
    local num_regla="$1"
    local detalle_regla="$2"

    local opciones="1. ❌ Eliminar esta regla (#$num_regla)\n2. 📥 Insertar regla antes de esta (#$num_regla)\n3. ↩ Volver"
    local sel
    sel=$(echo -e "$opciones" | stop4me_fzf_menu "Acción" "REGLA SELECCIONADA" "~70%")

    case ${sel:0:1} in
        1)
            echo -ne "\n${ROJO_BRILLANTE}⚠️ ¿Confirmar eliminación de la regla #$num_regla? (s/N): ${RESET}"
            read -r conf
            if [[ "$conf" =~ ^[sS]$ ]]; then
                if ufw --force delete "$num_regla"; then
                    pintar "$VERDE_BRILLANTE" "✔ Regla #$num_regla eliminada con éxito."
                    registrar_log "$LOG_WARN" "Regla UFW #$num_regla eliminada."
                else
                    pintar "$ROJO" "❌ Fallo al eliminar la regla."
                fi
            else
                pintar "$AZUL" "Operación cancelada."
            fi
            sleep 1.5
            ;;
        2)
            echo -ne "\n${AMARILLO}Ingrese la acción (allow/deny): ${RESET}"
            read -r acc_ins
            echo -ne "\n${AMARILLO}Ingrese la regla (ej: 80/tcp o from 192.168.1.1): ${RESET}"
            read -r rule_ins

            if [ -n "$acc_ins" ] && [ -n "$rule_ins" ]; then
                read -r -a extra_args <<< "$rule_ins"
                if ufw insert "$num_regla" "$acc_ins" "${extra_args[@]}"; then
                    pintar "$VERDE_BRILLANTE" "✔ Regla insertada correctamente en la posición #$num_regla."
                    registrar_log "$LOG_INFO" "Regla insertada en pos #$num_regla: $acc_ins $rule_ins"
                else
                    pintar "$ROJO" "❌ Error al insertar la regla en UFW."
                fi
            else
                pintar "$ROJO" "⚠️ Datos incompletos."
            fi
            read -p "Presione Enter para continuar..."
            ;;
    esac
}

gestionar_estado_ufw() {
    stk_limpiar
    mostrar_logo_stop4me
    pintar "$MAGENTA" "--- CONTROL DE ESTADO DE UFW ---"

    local st_ufw
    st_ufw=$(ufw status 2>/dev/null | head -n 1)

    local opciones=""
    if [[ "$st_ufw" == *"active"* ]] && [[ "$st_ufw" != *"inactive"* ]]; then
        opciones="0. 📊 Ver Estado Actual y Reglas Detalladas\n1. 🛑 Desactivar Cortafuegos (Disable)\n2. 🔄 Reiniciar Cortafuegos (Reload)\n3. ↩ Volver"
    else
        opciones="1. 🛡️ Activar Cortafuegos (Enable)\n2. ↩ Volver"
    fi

    local sel
    sel=$(echo -e "$opciones" | stop4me_fzf_menu "Acción de Estado" "ESTADO DE UFW" "~70%")

    case ${sel:0:1} in
        0) ver_estado_y_reglas ;;
        1)
            if [[ "$st_ufw" == *"active"* ]] && [[ "$st_ufw" != *"inactive"* ]]; then
                ufw --force disable
                registrar_log "$LOG_WARN" "Cortafuegos UFW desactivado."
                pintar "$ROJO_BRILLANTE" "⚠️ UFW ha sido desactivado."
            else
                systemctl enable ufw &>/dev/null
                ufw --force enable
                registrar_log "$LOG_INFO" "Cortafuegos UFW activado."
                pintar "$VERDE_BRILLANTE" "✔ UFW ha sido activado correctamente."
            fi
            read -p "Presione Enter para continuar..."
            ;;
        2)
            if [[ "$st_ufw" == *"active"* ]] && [[ "$st_ufw" != *"inactive"* ]]; then
                ufw reload
                registrar_log "$LOG_INFO" "Reglas de UFW recargadas."
                pintar "$VERDE" "✔ Reglas recargadas correctamente."
                read -p "Presione Enter para continuar..."
            fi
            ;;
    esac
}

ver_estado_y_reglas() {
    stk_limpiar
    mostrar_logo_stop4me
    pintar "$CIAN" "--- ESTADO Y REGLAS DE FILTRADO (UFW) ---"
    echo ""
    
    if ufw status 2>/dev/null | grep -q "inactive"; then
        pintar "$AMARILLO" "⚠️ El cortafuegos se encuentra actualmente DESACTIVADO."
    else
        echo -e "${VERDE_BRILLANTE}📋 REGLAS NUMERADAS ACTIVAS:${RESET}\n"
        ufw status verbose
    fi
    
    echo ""
    read -p "Presione Enter para volver..."
}

resetear_cortafuegos() {
    stk_limpiar
    mostrar_logo_stop4me
    pintar "$ROJO_BRILLANTE" "--- ⚠️ REINICIO DE FÁBRICA / RESET UFW ---"
    echo -e "${AMARILLO}Esta acción eliminará TODAS las reglas e inhabilitará el cortafuegos.${RESET}\n"

    echo -ne "${ROJO_BRILLANTE}¿Está seguro de restablecer el cortafuegos a los valores por defecto? (s/N): ${RESET}"
    read -r conf

    if [[ "$conf" =~ ^[sS]$ ]]; then
        echo "y" | ufw reset >/dev/null 2>&1
        ufw --force disable >/dev/null 2>&1
        
        registrar_log "$LOG_WARN" "Reset completo de UFW ejecutado correctamente."
        pintar "$VERDE_BRILLANTE" "✔ Cortafuegos restablecido de fábrica exitosamente."
    else
        pintar "$AZUL" "Operación cancelada."
    fi
    read -p "Presione Enter para continuar..."
}

obtener_logs_trafico() {
    if [ -f /var/log/ufw.log ]; then
        cat /var/log/ufw.log
    elif command -v journalctl &>/dev/null; then
        journalctl -u ufw --no-pager -n 1000 2>/dev/null | grep "UFW"
        if [ $? -ne 0 ]; then
            dmesg | grep "UFW"
        fi
    elif [ -f /var/log/syslog ]; then
        grep "UFW" /var/log/syslog
    elif [ -f /var/log/messages ]; then
        grep "UFW" /var/log/messages
    else
        echo ""
    fi
}

detectar_escaneo_puertos() {
    stk_limpiar
    mostrar_logo_stop4me
    pintar "$ROJO_BRILLANTE" "--- DETECTOR DE ESCANEOS DE PUERTOS (PORT SCAN) ---"
    echo -e "${AZUL}Analizando IPs que impactaron múltiples puertos distintos...${RESET}\n"

    local raw_logs
    raw_logs=$(obtener_logs_trafico | grep -E "BLOCK|DENY")
    
    if [ -z "$raw_logs" ]; then
        pintar "$VERDE_BRILLANTE" "✔ No hay registros suficientes para analizar escaneos."
    else
        echo -e "${ROJO}EVENTOS | PUERTOS UNICOS | IP ORIGEN${RESET}"
        echo -e "${CIAN}--------------------------------------------------${RESET}"
        
        local reporte_escan
        reporte_escan=$(echo "$raw_logs" | awk '
            /SRC=/ && /DPT=/ {
                for(i=1;i<=NF;i++) {
                    if($i ~ /^SRC=/) ip=substr($i,5)
                    if($i ~ /^DPT=/) port=substr($i,5)
                }
                if(ip != "" && port != "") {
                    count[ip]++
                    ports[ip, port]=1
                }
            }
            END {
                for(ip in count) {
                    unique=0
                    for(k in ports) {
                        split(k, idx, SUBSEP)
                        if(idx[1] == ip) unique++
                    }
                    print count[ip], unique, ip
                }
            }' | sort -nr -k2)

        if [ -z "$reporte_escan" ]; then
            pintar "$VERDE_BRILLANTE" "✔ No se detectaron patrones de escaneo de puertos activos."
        else
            echo "$reporte_escan" | awk '{printf "  %-7s|   %-13s|   %s\n", $1, $2, $3}'
            echo -e "${CIAN}--------------------------------------------------${RESET}"
            
            echo -ne "\n${AMARILLO}¿Desea bloquear alguna IP detectada? (s/N): ${RESET}"
            read -r bloq_conf
            if [[ "$bloq_conf" =~ ^[sS]$ ]]; then
                echo -ne "${AMARILLO}Ingrese la IP a bloquear en UFW: ${RESET}"
                read -r ip_block
                if [ -n "$ip_block" ]; then
                    ufw deny from "$ip_block"
                    registrar_log "$LOG_WARN" "IP bloqueada tras detectar escaneo: $ip_block"
                    pintar "$VERDE_BRILLANTE" "✔ Regla 'DENY' aplicada correctamente para $ip_block"
                fi
            fi
        fi
    fi
    read -p "Presione Enter para continuar..."
}

detector_fuerza_bruta(){
    stk_limpiar
    mostrar_logo_stop4me
    pintar "$ROJO_BRILLANTE" "--- DETECTOR DE INTENTOS DE FUERZA BRUTA (SSH / AUTH) ---"
    echo -e "${AZUL}Buscando accesos fallidos en /var/log/auth.log y systemd journal...${RESET}\n"

    local auth_logs=""
    if [ -f /var/log/auth.log ]; then
        auth_logs=$(grep -E "Failed password|Invalid user" /var/log/auth.log 2>/dev/null)
    elif command -v journalctl &>/dev/null; then
        auth_logs=$(journalctl -u ssh -u sshd --no-pager -n 2000 2>/dev/null | grep -E "Failed password|Invalid user")
    fi

    if [ -z "$auth_logs" ]; then
        pintar "$VERDE_BRILLANTE" "✔ No se encontraron intentos fallidos de autenticación recientes."
    else
        echo -e "${ROJO}INTENTOS FALLIDOS | IP ATACANTE${RESET}"
        echo -e "${CIAN}--------------------------------------------------${RESET}"
        
        local bf_report
        bf_report=$(echo "$auth_logs" | grep -oE "from [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+" | awk '{print $2}' | sort | uniq -c | sort -nr)
        
        echo "$bf_report" | awk '{printf "  %-16s|   %s\n", $1, $2}'
        echo -e "${CIAN}--------------------------------------------------${RESET}"

        echo -ne "\n${AMARILLO}¿Desea bloquear permanentemente una IP agresora? (s/N): ${RESET}"
        read -r bloq_bf
        if [[ "$bloq_bf" =~ ^[sS]$ ]]; then
            echo -ne "${AMARILLO}Ingrese la IP a aplicar DENY: ${RESET}"
            read -r ip_bf
            if [ -n "$ip_bf" ]; then
                ufw deny from "$ip_bf"
                registrar_log "$LOG_WARN" "IP Bloqueada por Fuerza Bruta: $ip_bf"
                pintar "$VERDE_BRILLANTE" "✔ IP $ip_bf bloqueada en el cortafuegos."
            fi
        fi
    fi
    read -p "Presione Enter para continuar..."
}

informe_auditoria_seguridad(){
    stk_limpiar
    mostrar_logo_stop4me
    pintar "$MAGENTA" "--- GENERADOR DE INFORME DE AUDITORÍA DE SEGURIDAD---"
    
    local raw_blocks
    raw_blocks=$(obtener_logs_trafico | grep -E "BLOCK|DENY")

    if [ -z "$raw_blocks" ]; then
        pintar "$AMARILLO" "⚠️ No se han encontrado registros de tráfico bloqueado."
        read -p "Presione Enter para volver..."
        return
    fi

    local lista_ips
    lista_ips=$(echo "$raw_blocks" | awk '
        /SRC=/ {
            for(i=1;i<=NF;i++) {
                if($i ~ /^SRC=/) ip=substr($i,5)
                if($i ~ /^PROTO=/) proto[ip]=$i
            }
            if(ip != "") count[ip]++
        }
        END {
            for(i in count) {
                printf "%-15s | Bloqueos: %-5d | Tipo: %s\n", i, count[i], proto[i]
            }
        }' | sort -k3 -nr)

    if [ -z "$lista_ips" ]; then
        pintar "$AMARILLO" "No se pudieron extraer direcciones IP del log."
        read -p "Presione Enter para volver..."
        return
    fi
    
    local seleccion_ip
    seleccion_ip=$(echo "$lista_ips" | stk_fzf_ejecutar "Seleccione IP" "IP ORIGEN | IMPACTOS | PROTOCOLO ULTIMO" "INFORME FORENSE" \
        --ansi \
        --height=18 \
        --reverse \
        --border=rounded \
        --prompt="🎯 Seleccione IP para Informe Forense: " \
        --header="IP ORIGEN        | IMPACTOS       | PROTOCOLO ULTIMO")

    if [ -n "$seleccion_ip" ]; then
        local target_ip
        target_ip=$(echo "$seleccion_ip" | awk '{print $1}')

        stk_limpiar
        local logs_ip
        logs_ip=$(echo "$raw_blocks" | grep "SRC=$target_ip")

        local total_intentos
        total_intentos=$(echo "$logs_ip" | wc -l)
        local primer_visto
        primer_visto=$(echo "$logs_ip" | head -n 1 | awk '{print $1, $2, $3}')
        local ultimo_visto
        ultimo_visto=$(echo "$logs_ip" | tail -n 1 | awk '{print $1, $2, $3}')
        local puertos_destino
        puertos_destino=$(echo "$logs_ip" | grep -oE "DPT=[0-9]+" | cut -d'=' -f2 | sort -u | tr '\n' ' ')
        local protocolos
        protocolos=$(echo "$logs_ip" | grep -oE "PROTO=[A-Z]+" | cut -d'=' -f2 | sort -u | tr '\n' ' ')
        local interfaces
        interfaces=$(echo "$logs_ip" | grep -oE "IN=[a-zA-Z0-9_-]+" | cut -d'=' -f2 | sort -u | tr '\n' ' ')
        local mac_addr
        mac_addr=$(echo "$logs_ip" | grep -oE "MAC=[a-fA-F0-9:]+" | head -n 1 | cut -d'=' -f2)

        local hostname_res="No resuelto / IP Pública"
        if command -v host &>/dev/null; then
            hostname_res=$(host "$target_ip" 2>/dev/null | head -n 1 | awk '{print $NF}')
        fi

        echo -e "${CIAN}================================================================================${RESET}"
        echo -e "${VERDE_BRILLANTE}                  INFORME DE AUDITORÍA: $target_ip${RESET}"
        echo -e "${CIAN}================================================================================${RESET}"
        echo -e " 📌 ${AMARILLO}Dominio / Hostname:${RESET}  ${AZUL}${hostname_res}${RESET}"
        echo -e " 📊 ${AMARILLO}Volumen de Impactos:${RESET} ${ROJO_BRILLANTE}${total_intentos} paquetes bloqueados${RESET}"
        echo -e " ⏱️  ${AMARILLO}Rango Temporal:${RESET}      ${CIAN}${primer_visto:-"N/A"}${RESET}  ➔  ${CIAN}${ultimo_visto:-"N/A"}${RESET}"
        echo -e " 🔌 ${AMARILLO}Interfaces Afectadas:${RESET}${VERDE}${interfaces:-"N/A"}${RESET}"
        echo -e " 🌐 ${AMARILLO}Protocolos Utilizados:${RESET}${MAGENTA}${protocolos:-"N/A"}${RESET}"
        echo -e " 🎯 ${AMARILLO}Puertos Destino (DPT):${RESET}${AMARILLO}${puertos_destino:-"N/A"}${RESET}"
        if [ -n "$mac_addr" ]; then
            echo -e " 💻 ${AMARILLO}Dirección MAC Traza:${RESET}  ${AZUL}${mac_addr}${RESET}"
        fi
        echo -e "${CIAN}--------------------------------------------------------------------------------${RESET}"
        echo -e "${AZUL}🔍 MUESTREO DE TRAZAS Y PAQUETES DETECTADOS (Filtrable con FZF):${RESET}\n"

        echo "$logs_ip" | awk '{
            fecha=$1" "$2" "$3
            for(i=1;i<=NF;i++) {
                if($i ~ /^IN=/) iface=substr($i,4)
                if($i ~ /^PROTO=/) proto=substr($i,7)
                if($i ~ /^SPT=/) sport=substr($i,5)
                if($i ~ /^DPT=/) dport=substr($i,5)
                if($i ~ /^LEN=/) len=substr($i,5)
                if($i ~ /^SYN|^ACK|^FIN|^RST/) flag=$i
            }
            if(flag == "") flag="N/A"
            printf " %-15s | Int: %-5s | Proto: %-4s | Puertos: %-5s -> %-5s | Tam: %-4s B | Flag: %-4s\n", fecha, iface, proto, sport, dport, len, flag
        }' | stk_fzf_ejecutar "Explorar logs" "LOGS DE $target_ip" "EXPLORADOR DE LOGS" \
            --ansi --height=15 --reverse --border=rounded \
            --prompt="🔍 Explorar logs de $target_ip: " \
            --header="FECHA/HORA       | INTERFAZ  | PROTO | ORIGEN -> DESTINO     | TAMAÑO   | FLAGS"

        echo -ne "\n${AMARILLO}¿Desea bloquear permanentemente la IP $target_ip en UFW? (s/N): ${RESET}"
        read -r conf_den
        if [[ "$conf_den" =~ ^[sS]$ ]]; then
            ufw deny from "$target_ip"
            registrar_log "$LOG_WARN" "IP bloqueada tras análisis forense: $target_ip"
            pintar "$VERDE_BRILLANTE" "✔ Regla 'DENY' aplicada correctamente para $target_ip"
        fi
    fi
    read -p "Presione Enter para continuar..."
}

analizar_trafico_red() {
    while true; do
        stk_limpiar
        mostrar_logo_stop4me
        pintar "$MAGENTA" "--- AUDITORÍA DE SEGURIDAD, ESCANEOS E INFORMES ---"

        local log_status
        log_status=$(ufw status verbose 2>/dev/null | grep -i "Logging:" | sed -n 's/.*Logging:[[:space:]]*//p')
        echo -e "${AMARILLO}➤ Nivel Logging UFW:${RESET} ${AZUL}${log_status:-"desconocido"}${RESET}\n"

        local opciones_tr="1. 🛑 Tráfico Bloqueado en Tiempo Real\n2. 📊 Auditoria de Seguridad de Logs\n3. ⚙️ Nivel de Registro de UFW\n4. 📋 Bitácora Interna de Gestión\n5. ↩ Volver"
        local sel_tr
        sel_tr=$(echo -e "$opciones_tr" | stop4me_fzf_menu "Centro de Seguridad" "DETECCIÓN DE AMENAZAS" "~80%")

        case ${sel_tr:0:1} in
            1)
                stk_limpiar
                pintar "$CIAN" "--- TRÁFICO BLOQUEADO REGISTRADO ---"
                echo -e "${AZUL}Filtra en tiempo real por IP (SRC=) o Puerto (DPT=) usando FZF${RESET}\n"
                
                local datos_block
                datos_block=$(obtener_logs_trafico | grep -E "BLOCK|DENY")

                if [ -z "$datos_block" ]; then
                    pintar "$AMARILLO" "⚠️ No hay logs de tráfico bloqueado. Comprueba si 'Logging' está activado."
                else
                    echo "$datos_block" | stk_fzf_ejecutar "Buscar evento" "TRÁFICO BLOQUEADO" "EVENTOS" --ansi --height=20 --reverse --border=rounded --prompt="🔍 Buscar evento: "
                fi
                read -p "Presione Enter para continuar..."
                ;;
            2)
                detectar_escaneo_puertos
                detector_fuerza_bruta
                informe_auditoria_seguridad
                ;;
            3)
                stk_limpiar
                mostrar_logo_stop4me
                pintar "$CIAN" "--- CONFIGURAR NIVEL DE REGISTRO (LOGGING) DE UFW ---"
                local opt_log="1. 🔴 off (Desactivar registro)\n2. 🟢 low (Básico: registra paquetes bloqueados - Recomendado)\n3. 🟡 medium (Medio: incluye paquetes rechazados e inválidos)\n4. 🟠 high (Alto: registra todos los paquetes con limitación)\n5. ↩ Volver"
                local sel_lvl
                sel_lvl=$(echo -e "$opt_log" | stop4me_fzf_menu "Nivel Logging" "CONFIGURACIÓN UFW LOGGING" "~70%")

                case ${sel_lvl:0:1} in
                    1) ufw logging off ;;
                    2) ufw logging low ;;
                    3) ufw logging medium ;;
                    4) ufw logging high ;;
                    *) continue ;;
                esac
                
                registrar_log "$LOG_INFO" "Nivel de logging de UFW cambiado."
                pintar "$VERDE_BRILLANTE" "✔ Nivel de registro actualizado."
                read -p "Presione Enter para continuar..."
                ;;
            4) gestionar_logs_script ;;
            *) break ;;
        esac
    done
}

gestionar_logs_script() {
    stk_limpiar
    mostrar_logo_stop4me
    pintar "$MAGENTA" "--- AUDITORÍA DE BITÁCORA DE ACCIONES (stk_mantenimiento.log) ---"

    if [ ! -f "$LOG_FILE" ]; then
        pintar "$ROJO" "❌ No se encontró el archivo de logs ($LOG_FILE)."
        read -p "Presione Enter para volver..."
        return
    fi

    local filtro_opt="1. 📋 Ver todos los logs\n2. 🟢 Filtrar por INFO\n3. 🟡 Filtrar por ADVERTENCIAS (WARN)\n4. 🔴 Filtrar por ERRORES (ERROR)\n5. ↩ Volver"
    local sel_filtro
    sel_filtro=$(echo -e "$filtro_opt" | stop4me_fzf_menu "Filtro Log" "ACCIONES DEL SCRIPT" "~70%")

    local tipo_filtro=""
    case ${sel_filtro:0:1} in
        1) tipo_filtro="[STOP4ME]" ;;
        2) tipo_filtro="[INFO]" ;;
        3) tipo_filtro="[WARN]" ;;
        4) tipo_filtro="[ERROR]" ;;
        *) return ;;
    esac

    stk_limpiar
    pintar "$CIAN" "--- LOGS FILTRADOS POR: $tipo_filtro ---"
    echo -e "${AZUL}Tip: Usa FZF para buscar términos dentro de los logs.${RESET}\n"

    grep "STOP4ME" "$LOG_FILE" | grep "$tipo_filtro" | stk_fzf_ejecutar "Buscar evento" "Pulsar ESC o Ctrl+C para salir" "LOGS FILTRADOS" \
        --ansi \
        --height=20 \
        --reverse \
        --border=rounded \
        --prompt="🔍 Buscar evento: " \
        --header="Pulsar ESC o 'Ctrl+C' para salir"

    read -p "Presione Enter para continuar..."
}

# --- MENÚ PRINCIPAL STOP4ME ---
stop4me_main_menu() {
    if ! verificar_e_instalar_ufw; then
        return
    fi

    while true; do
        local opciones="1. ⚡ ESTADO      | Activar / Desactivar / Recargar UFW\n2. 🔌 GESTIÓN     | Reglas por Puerto o Servicio o IP\n3. 🛡️ CONTROL     | Tráfico de Red y Auditoria de Eventos\n4. ⚠️ RESTART     | Vuelve a la Configuración de Fábrica\n5. ↩  Volver"
        local seleccion
        seleccion=$(echo -e "$opciones" | fzf_estilo "Selección")

        if [ $? -ne 0 ] || [ -z "$seleccion" ] || [[ "${seleccion:0:1}" == "5" ]]; then
            salir_stop4me
            break
        fi

        case ${seleccion:0:1} in
            1) gestionar_estado_ufw ;;
            2) gestionar_reglas_menu ;;
            3) analizar_trafico_red ;;
            4) resetear_cortafuegos ;;
        esac
    done
}

# --- PUNTO DE ENTRADA ---
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    stop4me_main_menu
fi

