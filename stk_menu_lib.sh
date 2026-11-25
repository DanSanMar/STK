# ==============================================================================
# stk_menu_lib.sh - submenús de STK
# Requiere stk_ui_lib.sh y las funciones de acción de stk.sh.
# ==============================================================================

# --- SUBMENÚ MONITORIZACIÓN ---
menu_monitoreo() {
    while true; do
        stk_limpiar
        local preview_mon='
            sel="$1"
            case "${sel%%.*}" in
                1)
                    printf "\033[1;36m📈 RENDIMIENTO DEL SISTEMA\033[0m\n\n"
                    printf "Monitor en vivo (DASH4ME).\n\n"
                    printf "\033[33mMuestra:\033[0m\n"
                    printf "  • CPU, RAM, disco y red\n"
                    printf "  • Temperaturas y GPU (si disponible)\n"
                    printf "  • Arranque y estado general\n\n"
                    printf "\033[32mUso:\033[0m Ver el estado del equipo en tiempo real.\n"
                    ;;
                2)
                    printf "\033[1;36m🌐 REDES Y PUERTOS\033[0m\n\n"
                    printf "Submenú de red local.\n\n"
                    printf "\033[33mIncluye:\033[0m\n"
                    printf "  • Información de red (IP, gateway, DNS, interfaces)\n"
                    printf "  • Escaneo de red local y puertos (LOCALSCAN4ME)\n\n"
                    printf "\033[32mUso:\033[0m Diagnóstico rápido de conectividad y exposición.\n"
                    ;;
                3)
                    printf "\033[1;36m⚙️ ANÁLISIS DE SERVICIOS\033[0m\n\n"
                    printf "Dashboard de servicios y tareas (JOBS4ME).\n\n"
                    printf "\033[33mMuestra:\033[0m\n"
                    printf "  • Servicios systemd y su estado\n"
                    printf "  • Tareas programadas / cron\n\n"
                    printf "\033[32mUso:\033[0m Detectar fallos o cargas anómalas.\n"
                    ;;
                4)
                    printf "\033[1;36m💽 ANÁLISIS DE DISCO\033[0m\n\n"
                    printf "Dashboard de discos (HARD4ME).\n\n"
                    printf "\033[33mMuestra:\033[0m\n"
                    printf "  • Salud SMART/NVMe y temperatura\n"
                    printf "  • Uso, inodos, rendimiento y capas\n\n"
                    printf "\033[32mUso:\033[0m Anticipar problemas de almacenamiento.\n"
                    ;;
                5)
                    printf "\033[1;36m↩ VOLVER\033[0m\n\n"
                    printf "Regresa al menú principal.\n"
                    ;;
            esac'
        accion=$(echo -e "1. 📈 Rendimiento del Sistema\n2. 🌐 Redes y puertos abiertos\n3. ⚙️ Análisis de Servicios\n4. 💽 Análisis de Disco\n5. ↩ Volver" | \
            stk_fzf preview "Seleccione" "MONITORIZACIÓN" "$preview_mon")
        if [[ $? -ne 0 || "$accion" == *"Volver"* ]]; then break; fi
        case ${accion%%.*} in
            1) ejecutar_dash4me ;;
            2)
                # --- SUBMENÚ FUSIONADO DE REDES ---
                while true; do
                    stk_limpiar
                    local preview_red='
                        sel="$1"
                        case "${sel%%.*}" in
                            1)
                                printf "\033[1;36m🌐 INFORMACIÓN DE RED\033[0m\n\n"
                                printf "Resumen de conectividad del equipo.\n\n"
                                printf "\033[33mMuestra:\033[0m\n"
                                printf "  • Interfaz activa, IP local/pública\n"
                                printf "  • Puerta de enlace, DNS, estado Internet\n"
                                printf "  • Detalle por interfaz (RX/TX, Wi-Fi)\n"
                                ;;
                            2)
                                printf "\033[1;36m🔎 LOCALSCAN4ME\033[0m\n\n"
                                printf "Escaneo de red local y puertos.\n\n"
                                printf "\033[33mMuestra:\033[0m\n"
                                printf "  • Dispositivos en la red local\n"
                                printf "  • Puertos abiertos/servicios detectados\n"
                                ;;
                            3)
                                printf "\033[1;36m↩ VOLVER\033[0m\n\nRegresa a Monitorización.\n"
                                ;;
                        esac'
                    red_accion=$(echo -e "1. 🌐 Información de red\n2. 🔎 Escaneo de red y puertos (LOCALSCAN4ME)\n3. ↩ Volver" | \
                        stk_fzf preview "Seleccione" "REDES Y PUERTOS" "$preview_red")
                    if [[ $? -ne 0 || "$red_accion" == *"Volver"* ]]; then break; fi
                    case ${red_accion%%.*} in
                        1) mostrar_info_red ;;
                        2) ejecutar_localscan4me ;;
                    esac
                done
                ;;
            3) ejecutar_jobs4me ;;
            4) ejecutar_hard4me ;;
        esac
    done
}
# --- SUBMENÚ SEGURIDAD ---
menu_seguridad() {
    while true; do
        stk_limpiar
        local preview_sec='
            sel="$1"
            case "${sel%%.*}" in
                1)
                    printf "\033[1;36m🔍 ANÁLISIS DE PROCESOS\033[0m\n\n"
                    printf "Investigador de procesos y amenazas (PROC4ME).\n\n"
                    printf "\033[33mPermite:\033[0m\n"
                    printf "  • Revisar procesos en ejecución\n"
                    printf "  • Detectar comportamientos sospechosos\n"
                    printf "  • Inspeccionar consumo y origen\n"
                    ;;
                2)
                    printf "\033[1;36m🛡️ AUDITORÍA DE SEGURIDAD\033[0m\n\n"
                    printf "Revisión de seguridad del sistema.\n\n"
                    printf "\033[33mComprueba:\033[0m\n"
                    printf "  • Usuarios, contraseñas y privilegios\n"
                    printf "  • Puertos, firewall y SSH\n"
                    printf "  • SUID, MAC, parámetros del kernel\n\n"
                    printf "\033[32mResultado:\033[0m Puntuación y sugerencias de acción.\n"
                    ;;
                3)
                    printf "\033[1;36m🔥 GESTOR DE FIREWALL UFW\033[0m\n\n"
                    printf "Control del cortafuegos (STOP4ME).\n\n"
                    printf "\033[33mPermite:\033[0m\n"
                    printf "  • Ver estado y reglas UFW\n"
                    printf "  • Gestionar puertos y perfiles\n"
                    printf "  • Detectar tráfico sospechoso\n"
                    ;;
                4)
                    printf "\033[1;36m↩ VOLVER\033[0m\n\n"
                    printf "Regresa al menú principal.\n"
                    ;;
            esac'
        accion=$(echo -e "1. 🔍 Análisis de Procesos\n2. 🛡️ Auditoría de Seguridad\n3. 🔥 Gestor de Firewall UFW\n4. ↩ Volver" | \
            stk_fzf preview "Seleccione" "SEGURIDAD" "$preview_sec")
        if [[ $? -ne 0 || "$accion" == *"Volver"* ]]; then break; fi
        case ${accion%%.*} in
            1) ejecutar_proc4me ;;
            2) auditoria_seguridad ;;
            3) ejecutar_stop4me ;;
        esac
    done
}
# --- SUBMENÚ SOFTWARE ---
menu_software() {
    while true; do
        stk_limpiar
        local preview_soft='
            sel="$1"
            case "${sel%%.*}" in
                1)
                    printf "\033[1;36m🔄 ACTUALIZACIÓN DEL SISTEMA (ASISTIDA)\033[0m\n\n"
                    printf "Actualización interactiva: tú decides.\n\n"
                    printf "\033[33mIncluye:\033[0m\n"
                    printf "  • Repositorios y paquetes del sistema\n"
                    printf "  • Flatpak y Snap si están instalados\n"
                    printf "  • Preguntas/prompts de configuración visibles\n\n"
                    printf "\033[33mProtecciones:\033[0m\n"
                    printf "  • Timeouts de red/bloqueo APT\n"
                    printf "  • Si falla APT, ofrece reparar con dpkg\n\n"
                    printf "\033[32mUso:\033[0m Cuando quieres control total sobre la actualización.\n"
                    ;;
                2)
                    printf "\033[1;36m📦 INSTALL4ME\033[0m\n\n"
                    printf "Instalador por categorías.\n\n"
                    printf "\033[33mPermite:\033[0m\n"
                    printf "  • Instalar software desde repos, Flatpak, GitHub, AUR\n"
                    printf "  • Navegar por categorías de aplicaciones\n\n"
                    printf "\033[32mUso:\033[0m Descubrir e instalar programas guiado por menús.\n"
                    ;;
                3)
                    printf "\033[1;36m➕ INSTALAR / DESINSTALAR\033[0m\n\n"
                    printf "Gestión rápida de un paquete por nombre.\n\n"
                    printf "\033[33mPermite:\033[0m\n"
                    printf "  • Instalar un programa indicando su nombre\n"
                    printf "  • Desinstalar un programa existente\n\n"
                    printf "\033[32mUso:\033[0m Cuando ya sabes el nombre exacto del paquete.\n"
                    ;;
                4)
                    printf "\033[1;36m↩ VOLVER\033[0m\n\n"
                    printf "Regresa al menú principal.\n"
                    ;;
            esac'
        accion=$(echo -e "1. 🔄 Actualización del Sistema (Asistida)\n2. 📦 Instalador por categorías (INSTALL4ME)\n3. ➕ Instalar / Desinstalar programa\n4. ↩ Volver" | \
            stk_fzf preview "Seleccione" "SOFTWARE" "$preview_soft")
        if [[ $? -ne 0 || "$accion" == *"Volver"* ]]; then break; fi
        case ${accion%%.*} in
            1) Actualizar_sistema ;;
            2) ejecutar_install4me ;;
            3)
                while true; do
                    stk_limpiar
                    accion_inst=$(echo -e "1. Instalar programa\n2. Desinstalar programa\n3. ↩ Volver" | stk_fzf_menu "Seleccione" "INSTALAR / DESINSTALAR")
                    if [[ $? -ne 0 || "$accion_inst" == *"Volver"* ]]; then break; fi
                    case ${accion_inst%%.*} in
                        1) instalar_programa ;;
                        2) desinstalar_programa ;;
                    esac
                done
                ;;
        esac
    done
}
# --- SUBMENÚ ADMINISTRACIÓN ---
menu_administracion() {
    while true; do
        stk_limpiar
        local preview_admin='
            sel="$1"
            case "${sel%%.*}" in
                1)
                    printf "\033[1;36m👤 GESTIÓN DE USUARIOS\033[0m\n\n"
                    printf "Administración de cuentas del sistema.\n\n"
                    printf "\033[33mPermite:\033[0m\n"
                    printf "  • Listar usuarios humanos\n"
                    printf "  • Crear usuarios y asignar permisos\n"
                    printf "  • Modificar roles (estándar/admin)\n"
                    printf "  • Eliminar usuarios\n"
                    ;;
                2)
                    printf "\033[1;36m⚙️ GESTIÓN DE SERVICIOS\033[0m\n\n"
                    printf "Control de servicios systemd.\n\n"
                    printf "\033[33mPermite:\033[0m\n"
                    printf "  • Ver servicios fallidos/activos\n"
                    printf "  • Reiniciar, detener o ver estado\n"
                    printf "  • Consultar logs (journalctl)\n"
                    printf "  • Habilitar/deshabilitar en arranque\n"
                    ;;
                3)
                    printf "\033[1;36m💾 GESTIÓN DE BACKUPS\033[0m\n\n"
                    printf "Copias de seguridad locales y perfiles.\n\n"
                    printf "\033[33mPermite:\033[0m\n"
                    printf "  • Crear backups comprimidos (.tar.gz)\n"
                    printf "  • Restaurar, inspeccionar o eliminar backups\n"
                    printf "  • Sincronización con COPY4ME/rsync\n"
                    ;;
                4)
                    printf "\033[1;36m↩ VOLVER\033[0m\n\n"
                    printf "Regresa al menú principal.\n"
                    ;;
            esac'
        accion=$(echo -e "1. 👤 Gestión de Usuarios\n2. ⚙️ Gestión de Servicios\n3. 💾 Gestión de Backups\n4. ↩ Volver" | \
            stk_fzf preview "Seleccione" "ADMINISTRACIÓN" "$preview_admin")
        if [[ $? -ne 0 || "$accion" == *"Volver"* ]]; then break; fi
        case ${accion%%.*} in
            1) gestionar_usuarios ;;
            2) gestionar_servicios ;;
            3) hacer_backup ;;
        esac
    done
}
# --- SUBMENÚ MANTENIMIENTO ---
menu_mantenimiento() {
    while true; do
        stk_limpiar
        local preview_mant='
            sel="$1"
            case "${sel%%.*}" in
                1)
                    printf "\033[1;36m🧹 LIMPIEZA AUTO\033[0m\n\n"
                    printf "Ejecuta todos los pasos de limpieza directamente.\n\n"
                    printf "\033[33mIncluye:\033[0m\n"
                    printf "  • Logs del journal antiguos\n"
                    printf "  • Caché de gestores de paquetes\n"
                    printf "  • Miniaturas antiguas\n"
                    printf "  • Paquetes huérfanos/dependencias\n"
                    printf "  • Papelera de usuarios (pide confirmación)\n\n"
                    printf "\033[32mUso:\033[0m Rápido, sin elegir pasos.\n"
                    ;;
                2)
                    printf "\033[1;36m✋ LIMPIEZA MANUAL\033[0m\n\n"
                    printf "Tú eliges qué pasos ejecutar.\n\n"
                    printf "\033[33mPasos disponibles:\033[0m\n"
                    printf "  • Journal\n  • Caché de paquetes\n  • Miniaturas\n"
                    printf "  • Huérfanos/dependencias\n  • Papelera\n\n"
                    printf "\033[32mUso:\033[0m Control fino cuando no quieres limpiar todo.\n"
                    ;;
                3)
                    printf "\033[1;36m📜 BITÁCORA DE STK\033[0m\n\n"
                    printf "Historial completo de eventos de STK.\n\n"
                    printf "\033[33mMuestra:\033[0m\n"
                    printf "  • Acciones del sistema y mantenimiento\n"
                    printf "  • Advertencias y errores\n"
                    printf "  • Cambios de usuarios, servicios y permisos\n\n"
                    printf "\033[32mUso:\033[0m Vista general para auditar lo que hizo STK.\n"
                    ;;
                4)
                    printf "\033[1;36m📦 LOGS DE ACTUALIZACIONES\033[0m\n\n"
                    printf "Vista filtrada solo de actualizaciones.\n\n"
                    printf "\033[33mMuestra:\033[0m\n"
                    printf "  • Actualizaciones de paquetes y sistema\n"
                    printf "  • Errores/incidencias de gestores de paquetes\n"
                    printf "  • Resultados de apt/dnf/pacman/zypper/rpm-ostree\n\n"
                    printf "\033[32mUso:\033[0m Más rápido para revisar problemas de updates.\n"
                    ;;
                5)
                    printf "\033[1;36m🔄 ROTAR LOGS\033[0m\n\n"
                    printf "Mantenimiento del archivo de bitácora.\n\n"
                    printf "\033[33mHace:\033[0m\n"
                    printf "  • Comprueba el tamaño de /var/log/stk_mantenimiento.log\n"
                    printf "  • Si supera el límite, rota y conserva historial en .1\n"
                    printf "  • Reafirma permisos seguros del log\n\n"
                    printf "\033[32mUso:\033[0m Evita que la bitácora crezca sin control.\n"
                    ;;
                6)
                    printf "\033[1;36m↩ VOLVER\033[0m\n\n"
                    printf "Regresa al menú principal.\n"
                    ;;
            esac'
        accion=$(echo -e "1. 🧹 Limpieza auto\n2. ✋ Limpieza manual\n3. 📜 Bitácora de STK\n4. 📦 Logs de actualizaciones\n5. 🔄 Rotar logs\n6. ↩ Volver" | \
            stk_fzf preview "Seleccione" "MANTENIMIENTO" "$preview_mant")
        if [[ $? -ne 0 || "$accion" == *"Volver"* ]]; then break; fi
        case ${accion%%.*} in
            1) stk_limpiar; mostrar_logo; stk_limpieza completa; stk_volver_menu ;;
            2) stk_limpieza_manual_menu ;;
            3) ver_logs ;;
            4) ver_logs_actualizaciones ;;
            5) rotar_logs ;;
        esac
    done
}
