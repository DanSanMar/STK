#!/bin/bash

# --- INFORMACIÓN DEL MÓDULO ---
V="1.5"
DESCRIPCION="Instalación, Gestión y Configuración de Cortafuegos UFW para Linux"
AUTOR="DanSanMar"

# --- CONFIGURACIÓN DE COLORES (Estilo STK) ---
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

pintar() { 
    local COLOR="$1" 
    local MENSAJE="$2" 
    echo -e "${COLOR}${MENSAJE}${RESET}"
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
    registrar_log "$LOG_INFO" "Bitácora inicializada desde STOP4ME v$V"
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

# --- LOGO ASCII ---
mostrar_logo_stop4me() {
    echo -e "${ROJO}  ███████╗████████╗██████╗ ██████╗  ██╗  ██╗███╗   ███╗███████╗${RESET}"
    echo -e "${ROJO_BRILLANTE}  ██╔════╝╚══██╔══╝██╔═══██╗██╔══██╗ ██║  ██║████╗ ████║██╔════╝${RESET}"
    echo -e "${AMARILLO}  ███████╗   ██║   ██║   ██║██████╔╝ ███████║██╔████╔██║█████╗  ${RESET}"
    echo -e "${AMARILLO}  ╚════██║   ██║   ██║   ██║██╔═══╝  ╚════██║██║╚██╔╝██║██╔══╝  ${RESET}"
    echo -e "${VERDE}  ███████║   ██║   ╚██████╔╝██║           ██║██║ ╚═╝ ██║███████╗${RESET}"
    echo -e "${VERDE_BRILLANTE}  ╚══════╝   ╚═╝    ╚═════╝ ╚═╝           ╚═╝╚═╝     ╚═╝╚══════╝${RESET}"
    echo -e "${VERDE_BRILLANTE}  UFW FIREWALL MANAGER - STOP4ME    ${RESET}\n${AZUL_BRILLANTE}  v${V}${RESET}"
    echo -e "${AZUL}  By: ${AUTOR}${RESET}"
    echo -e "${CIAN}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e "${AMARILLO}➤ Sistema detectado:${RESET} ${AZUL}${OS_ID:-"Desconocido"}${RESET}"
    echo -e "${AMARILLO}➤ Gestor de Paquetes:${RESET} ${AZUL}${Package:-"Desconocido"}${RESET}"
    
    if command -v ufw &>/dev/null; then
        local st_ufw
        st_ufw=$(ufw status 2>/dev/null | head -n 1)
        if [[ "$st_ufw" == *"active"* ]] && [[ "$st_ufw" != *"inactive"* ]]; then
            echo -e "${AMARILLO}➤ Estado UFW:${RESET} ${VERDE_BRILLANTE}ACTIVO 🛡️${RESET}"
        else
            echo -e "${AMARILLO}➤ Estado UFW:${RESET} ${ROJO_BRILLANTE}INACTIVO ⚠️${RESET}"
        fi
    else
        echo -e "${AMARILLO}➤ Estado UFW:${RESET} ${ROJO}NO INSTALADO ❌${RESET}"
    fi
    echo -e "${CIAN}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
}

# --- ESTILOS DE SELECCIÓN ---
fzf_estilo() {
    local prompt_text="$1"
    local header_text="$2"
    fzf --ansi \
        --height=15 \
        --reverse \
        --border=rounded \
        --prompt="➤ $prompt_text: " \
        --header="$header_text" \
        --color="border:#ff5555,pointer:#92ff92,header:#5fb2ff"
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
        clear
        mostrar_logo_stop4me
        pintar "$AMARILLO" "⚠️ No se detectó el cortafuegos 'ufw' instalado en el sistema."
        echo -ne "${CIAN}¿Desea instalar UFW automáticamente usando $Package? (s/N): ${RESET}"
        read -r inst_conf

        if [[ "$inst_conf" =~ ^[sS]$ ]]; then
            echo -e "\n${AZUL}🔄 Instalando UFW...${RESET}"
            case "$Package" in
                apt) apt update -y && apt install -y ufw ;;
                dnf) dnf install -y ufw ;;
                pacman) pacman -S --noconfirm ufw ;;
                zypper) zypper install -y ufw ;;
                *) pintar "$ROJO" "❌ No se puede instalar UFW automáticamente." ; return 1 ;;
            esac

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

