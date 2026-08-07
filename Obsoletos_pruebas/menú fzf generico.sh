# --- NUEVA CONFIGURACIÓN DE FZF PARA EL MENÚ PRINCIPAL ---
fzf_menu_principal() {
    fzf --ansi \
        --height=18 \
        --layout=reverse \
        --border=double \
        --inline-info \
        --prompt=" ❯ " \
        --header-first \
        --header="     S Y S T E M   T O O L   K I T   -   M E N Ú   P R I N C I P A L" \
        --color="border:#5fafd7,header:#af87ff,prompt:#5fffff,pointer:#afff00,marker:#ff5f87" \
        --preview-window="right:40%:border-left" \
        --preview="echo -e '
\033[1;36m   ESTADO DEL SISTEMA\033[0m
\033[1;34m------------------------\033[0m
\033[1;33m Usuario:\033[0m $USER
\033[1;33m Host:\033[0m $(hostname)
\033[1;33m Kernel:\033[0m $(uname -r | cut -d- -f1)
\033[1;33m Uptime:\033[0m $(uptime -p | sed \"s/up //\")
\033[1;34m------------------------\033[0m
\033[1;32m [Módulos STK Listos]\033[0m' "
}

# --- FUNCIÓN DEL MENÚ PRINCIPAL MEJORADA ---
menu() {
    while true; do
        clear
        mostrar_logo
        
        # Definición de opciones con espaciado y mejores iconos
        # Estructura: "Icono | Título | Descripción"
        opciones=(
            "📊 | MONITORIZACIÓN  | Rendimiento, procesos y red en tiempo real"
            "📦 | SOFTWARE        | Actualizar, instalar y desinstalar paquetes"
            "⚙️ | ADMINISTRACIÓN | Usuarios, servicios y copias de seguridad"
            "🧹 | MANTENIMIENTO   | Limpieza de logs y archivos temporales"
            "✘ | SALIR           | Finalizar ejecución del script"
        )

        # Unimos las opciones en un string para fzf
        seleccion=$(printf "%s\n" "${opciones[@]}" | fzf_menu_principal)

        # Salida si se cancela
        if [ $? -ne 0 ] || [ -z "$seleccion" ]; then salir; fi

        # Lógica de selección basada en el texto (más limpia que números)
        case "$seleccion" in
            *"MONITORIZACIÓN"*)
                while true; do
                    clear
                    mostrar_logo
                    accion=$(echo -e "1. Rendimiento del Sistema\n2. Información de Red \n3. ↩ Volver" | fzf_estilo "Seleccione la opción" "MONITORIZACIÓN Y ESTADO")
                    if [[ $? -ne 0 || "$accion" == *"Volver"* ]]; then break; fi
                    case ${accion%%.*} in
                        1) monitor_rendimiento ;;
                        2) mostrar_info_red ;;
                    esac
                done
                ;;

            *"SOFTWARE"*)
                while true; do
                    clear
                    mostrar_logo
                    accion=$(echo -e "1. Actualización del Sistema\n2. Instalar programa\n3. Desinstalar programa\n4. ↩ Volver" | fzf_estilo "Seleccione la opción" "GESTIÓN DE SOFTWARE")
                    if [[ $? -ne 0 || "$accion" == *"Volver"* ]]; then break; fi
                    case ${accion%%.*} in
                        1) Actualizar_sistema ;;
                        2) instalar_programa ;;
                        3) desinstalar_programa ;;
                    esac
                done
                ;;

            *"ADMINISTRACIÓN"*)
                while true; do
                    clear
                    mostrar_logo
                    accion=$(echo -e "1. Gestión de Usuarios\n2. Gestión de Servicios\n3. Gestión de Backups\n4. ↩ Volver" | fzf_estilo "Seleccione la opción" "ADMINISTRACIÓN DEL SISTEMA")
                    if [[ $? -ne 0 || "$accion" == *"Volver"* ]]; then break; fi
                    case ${accion%%.*} in
                        1) gestionar_usuarios ;;
                        2) gestionar_servicios ;;
                        3) hacer_backup;;                     
                    esac
                done
                ;;

            *"MANTENIMIENTO"*)
                while true; do
                    clear
                    mostrar_logo
                    accion=$(echo -e "1. Limpieza de Archivos\n2. Ver Bitácora (Logs)\n3. Limpiar archivos de log\n4. ↩ Volver" | fzf_estilo "Seleccione la opicón" "MANTENIMIENTO Y LOGS")
                    if [[ $? -ne 0 || "$accion" == *"Volver"* ]]; then break; fi
                    case ${accion%%.*} in
                        1) super_limpieza ;;
                        2) ver_logs ;;
                        3) rotar_logs ;;
                    esac                   
                done
                ;;

            *"SALIR"*) salir ;;
        esac
    done
}


#Menu antiguo ampliado
menu() {
    while true; do
        clear
        mostrar_logo
        
        opciones="1. 📊 Monitorización y Estado - Rendimiento y Red\n2. 📦 Gestión de Software - Actualizar, Instalar y Desinstalar\n3. ⚙️ Administración del Sistema - Gestión Usuarios, Servicios y Backups\n4. 🧹 Mantenimiento y STK - Limpieza del Sistema y Gestión de Logs\n5. ✘ Salir"
        
        seleccion=$(echo -e "$opciones" | fzf_estilo "Seleccione menú" "P A N E L   D E   C O N T R O L")

        # Salida si se cancela con ESC o Ctrl+C
        if [ $? -ne 0 ] || [ -z "$seleccion" ]; then salir; fi

        case ${seleccion%%.*} in
            1) # --- SUBMENÚ MONITORIZACIÓN Y ESTADO ---
                while true; do
                    clear
                    mostrar_logo
                    accion=$(echo -e "1. Rendimiento del Sistema\n2. Información de Red \n3. ↩ Volver" | fzf_estilo "Seleccione la opción" "MONITORIZACIÓN Y ESTADO")
                    
                    # Si pulsa ESC o elige Volver, rompe este bucle y regresa al principal
                    if [[ $? -ne 0 || "$accion" == *"Volver"* ]]; then break; fi
                    
                    case ${accion%%.*} in
                        1) monitor_rendimiento ;;
                        2) mostrar_info_red ;;
                    esac
                done
                ;;

            2) # --- SUBMENÚ GESTIÓN DE SOFTWARE ---
                while true; do
                    clear
                    mostrar_logo
                    accion=$(echo -e "1. Actualización del Sistema\n2. Instalar programa\n3. Desinstalar programa\n4. ↩ Volver" | fzf_estilo "Seleccione la opción" "GESTIÓN DE SOFTWARE")
                    
                    if [[ $? -ne 0 || "$accion" == *"Volver"* ]]; then break; fi
                    
                    case ${accion%%.*} in
                        1) Actualizar_sistema ;;
                        2) instalar_programa ;;
                        3) desinstalar_programa ;;
                        
                    esac
                done
                ;;

            3) # --- SUBMENÚ ADMINISTRACIÓN DEL SISTEMA ---
                while true; do
                    clear
                    mostrar_logo
                    accion=$(echo -e "1. Gestión de Usuarios\n2. Gestión de Servicios\n3. Gestión de Backups\n4. ↩ Volver" | fzf_estilo "Seleccione la opción" "ADMINISTRACIÓN DEL SISTEMA")
                    
                    if [[ $? -ne 0 || "$accion" == *"Volver"* ]]; then break; fi
                    
                    case ${accion%%.*} in
                        1) gestionar_usuarios ;;
                        2) gestionar_servicios ;;
                        3) hacer_backup;;                     
                    esac
                done
                ;;

            4) # --- SUBMENÚ MANTENIMIENTO Y LOGS ---
                while true; do
                    clear
                    mostrar_logo
                    accion=$(echo -e "1. Limpieza de Archivos\n2. Ver Bitácora (Logs)\n3. Limpiar archivos de log\n4. ↩ Volver" | fzf_estilo "Seleccione la opicón" "MANTENIMIENTO Y LOGS")
                    
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