# ==============================================================================
# --- GESTIÓN UNIFICADA DE REGLAS (UFW + FZF) ---
# ==============================================================================

gestionar_reglas_menu() {
    while true; do
        clear
        mostrar_logo_stop4me
        pintar "$MAGENTA" "--- 🔒 GESTIÓN INTERACTIVA DE REGLAS UFW ---"

        # 1. Obtención y formateo limpio de reglas activas
        local raw_rules
        raw_rules=$(ufw status numbered 2>/dev/null | grep -E '^\[ *[0-9]+\]')

        # 2. Construcción de la lista para FZF
        local fzf_input="[+] ➕ AÑADIR NUEVA REGLA (Puerto / IP / Servicio)\n"
        if [ -n "$raw_rules" ]; then
            fzf_input+="$raw_rules"
        else
            fzf_input+="    (No hay reglas activas registradas)"
        fi

        # 3. Menú interactivo principal
        local sel_regla
        sel_regla=$(echo -e "$fzf_input" | fzf_estilo "Seleccione regla o acción" "REGLAS ACTIVAS EN UFW (Seleccione para gestionar o eliminar)")

        # Cancelación o salida con ESC
        [ -z "$sel_regla" ] && break

        # 4. Enrutamiento de acción según selección
        if [[ "$sel_regla" == *"[+] ➕"* ]]; then
            agregar_regla_unificada
        elif [[ "$sel_regla" =~ \[[[:space:]]*([0-9]+)\] ]]; then
            # Extracción limpia del número de regla (maneja alineaciones [ 1] y [10])
            local num_regla="${BASH_REMATCH[1]}"
            gestionar_regla_existente "$num_regla" "$sel_regla"
        fi
    done
}

# --- AÑADIR REGLA (PUERTO, IP O COMBINADO) ---
agregar_regla_unificada() {
    clear
    mostrar_logo_stop4me
    pintar "$CIAN" "--- ➕ CREAR NUEVA REGLA DE FILTRADO ---"

    # Seleccionar Acción
    local opt_accion="1. 🟢 ALLOW (Permitir)\n2. 🔴 DENY (Bloquear/Denegar)\n3. 🚫 REJECT (Rechazar con respuesta)"
    local sel_acc
    sel_acc=$(echo -e "$opt_accion" | fzf_estilo "Acción" "TIPO DE POLÍTICA")
    [ -z "$sel_acc" ] && return

    local accion=""
    case ${sel_acc:0:1} in
        1) accion="allow" ;;
        2) accion="deny" ;;
        3) accion="reject" ;;
        *) return ;;
    esac

    # Seleccionar Criterio
    local opt_tipo="1. 🔌 Por Puerto / Servicio (ej: 80, 443/tcp, ssh)\n2. 🌐 Por Dirección IP / Subred (ej: 192.168.1.50, 10.0.0.0/24)\n3. 🎯 Por IP Y Puerto Específico"
    local sel_tipo
    sel_tipo=$(echo -e "$opt_tipo" | fzf_estilo "Criterio" "APLICAR REGLA POR:")
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

    # Ejecución segura mediante array
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