# Función genérica para que todos los menús se vean iguales
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

menu() {
    while true; do
        clear
        mostrar_logo
        
        local opciones="1. 📦 Gestión de Software\n2. ⚙️ Mantenimiento y Sistema\n3. 📊 Monitorización y Red\n4. 📜 Administración de STK\n5. ✘ Salir"
        seleccion=$(echo -e "$opciones" | fzf_estilo "Seleccione menú" "P A N E L   D E   C O N T R O L")

        # Salida si se cancela con ESC o Ctrl+C
        if [ $? -ne 0 ] || [ -z "$seleccion" ]; then salir; fi

        case ${seleccion%%.*} in
            1) # --- SUBMENÚ GESTIÓN DE SOFTWARE ---
                while true; do
                    accion=$(echo -e "1. Actualizar sistema\n2. Instalar programa\n3. Desinstalar programa\n4. ↩ Volver" | fzf_estilo "Software" "G E S T I Ó N  DE  S O F T W A R E")
                    
                    # Si pulsa ESC o elige Volver, rompe este bucle y regresa al principal
                    if [[ $? -ne 0 || "$accion" == *"Volver"* ]]; then break; fi
                    
                    case ${accion%%.*} in
                        1) Actualizar_sistema ;;
                        2) instalar_programa ;;
                        3) desinstalar_programa ;;
                    esac
                done
                ;;

            2) # --- SUBMENÚ MANTENIMIENTO ---
                while true; do
                    accion=$(echo -e "1. Súper Limpieza\n2. Copia de Seguridad\n3. Gestión de Usuarios\n4. ↩ Volver" | fzf_estilo "Mantenimiento" "M A N T E N I M I E N T O")
                    
                    if [[ $? -ne 0 || "$accion" == *"Volver"* ]]; then break; fi
                    
                    case ${accion%%.*} in
                        1) super_limpieza ;;
                        2) hacer_backup ;;
                        3) gestionar_usuarios ;;
                    esac
                done
                ;;

            3) # --- SUBMENÚ MONITORIZACIÓN ---
                while true; do
                    accion=$(echo -e "1. Rendimiento del Sistema\n2. Información de Red\n3. Gestión de Servicios\n4. ↩ Volver" | fzf_estilo "Monitor" "M O N I T O R I Z A C I Ó N")
                    
                    if [[ $? -ne 0 || "$accion" == *"Volver"* ]]; then break; fi
                    
                    case ${accion%%.*} in
                        1) monitor_rendimiento ;;
                        2) mostrar_info_red ;;
                        3) gestionar_servicios ;;
                    esac
                done
                ;;

            4) # --- SUBMENÚ ADMIN ---
                while true; do
                    accion=$(echo -e "1. Ver Bitácora (Logs)\n2. ↩ Volver" | fzf_estilo "STK" "A D M I N I S T R A C I Ó N")
                    
                    if [[ $? -ne 0 || "$accion" == *"Volver"* ]]; then break; fi
                    
                    [[ ${accion%%.*} == "1" ]] && ver_logs
                done
                ;;

            5) salir ;;
        esac
    done
}