# --- SUBMENÚ PARA REGLA SELECCIONADA ---
gestionar_regla_existente() {
    local num_regla="$1"
    local detalle_regla="$2"

    local opciones="1. ❌ Eliminar esta regla (#$num_regla)\n2. 📥 Insertar regla antes de esta (#$num_regla)\n3. ↩ Volver"
    local sel
    sel=$(echo -e "$opciones" | fzf_estilo "Acción" "REGLA SELECCIONADA: $detalle_regla")

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
            echo -ne "${AMARILLO}Ingrese la regla (ej: 80/tcp o from 192.168.1.1): ${RESET}"
            read -r rule_ins

            if [ -n "$acc_ins" ] && [ -n "$rule_ins" ]; then
                # Construcción y parseo seguro de argumentos
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
# Gestión estado UFW
gestionar_estado_ufw() {
    clear
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
    sel=$(echo -e "$opciones" | fzf_estilo "Acción de Estado" "ESTADO DE UFW")

    case ${sel:0:1} in
        0) ver_estado_y_reglas
            ;;
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
    clear
    mostrar_logo_stop4me
    pintar "$CIAN" "--- ESTADO Y REGLAS DE FILTRADO (UFW) ---"
    echo ""
    
    if ufw status 2>/dev/null | grep -q "inactive"; then
        pintar "$AMARILLO" "⚠️ El cortafuegos se encuentra actualmente DESACTIVADO."
    else
        echo -e "${VERDE_BRILLANTE}📋 REGLAS NUMERADAS ACTIVAS:${RESET}\n"
        ufw status numbered
    fi
    
    echo ""
    read -p "Presione Enter para volver..."
}

resetear_cortafuegos() {
    clear
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

# --- OBTENER LOGS DE TRÁFICO DEL KERNEL / UFW ---
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
        clear
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
    clear
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
    clear
    mostrar_logo_stop4me
                pintar "$MAGENTA" "--- GENERADOR DE INFORME DE AUDITORÍA DE SEGURIDAD---"
                
                local raw_blocks
                raw_blocks=$(obtener_logs_trafico | grep -E "BLOCK|DENY")

                if [ -z "$raw_blocks" ]; then
                    pintar "$AMARILLO" "⚠️ No se han encontrado registros de tráfico bloqueado."
                    read -p "Presione Enter para volver..."
                    return
                fi

                # Generar estructura resumida para la vista de selección
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
                seleccion_ip=$(echo "$lista_ips" | fzf --ansi \
                    --height=18 \
                    --reverse \
                    --border=rounded \
                    --prompt="🎯 Seleccione IP para Informe Forense: " \
                    --header="IP ORIGEN        | IMPACTOS       | PROTOCOLO ULTIMO")

                if [ -n "$seleccion_ip" ]; then
                    local target_ip
                    target_ip=$(echo "$seleccion_ip" | awk '{print $1}')

                    clear
                    local logs_ip
                    logs_ip=$(echo "$raw_blocks" | grep "SRC=$target_ip")

                    # Métricas avanzadas
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

                    # Intento de resolución DNS inversa
                    local hostname_res="No resuelto / IP Pública"
                    if command -v host &>/dev/null; then
                        hostname_res=$(host "$target_ip" 2>/dev/null | head -n 1 | awk '{print $NF}')
                    fi

                    # Renderizado del Informe en pantalla
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

                    # Generador de tabla de trazabilidad completa
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
                    }' | fzf --ansi --height=15 --reverse --border=rounded \
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

# --- AUDITORÍA AVANZADA DE TRÁFICO, ESCANEOS E INFORMES EXHAUSTIVOS ---
analizar_trafico_red() {
    while true; do
        clear
        mostrar_logo_stop4me
        pintar "$MAGENTA" "--- AUDITORÍA DE SEGURIDAD, ESCANEOS E INFORMES ---"

        local log_status
        log_status=$(ufw status verbose 2>/dev/null | grep -i "Logging:" | sed -n 's/.*Logging:[[:space:]]*//p')
        echo -e "${AMARILLO}➤ Nivel Logging UFW:${RESET} ${AZUL}${log_status:-"desconocido"}${RESET}\n"

        local opciones_tr="1. 🛑 Tráfico Bloqueado en Tiempo Real\n2. 📊 Auditoria de Seguridad de Logs\n3. ⚙️ Nivel de Registro de UFW\n4. 📋 Bitácora Interna de Gestión\n5. ↩ Volver"
        local sel_tr
        sel_tr=$(echo -e "$opciones_tr" | fzf_estilo "Centro de Seguridad" "DETECCIÓN DE AMENAZAS")

        case ${sel_tr:0:1} in
            1)
                clear
                pintar "$CIAN" "--- TRÁFICO BLOQUEADO REGISTRADO ---"
                echo -e "${AZUL}Filtra en tiempo real por IP (SRC=) o Puerto (DPT=) usando FZF${RESET}\n"
                
                local datos_block
                datos_block=$(obtener_logs_trafico | grep -E "BLOCK|DENY")

                if [ -z "$datos_block" ]; then
                    pintar "$AMARILLO" "⚠️ No hay logs de tráfico bloqueado. Comprueba si 'Logging' está activado."
                else
                    echo "$datos_block" | fzf --ansi --height=20 --reverse --border=rounded --prompt="🔍 Buscar evento: "
                fi
                read -p "Presione Enter para continuar..."
                ;;

            2)
                
                detectar_escaneo_puertos
                detector_fuerza_bruta
                informe_auditoria_seguridad
                ;;
                         

            3)
                clear
                mostrar_logo_stop4me
                pintar "$CIAN" "--- CONFIGURAR NIVEL DE REGISTRO (LOGGING) DE UFW ---"
                local opt_log="1. 🔴 off (Desactivar registro)\n2. 🟢 low (Básico: registra paquetes bloqueados - Recomendado)\n3. 🟡 medium (Medio: incluye paquetes rechazados e inválidos)\n4. 🟠 high (Alto: registra todos los paquetes con limitación)\n5. ↩ Volver"
                local sel_lvl
                sel_lvl=$(echo -e "$opt_log" | fzf_estilo "Nivel Logging" "CONFIGURACIÓN UFW LOGGING")

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

# --- BITÁCORA INTERNA DE MANTENIMIENTO ---
gestionar_logs_script() {
    clear
    mostrar_logo_stop4me
    pintar "$MAGENTA" "--- AUDITORÍA DE BITÁCORA DE ACCIONES (stk_mantenimiento.log) ---"

    if [ ! -f "$LOG_FILE" ]; then
        pintar "$ROJO" "❌ No se encontró el archivo de logs ($LOG_FILE)."
        read -p "Presione Enter para volver..."
        return
    fi

    local filtro_opt="1. 📋 Ver todos los logs\n2. 🟢 Filtrar por INFO\n3. 🟡 Filtrar por ADVERTENCIAS (WARN)\n4. 🔴 Filtrar por ERRORES (ERROR)\n5. ↩ Volver"
    local sel_filtro
    sel_filtro=$(echo -e "$filtro_opt" | fzf_estilo "Filtro Log" "ACCIONES DEL SCRIPT")

    local tipo_filtro=""
    case ${sel_filtro:0:1} in
        1) tipo_filtro="[STOP4ME]" ;;
        2) tipo_filtro="[INFO]" ;;
        3) tipo_filtro="[WARN]" ;;
        4) tipo_filtro="[ERROR]" ;;
        *) return ;;
    esac

    clear
    pintar "$CIAN" "--- LOGS FILTRADOS POR: $tipo_filtro ---"
    echo -e "${AZUL}Tip: Usa FZF para buscar términos dentro de los logs.${RESET}\n"

    grep "STOP4ME" "$LOG_FILE" | grep "$tipo_filtro" | fzf --ansi \
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
        clear
        mostrar_logo_stop4me

        local opciones="1. ⚡ Estado / Activar / Desactivar / Recargar UFW\n2. 🔌 Gestión de Reglas por Puerto o Servicio o IP (ALLOW/DENY)\n3. 🛡️ Control de Tráfico de Red y Auditoria de Eventos\n4. ⚠️ Restablecer Cortafuegos de Fábrica (Reset)\n5. ↩ Volver"
        local seleccion
        seleccion=$(echo -e "$opciones" | fzf_estilo "Selección" "S T O P 4 M E  -  U F W  M A N A G E R")

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

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    stop4me_main_menu
fi