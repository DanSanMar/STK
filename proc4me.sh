#!/bin/bash

# ==============================================================================
# PROC4ME - Investigador de procesos, puertos y amenazas silenciosas
# ==============================================================================
# Módulo independiente para Linux. No instala nada automáticamente.
# Pensado para ejecutarse solo (sudo ./proc4me.sh) o integrarse después en STK.
# ==============================================================================

V="1.2"
DESCRIPCION="Investigador de procesos, puertos, persistencia y amenazas silenciosas en Linux"
AUTOR="DanSanMar"

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

# --- LOGS E INFORMES ---
LOG_FILE="/var/log/stk_mantenimiento.log"
REPORT_DIR="/var/log/proc4me"
LOG_INFO="INFO"
LOG_WARN="WARN"
LOG_ERR="ERROR"

# --- RUTA ABSOLUTA DEL PROPIO SCRIPT (para vistas previas de FZF) ---
SELF_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)/$(basename "${BASH_SOURCE[0]}")"

# --- HALLAZGOS DE AUDITORÍA ---
HALLAZGOS_SEV=()
HALLAZGOS_MOD=()
HALLAZGOS_DESC=()
HALLAZGOS_REC=()

# --- UTILIDADES BÁSICAS ---
registrar_log() {
    local NIVEL="${1:-INFO}"
    local MENSAJE="${2}"
    local FECHA
    FECHA=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$FECHA] [$NIVEL] [${USER:-$(id -un 2>/dev/null)}] - [PROC4ME] $MENSAJE" >> "$LOG_FILE" 2>/dev/null
}

pintar() {
    local COLOR="$1"
    local MENSAJE="$2"
    echo -e "${COLOR}${MENSAJE}${RESET}"
}

ok()      { pintar "$VERDE_BRILLANTE" "✔ $1"; }
alerta()  { pintar "$ROJO_BRILLANTE" "⚠️ $1"; }
info()    { pintar "$AZUL" "ℹ️ $1"; }
seccion() { echo ""; pintar "$MAGENTA" "--- $1 ---"; }

pausa() {
    echo ""
    read -r -p "Presione Enter para continuar..." _
}

es_numero() {
    [[ "$1" =~ ^[0-9]+$ ]]
}

uid_a_usuario() {
    local uid="$1"
    local nombre
    nombre=$(getent passwd "$uid" 2>/dev/null | cut -d: -f1)
    [ -z "$nombre" ] && nombre=$(awk -F: -v u="$uid" '$3==u {print $1; exit}' /etc/passwd 2>/dev/null)
    [ -z "$nombre" ] && nombre="$uid"
    printf '%s' "$nombre"
}

# Devuelve la propiedad de una ruta al usuario que invocó el script con sudo.
# Así las carpetas y exportaciones creadas como root siguen siendo accesibles.
devolver_propietario_usuario() {
    local ruta="$1"
    local usuario grupo

    [ -n "${SUDO_USER:-}" ] && [ "$SUDO_USER" != "root" ] || return 0
    usuario="$SUDO_USER"
    grupo=$(id -gn "$usuario" 2>/dev/null) || grupo="$usuario"
    chown "$usuario:$grupo" "$ruta" 2>/dev/null || true
}

estado_tcp() {
    case "$1" in
        01) echo "ESTABLISHED" ;;
        02) echo "SYN_SENT" ;;
        03) echo "SYN_RECV" ;;
        04) echo "FIN_WAIT1" ;;
        05) echo "FIN_WAIT2" ;;
        06) echo "TIME_WAIT" ;;
        07) echo "CLOSE" ;;
        08) echo "CLOSE_WAIT" ;;
        09) echo "LAST_ACK" ;;
        0A) echo "LISTEN" ;;
        0B) echo "CLOSING" ;;
        *)  echo "$1" ;;
    esac
}

# --- ESTILOS FZF ---
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

# Menú FZF con el logo como cabecera viva: se refresca cada 5 segundos.
proc4me_fzf_menu() {
    local prompt_text="$1"
    local titulo="$2"
    local altura="${3:-~90%}"
    local logo logo_cmd

    logo=$(logo_texto)
    printf -v logo_cmd 'bash %q --logo-header' "$SELF_PATH"

    fzf --ansi \
        --height="$altura" \
        --layout=reverse \
        --no-sort \
        --header-first \
        --border=rounded \
        --border-label=" $titulo " \
        --prompt="➤ $prompt_text: " \
        --header="$logo" \
        --bind "every(5):bg-transform-header:$logo_cmd" \
        --color="border:#ff5555,pointer:#92ff92,header:#5fb2ff,label:#5fb2ff"
}

# ==============================================================================
# --- GUÍAS EDUCATIVAS Y PREVIEWS ---
# ==============================================================================

texto_educativo() {
    local categoria="$1"
    case "$categoria" in
        tmp)
            cat <<'EOF'
QUÉ ES: ejecutables o scripts en /tmp, /var/tmp, /dev/shm o /run.
POR QUÉ IMPORTA: el malware suele ejecutarse desde directorios temporales
para no dejar un binario persistente en disco.
FALSOS POSITIVOS: instaladores, contenedores, herramientas de desarrollo,
scripts propios y cachés de aplicaciones.
QUÉ REVISAR: quién creó el archivo, su hash, su contenido, si hay un proceso
ejecutándolo y a qué paquete pertenece.
EOF
            ;;
        oculto)
            cat <<'EOF'
QUÉ ES: archivos cuyo nombre empieza por punto en directorios temporales.
POR QUÉ IMPORTA: ocultar un archivo es una técnica simple para pasar
desapercibido en /tmp, /var/tmp o /dev/shm.
FALSOS POSITIVOS: configuraciones temporales de aplicaciones, cachés,
archivos de sesión y restos de instaladores.
QUÉ REVISAR: contenido, fecha de creación, proceso que lo abrió y si el
nombre imita a un archivo legítimo.
EOF
            ;;
        reciente)
            cat <<'EOF'
QUÉ ES: archivos modificados en las últimas 48 h en rutas críticas.
POR QUÉ IMPORTA: un cambio reciente en /etc, /usr/bin o /usr/sbin puede
indicar manipulación, persistencia o una actualización a medias.
FALSOS POSITIVOS: actualizaciones legítimas del sistema, gestores de
paquetes, configuración editada por el administrador.
QUÉ REVISAR: paquete propietario, fecha exacta, hash y si el cambio
coincide con una instalación conocida.
EOF
            ;;
        suid)
            cat <<'EOF'
QUÉ ES: binarios con bit SUID o SGID activo.
POR QUÉ IMPORTA: se ejecutan con los privilegios del propietario (a menudo
root). Un SUID mal ubicado o modificado es una vía clásica de escalada.
FALSOS POSITIVOS: sudo, passwd, su, mount, ping, fusermount y utilidades
del sistema con SUID legítimo.
QUÉ REVISAR: ruta, propietario, paquete, fecha y si aparece fuera de
/usr/bin, /usr/sbin, /bin o /sbin.
EOF
            ;;
        capability)
            cat <<'EOF'
QUÉ ES: capacidades POSIX asignadas a un ejecutable.
POR QUÉ IMPORTA: otorgan privilegios concretos sin necesidad de SUID.
Una capability amplia (cap_sys_admin, cap_setuid, cap_net_raw) puede
abusarse para escalar o manipular la red.
FALSOS POSITIVOS: ping, NetworkManager, Wireshark, tcpdump, herramientas
de virtualización y contenedores.
QUÉ REVISAR: paquete propietario, ruta y si la capability es realmente
necesaria para esa herramienta.
EOF
            ;;
        deleted)
            cat <<'EOF'
QUÉ ES: archivos borrados que siguen abiertos por un proceso.
POR QUÉ IMPORTA: el malware puede borrar su binario del disco y seguir
ejecutándose desde memoria; también ocurre tras actualizar un servicio.
FALSOS POSITIVOS: servicios actualizados sin reiniciar, logs rotados,
navegadores y aplicaciones de larga duración.
QUÉ REVISAR: proceso propietario, ruta original, si el binario existe en
disco y si el proceso se inició antes o después de una actualización.
EOF
            ;;
        integrity)
            cat <<'EOF'
QUÉ ES: diferencias entre los archivos instalados y el manifiesto del paquete.
POR QUÉ IMPORTA: revela binarios o configuraciones del sistema modificados
fuera del gestor de paquetes, una señal típica de manipulación.
FALSOS POSITIVOS: configuraciones editadas a mano, archivos generados en
tiempo de ejecución y actualizaciones parciales.
QUÉ REVISAR: reinstala el paquete afectado, compara con una copia limpia y
revisa la fecha del cambio.
EOF
            ;;
        cron)
            cat <<'EOF'
QUÉ ES: tareas programadas de usuarios y del sistema.
POR QUÉ IMPORTA: cron es una de las técnicas de persistencia más usadas:
ejecuta comandos al arrancar o cada cierto tiempo.
FALSOS POSITIVOS: mantenimiento, backups, rotación de logs, tareas de STK
y scripts legítimos del administrador.
QUÉ REVISAR: autor de la entrada, ruta del script, contenido, frecuencia y
si el archivo pertenece a un paquete.
EOF
            ;;
        systemd)
            cat <<'EOF'
QUÉ ES: unidades, servicios y timers de systemd.
POR QUÉ IMPORTA: permiten ejecutar código automáticamente, a menudo como
root, y sobrevivir a reinicios.
FALSOS POSITIVOS: servicios del sistema, unidades de paquetes, timers de
actualización y servicios de usuario.
QUÉ REVISAR: ExecStart, usuario, ruta del binario, si está habilitado y si
la unidad vive en /etc/systemd/system (personalizada).
EOF
            ;;
        ld_preload)
            cat <<'EOF'
QUÉ ES: librerías compartidas que se cargan antes que el resto.
POR QUÉ IMPORTA: LD_PRELOAD o /etc/ld.so.preload permiten interceptar
funciones de la libc y ocultar procesos, archivos o conexiones.
FALSOS POSITIVOS: aceleración gráfica, instrumentación, profiling,
accesibilidad y algunas aplicaciones de escritorio.
QUÉ REVISAR: ruta, propietario, paquete, hash y si la ruta está en un
directorio temporal o no pertenece a ningún paquete.
EOF
            ;;
        ssh)
            cat <<'EOF'
QUÉ ES: claves autorizadas, configuración SSH y registros de acceso.
POR QUÉ IMPORTA: una clave no autorizada en authorized_keys es una puerta
trasera persistente y silenciosa.
FALSOS POSITIVOS: administración legítima, automatización y claves de
usuarios reales.
QUÉ REVISAR: huella de la clave, fecha de modificación, usuario, IP de
origen y si la clave corresponde a un acceso conocido.
EOF
            ;;
        ssh_sudo)
            cat <<'EOF'
QUÉ ES: claves SSH, configuración de sshd y reglas de sudoers.
POR QUÉ IMPORTA: ambos mecanismos conceden acceso o privilegios y son
objetivos habituales de persistencia y escalada.
FALSOS POSITIVOS: administración legítima, grupos de soporte y reglas
necesarias para tareas concretas.
QUÉ REVISAR: claves desconocidas, NOPASSWD, ALL, usuarios inesperados y
opciones débiles como PasswordAuthentication yes.
EOF
            ;;
        sudoers)
            cat <<'EOF'
QUÉ ES: reglas que determinan quién puede ejecutar qué como root.
POR QUÉ IMPORTA: una regla mal configurada o añadida por un atacante
concede escalada de privilegios inmediata.
FALSOS POSITIVOS: reglas de administración, grupos de soporte y
automatizaciones legítimas.
QUÉ REVISAR: NOPASSWD, ALL, usuarios o grupos inesperados y archivos en
/etc/sudoers.d que no pertenezcan a un paquete.
EOF
            ;;
        persistencia)
            cat <<'EOF'
QUÉ ES: mecanismos que hacen que un programa se ejecute al arrancar o
periódicamente (cron, systemd, rc.local, LD_PRELOAD, SSH, etc.).
POR QUÉ IMPORTA: la persistencia es lo que permite a una amenaza sobrevivir
a reinicios y volver a activarse sin intervención.
QUÉ REVISAR: autor, ruta, contenido, frecuencia y paquete propietario.
Desconfía de rutas en /tmp, /dev/shm, comandos ofuscados o descargas
canalizadas a un shell.
EOF
            ;;
        usuario)
            cat <<'EOF'
QUÉ ES: cuentas locales del sistema.
POR QUÉ IMPORTA: una cuenta con UID 0 o con shell válida puede ser una
puerta trasera; las cuentas de servicio no deberían tener shell.
FALSOS POSITIVOS: cuentas de servicio legítimas, usuarios reales y cuentas
creadas por paquetes.
QUÉ REVISAR: UID, shell, home, grupos, último acceso y si la cuenta debería
existir.
EOF
            ;;
        sesion)
            cat <<'EOF'
QUÉ ES: sesiones activas y últimos accesos al sistema.
POR QUÉ IMPORTA: una sesión desconocida puede indicar acceso no autorizado
o un proceso que mantiene una conexión abierta.
FALSOS POSITIVOS: sesiones de administración, SSH legítimo, terminales
abiertas y servicios que usan utmp.
QUÉ REVISAR: usuario, origen (IP), hora, TTY y si coincide con tu actividad.
EOF
            ;;
        ssh_log)
            cat <<'EOF'
QUÉ ES: registros de autenticación SSH (accesos, fallos, usuarios inválidos).
POR QUÉ IMPORTA: muchos fallos seguidos sugieren fuerza bruta; un acceso
aceptado desde una IP desconocida puede ser un compromiso.
FALSOS POSITIVOS: errores de usuarios legítimos, escaneos de Internet y
automatizaciones.
QUÉ REVISAR: IP de origen, usuario, hora, método de autenticación y
patrones repetidos.
EOF
            ;;
        ssh_config)
            cat <<'EOF'
QUÉ ES: configuración efectiva de sshd.
POR QUÉ IMPORTA: opciones débiles (root login, contraseñas, puertos
inesperados) amplían la superficie de ataque.
FALSOS POSITIVOS: configuraciones heredadas o adaptadas a un entorno
concreto.
QUÉ REVISAR: PermitRootLogin, PasswordAuthentication, Port, AllowUsers y
DenyUsers.
EOF
            ;;
        modulo)
            cat <<'EOF'
QUÉ ES: módulos cargados en el kernel.
POR QUÉ IMPORTA: un módulo malicioso o no firmado puede ocultar procesos,
archivos y conexiones (rootkit).
FALSOS POSITIVOS: drivers de terceros, DKMS, virtualización, VPN y
controladores de hardware.
QUÉ REVISAR: modinfo, firma, ruta, si está en /lib/modules/$(uname -r) y
el estado tainted del kernel.
EOF
            ;;
        dmesg)
            cat <<'EOF'
QUÉ ES: mensajes recientes del kernel.
POR QUÉ IMPORTA: taint, fallos de verificación de módulos, errores de
hardware y denegaciones pueden revelar manipulación o inestabilidad.
FALSOS POSITIVOS: mensajes normales de hardware, suspend/resume y drivers
propietarios.
QUÉ REVISAR: líneas con taint, module verification failed, rootkit, OOM o
denegaciones inesperadas.
EOF
            ;;
        rootkit_tool)
            cat <<'EOF'
QUÉ ES: herramientas externas de detección de rootkits.
POR QUÉ IMPORTA: complementan a PROC4ME con firmas y comprobaciones
específicas que este script no implementa.
QUÉ REVISAR: instala rkhunter, chkrootkit o unhide solo si los necesitas y
contrasta siempre sus resultados con un análisis manual.
EOF
            ;;
        kernel)
            cat <<'EOF'
QUÉ ES: información del kernel, módulos, taint y hardening.
POR QUÉ IMPORTA: un kernel tainted o con protecciones débiles facilita la
instalación de módulos y la ocultación de actividad.
QUÉ REVISAR: tainted, kptr_restrict, dmesg_restrict, módulos fuera del
árbol y mensajes de verificación.
EOF
            ;;
        puerto)
            cat <<'EOF'
QUÉ ES: un socket en escucha.
POR QUÉ IMPORTA: cada puerto abierto es una superficie de ataque; los
puertos en 0.0.0.0 o :: están expuestos en todas las interfaces.
FALSOS POSITIVOS: servicios legítimos (SSH, Docker, bases de datos,
navegadores, mDNS).
QUÉ REVISAR: PID, ruta del ejecutable, paquete propietario, si escucha solo
en localhost y si el firewall lo permite.
EOF
            ;;
        conexion)
            cat <<'EOF'
QUÉ ES: una conexión de red establecida.
POR QUÉ IMPORTA: puede ser tráfico normal o un canal de mando y control,
exfiltración o una reverse shell.
FALSOS POSITIVOS: navegación, actualizaciones, sincronización en la nube y
servicios de mensajería.
QUÉ REVISAR: proceso, IP remota, puerto, hora de inicio y reputación del
destino.
EOF
            ;;
        socket_oculto)
            cat <<'EOF'
QUÉ ES: un puerto TCP visible en /proc/net pero que ss no muestra.
POR QUÉ IMPORTA: puede indicar ocultación deliberada de un socket.
FALSOS POSITIVOS: carreras entre la lectura de /proc y ss, namespaces de
contenedores y diferencias de versión.
QUÉ REVISAR: repite con ss -lntp, lsof -i y compara namespaces de red;
analiza desde un medio confiable si persiste.
EOF
            ;;
        proceso_oculto)
            cat <<'EOF'
QUÉ ES: un PID visible en /proc que ps no muestra.
POR QUÉ IMPORTA: apunta a manipulación de libproc, hooking o un rootkit.
FALSOS POSITIVOS: procesos efímeros que desaparecen entre las dos lecturas
(PROC4ME ya los filtra).
QUÉ REVISAR: analiza desde un medio confiable, compara con un ps estático y
revisa módulos y taint del kernel.
EOF
            ;;
        top)
            cat <<'EOF'
QUÉ ES: procesos ordenados por consumo de CPU o memoria.
POR QUÉ IMPORTA: un proceso desconocido con consumo alto puede ser minería,
un bucle infinito o una exfiltración.
FALSOS POSITIVOS: navegadores, compilaciones, contenedores, indexadores y
procesos del sistema.
QUÉ REVISAR: PID, usuario, comando completo, tiempo de ejecución y si el
consumo se mantiene en el tiempo.
EOF
            ;;
        proceso)
            cat <<'EOF'
QUÉ ES: un proceso en ejecución con su PID, usuario y comando.
POR QUÉ IMPORTA: los atacantes suelen usar nombres que imitan procesos
legítimos o ejecutarse desde rutas inusuales.
FALSOS POSITIVOS: servicios del sistema, aplicaciones de escritorio y
procesos de contenedores.
QUÉ REVISAR: ejecutable real, PPID, usuario, fecha de inicio, línea de
comandos completa, sockets abiertos y paquete propietario.
EOF
            ;;
        reverse_shell)
            cat <<'EOF'
QUÉ ES: un intérprete (bash, sh, python, perl, nc...) con una conexión de red.
POR QUÉ IMPORTA: es el patrón típico de una reverse shell: el atacante
obtiene una consola interactiva desde la víctima hacia su servidor.
FALSOS POSITIVOS: herramientas de administración remota, túneles SSH,
agentes de monitorización y scripts de automatización.
QUÉ REVISAR: IP remota y reputación, usuario que lo ejecuta, padre del
proceso, hora de inicio, descriptores y si el binario pertenece a un paquete.
EOF
            ;;
        *)
            cat <<'EOF'
Selecciona una línea para ver su contexto.
Usa el sentido común: un hallazgo no es malware por sí solo.
Contrasta con el paquete propietario, la fecha y el proceso asociado.
EOF
            ;;
    esac
}

extraer_ruta_de_linea() {
    local linea="$1"
    # Se detiene en espacio o ':' para soportar salidas tipo "ruta:contenido".
    if [[ "$linea" =~ (/[^[:space:]:]+) ]]; then
        printf '%s' "${BASH_REMATCH[1]}"
    fi
}

preview_educativo() {
    local categoria="$1"
    shift
    local linea="$*"
    local ruta pkg usuario modulo pid_cand unidad

    echo -e "${CIAN}════════════════════════════════════════════════════════════${RESET}"
    echo -e "${VERDE_BRILLANTE} GUÍA DE LECTURA${RESET}"
    echo -e "${CIAN}════════════════════════════════════════════════════════════${RESET}"
    texto_educativo "$categoria"
    echo ""
    echo -e "${AMARILLO}── LÍNEA SELECCIONADA ──${RESET}"
    printf '%s\n' "$linea"

    case "$categoria" in
        tmp|oculto|reciente|suid|capability|deleted|ssh|ld_preload|ssh_sudo|cron|systemd|sudoers|integrity)
            ruta=$(extraer_ruta_de_linea "$linea")
            if [ -n "$ruta" ] && [ -e "$ruta" ]; then
                echo ""
                echo -e "${AMARILLO}── CONTEXTO DEL ARCHIVO ──${RESET}"
                ls -l "$ruta" 2>/dev/null
                if command -v file >/dev/null 2>&1; then
                    file -b "$ruta" 2>/dev/null | head -n 1
                fi
                pkg=$(propietario_paquete "$ruta")
                [ -n "$pkg" ] && echo "Paquete: $pkg"
                if command -v getcap >/dev/null 2>&1; then
                    getcap "$ruta" 2>/dev/null
                fi
                if [ "$categoria" = "ssh" ] && command -v ssh-keygen >/dev/null 2>&1; then
                    echo ""
                    echo -e "${AMARILLO}── HUELLAS SSH ──${RESET}"
                    ssh-keygen -lf "$ruta" 2>/dev/null | head -n 5
                fi
                if [ "$categoria" = "ld_preload" ] && [ -f "$ruta" ]; then
                    echo "sha256: $(sha256sum "$ruta" 2>/dev/null | awk '{print $1}')"
                fi
                if { [ "$categoria" = "cron" ] || [ "$categoria" = "systemd" ] || [ "$categoria" = "sudoers" ]; } && [ -f "$ruta" ] && [ -r "$ruta" ]; then
                    echo ""
                    echo -e "${AMARILLO}── CONTENIDO DEL ARCHIVO ──${RESET}"
                    head -n 30 "$ruta" 2>/dev/null
                fi
            elif [ "$categoria" = "systemd" ]; then
                unidad=$(printf '%s' "$linea" | grep -oE '[A-Za-z0-9@._:-]+\.(service|timer|socket|path)' | head -n 1)
                if [ -n "$unidad" ]; then
                    echo ""
                    echo -e "${AMARILLO}── CONTEXTO DE LA UNIDAD ──${RESET}"
                    if command -v systemctl >/dev/null 2>&1; then
                        systemctl status "$unidad" --no-pager -n 8 2>/dev/null | head -n 20
                        echo ""
                        systemctl cat "$unidad" 2>/dev/null | head -n 30
                    fi
                fi
            fi
            ;;
        usuario)
            usuario=$(printf '%s' "$linea" | awk '{print $1}')
            if [ -n "$usuario" ] && getent passwd "$usuario" >/dev/null 2>&1; then
                echo ""
                echo -e "${AMARILLO}── CONTEXTO DEL USUARIO ──${RESET}"
                getent passwd "$usuario"
                id "$usuario" 2>/dev/null
                last -n 1 "$usuario" 2>/dev/null | head -n 1
            fi
            ;;
        modulo)
            modulo=$(printf '%s' "$linea" | awk '{print $1}')
            if [ -n "$modulo" ]; then
                echo ""
                echo -e "${AMARILLO}── CONTEXTO DEL MÓDULO ──${RESET}"
                if command -v modinfo >/dev/null 2>&1; then
                    modinfo "$modulo" 2>/dev/null | head -n 15
                fi
                lsmod 2>/dev/null | awk -v m="$modulo" 'NR==1 || $1==m'
            fi
            ;;
        proceso|proceso_oculto|top|reverse_shell)
            pid_cand=$(printf '%s' "$linea" | cut -f1 | awk '{print $1}')
            if [[ "$pid_cand" =~ ^[0-9]+$ ]] && [ -d "/proc/$pid_cand" ]; then
                echo ""
                echo -e "${AMARILLO}── DETALLE DEL PROCESO ──${RESET}"
                detalle_pid "$pid_cand"
            else
                echo ""
                echo -e "${AZUL}Esta línea no tiene un PID válido o el proceso ya terminó.${RESET}"
            fi
            ;;
        *)
            ;;
    esac
}

preview_puerto() {
    local pid="$1"

    texto_educativo "puerto"
    echo ""

    if [[ "$pid" =~ ^[0-9]+$ ]] && [ -d "/proc/$pid" ]; then
        echo -e "${AMARILLO}── DETALLE DEL PROCESO ──${RESET}"
        detalle_pid "$pid"
    else
        echo -e "${AZUL}Esta línea no tiene un PID asociado o ya no existe.${RESET}"
    fi
}

# Lista FZF con panel de explicación educativa.
fzf_lista_educativa() {
    local categoria="$1"
    local titulo="$2"
    local prompt="${3:-🔍 Seleccione una línea: }"
    local preview_cmd

    printf -v preview_cmd 'bash %q --preview-educativo %q {}' "$SELF_PATH" "$categoria"

    fzf --ansi \
        --height=85% \
        --min-height=20 \
        --layout=reverse \
        --border=rounded \
        --border-label=" $titulo " \
        --prompt="$prompt" \
        --preview "$preview_cmd" \
        --preview-window="right:55%:wrap" \
        --color="border:#ff5555,pointer:#92ff92,header:#5fb2ff,label:#5fb2ff"
}

ver_lista_educativa() {
    local categoria="$1"
    local titulo="$2"
    local datos="$3"

    if [ -z "$datos" ]; then
        ok "No se encontraron resultados para esta categoría."
        return 1
    fi

    printf '%s\n' "$datos" | fzf_lista_educativa "$categoria" "$titulo"
}

# Elimina encabezados y líneas vacías de los informes de texto.
filtrar_lineas_lista() {
    grep -vE '^[[:space:]]*(===|---|\(|$)' \
        | grep -vE '^\[[a-zA-Z0-9._-]+\]$' \
        | grep -vE '^[[:space:]]*Module[[:space:]]+Size[[:space:]]+Used' \
        | grep -vE '^[[:space:]]*COMMAND[[:space:]]+PID' \
        | grep -vE '^[[:space:]]*(PID|USER|Netid|Proto|State)[[:space:]]'
}

# Convierte bloques "--- ruta ---" en líneas "ruta<TAB>contenido" para que el
# preview pueda localizar el archivo y mostrar su contexto.
etiquetar_bloques() {
    local etiqueta="" line
    while IFS= read -r line; do
        if [[ "$line" =~ ^---\ (.+)\ ---$ ]]; then
            etiqueta="${BASH_REMATCH[1]}"
            continue
        fi
        if [[ "$line" == "==="* || "$line" =~ ^\[[a-zA-Z0-9._-]+\]$ ]]; then
            etiqueta=""
            printf '%s\n' "$line"
            continue
        fi
        [ -z "$line" ] && continue
        if [ -n "$etiqueta" ]; then
            printf '%s\t%s\n' "$etiqueta" "$line"
        else
            printf '%s\n' "$line"
        fi
    done
}

# --- DETECCIÓN DEL SISTEMA ---
OS_ID="Desconocido"
OS_LIKE="Desconocido"
Package="unknown"
IMMUTABLE=false

detectar_sistema() {
    if [ -f /etc/os-release ]; then
        # shellcheck disable=SC1091
        . /etc/os-release
        OS_ID="${ID:-Desconocido}"
        OS_LIKE="${ID_LIKE:-Desconocido}"
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
            elif command -v apt >/dev/null 2>&1; then Package="apt"
            elif command -v dnf >/dev/null 2>&1; then Package="dnf"
            elif command -v pacman >/dev/null 2>&1; then Package="pacman"
            elif command -v zypper >/dev/null 2>&1; then Package="zypper"
            fi
            ;;
    esac

    if [ -f /run/ostree-booted ] && command -v rpm-ostree >/dev/null 2>&1; then
        IMMUTABLE=true
        [ "$Package" = "unknown" ] && Package="dnf"
    fi
}

# --- COMPROBACIÓN DE ROOT ---
verificar_root() {
    if [ "$EUID" -ne 0 ]; then
        echo -e "${ROJO_BRILLANTE}⚠️ Error: PROC4ME requiere privilegios de root.${RESET}"
        echo -e "${AMARILLO}Prueba con: sudo $0${RESET}"
        exit 1
    fi
}

# --- DEPENDENCIAS ---
comprobar_dependencias() {
    local faltan=()
    local cmd

    for cmd in bash ps ss find awk grep sed fzf timeout uname hostname date \
               readlink sort head tail tr cut wc xargs mktemp sha256sum basename id; do
        command -v "$cmd" >/dev/null 2>&1 || faltan+=("$cmd")
    done

    if [ ${#faltan[@]} -gt 0 ]; then
        clear
        mostrar_logo_proc4me
        pintar "$ROJO_BRILLANTE" "⚠️ Faltan dependencias obligatorias: ${faltan[*]}"
        echo ""
        pintar "$AMARILLO" "Instálalas manualmente según tu distribución:"
        case "$Package" in
            apt)    echo -e "  ${BLANCO}sudo apt update && sudo apt install -y fzf iproute2 procps findutils gawk grep sed coreutils util-linux${RESET}" ;;
            dnf)    echo -e "  ${BLANCO}sudo dnf install -y fzf iproute procps-ng findutils gawk grep sed coreutils util-linux${RESET}" ;;
            pacman) echo -e "  ${BLANCO}sudo pacman -S --needed fzf iproute2 procps-ng findutils gawk grep sed coreutils util-linux${RESET}" ;;
            zypper) echo -e "  ${BLANCO}sudo zypper install -y fzf iproute2 procps findutils gawk grep sed coreutils util-linux${RESET}" ;;
            *)      echo -e "  ${BLANCO}Instala: ${faltan[*]}${RESET}" ;;
        esac
        echo ""
        pintar "$AZUL" "PROC4ME no instala nada automáticamente."
        exit 1
    fi
}

# --- PREPARACIÓN DE DIRECTORIOS Y ROTACIÓN ---
preparar_directorios() {
    umask 027

    if [ ! -d "$REPORT_DIR" ]; then
        mkdir -p "$REPORT_DIR" 2>/dev/null
    fi
    chmod 750 "$REPORT_DIR" 2>/dev/null

    if [ ! -f "$LOG_FILE" ]; then
        touch "$LOG_FILE" 2>/dev/null
        chmod 640 "$LOG_FILE" 2>/dev/null
    fi

    local count
    count=$(find "$REPORT_DIR" -maxdepth 1 -type f -name 'proc4me_*.txt' 2>/dev/null | wc -l)
    if [ "$count" -gt 20 ]; then
        find "$REPORT_DIR" -maxdepth 1 -type f -name 'proc4me_*.txt' -printf '%T@ %p\n' 2>/dev/null \
            | sort -nr | tail -n +21 | cut -d' ' -f2- \
            | while IFS= read -r f; do rm -f "$f"; done
    fi
}

# --- LOGO ANIMADO (estilo dash4me) ---
# Paleta cíclica de 10 colores; el índice 0 se usa como base.
PALETA_LOGO=(
    "$ROJO"
    "$AZUL_BRILLANTE"
    "$VERDE_BRILLANTE"
    "$AMARILLO_BRILLANTE"
    "$CIAN_BRILLANTE"
    "$ROJO_BRILLANTE"
    "$AZUL_CLARO"
    "$VERDE"
    "$AMARILLO"
    "$CIAN"
)
actualizar_colores_logo() {
    # El color avanza una posición cada 5 segundos (epoch / 5).
    local epoch
    epoch=$(date +%s 2>/dev/null)
    [[ "$epoch" =~ ^[0-9]+$ ]] || epoch=0

    local base=$(( (epoch / 5) % 10 ))

    COLOR_LOGO="${PALETA_LOGO[$base]}"
    COLOR_DASH="${PALETA_LOGO[$(( (base + 3) % 10 ))]}"
    COLOR_VER="${PALETA_LOGO[$(( (base + 6) % 10 ))]}"
}

# Devuelve el logo sin la línea en blanco inicial (para usarlo como header de FZF).
logo_texto() {
    actualizar_colores_logo

    local hora
    hora=$(date '+%H:%M:%S')

    echo -e " ${AZUL_BRILLANTE}--- ⚡ ${NEGRITA}${COLOR_LOGO}PROC4ME${RESET} ${AZUL_OSCURO}| ${COLOR_DASH}PROC & THREAT INVESTIGATOR${RESET} ${AZUL_OSCURO}| ${COLOR_VER}v${V}${RESET} ${BLANCO}:${hora}: ${AZUL_BRILLANTE}⚡---${RESET}"
    echo -e " ${CIAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    echo -e " ${AMARILLO}➤ Sistema:${RESET} ${AZUL}${OS_ID}${RESET}  ${AMARILLO}Kernel:${RESET} ${AZUL}$(uname -r 2>/dev/null)${RESET}"
    echo -e " ${AMARILLO}➤ Host:${RESET} ${AZUL}$(hostname 2>/dev/null)${RESET}  ${AMARILLO}Usuario:${RESET} ${AZUL}${USER:-root}${RESET}  ${AMARILLO}By:${RESET} ${AZUL}${AUTOR}${RESET}"
    echo -e " ${AMARILLO}➤ Modo:${RESET} ${AZUL}Investigación (acciones destructivas con confirmación)${RESET}"
    echo -e " ${CIAN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
}

mostrar_logo_proc4me() {
    echo ""
    logo_texto
}

salir_proc4me() {
    echo -e "\n${CIAN}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}"
    pintar "$AZUL" "Saliendo de PROC4ME..."
    pintar "$VERDE" "Recuerda: un rootkit avanzado puede ocultar procesos, puertos y archivos."
    echo -e "${CIAN}  ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${RESET}\n"
    if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
        exit 0
    fi
}

# ==============================================================================
# --- RECOLECCIÓN: PROCESOS Y MEMORIA ---
# ==============================================================================

detectar_procesos_sospechosos() {
    declare -A razones=()
    declare -A detalle=()
    declare -A cache_usuarios=()
    local -a conocidos=(sshd systemd cron crond bash sh dash zsh ksh python python3 perl php nginx apache2 httpd mysql mariadb postgres redis-server docker containerd)
    local pid_dir pid exe cmdline comm uid usuario cwd base_exe patron preload fd target

    for pid_dir in /proc/[0-9]*; do
        [ -d "$pid_dir" ] || continue
        [ -r "$pid_dir/status" ] || continue

        pid="${pid_dir#/proc/}"
        exe=$(readlink "$pid_dir/exe" 2>/dev/null)
        cmdline=$(tr '\0' ' ' < "$pid_dir/cmdline" 2>/dev/null | sed 's/[[:space:]]*$//')
        comm=$(cat "$pid_dir/comm" 2>/dev/null)
        uid=$(awk '/^Uid:/{print $2; exit}' "$pid_dir/status" 2>/dev/null)
        uid="${uid:-0}"

        if [ -z "${cache_usuarios[$uid]}" ]; then
            cache_usuarios[$uid]=$(uid_a_usuario "$uid")
        fi
        usuario="${cache_usuarios[$uid]}"
        cwd=$(readlink "$pid_dir/cwd" 2>/dev/null)

        # Hilos del kernel: sin ejecutable ni línea de comandos.
        if [ -z "$exe" ] && [ -z "$cmdline" ]; then
            continue
        fi

        razones[$pid]=""

        if [ -n "$exe" ] && [[ "$exe" =~ ^/(tmp|var/tmp|dev/shm|run/shm|run/user)/ ]]; then
            razones[$pid]+="ejecutable en directorio temporal; "
        fi

        if [[ "$exe" == *" (deleted)" ]]; then
            razones[$pid]+="binario borrado del disco; "
        fi

        if [[ "$exe" == *"memfd:"* ]] || [[ "$cmdline" == *"memfd:"* ]]; then
            razones[$pid]+="ejecución desde memoria (memfd); "
        fi

        if [ -z "$exe" ] && [ -n "$cmdline" ]; then
            razones[$pid]+="sin ejecutable visible; "
        fi

        if [ -n "$cwd" ] && [[ "$cwd" =~ ^/(tmp|var/tmp|dev/shm|run/shm)/ ]]; then
            razones[$pid]+="cwd en directorio temporal; "
        fi

        if [[ "$cwd" == *"(deleted)"* ]]; then
            razones[$pid]+="cwd borrado; "
        fi

        if [ -r "$pid_dir/maps" ]; then
            if grep -qE ' r-xp .*/(tmp|var/tmp|dev/shm|run/shm)/' "$pid_dir/maps" 2>/dev/null; then
                razones[$pid]+="librerías ejecutables en temporal; "
            fi
            if grep -qE ' r-xp .*\(deleted\)' "$pid_dir/maps" 2>/dev/null; then
                razones[$pid]+="librerías ejecutables borradas; "
            fi
            if grep -qE ' r-xp .*memfd:' "$pid_dir/maps" 2>/dev/null; then
                razones[$pid]+="código ejecutable memfd; "
            fi
        fi

        preload=$( { tr '\0' '\n' < "$pid_dir/environ"; } 2>/dev/null | sed -n 's/^LD_PRELOAD=//p' | head -n 1 )
        if [ -n "$preload" ] && [[ "$preload" =~ /tmp|/dev/shm|/var/tmp|\(deleted\) ]]; then
            razones[$pid]+="LD_PRELOAD sospechoso ($preload); "
        fi

        if [ -n "$cmdline" ]; then
            if [[ "$cmdline" =~ (curl|wget).*\|.*(sh|bash) ]]; then
                razones[$pid]+="descarga canalizada a shell; "
            fi
            if [[ "$cmdline" =~ (base64[[:space:]]+-d|base64[[:space:]]+--decode) ]]; then
                razones[$pid]+="uso de base64 -d; "
            fi
            if [[ "$cmdline" =~ (nc|ncat)[[:space:]]+.*-e ]]; then
                razones[$pid]+="netcat con -e; "
            fi
            if [[ "$cmdline" =~ bash[[:space:]]+-i ]]; then
                razones[$pid]+="bash interactivo; "
            fi
            if [[ "$cmdline" == *"/dev/tcp/"* ]]; then
                razones[$pid]+="conexión /dev/tcp; "
            fi
            if [[ "$cmdline" =~ socat[[:space:]] ]]; then
                razones[$pid]+="socat; "
            fi
            if [[ "$cmdline" =~ (python|python3|perl|php|ruby)[[:space:]]+-[ce] ]]; then
                razones[$pid]+="intérprete con código inline; "
            fi
            if [[ "$cmdline" =~ chmod[[:space:]]+\+x[[:space:]]+/tmp ]]; then
                razones[$pid]+="chmod +x en /tmp; "
            fi
            if [[ "$cmdline" =~ history[[:space:]]+-c ]]; then
                razones[$pid]+="borrado de historial; "
            fi
        fi

        if [ -n "$exe" ] && [ -n "$comm" ]; then
            base_exe=$(basename "${exe% (deleted)}")
            for patron in "${conocidos[@]}"; do
                if [ "$comm" = "$patron" ] && [ "$base_exe" != "$patron" ]; then
                    razones[$pid]+="nombre '$comm' no coincide con '$base_exe'; "
                    break
                fi
            done
        fi

        case "$comm" in
            bash|sh|dash|zsh|ksh|python|python3|perl|php|ruby|nc|ncat|socat)
                for fd in 0 1 2; do
                    target=$(readlink "$pid_dir/fd/$fd" 2>/dev/null)
                    if [[ "$target" == socket:* ]]; then
                        razones[$pid]+="shell con stdio en socket; "
                        break
                    fi
                done
                ;;
        esac

        if [ -n "${razones[$pid]}" ]; then
            razones[$pid]="${razones[$pid]%; }"
            if [ -n "$exe" ]; then
                detalle[$pid]="$exe"
            else
                detalle[$pid]="${cmdline:-$comm}"
            fi
            printf '%s\t%s\t%s\t%s\n' "$pid" "$usuario" "${razones[$pid]}" "${detalle[$pid]}"
        fi
    done | sort -t$'\t' -k1,1n
}

detectar_procesos_ocultos() {
    local proc_pids ps_pids pid
    proc_pids=$(ls -d /proc/[0-9]* 2>/dev/null | sed 's#/proc/##' | sort)
    ps_pids=$(ps -e -o pid= 2>/dev/null | tr -d ' ' | sort)
    comm -23 <(printf '%s\n' "$proc_pids") <(printf '%s\n' "$ps_pids") 2>/dev/null \
        | while IFS= read -r pid; do
            [ -z "$pid" ] && continue
            # Filtrar procesos efímeros: si ya no existen, no son "ocultos".
            [ -d "/proc/$pid" ] && printf '%s\n' "$pid"
        done
}

hex_a_ip() {
    local hex="$1"
    local ip_hex="${hex%%:*}"
    local port_hex="${hex##*:}"
    local port

    port=$((16#$port_hex))

    if [ ${#ip_hex} -eq 8 ]; then
        local b1=$((16#${ip_hex:6:2}))
        local b2=$((16#${ip_hex:4:2}))
        local b3=$((16#${ip_hex:2:2}))
        local b4=$((16#${ip_hex:0:2}))
        printf '%d.%d.%d.%d:%d' "$b1" "$b2" "$b3" "$b4" "$port"
    else
        printf '[IPv6]:%d' "$port"
    fi
}

inodo_a_conexion() {
    local inode="$1"
    awk -v ino="$inode" 'FNR>1 && $10==ino {print $2, $3, $4}' /proc/net/tcp /proc/net/tcp6 2>/dev/null | head -n 1
}

detectar_reverse_shells() {
    local pid_dir pid comm fd target inode conn local_hex remote_hex state local_ip remote_ip uid usuario

    for pid_dir in /proc/[0-9]*; do
        [ -d "$pid_dir" ] || continue
        comm=$(cat "$pid_dir/comm" 2>/dev/null)
        case "$comm" in
            bash|sh|dash|zsh|ksh|python|python3|perl|php|ruby|nc|ncat|socat) ;;
            *) continue ;;
        esac

        ls -l "$pid_dir/fd" 2>/dev/null | grep -q 'socket:' || continue

        pid="${pid_dir#/proc/}"
        uid=$(awk '/^Uid:/{print $2; exit}' "$pid_dir/status" 2>/dev/null)
        usuario=$(uid_a_usuario "${uid:-0}")

        for fd in "$pid_dir"/fd/*; do
            [ -e "$fd" ] || continue
            target=$(readlink "$fd" 2>/dev/null)
            [[ "$target" =~ ^socket:\[([0-9]+)\]$ ]] || continue
            inode="${BASH_REMATCH[1]}"
            conn=$(inodo_a_conexion "$inode")
            [ -n "$conn" ] || continue
            read -r local_hex remote_hex state <<< "$conn"
            remote_ip=$(hex_a_ip "$remote_hex")
            [[ "$remote_ip" == *":0" ]] && continue
            local_ip=$(hex_a_ip "$local_hex")
            printf '%s\t%s\t%s\t%s\t%s\t%s\n' "$pid" "$usuario" "$comm" "$local_ip" "$remote_ip" "$state"
        done
    done | sort -u
}

# ==============================================================================
# --- RECOLECCIÓN: PUERTOS Y SOCKETS ---
# ==============================================================================

detectar_puertos_publicos() {
    ss -tulpnH 2>/dev/null | awk '$5 ~ /^(0\.0\.0\.0:|\*:|\[::\]:|:::)/ {print}'
}

detectar_sockets_ocultos() {
    local ss_tcp proc_tcp

    ss_tcp=$(ss -tlnH 2>/dev/null | awk '{split($4,a,":"); print a[length(a)]}' | sort -u)
    proc_tcp=$(
        for f in /proc/net/tcp /proc/net/tcp6; do
            [ -r "$f" ] || continue
            awk 'FNR>1 && $4=="0A" {split($2,a,":"); print a[2]}' "$f"
        done | while read -r h; do
            [ -n "$h" ] && printf '%d\n' "$((16#$h))"
        done | sort -u
    )

    comm -23 <(printf '%s\n' "$proc_tcp") <(printf '%s\n' "$ss_tcp") 2>/dev/null \
        | while read -r p; do
            [ -n "$p" ] && printf 'Puerto TCP %s escucha en /proc/net pero no aparece en ss\n' "$p"
        done
}

# ==============================================================================
# --- RECOLECCIÓN: PERSISTENCIA ---
# ==============================================================================

detectar_persistencia_critica() {
    local user line f rc

    if [ -s /etc/ld.so.preload ]; then
        printf '[CRITICO] /etc/ld.so.preload contiene: %s\n' "$(tr '\n' ' ' < /etc/ld.so.preload)"
    fi

    for user in $(cut -d: -f1 /etc/passwd 2>/dev/null); do
        crontab -u "$user" -l 2>/dev/null | grep -vE '^[[:space:]]*(#|$)' | while IFS= read -r line; do
            # Ignorar la automatización legítima de STK.
            if [[ "$line" == *"STK-AUTO-MAINTENANCE"* ]] || [[ "$line" == *"stk_auto_wrapper.sh"* ]]; then
                continue
            fi
            if [[ "$line" == *"@reboot"* ]] || [[ "$line" =~ (^|[[:space:]=])/(tmp|var/tmp|dev/shm|run/shm)(/|[[:space:]]|$) ]] || [[ "$line" =~ (curl|wget|base64|nc[[:space:]]|ncat|socat) ]]; then
                printf '[CRON] [%s] %s\n' "$user" "$line"
            fi
        done
    done

    find /etc/cron.d /etc/cron.daily /etc/cron.hourly /etc/cron.weekly /etc/cron.monthly -maxdepth 1 -type f 2>/dev/null \
        | while IFS= read -r f; do
            grep -nE '(^|[[:space:]=])/(tmp|var/tmp|dev/shm|run/shm)(/|[[:space:]]|$)|curl|wget|base64|nc[[:space:]]|ncat|socat|@reboot' "$f" 2>/dev/null \
                | while IFS= read -r line; do
                    printf '[CRON-FILE] %s: %s\n' "$f" "$line"
                done
        done

    grep -RlE '^[[:space:]]*ExecStart=.*[[:space:]=]/(tmp|var/tmp|dev/shm|run/shm)(/|[[:space:]]|$)' \
        /etc/systemd/system 2>/dev/null \
        | while IFS= read -r f; do
            printf '[SYSTEMD-TMP] %s: %s\n' "$f" "$(grep -E '^[[:space:]]*ExecStart=' "$f" 2>/dev/null | tr '\n' ' ')"
        done

    if [ -f /etc/rc.local ]; then
        rc=$(grep -vE '^[[:space:]]*(#|$)' /etc/rc.local 2>/dev/null | tr '\n' ' ')
        [ -n "$rc" ] && printf '[RC.LOCAL] %s\n' "$rc"
    fi

    find /root /home -maxdepth 4 -path '*/.ssh/authorized_keys' -type f -mtime -7 2>/dev/null \
        | while IFS= read -r f; do
            printf '[SSH-KEYS] %s modificado recientemente\n' "$f"
        done
}

datos_persistencia_cron() {
    local user line f

    echo "=== CRONTAB DE USUARIOS ==="
    if command -v crontab >/dev/null 2>&1; then
        for user in $(cut -d: -f1 /etc/passwd 2>/dev/null); do
            local out
            out=$(crontab -u "$user" -l 2>/dev/null | grep -vE '^[[:space:]]*(#|$)')
            if [ -n "$out" ]; then
                echo "[$user]"
                printf '%s\n' "$out"
            fi
        done
    else
        echo "(crontab no disponible)"
    fi

    echo ""
    echo "=== /etc/crontab ==="
    [ -r /etc/crontab ] && grep -vE '^[[:space:]]*(#|$)' /etc/crontab 2>/dev/null || echo "(no existe)"

    echo ""
    echo "=== ARCHIVOS DE CRON ==="
    find /etc/cron.d /etc/cron.daily /etc/cron.hourly /etc/cron.weekly /etc/cron.monthly /var/spool/cron -maxdepth 2 -type f 2>/dev/null \
        | while IFS= read -r f; do
            echo "--- $f ---"
            grep -vE '^[[:space:]]*(#|$)' "$f" 2>/dev/null | head -n 30
        done

    echo ""
    echo "=== TAREAS AT ==="
    if command -v atq >/dev/null 2>&1; then
        atq 2>/dev/null || echo "(sin tareas)"
    else
        echo "(atq no disponible)"
    fi
}

datos_persistencia_systemd() {
    if ! command -v systemctl >/dev/null 2>&1; then
        echo "(systemctl no disponible)"
        return
    fi

    echo "=== UNIDADES HABILITADAS ==="
    systemctl list-unit-files --state=enabled --no-pager --no-legend 2>/dev/null

    echo ""
    echo "=== TIMERS ==="
    systemctl list-timers --all --no-pager --no-legend 2>/dev/null

    echo ""
    echo "=== UNIDADES DEL SISTEMA CON ExecStart EN DIRECTORIOS TEMPORALES ==="
    grep -RlE '^[[:space:]]*ExecStart=.*[[:space:]=]/(tmp|var/tmp|dev/shm|run/shm)(/|[[:space:]]|$)' \
        /etc/systemd/system 2>/dev/null \
        | while IFS= read -r f; do
            echo "--- $f ---"
            grep -E '^[[:space:]]*(ExecStart|ExecStop|ExecReload)=' "$f" 2>/dev/null
        done

    echo ""
    echo "=== UNIDADES DE VENDOR CON ExecStart EN DIRECTORIOS TEMPORALES (REVISAR) ==="
    grep -RlE '^[[:space:]]*ExecStart=.*[[:space:]=]/(tmp|var/tmp|dev/shm|run/shm)(/|[[:space:]]|$)' \
        /lib/systemd/system /usr/lib/systemd/system 2>/dev/null \
        | while IFS= read -r f; do
            echo "--- $f ---"
            grep -E '^[[:space:]]*(ExecStart|ExecStop|ExecReload)=' "$f" 2>/dev/null
        done
}

datos_persistencia_ld_preload() {
    echo "=== /etc/ld.so.preload ==="
    if [ -e /etc/ld.so.preload ]; then
        ls -l /etc/ld.so.preload 2>/dev/null
        cat /etc/ld.so.preload 2>/dev/null
    else
        echo "(no existe)"
    fi

    echo ""
    echo "=== /etc/ld.so.conf.d ==="
    find /etc/ld.so.conf.d -maxdepth 1 -type f 2>/dev/null | while IFS= read -r f; do
        echo "--- $f ---"
        cat "$f" 2>/dev/null
    done

    echo ""
    echo "=== Librerías precargadas en procesos ==="
    local pid_dir
    for pid_dir in /proc/[0-9]*; do
        [ -r "$pid_dir/environ" ] || continue
        local valor
        valor=$(tr '\0' '\n' < "$pid_dir/environ" 2>/dev/null | grep '^LD_PRELOAD=' | head -n 1)
        [ -n "$valor" ] && printf 'PID %s: %s\n' "${pid_dir#/proc/}" "$valor"
    done
}

datos_persistencia_ssh_sudo() {
    echo "=== AUTHORIZED_KEYS ==="
    find /root /home -maxdepth 4 -path '*/.ssh/authorized_keys' -type f -printf '%TY-%Tm-%Td %TH:%TM %u %p\n' 2>/dev/null

    echo ""
    echo "=== CONFIGURACIÓN SSH EFECTIVA ==="
    if command -v sshd >/dev/null 2>&1; then
        sshd -T 2>/dev/null | grep -E '^(port|permitrootlogin|passwordauthentication|pubkeyauthentication|allowusers|denyusers)'
    elif [ -r /etc/ssh/sshd_config ]; then
        grep -iE '^[[:space:]]*(Port|PermitRootLogin|PasswordAuthentication|PubkeyAuthentication|AllowUsers|DenyUsers)' /etc/ssh/sshd_config
    else
        echo "(sin configuración SSH legible)"
    fi

    echo ""
    echo "=== SUDOERS ==="
    [ -r /etc/sudoers ] && grep -vE '^[[:space:]]*(#|$)' /etc/sudoers 2>/dev/null
    find /etc/sudoers.d -maxdepth 1 -type f -exec grep -HvE '^[[:space:]]*(#|$)' {} \; 2>/dev/null
}

datos_persistencia_reciente() {
    find /etc/systemd/system /etc/cron.d /etc/cron.daily /etc/cron.hourly \
         /etc/cron.weekly /etc/cron.monthly /etc/init.d /etc/ld.so.preload \
         /etc/profile /etc/profile.d /etc/bash.bashrc /root/.ssh /home/*/.ssh \
         -maxdepth 2 -type f -mtime -7 -printf '%TY-%Tm-%Td %TH:%TM %u %p\n' 2>/dev/null
}

# ==============================================================================
# --- RECOLECCIÓN: ARCHIVOS, RAM Y BINARIOS ---
# ==============================================================================

detectar_archivos_tmp() {
    find /tmp /var/tmp /dev/shm /run/shm /run/user -xdev -type f \
        \( -perm -111 -o -name '*.sh' -o -name '*.py' -o -name '*.pl' -o -name '*.elf' \) \
        -printf '%TY-%Tm-%Td %TH:%TM %u %m %10s %p\n' 2>/dev/null | head -n 200
}

detectar_archivos_ocultos_tmp() {
    find /tmp /var/tmp /dev/shm /run/shm -xdev -name '.*' \
        -printf '%TY-%Tm-%Td %TH:%TM %u %m %10s %p\n' 2>/dev/null | head -n 100
}

detectar_cambios_recientes() {
    find /etc /usr/bin /usr/sbin /usr/local/bin /usr/local/sbin -xdev -type f -mtime -2 \
        -printf '%TY-%Tm-%Td %TH:%TM %u %m %10s %p\n' 2>/dev/null | head -n 200
}

detectar_suid() {
    find /usr/bin /usr/sbin /usr/local/bin /usr/local/sbin /bin /sbin /opt \
        -xdev -type f \( -perm -4000 -o -perm -2000 \) \
        -printf '%m %u %p\n' 2>/dev/null | sort
}

detectar_capabilities() {
    if command -v getcap >/dev/null 2>&1; then
        timeout 30 getcap -r / 2>/dev/null | head -n 200
    else
        echo "(getcap no instalado; instala libcap2-bin / libcap)"
    fi
}

detectar_archivos_borrados_abiertos() {
    if command -v lsof >/dev/null 2>&1; then
        lsof +L1 2>/dev/null | head -n 100
    else
        local pid_dir fd target
        for pid_dir in /proc/[0-9]*; do
            [ -d "$pid_dir/fd" ] || continue
            for fd in "$pid_dir"/fd/*; do
                target=$(readlink "$fd" 2>/dev/null)
                if [[ "$target" == *"(deleted)"* ]]; then
                    printf '%s\t%s\n' "${pid_dir#/proc/}" "$target"
                fi
            done
        done | head -n 100
    fi
}

propietario_paquete() {
    local exe="$1"
    [ -n "$exe" ] || { echo "desconocido"; return; }
    if command -v dpkg >/dev/null 2>&1; then
        dpkg -S "$exe" 2>/dev/null | head -n 1
    elif command -v rpm >/dev/null 2>&1; then
        rpm -qf "$exe" 2>/dev/null | head -n 1
    elif command -v pacman >/dev/null 2>&1; then
        pacman -Qo "$exe" 2>/dev/null | head -n 1
    else
        echo "desconocido"
    fi
}

verificar_integridad_paquetes() {
    case "$Package" in
        apt)
            if command -v dpkg >/dev/null 2>&1; then
                timeout 180 dpkg -V 2>/dev/null | head -n 200
            else
                echo "(dpkg no disponible)"
            fi
            ;;
        dnf|zypper)
            if command -v rpm >/dev/null 2>&1; then
                timeout 180 rpm -Va 2>/dev/null | head -n 200
            else
                echo "(rpm no disponible)"
            fi
            ;;
        pacman)
            if command -v pacman >/dev/null 2>&1; then
                timeout 180 pacman -Qkk 2>/dev/null | grep -v '0 missing files' | head -n 200
            else
                echo "(pacman no disponible)"
            fi
            ;;
        *)
            echo "(gestor de paquetes no reconocido)"
            ;;
    esac
}

# ==============================================================================
# --- RECOLECCIÓN: USUARIOS Y ACCESOS ---
# ==============================================================================

datos_usuarios_uid0() {
    awk -F: '$3==0 {printf "%s (UID 0, shell %s)\n", $1, $7}' /etc/passwd
}

datos_usuarios_shell() {
    awk -F: '$7 !~ /(nologin|false|sync|shutdown|halt)$/ {printf "%s UID=%s shell=%s\n", $1, $3, $7}' /etc/passwd
}

datos_sesiones() {
    echo "=== WHO ==="
    who -a 2>/dev/null
    echo ""
    echo "=== W ==="
    w -h 2>/dev/null
}

datos_ultimos_accesos() {
    echo "=== LAST ==="
    last -n 15 2>/dev/null
    echo ""
    echo "=== LASTB (fallos) ==="
    lastb -n 15 2>/dev/null
}

datos_ssh_logs() {
    local logs=""
    if command -v journalctl >/dev/null 2>&1; then
        logs=$(journalctl -u ssh -u sshd --no-pager -n 500 2>/dev/null \
            | grep -E 'Accepted|Failed|Invalid user' | tail -n 50)
    fi
    if [ -z "$logs" ]; then
        local f
        for f in /var/log/auth.log /var/log/secure; do
            if [ -r "$f" ]; then
                logs=$(grep -E 'Accepted|Failed|Invalid user' "$f" 2>/dev/null | tail -n 50)
                [ -n "$logs" ] && break
            fi
        done
    fi
    printf '%s\n' "${logs:-(sin registros SSH recientes)}"
}

datos_ssh_keys() {
    find /root /home -maxdepth 4 -path '*/.ssh/authorized_keys' -type f \
        -printf '%TY-%Tm-%Td %TH:%TM %u %m %p\n' 2>/dev/null
}

datos_sudoers() {
    [ -r /etc/sudoers ] && grep -vE '^[[:space:]]*(#|$)' /etc/sudoers 2>/dev/null
    find /etc/sudoers.d -maxdepth 1 -type f -exec grep -HvE '^[[:space:]]*(#|$)' {} \; 2>/dev/null
}

datos_ssh_config() {
    if command -v sshd >/dev/null 2>&1; then
        sshd -T 2>/dev/null | grep -E '^(port|permitrootlogin|passwordauthentication|pubkeyauthentication|allowusers|denyusers)'
    elif [ -r /etc/ssh/sshd_config ]; then
        grep -iE '^[[:space:]]*(Port|PermitRootLogin|PasswordAuthentication|PubkeyAuthentication|AllowUsers|DenyUsers)' /etc/ssh/sshd_config
    else
        echo "(sin configuración SSH legible)"
    fi
}

# ==============================================================================
# --- RECOLECCIÓN: KERNEL Y ROOTKITS ---
# ==============================================================================

datos_kernel_info() {
    echo "=== KERNEL ==="
    uname -a
    echo ""
    echo "=== TAINTED ==="
    local taint
    taint=$(cat /proc/sys/kernel/tainted 2>/dev/null)
    echo "${taint:-N/A}"
    echo ""
    echo "=== SYSCTL DE HARDENING ==="
    local k
    for k in kernel.kptr_restrict kernel.dmesg_restrict kernel.modules_disabled kernel.perf_event_paranoid; do
        printf '%s = %s\n' "$k" "$(sysctl -n "$k" 2>/dev/null)"
    done
}

datos_modulos() {
    echo "=== MÓDULOS CARGADOS ==="
    lsmod 2>/dev/null

    echo ""
    echo "=== MÓDULOS FUERA DE /lib/modules/$(uname -r) ==="
    local mod rest path
    while read -r mod rest; do
        [ -z "$mod" ] && continue
        [ "$mod" = "Module" ] && continue
        path=""
        if command -v modinfo >/dev/null 2>&1; then
            path=$(modinfo -n "$mod" 2>/dev/null)
        fi
        if [ -z "$path" ] || [ ! -e "$path" ]; then
            path=$(find "/lib/modules/$(uname -r)" -name "${mod}.ko*" -print -quit 2>/dev/null)
        fi
        if [ -z "$path" ]; then
            path=$(find "/lib/modules/$(uname -r)" -name "${mod//_/-}.ko*" -print -quit 2>/dev/null)
        fi
        [ -z "$path" ] && printf '%s (no encontrado en /lib/modules)\n' "$mod"
    done < <(lsmod 2>/dev/null)
}

datos_dmesg() {
    if command -v dmesg >/dev/null 2>&1; then
        dmesg -T 2>/dev/null | tail -n 200 \
            | grep -Ei 'error|fail|segfault|oom|taint|module|rootkit|denied|verification' \
            | tail -n 60
    else
        echo "(dmesg no disponible)"
    fi
}

datos_rootkit_tools() {
    local tool
    for tool in rkhunter chkrootkit unhide unhide-tcp; do
        if command -v "$tool" >/dev/null 2>&1; then
            echo "$tool: disponible ($(command -v "$tool"))"
        else
            echo "$tool: no instalado (recomendado para análisis profundo)"
        fi
    done
}

# ==============================================================================
# --- VISTAS PREVIAS FZF ---
# ==============================================================================

preview_campo1() {
    printf "bash '%s' --pid {1} 2>/dev/null" "$SELF_PATH"
}

preview_proceso_campo1() {
    printf "bash '%s' --preview-educativo proceso {} 2>/dev/null" "$SELF_PATH"
}

preview_reverse_shell() {
    printf "bash '%s' --preview-educativo reverse_shell {} 2>/dev/null" "$SELF_PATH"
}

preview_puerto_campo1() {
    printf "bash '%s' --preview-puerto {1} 2>/dev/null" "$SELF_PATH"
}

preview_patron_pid() {
    printf "pid=\$(echo {} | sed -n 's/.*pid=\\([0-9]*\\).*/\\1/p' | head -n1); [ -n \"\$pid\" ] && bash '%s' --pid \"\$pid\" 2>/dev/null" "$SELF_PATH"
}

# ==============================================================================
# --- DETALLE Y ACCIONES SOBRE PROCESOS ---
# ==============================================================================

detalle_pid() {
    local pid="$1"
    es_numero "$pid" || { alerta "PID inválido."; return 1; }
    [ -d "/proc/$pid" ] || { alerta "El PID $pid no existe."; return 1; }

    local status="/proc/$pid/status"
    local exe cmdline cwd root comm user ppid state rss threads

    exe=$(readlink "/proc/$pid/exe" 2>/dev/null)
    cmdline=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | sed 's/[[:space:]]*$//')
    cwd=$(readlink "/proc/$pid/cwd" 2>/dev/null)
    root=$(readlink "/proc/$pid/root" 2>/dev/null)
    comm=$(cat "/proc/$pid/comm" 2>/dev/null)
    user=$(uid_a_usuario "$(awk '/^Uid:/{print $2; exit}' "$status" 2>/dev/null)")
    ppid=$(awk '/^PPid:/{print $2; exit}' "$status" 2>/dev/null)
    state=$(awk '/^State:/{print $2" "$3" "$4; exit}' "$status" 2>/dev/null)
    rss=$(awk '/^VmRSS:/{print $2" "$3; exit}' "$status" 2>/dev/null)
    threads=$(awk '/^Threads:/{print $2; exit}' "$status" 2>/dev/null)

    echo ""
    echo -e "${CIAN}════════════════════════════════════════════════════════════${RESET}"
    echo -e "${VERDE_BRILLANTE} DETALLE DEL PROCESO PID $pid${RESET}"
    echo -e "${CIAN}════════════════════════════════════════════════════════════${RESET}"
    echo -e " ${AMARILLO}Comando   :${RESET} ${BLANCO}${comm}${RESET}"
    echo -e " ${AMARILLO}Usuario   :${RESET} ${BLANCO}${user}${RESET}"
    echo -e " ${AMARILLO}PPID      :${RESET} ${BLANCO}${ppid}${RESET}"
    echo -e " ${AMARILLO}Estado    :${RESET} ${BLANCO}${state}${RESET}"
    echo -e " ${AMARILLO}RSS       :${RESET} ${BLANCO}${rss}${RESET}  ${AMARILLO}Hilos:${RESET} ${BLANCO}${threads}${RESET}"
    echo -e " ${AMARILLO}Ejecutable:${RESET} ${BLANCO}${exe:-"(sin ejecutable visible)"}${RESET}"
    if [ -n "$exe" ]; then
        local pkg
        pkg=$(propietario_paquete "${exe% (deleted)}")
        [ -n "$pkg" ] && echo -e " ${AMARILLO}Paquete   :${RESET} ${BLANCO}${pkg}${RESET}"
    fi
    echo -e " ${AMARILLO}CWD       :${RESET} ${BLANCO}${cwd:-N/A}${RESET}"
    echo -e " ${AMARILLO}Raíz      :${RESET} ${BLANCO}${root:-N/A}${RESET}"
    echo -e " ${AMARILLO}Cmdline   :${RESET} ${BLANCO}${cmdline:-"(vacío)"}${RESET}"
    echo ""
    echo -e " ${AMARILLO}Árbol de procesos:${RESET}"
    if command -v pstree >/dev/null 2>&1; then
        pstree -p -s "$pid" 2>/dev/null | sed 's/^/   /'
    else
        ps -o pid,ppid,user,args -p "$pid" 2>/dev/null | sed 's/^/   /'
    fi
    echo ""
    echo -e " ${AMARILLO}Conexiones de red:${RESET}"
    ss -tunap 2>/dev/null | grep -E "pid=$pid[,)]" | sed 's/^/   /' | head -n 20
    echo ""
    echo -e " ${AMARILLO}Descriptores abiertos:${RESET}"
    ls -l "/proc/$pid/fd" 2>/dev/null | head -n 30 | sed 's/^/   /'
    echo ""
    echo -e " ${AMARILLO}Mapas de memoria sospechosos:${RESET}"
    grep -E ' r-xp .*/(tmp|var/tmp|dev/shm|run/shm)/| r-xp .*\(deleted\)| r-xp .*memfd:' "/proc/$pid/maps" 2>/dev/null \
        | head -n 20 | sed 's/^/   /'
    echo ""
    echo -e " ${AMARILLO}Entorno relevante:${RESET}"
    tr '\0' '\n' < "/proc/$pid/environ" 2>/dev/null \
        | grep -E '^(LD_PRELOAD|LD_LIBRARY_PATH|PATH|HOME|SHELL|USER|HISTFILE)=' \
        | sed 's/^/   /' | head -n 20
    echo ""
    echo -e " ${AMARILLO}Unidad systemd asociada:${RESET}"
    if command -v systemctl >/dev/null 2>&1; then
        systemctl status "$pid" --no-pager 2>/dev/null | head -n 5 | sed 's/^/   /'
    fi
    echo ""
}

accion_enviar_senal() {
    local pid="$1"
    local sig="$2"
    local cmd conf

    cmd=$(tr '\0' ' ' < "/proc/$pid/cmdline" 2>/dev/null | sed 's/[[:space:]]*$//')
    echo ""
    alerta "Vas a enviar la señal $sig al PID $pid."
    echo -e " ${AMARILLO}Comando:${RESET} ${BLANCO}${cmd:-"(desconocido)"}${RESET}"

    if [ "$sig" = "KILL" ]; then
        echo -ne "${ROJO_BRILLANTE}Escribe MATAR para confirmar: ${RESET}"
        read -r conf
        if [ "$conf" != "MATAR" ]; then
            info "Operación cancelada."
            registrar_log "$LOG_WARN" "SIGKILL cancelado para PID $pid"
            pausa
            return
        fi
    else
        echo -ne "${AMARILLO}¿Confirmar? (s/N): ${RESET}"
        read -r conf
        if [[ ! "$conf" =~ ^[sS]$ ]]; then
            info "Operación cancelada."
            pausa
            return
        fi
    fi

    if kill -s "$sig" "$pid" 2>/dev/null; then
        ok "Señal $sig enviada al PID $pid."
        registrar_log "$LOG_WARN" "Señal $sig enviada al PID $pid ($cmd)"
    else
        alerta "No se pudo enviar la señal al PID $pid."
        registrar_log "$LOG_ERR" "Fallo al enviar $sig al PID $pid"
    fi
    pausa
}

accion_renice() {
    local pid="$1"
    local nice

    echo -ne "${AMARILLO}Nueva prioridad (-20 a 19): ${RESET}"
    read -r nice
    if [[ ! "$nice" =~ ^-?[0-9]+$ ]] || [ "$nice" -lt -20 ] || [ "$nice" -gt 19 ]; then
        alerta "Valor inválido."
        pausa
        return
    fi

    if renice "$nice" -p "$pid" 2>/dev/null; then
        ok "Prioridad del PID $pid cambiada a $nice."
        registrar_log "$LOG_INFO" "renice $nice aplicado al PID $pid"
    else
        alerta "No se pudo cambiar la prioridad del PID $pid."
        registrar_log "$LOG_ERR" "Fallo al aplicar renice al PID $pid"
    fi
    pausa
}

exportar_informe_pid() {
    local pid="$1"
    local reporte="$REPORT_DIR/proc4me_pid_${pid}_$(date +%Y-%m-%d_%H-%M-%S).txt"

    {
        echo "PROC4ME v$V - Informe del PID $pid"
        echo "Fecha: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Host: $(hostname 2>/dev/null)"
        echo ""
        detalle_pid "$pid"
    } | sed -r 's/\x1B\[[0-9;]*[mK]//g' > "$reporte" 2>&1

    chmod 640 "$reporte" 2>/dev/null
    ok "Informe guardado en: $reporte"
    registrar_log "$LOG_INFO" "Informe de PID $pid exportado a $reporte"
    pausa
}

menu_acciones_pid() {
    local pid="$1"
    while true; do
        local opciones="1. 🔍 Ver detalle completo
2. ⛔ Enviar SIGTERM (terminar)
3. 💀 Enviar SIGKILL (forzar)
4. ⏸️ Suspender (SIGSTOP)
5. ▶️ Reanudar (SIGCONT)
6. ⚖️ Cambiar prioridad (renice)
7. 📄 Exportar informe del PID
8. ↩ Volver"
        local sel
        sel=$(echo -e "$opciones" | fzf_estilo "PID $pid" "ACCIONES SOBRE EL PROCESO")
                [ -z "$sel" ] && return 0

        case ${sel%%.*} in
            1) clear; mostrar_logo_proc4me; detalle_pid "$pid"; pausa ;;
            2) accion_enviar_senal "$pid" TERM ;;
            3) accion_enviar_senal "$pid" KILL ;;
            4) accion_enviar_senal "$pid" STOP ;;
            5) accion_enviar_senal "$pid" CONT ;;
            6) accion_renice "$pid" ;;
            7) exportar_informe_pid "$pid" ;;
            8|*) return 0 ;;
        esac
    done
}

# ==============================================================================
# --- VISTAS DE PROCESOS ---
# ==============================================================================

listar_todos_procesos() {
    clear
    mostrar_logo_proc4me
    seccion "PROCESOS DEL SISTEMA (ordenados por CPU)"

    local sel
    sel=$(ps -eo pid=,ppid=,user=,%cpu=,%mem=,stat=,etimes=,comm=,args= --sort=-%cpu 2>/dev/null \
        | sed 's/^ *//' \
        | fzf --ansi --height=80% --reverse --border=rounded \
            --prompt="🔍 Seleccione PID para inspeccionar: " \
            --header="PID PPID USUARIO %CPU %MEM STAT ETIMES COMMAND" \
            --preview "$(preview_proceso_campo1)" \
            --preview-window="right:60%:wrap")

    if [ -n "$sel" ]; then
        local pid
        pid=$(printf '%s' "$sel" | awk '{print $1}')
        if es_numero "$pid"; then
            detalle_pid "$pid"
            menu_acciones_pid "$pid"
        fi
    fi
}

mostrar_procesos_sospechosos() {
    clear
    mostrar_logo_proc4me
    seccion "PROCESOS SOSPECHOSOS"

    local datos
    datos=$(detectar_procesos_sospechosos)
    if [ -z "$datos" ]; then
        ok "No se detectaron procesos sospechosos con los criterios actuales."
        pausa
        return
    fi

    local sel
    sel=$(printf '%s\n' "$datos" | fzf --ansi --height=80% --reverse --border=rounded \
        --delimiter='\t' --with-nth=1,2,3,4 \
        --prompt="🔍 Seleccione proceso sospechoso: " \
        --header="PID | USUARIO | MOTIVO | EJECUTABLE / CMD" \
        --preview "$(preview_proceso_campo1)" \
        --preview-window="right:60%:wrap")

    if [ -n "$sel" ]; then
        local pid
        pid=$(printf '%s' "$sel" | cut -f1)
        if es_numero "$pid"; then
            detalle_pid "$pid"
            menu_acciones_pid "$pid"
        fi
    fi
}

mostrar_procesos_ram() {
    clear
    mostrar_logo_proc4me
    seccion "PROCESOS EN RAM / BINARIOS BORRADOS / MEMFD"

    local datos filtrado
    datos=$(detectar_procesos_sospechosos)
    filtrado=$(printf '%s\n' "$datos" | awk -F'\t' '$3 ~ /memfd|borrado|sin ejecutable|librerías|RAM/')

    if [ -z "$filtrado" ]; then
        ok "No se detectaron procesos ejecutándose desde RAM o con binarios borrados."
        pausa
        return
    fi

    local sel
    sel=$(printf '%s\n' "$filtrado" | fzf --ansi --height=80% --reverse --border=rounded \
        --delimiter='\t' --with-nth=1,2,3,4 \
        --prompt="🔍 Seleccione proceso: " \
        --header="PID | USUARIO | MOTIVO | EJECUTABLE / CMD" \
        --preview "$(preview_proceso_campo1)" \
        --preview-window="right:60%:wrap")

    if [ -n "$sel" ]; then
        local pid
        pid=$(printf '%s' "$sel" | cut -f1)
        if es_numero "$pid"; then
            detalle_pid "$pid"
            menu_acciones_pid "$pid"
        fi
    fi
}

mostrar_reverse_shells() {
    clear
    mostrar_logo_proc4me
    seccion "SHELLS CON SOCKETS / POSIBLES REVERSE SHELLS"

    local datos
    datos=$(detectar_reverse_shells)
    if [ -z "$datos" ]; then
        ok "No se detectaron shells o intérpretes con conexiones de red."
        pausa
        return
    fi

    local sel
    sel=$(printf '%s\n' "$datos" | fzf --ansi --height=80% --reverse --border=rounded \
        --delimiter='\t' --with-nth=1,2,3,4,5,6 \
        --prompt="🔍 Seleccione conexión sospechosa: " \
        --header="PID | USUARIO | PROCESO | LOCAL | REMOTO | ESTADO" \
        --preview "$(preview_reverse_shell)" \
        --preview-window="right:60%:wrap")

    if [ -n "$sel" ]; then
        local pid
        pid=$(printf '%s' "$sel" | cut -f1)
        if es_numero "$pid"; then
            detalle_pid "$pid"
            menu_acciones_pid "$pid"
        fi
    fi
}

mostrar_procesos_ocultos() {
    clear
    mostrar_logo_proc4me
    seccion "PROCESOS OCULTOS (/proc vs ps)"

    local datos
    datos=$(detectar_procesos_ocultos)
    ver_lista_educativa proceso_oculto "PIDS OCULTOS (/proc vs ps)" "$datos"
    pausa
}

mostrar_top_procesos() {
    clear
    mostrar_logo_proc4me
    seccion "TOP PROCESOS POR CPU Y MEMORIA"

    local cpu mem
    cpu=$(ps -eo pid,ppid,user,%cpu,%mem,stat,etimes,comm,args --sort=-%cpu 2>/dev/null \
        | head -n 21 | filtrar_lineas_lista)
    mem=$(ps -eo pid,ppid,user,%cpu,%mem,stat,etimes,comm,args --sort=-%mem 2>/dev/null \
        | head -n 21 | filtrar_lineas_lista)

    ver_lista_educativa top "TOP CPU (selecciona para inspeccionar)" "$cpu"
    ver_lista_educativa top "TOP MEMORIA (selecciona para inspeccionar)" "$mem"
    pausa
}

inspector_pid() {
    clear
    mostrar_logo_proc4me
    seccion "INSPECTOR INTERACTIVO DE PID"

    local sel
    sel=$(ps -eo pid=,ppid=,user=,%cpu=,%mem=,stat=,etimes=,comm=,args= --sort=-%cpu 2>/dev/null \
        | sed 's/^ *//' \
        | fzf --ansi --height=80% --reverse --border=rounded \
            --prompt="🔍 Seleccione PID para inspeccionar: " \
            --header="PID PPID USUARIO %CPU %MEM STAT ETIMES COMMAND" \
            --preview "$(preview_proceso_campo1)" \
            --preview-window="right:60%:wrap")

    if [ -n "$sel" ]; then
        local pid
        pid=$(printf '%s' "$sel" | awk '{print $1}')
        if es_numero "$pid"; then
            detalle_pid "$pid"
            menu_acciones_pid "$pid"
        fi
    fi
}

# ==============================================================================
# --- VISTAS DE PUERTOS Y CONEXIONES ---
# ==============================================================================

normalizar_ss() {
    local line pid
    while IFS= read -r line; do
        [ -z "$line" ] && continue
        pid=$(printf '%s' "$line" | sed -n 's/.*pid=\([0-9]*\).*/\1/p' | head -n 1)
        [ -z "$pid" ] && pid="-"
        printf '%s\t%s\n' "$pid" "$line"
    done
}

seleccionar_pid_de_ss() {
    local datos="$1"
    local header="$2"
    local prompt="$3"
    local sel pid

    sel=$(printf '%s\n' "$datos" | fzf --ansi --height=80% --reverse --border=rounded \
        --prompt="$prompt" \
        --header="$header" \
        --preview "$(preview_puerto_campo1)" \
        --preview-window="right:60%:wrap")

    [ -z "$sel" ] && return 1

    pid=$(printf '%s' "$sel" | cut -f1)
    if es_numero "$pid"; then
        detalle_pid "$pid"
        menu_acciones_pid "$pid"
    else
        info "El socket seleccionado no tiene un PID asociado o no se pudo leer."
        pausa
    fi
    return 0
}

mostrar_puertos_escucha() {
    clear
    mostrar_logo_proc4me
    seccion "PUERTOS EN ESCUCHA"

    local datos
    datos=$(ss -tulpnH 2>/dev/null | normalizar_ss)
    if [ -z "$datos" ]; then
        ok "No hay puertos en escucha."
        pausa
        return
    fi

    seleccionar_pid_de_ss "$datos" \
        "PID | Netid State Recv-Q Send-Q Local Address:Port Peer Address:Port Process" \
        "🔍 Seleccione un socket: "
}

mostrar_puertos_publicos() {
    clear
    mostrar_logo_proc4me
    seccion "PUERTOS EXPUESTOS PÚBLICAMENTE (0.0.0.0 / ::)"

    local raw datos
    raw=$(detectar_puertos_publicos)
    if [ -z "$raw" ]; then
        ok "No se detectaron puertos escuchando en todas las interfaces."
        pausa
        return
    fi

    echo -e "${ROJO}Netid State  Local Address:Port        Process${RESET}"
    echo -e "${CIAN}──────────────────────────────────────────────────────────────${RESET}"
    printf '%s\n' "$raw" | awk '{printf "%-5s %-6s %-26s %s\n", $1, $2, $5, substr($0, index($0,$7))}'
    echo ""

    datos=$(printf '%s\n' "$raw" | normalizar_ss)
    seleccionar_pid_de_ss "$datos" \
        "PID | Netid State Recv-Q Send-Q Local Address:Port Peer Address:Port Process" \
        "🔍 Seleccione un puerto público: "
}

mostrar_conexiones_establecidas() {
    clear
    mostrar_logo_proc4me
    seccion "CONEXIONES ESTABLECIDAS"

    local datos
    datos=$(ss -tunp state established 2>/dev/null | normalizar_ss)
    if [ -z "$datos" ]; then
        ok "No hay conexiones establecidas."
        pausa
        return
    fi

    seleccionar_pid_de_ss "$datos" \
        "PID | Netid State Recv-Q Send-Q Local Address:Port Peer Address:Port Process" \
        "🔍 Seleccione una conexión: "
}

mostrar_sockets_ocultos() {
    clear
    mostrar_logo_proc4me
    seccion "COMPARACIÓN ss vs /proc/net (SOCKETS OCULTOS)"

    local datos
    datos=$(detectar_sockets_ocultos)
    if [ -z "$datos" ]; then
        ok "No se detectaron discrepancias TCP entre ss y /proc/net."
    else
        alerta "Se detectaron puertos TCP en /proc/net que ss no muestra:"
        ver_lista_educativa socket_oculto "SOCKETS OCULTOS (ss vs /proc/net)" "$datos"
        info "Puede ser un fallo de ss o un intento de ocultación."
    fi
    pausa
}

# ==============================================================================
# --- VISTAS EDUCATIVAS DE UN VISTAZO ---
# ==============================================================================

ver_archivos_tmp() {
    clear
    mostrar_logo_proc4me
    seccion "EJECUTABLES EN /tmp Y RAM"
    local datos
    datos=$(detectar_archivos_tmp | filtrar_lineas_lista)
    ver_lista_educativa tmp "EJECUTABLES EN TEMPORALES" "$datos"
    pausa
}

ver_archivos_ocultos() {
    clear
    mostrar_logo_proc4me
    seccion "ARCHIVOS OCULTOS EN TEMPORALES"
    local datos
    datos=$(detectar_archivos_ocultos_tmp | filtrar_lineas_lista)
    ver_lista_educativa oculto "ARCHIVOS OCULTOS EN TEMPORALES" "$datos"
    pausa
}

ver_cambios_recientes() {
    clear
    mostrar_logo_proc4me
    seccion "CAMBIOS RECIENTES (48h)"
    local datos
    datos=$(detectar_cambios_recientes | filtrar_lineas_lista)
    ver_lista_educativa reciente "CAMBIOS RECIENTES EN RUTAS CRÍTICAS" "$datos"
    pausa
}

ver_suid() {
    clear
    mostrar_logo_proc4me
    seccion "BINARIOS SUID / SGID"
    local datos
    datos=$(detectar_suid | filtrar_lineas_lista)
    ver_lista_educativa suid "BINARIOS SUID / SGID" "$datos"
    pausa
}

ver_capabilities() {
    clear
    mostrar_logo_proc4me
    seccion "CAPABILITIES"
    local datos
    datos=$(detectar_capabilities | filtrar_lineas_lista)
    ver_lista_educativa capability "CAPABILITIES ASIGNADAS" "$datos"
    pausa
}

ver_archivos_borrados() {
    clear
    mostrar_logo_proc4me
    seccion "ARCHIVOS BORRADOS ABIERTOS"
    local datos
    datos=$(detectar_archivos_borrados_abiertos | filtrar_lineas_lista)
    ver_lista_educativa deleted "ARCHIVOS BORRADOS PERO ABIERTOS" "$datos"
    pausa
}

ver_integridad() {
    clear
    mostrar_logo_proc4me
    seccion "INTEGRIDAD DE PAQUETES"
    echo -ne "${AMARILLO}Este análisis puede tardar varios minutos. ¿Continuar? (s/N): ${RESET}"
    read -r resp
    if [[ ! "$resp" =~ ^[sS]$ ]]; then
        info "Análisis cancelado."
        pausa
        return
    fi
    local datos
    datos=$(verificar_integridad_paquetes | filtrar_lineas_lista)
    ver_lista_educativa integrity "INTEGRIDAD DE PAQUETES" "$datos"
    pausa
}

ver_persistencia_cron() {
    clear
    mostrar_logo_proc4me
    seccion "CRON Y TAREAS PROGRAMADAS"
    local datos
    datos=$(datos_persistencia_cron | etiquetar_bloques | filtrar_lineas_lista)
    ver_lista_educativa cron "CRON Y TAREAS PROGRAMADAS" "$datos"
    pausa
}

ver_persistencia_systemd() {
    clear
    mostrar_logo_proc4me
    seccion "SYSTEMD: UNIDADES Y TIMERS"
    local datos
    datos=$(datos_persistencia_systemd | etiquetar_bloques | filtrar_lineas_lista)
    ver_lista_educativa systemd "SYSTEMD: UNIDADES Y TIMERS" "$datos"
    pausa
}

ver_persistencia_ld_preload() {
    clear
    mostrar_logo_proc4me
    seccion "LD_PRELOAD Y LIBRERÍAS"
    local datos
    datos=$(datos_persistencia_ld_preload | etiquetar_bloques | filtrar_lineas_lista)
    ver_lista_educativa ld_preload "LD_PRELOAD Y LIBRERÍAS" "$datos"
    pausa
}

ver_persistencia_ssh_sudo() {
    clear
    mostrar_logo_proc4me
    seccion "SSH, AUTHORIZED_KEYS Y SUDOERS"
    local datos
    datos=$(datos_persistencia_ssh_sudo | etiquetar_bloques | filtrar_lineas_lista)
    ver_lista_educativa ssh_sudo "SSH, AUTHORIZED_KEYS Y SUDOERS" "$datos"
    pausa
}

ver_persistencia_reciente() {
    clear
    mostrar_logo_proc4me
    seccion "PERSISTENCIA MODIFICADA RECIENTEMENTE"
    local datos
    datos=$(datos_persistencia_reciente | filtrar_lineas_lista)
    ver_lista_educativa persistencia "PERSISTENCIA MODIFICADA RECIENTEMENTE" "$datos"
    pausa
}

ver_usuarios_uid0() {
    clear
    mostrar_logo_proc4me
    seccion "USUARIOS CON UID 0"
    local datos
    datos=$(datos_usuarios_uid0 | filtrar_lineas_lista)
    ver_lista_educativa usuario "USUARIOS CON UID 0" "$datos"
    pausa
}

ver_usuarios_shell() {
    clear
    mostrar_logo_proc4me
    seccion "USUARIOS CON SHELL VÁLIDA"
    local datos
    datos=$(datos_usuarios_shell | filtrar_lineas_lista)
    ver_lista_educativa usuario "USUARIOS CON SHELL VÁLIDA" "$datos"
    pausa
}

ver_sesiones() {
    clear
    mostrar_logo_proc4me
    seccion "SESIONES ACTIVAS"
    local datos
    datos=$(datos_sesiones | filtrar_lineas_lista)
    ver_lista_educativa sesion "SESIONES ACTIVAS" "$datos"
    pausa
}

ver_ultimos_accesos() {
    clear
    mostrar_logo_proc4me
    seccion "ÚLTIMOS ACCESOS Y FALLOS"
    local datos
    datos=$(datos_ultimos_accesos | filtrar_lineas_lista)
    ver_lista_educativa sesion "ÚLTIMOS ACCESOS Y FALLOS" "$datos"
    pausa
}

ver_ssh_logs() {
    clear
    mostrar_logo_proc4me
    seccion "REGISTROS SSH RECIENTES"
    local datos
    datos=$(datos_ssh_logs | filtrar_lineas_lista)
    ver_lista_educativa ssh_log "REGISTROS SSH RECIENTES" "$datos"
    pausa
}

ver_ssh_keys() {
    clear
    mostrar_logo_proc4me
    seccion "AUTHORIZED_KEYS"
    local datos
    datos=$(datos_ssh_keys | filtrar_lineas_lista)
    ver_lista_educativa ssh "AUTHORIZED_KEYS" "$datos"
    pausa
}

ver_sudoers() {
    clear
    mostrar_logo_proc4me
    seccion "SUDOERS"
    local datos
    datos=$(datos_sudoers | filtrar_lineas_lista)
    ver_lista_educativa sudoers "REGLAS DE SUDOERS" "$datos"
    pausa
}

ver_ssh_config() {
    clear
    mostrar_logo_proc4me
    seccion "CONFIGURACIÓN SSH"
    local datos
    datos=$(datos_ssh_config | filtrar_lineas_lista)
    ver_lista_educativa ssh_config "CONFIGURACIÓN SSH EFECTIVA" "$datos"
    pausa
}

ver_kernel_info() {
    clear
    mostrar_logo_proc4me
    seccion "INFORMACIÓN DEL KERNEL"
    local datos
    datos=$(datos_kernel_info | filtrar_lineas_lista)
    ver_lista_educativa kernel "INFORMACIÓN DEL KERNEL" "$datos"
    pausa
}

ver_modulos() {
    clear
    mostrar_logo_proc4me
    seccion "MÓDULOS DEL KERNEL"
    local datos
    datos=$(datos_modulos | filtrar_lineas_lista)
    ver_lista_educativa modulo "MÓDULOS DEL KERNEL" "$datos"
    pausa
}

ver_dmesg() {
    clear
    mostrar_logo_proc4me
    seccion "DMESG RECIENTE"
    local datos
    datos=$(datos_dmesg | filtrar_lineas_lista)
    ver_lista_educativa dmesg "MENSAJES RECIENTES DEL KERNEL" "$datos"
    pausa
}

ver_rootkit_tools() {
    clear
    mostrar_logo_proc4me
    seccion "HERRAMIENTAS ROOTKIT"
    local datos
    datos=$(datos_rootkit_tools | filtrar_lineas_lista)
    ver_lista_educativa rootkit_tool "HERRAMIENTAS ROOTKIT DISPONIBLES" "$datos"
    pausa
}

# ==============================================================================
# --- MENÚS DE MÓDULOS ---
# ==============================================================================

menu_procesos() {
    while true; do
        clear
        local opciones="1. 📋 Listar todos los procesos (FZF)
2. 🚨 Procesos sospechosos
3. 🧠 Binarios borrados / memfd / RAM
4. 🌐 Shells con sockets (posible reverse shell)
5. 👻 Procesos ocultos (/proc vs ps)
6. 📈 Top CPU / RAM
7. 🕵️ Inspector de PID
8. ↩ Volver"
        local sel
        sel=$(echo -e "$opciones" | proc4me_fzf_menu "Procesos" "PROCESOS Y MEMORIA")
        [ -z "$sel" ] && return 0

        case ${sel%%.*} in
            1) listar_todos_procesos ;;
            2) mostrar_procesos_sospechosos ;;
            3) mostrar_procesos_ram ;;
            4) mostrar_reverse_shells ;;
            5) mostrar_procesos_ocultos ;;
            6) mostrar_top_procesos ;;
            7) inspector_pid ;;
            8|*) return 0 ;;
        esac
    done
}

menu_puertos() {
    while true; do
        clear
        local opciones="1. 🔌 Puertos en escucha
2. 🌐 Puertos públicos (0.0.0.0 / ::)
3. 🔗 Conexiones establecidas
4. 🐚 Shells con sockets / reverse shells
5. 🕵️ Comparar ss vs /proc/net (sockets ocultos)
6. ℹ️ Nota sobre puertos y firewall
7. ↩ Volver"
        local sel
        sel=$(echo -e "$opciones" | proc4me_fzf_menu "Puertos" "PUERTOS, SOCKETS Y CONEXIONES")
        [ -z "$sel" ] && return 0

        case ${sel%%.*} in
            1) mostrar_puertos_escucha ;;
            2) mostrar_puertos_publicos ;;
            3) mostrar_conexiones_establecidas ;;
            4) mostrar_reverse_shells ;;
            5) mostrar_sockets_ocultos ;;
            6)
                clear
                mostrar_logo_proc4me
                seccion "NOTA SOBRE PUERTOS Y FIREWALL"
                echo -e " ${AMARILLO}Un puerto en escucha no es sinónimo de malware.${RESET}"
                echo " Verifica siempre:"
                echo "   • Qué proceso lo usa (PID)."
                echo "   • Ruta del ejecutable y paquete propietario."
                echo "   • Si el puerto está expuesto en 0.0.0.0 o solo en localhost."
                echo "   • Si el firewall del sistema lo permite."
                echo ""
                echo -e " ${AZUL}Estado del firewall:${RESET}"
                if command -v ufw >/dev/null 2>&1; then
                    ufw status 2>/dev/null | head -n 5
                elif command -v firewall-cmd >/dev/null 2>&1; then
                    firewall-cmd --state 2>/dev/null
                elif command -v nft >/dev/null 2>&1; then
                    nft list ruleset 2>/dev/null | head -n 20
                else
                    echo " (no se detectó ufw, firewalld ni nftables)"
                fi
                pausa
                ;;
            7|*) return 0 ;;
        esac
    done
}

mostrar_persistencia_todo() {
    clear
    mostrar_logo_proc4me
    seccion "PERSISTENCIA: CRON"
    datos_persistencia_cron
    echo ""
    seccion "PERSISTENCIA: SYSTEMD"
    datos_persistencia_systemd
    echo ""
    seccion "PERSISTENCIA: LD_PRELOAD"
    datos_persistencia_ld_preload
    echo ""
    seccion "PERSISTENCIA: SSH Y SUDOERS"
    datos_persistencia_ssh_sudo
    echo ""
    seccion "PERSISTENCIA: ARCHIVOS MODIFICADOS RECIENTEMENTE"
    datos_persistencia_reciente
    pausa
}

menu_persistencia() {
    while true; do
        clear
        local opciones="1. 📋 Ver toda la persistencia
2. ⏰ Cron y tareas programadas
3. ⚙️ Systemd (unidades y timers)
4. 🧬 LD_PRELOAD y librerías
5. 🔑 SSH, authorized_keys y sudoers
6. 🕒 Archivos de persistencia modificados recientemente
7. ↩ Volver"
        local sel
        sel=$(echo -e "$opciones" | proc4me_fzf_menu "Persistencia" "PERSISTENCIA Y ARRANQUE AUTOMÁTICO")
        [ -z "$sel" ] && return 0

        case ${sel%%.*} in
            1) mostrar_persistencia_todo ;;
            2) ver_persistencia_cron ;;
            3) ver_persistencia_systemd ;;
            4) ver_persistencia_ld_preload ;;
            5) ver_persistencia_ssh_sudo ;;
            6) ver_persistencia_reciente ;;
            7|*) return 0 ;;
        esac
    done
}

menu_archivos() {
    while true; do
        clear
        local opciones="1. 📂 Ejecutables y scripts en /tmp y RAM
2. 👁️ Archivos ocultos en directorios temporales
3. 🕒 Cambios recientes en directorios críticos
4. 🔐 Binarios SUID / SGID
5. 🧬 Capabilities
6. 🗑️ Archivos borrados pero abiertos
7. 🧾 Integridad de paquetes (profundo)
8. ↩ Volver"
        local sel
        sel=$(echo -e "$opciones" | proc4me_fzf_menu "Archivos" "ARCHIVOS, RAM Y BINARIOS")
        [ -z "$sel" ] && return 0

        case ${sel%%.*} in
            1) ver_archivos_tmp ;;
            2) ver_archivos_ocultos ;;
            3) ver_cambios_recientes ;;
            4) ver_suid ;;
            5) ver_capabilities ;;
            6) ver_archivos_borrados ;;
            7) ver_integridad ;;
            8|*) return 0 ;;
        esac
    done
}

mostrar_usuarios_todo() {
    clear
    mostrar_logo_proc4me
    seccion "USUARIOS CON UID 0"
    datos_usuarios_uid0
    echo ""
    seccion "USUARIOS CON SHELL VÁLIDA"
    datos_usuarios_shell
    echo ""
    seccion "SESIONES ACTIVAS"
    datos_sesiones
    echo ""
    seccion "ÚLTIMOS ACCESOS"
    datos_ultimos_accesos
    echo ""
    seccion "REGISTROS SSH"
    datos_ssh_logs
    echo ""
    seccion "AUTHORIZED_KEYS"
    datos_ssh_keys
    echo ""
    seccion "SUDOERS"
    datos_sudoers
    echo ""
    seccion "CONFIGURACIÓN SSH"
    datos_ssh_config
    pausa
}

menu_usuarios() {
    while true; do
        clear
        local opciones="1. 👤 Usuarios con UID 0
2. 🐚 Usuarios con shell válida
3. 🖥️ Sesiones activas
4. 🕒 Últimos accesos y fallos
5. 📜 Registros SSH recientes
6. 🔑 Authorized_keys
7. ⚙️ Sudoers
8. 🔐 Configuración SSH
9. 📋 Ver todo
10. ↩ Volver"
        local sel
        sel=$(echo -e "$opciones" | proc4me_fzf_menu "Usuarios" "USUARIOS, SESIONES Y ACCESOS")
        [ -z "$sel" ] && return 0

        case ${sel%%.*} in
            1) ver_usuarios_uid0 ;;
            2) ver_usuarios_shell ;;
            3) ver_sesiones ;;
            4) ver_ultimos_accesos ;;
            5) ver_ssh_logs ;;
            6) ver_ssh_keys ;;
            7) ver_sudoers ;;
            8) ver_ssh_config ;;
            9) mostrar_usuarios_todo ;;
            10|*) return 0 ;;
        esac
    done
}

mostrar_kernel_todo() {
    clear
    mostrar_logo_proc4me
    seccion "INFORMACIÓN DEL KERNEL"
    datos_kernel_info
    echo ""
    seccion "MÓDULOS"
    datos_modulos
    echo ""
    seccion "DMESG RECIENTE"
    datos_dmesg
    echo ""
    seccion "HERRAMIENTAS ROOTKIT"
    datos_rootkit_tools
    pausa
}

menu_kernel() {
    while true; do
        clear
        local opciones="1. 🧠 Información y estado tainted
2. 🧩 Módulos cargados y fuera del árbol
3. 📜 dmesg reciente
4. 🛡️ Herramientas rootkit disponibles
5. 📋 Ver todo
6. ↩ Volver"
        local sel
        sel=$(echo -e "$opciones" | proc4me_fzf_menu "Kernel" "KERNEL, MÓDULOS Y ROOTKITS")
        [ -z "$sel" ] && return 0

        case ${sel%%.*} in
            1) ver_kernel_info ;;
            2) ver_modulos ;;
            3) ver_dmesg ;;
            4) ver_rootkit_tools ;;
            5) mostrar_kernel_todo ;;
            6|*) return 0 ;;
        esac
    done
}

# Pregunta por una carpeta usando FZF; permite navegar y crear directorios.
# Devuelve la ruta elegida por stdout, o nada si se cancela.
elegir_directorio_fzf() {
    local dir="${1:-}"
    local sel sub opciones nombre_carpeta

    if [ -z "$dir" ]; then
        if [ -n "${SUDO_USER:-}" ]; then
            dir=$(getent passwd "$SUDO_USER" 2>/dev/null | cut -d: -f6)
        fi
        [ -n "$dir" ] && [ -d "$dir" ] || dir="${HOME:-/tmp}"
    fi

    while true; do
        opciones="✔ Usar esta carpeta
⬆ Subir un nivel
🏠 Ir al inicio del usuario
📁 /tmp
➕ Crear nueva carpeta aquí"

        while IFS= read -r sub; do
            [ -n "$sub" ] && opciones+=$'\n'"📁 $sub"
        done < <(find "$dir" -mindepth 1 -maxdepth 1 -type d ! -name '.*' -printf '%f\n' 2>/dev/null | LC_ALL=C sort)

        sel=$(printf '%s\n' "$opciones" | proc4me_fzf_menu "Carpeta" "ELEGIR DESTINO | $dir" "~75%")
        [ -z "$sel" ] && return 1

        case "$sel" in
            "✔ Usar esta carpeta")
                printf '%s\n' "$dir"
                return 0
                ;;
            "⬆ Subir un nivel")
                dir=$(dirname "$dir")
                ;;
            "🏠 Ir al inicio del usuario")
                if [ -n "${SUDO_USER:-}" ]; then
                    dir=$(getent passwd "$SUDO_USER" 2>/dev/null | cut -d: -f6)
                fi
                [ -n "$dir" ] && [ -d "$dir" ] || dir="${HOME:-/tmp}"
                ;;
            "📁 /tmp")
                dir="/tmp"
                ;;
            "➕ Crear nueva carpeta aquí")
                echo -ne "${AMARILLO}Nombre de la nueva carpeta: ${RESET}" >&2
                read -r nombre_carpeta
                if [ -z "$nombre_carpeta" ]; then
                    continue
                fi
                if [[ "$nombre_carpeta" == */* ]]; then
                    echo "El nombre no puede contener '/'." >&2
                    sleep 1
                    continue
                fi
                if mkdir -p "$dir/$nombre_carpeta" 2>/dev/null; then
                    devolver_propietario_usuario "$dir/$nombre_carpeta"
                    dir="$dir/$nombre_carpeta"
                else
                    echo "No se pudo crear la carpeta en $dir." >&2
                    sleep 1
                fi
                ;;
            "📁 "*)
                dir="$dir/${sel#📁 }"
                ;;
        esac
    done
}

# Exporta un informe de texto a Markdown eligiendo carpeta y nombre.
exportar_informe_markdown() {
    local ruta="$1"
    local base dir nombre destino resp

    base=$(basename "$ruta" .txt)
    dir=$(elegir_directorio_fzf)
    if [ -z "$dir" ]; then
        info "Exportación cancelada."
        pausa
        return 1
    fi

    echo -e "${AMARILLO}Carpeta destino:${RESET} $dir"
    echo -ne "${AMARILLO}Nombre del archivo Markdown [${base}.md]: ${RESET}"
    read -r nombre
    [ -z "$nombre" ] && nombre="${base}.md"
    [[ "$nombre" == *.* ]] || nombre="${nombre}.md"
    if [[ "$nombre" == */* ]]; then
        alerta "El nombre no puede contener '/'. La carpeta ya se eligió antes."
        pausa
        return 1
    fi

    destino="$dir/$nombre"
    if [ -e "$destino" ]; then
        echo -ne "${AMARILLO}El archivo ya existe. ¿Sobrescribir? (s/N): ${RESET}"
        read -r resp
        [[ "$resp" =~ ^[sS]$ ]] || { info "Exportación cancelada."; pausa; return 1; }
    fi

    if convertir_informe_markdown "$ruta" "$destino"; then
        devolver_propietario_usuario "$destino"
        ok "Informe exportado a: $destino"
        registrar_log "$LOG_INFO" "Informe exportado a Markdown: $destino"
    else
        alerta "No se pudo exportar el informe a $destino."
    fi
    pausa
}

# Copia el informe original (.txt) eligiendo carpeta y nombre.
exportar_informe_txt() {
    local ruta="$1"
    local base dir nombre destino resp

    base=$(basename "$ruta")
    dir=$(elegir_directorio_fzf)
    if [ -z "$dir" ]; then
        info "Copia cancelada."
        pausa
        return 1
    fi

    echo -e "${AMARILLO}Carpeta destino:${RESET} $dir"
    echo -ne "${AMARILLO}Nombre del archivo [${base}]: ${RESET}"
    read -r nombre
    [ -z "$nombre" ] && nombre="$base"
    [[ "$nombre" == *.* ]] || nombre="${nombre}.txt"
    if [[ "$nombre" == */* ]]; then
        alerta "El nombre no puede contener '/'. La carpeta ya se eligió antes."
        pausa
        return 1
    fi

    destino="$dir/$nombre"
    if [ -e "$destino" ]; then
        echo -ne "${AMARILLO}El archivo ya existe. ¿Sobrescribir? (s/N): ${RESET}"
        read -r resp
        [[ "$resp" =~ ^[sS]$ ]] || { info "Copia cancelada."; pausa; return 1; }
    fi

    if cp -f "$ruta" "$destino" 2>/dev/null; then
        devolver_propietario_usuario "$destino"
        ok "Informe copiado a: $destino"
        registrar_log "$LOG_INFO" "Informe copiado a: $destino"
    else
        alerta "No se pudo copiar el informe a $destino."
    fi
    pausa
}

menu_acciones_informe() {
    local archivo="$1"
    local ruta="$REPORT_DIR/$archivo"

    if [ ! -r "$ruta" ]; then
        alerta "El informe ya no existe o no se puede leer: $archivo"
        pausa
        return
    fi

    while true; do
        clear
        mostrar_logo_proc4me
        seccion "INFORME: $archivo"
        echo -e " ${AZUL}Ruta:${RESET} $ruta"
        echo -e " ${AZUL}Tamaño:${RESET} $(du -h "$ruta" 2>/dev/null | cut -f1)  ${AZUL}Líneas:${RESET} $(wc -l < "$ruta" 2>/dev/null)"

        local opciones="1. 👁️ Ver contenido completo
2. 📝 Exportar a Markdown (elegir carpeta y nombre)
3. 💾 Copiar informe .txt (elegir carpeta y nombre)
4. ↩ Volver"
        local sel
        sel=$(echo -e "$opciones" | proc4me_fzf_menu "Informe" "ACCIONES SOBRE EL INFORME" "~60%")
        [ -z "$sel" ] && return 0

        case ${sel%%.*} in
            1)
                clear
                mostrar_logo_proc4me
                seccion "INFORME: $archivo"
                if command -v less >/dev/null 2>&1; then
                    less -R "$ruta"
                else
                    cat "$ruta"
                fi
                pausa
                ;;
            2) exportar_informe_markdown "$ruta" ;;
            3) exportar_informe_txt "$ruta" ;;
            4|*) return 0 ;;
        esac
    done
}

seleccionar_informe() {
    local datos sel archivo preview_cmd

    datos=$(listar_informes)
    if [ -z "$datos" ]; then
        ok "Todavía no hay informes en $REPORT_DIR."
        pausa
        return
    fi

    printf -v preview_cmd 'bash %q --preview-informe {4}' "$SELF_PATH"

    sel=$(printf '%s\n' "$datos" | fzf --ansi \
        --height=85% --min-height=20 \
        --layout=reverse \
        --border=rounded \
        --border-label=" INFORMES DISPONIBLES " \
        --prompt="🔍 Seleccione un informe: " \
        --header="FECHA | HORA | TAMAÑO | ARCHIVO   (Enter: ver / exportar)" \
        --preview "$preview_cmd" \
        --preview-window="right:60%:wrap" \
        --color="border:#ff5555,pointer:#92ff92,header:#5fb2ff,label:#5fb2ff")

    [ -z "$sel" ] && return
    archivo=$(printf '%s' "$sel" | awk '{print $NF}')
    [ -n "$archivo" ] && menu_acciones_informe "$archivo"
}


menu_ayuda() {
    clear
    mostrar_logo_proc4me
    seccion "AYUDA Y LIMITACIONES"
    cat <<'AYUDA'

 PROC4ME es un investigador forense ligero. No es un antivirus ni un EDR.

 QUÉ HACE:
   • Analiza procesos, memoria, puertos, persistencia, archivos, usuarios y kernel.
   • Guarda los informes en texto en /var/log/proc4me/.
   • Permite verlos y exportarlos a Markdown o copiarlos donde elijas.
   • Permite enviar señales a procesos con confirmación explícita.
   • Muestra una guía educativa y contexto en el panel de vista previa de cada lista.

 CÓMO LEER LAS LISTAS:
   • Selecciona una línea con las flechas para ver su explicación y contexto.
   • La guía indica qué es, por qué importa, falsos positivos y qué revisar.
   • Un hallazgo no es malware por sí solo: contrasta ruta, paquete, fecha y proceso.

 QUÉ NO HACE:
   • No instala herramientas automáticamente.
   • No elimina archivos ni entradas de persistencia.
   • No garantiza detectar rootkits avanzados que oculten información.

 RECOMENDACIONES:
   • Un rootkit puede ocultar procesos, puertos y archivos.
   • Ante una sospecha grave, analiza el disco desde un medio confiable.
   • Contrasta con rkhunter, chkrootkit, unhide, debsums o rpm -Va.
   • Revisa los falsos positivos: contenedores, snaps, flatpaks y servicios de usuario.

 FLAGS:
   --help      Muestra esta ayuda
   --version   Muestra la versión
   --quick     Escaneo rápido y salida
   --full      Auditoría completa y salida
   --pid PID   Muestra el detalle de un PID

AYUDA
    pausa
}

# ==============================================================================
# --- AUDITORÍA: HALLAZGOS, RIESGO E INFORMES ---
# ==============================================================================

INCLUIR_INTEGRIDAD="no"
INTEGRIDAD_OUTPUT=""

limpiar_hallazgos() {
    HALLAZGOS_SEV=()
    HALLAZGOS_MOD=()
    HALLAZGOS_DESC=()
    HALLAZGOS_REC=()
    INTEGRIDAD_OUTPUT=""
}

registrar_hallazgo() {
    local sev="$1"
    local mod="$2"
    local desc="$3"
    local rec="$4"
    HALLAZGOS_SEV+=("$sev")
    HALLAZGOS_MOD+=("$mod")
    HALLAZGOS_DESC+=("$desc")
    HALLAZGOS_REC+=("$rec")
}

calcular_riesgo() {
    local score=0 sev
    for sev in "${HALLAZGOS_SEV[@]}"; do
        case "$sev" in
            CRITICO) score=$((score + 20)) ;;
            ALTO)    score=$((score + 10)) ;;
            MEDIO)   score=$((score + 5)) ;;
            BAJO)    score=$((score + 1)) ;;
        esac
    done
    [ "$score" -gt 100 ] && score=100
    printf '%s' "$score"
}

nivel_riesgo() {
    local score="$1"
    if [ "$score" -ge 75 ]; then
        echo "CRÍTICO"
    elif [ "$score" -ge 50 ]; then
        echo "ALTO"
    elif [ "$score" -ge 20 ]; then
        echo "MEDIO"
    else
        echo "BAJO"
    fi
}

mostrar_resumen_riesgo() {
    local score nivel color i c
    score=$(calcular_riesgo)
    nivel=$(nivel_riesgo "$score")
    color="$VERDE_BRILLANTE"
    case "$nivel" in
        CRÍTICO) color="$ROJO_BRILLANTE" ;;
        ALTO)    color="$ROJO" ;;
        MEDIO)   color="$AMARILLO" ;;
    esac

    echo ""
    echo -e "${CIAN}════════════════════════════════════════════════════════════${RESET}"
    echo -e " ${NEGRITA}RESUMEN DE RIESGO:${RESET} ${color}${nivel} (${score}/100)${RESET}"
    echo -e " Hallazgos registrados: ${#HALLAZGOS_SEV[@]}"
    echo -e "${CIAN}════════════════════════════════════════════════════════════${RESET}"

    if [ ${#HALLAZGOS_SEV[@]} -eq 0 ]; then
        ok "No se registraron hallazgos con los criterios actuales."
        return
    fi

    for i in "${!HALLAZGOS_SEV[@]}"; do
        c="$AMARILLO"
        case "${HALLAZGOS_SEV[$i]}" in
            CRITICO) c="$ROJO_BRILLANTE" ;;
            ALTO)    c="$ROJO" ;;
            MEDIO)   c="$AMARILLO" ;;
            BAJO)    c="$AZUL" ;;
        esac
        echo -e " ${c}[${HALLAZGOS_SEV[$i]}]${RESET} ${NEGRITA}${HALLAZGOS_MOD[$i]}${RESET}: ${HALLAZGOS_DESC[$i]}"
        [ -n "${HALLAZGOS_REC[$i]}" ] && echo -e "        ${AZUL}→ ${HALLAZGOS_REC[$i]}${RESET}"
    done
}

evaluar_procesos() {
    local datos pid usuario motivo exe sev
    datos=$(detectar_procesos_sospechosos)
    [ -z "$datos" ] && return

    while IFS=$'\t' read -r pid usuario motivo exe; do
        [ -z "$pid" ] && continue
        sev="ALTO"
        if [[ "$motivo" == *"binario borrado"* ]] || [[ "$motivo" == *"memfd"* ]] || [[ "$motivo" == *"sin ejecutable"* ]]; then
            sev="CRITICO"
        fi
        registrar_hallazgo "$sev" "Proceso" "PID $pid ($usuario): $motivo" "Investigue el origen y el ejecutable: $exe"
    done <<< "$datos"
}

evaluar_reverse_shells() {
    local datos pid usuario comm local_ip remote_ip state
    datos=$(detectar_reverse_shells)
    [ -z "$datos" ] && return

    while IFS=$'\t' read -r pid usuario comm local_ip remote_ip state; do
        [ -z "$pid" ] && continue
        registrar_hallazgo "CRITICO" "Reverse Shell" \
            "PID $pid ($usuario, $comm): $local_ip -> $remote_ip ($(estado_tcp "$state"))" \
            "Aísle el equipo y analice el proceso y la conexión."
    done <<< "$datos"
}

evaluar_procesos_ocultos() {
    local datos pid
    datos=$(detectar_procesos_ocultos)
    [ -z "$datos" ] && return

    while IFS= read -r pid; do
        [ -z "$pid" ] && continue
        registrar_hallazgo "CRITICO" "Proceso oculto" \
            "PID $pid visible en /proc pero no en ps." \
            "Posible manipulación de libproc o rootkit. Analice desde un medio confiable."
    done <<< "$datos"
}

evaluar_puertos() {
    local datos line

    datos=$(detectar_puertos_publicos)
    if [ -n "$datos" ]; then
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            registrar_hallazgo "BAJO" "Puerto público" "$line" \
                "Verifique que el servicio sea necesario y esté protegido por firewall."
        done <<< "$datos"
    fi

    datos=$(detectar_sockets_ocultos)
    if [ -n "$datos" ]; then
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            registrar_hallazgo "CRITICO" "Socket oculto" "$line" \
                "Compare /proc/net con ss y analice posibles rootkits."
        done <<< "$datos"
    fi
}

evaluar_persistencia() {
    local datos line sev
    datos=$(detectar_persistencia_critica)
    [ -z "$datos" ] && return

    while IFS= read -r line; do
        [ -z "$line" ] && continue
        sev="ALTO"
        case "$line" in
            \[CRITICO\]*)     sev="CRITICO" ;;
            \[SYSTEMD-TMP\]*) sev="ALTO" ;;
            \[CRON\]*|\[CRON-FILE\]*) sev="ALTO" ;;
            \[RC.LOCAL\]*)    sev="MEDIO" ;;
            \[SSH-KEYS\]*)    sev="MEDIO" ;;
        esac
        registrar_hallazgo "$sev" "Persistencia" "$line" \
            "Revise la entrada y elimínela si no es legítima."
    done <<< "$datos"
}

evaluar_archivos() {
    local datos count line

    datos=$(detectar_archivos_tmp)
    if [ -n "$datos" ]; then
        count=$(printf '%s\n' "$datos" | wc -l)
        registrar_hallazgo "ALTO" "Archivos temporales" \
            "$count ejecutables/scripts en /tmp, /var/tmp, /dev/shm o /run." \
            "Revise la lista y elimine lo que no reconozca."
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            registrar_hallazgo "MEDIO" "Archivo temporal" "$line" "Verifique el archivo."
        done < <(printf '%s\n' "$datos" | head -n 3)
    fi

    datos=$(detectar_archivos_ocultos_tmp)
    if [ -n "$datos" ]; then
        count=$(printf '%s\n' "$datos" | wc -l)
        registrar_hallazgo "MEDIO" "Archivos ocultos" \
            "$count archivos ocultos en directorios temporales." \
            "Revise los archivos ocultos y su origen."
    fi

    datos=$(detectar_archivos_borrados_abiertos)
    if [ -n "$datos" ]; then
        count=$(printf '%s\n' "$datos" | wc -l)
        registrar_hallazgo "MEDIO" "Archivos borrados abiertos" \
            "$count archivos borrados siguen abiertos por procesos." \
            "Identifique el proceso y el archivo original."
    fi

    count=$(detectar_suid | wc -l)
    if [ "$count" -gt 60 ]; then
        registrar_hallazgo "MEDIO" "SUID/SGID" \
            "Se detectaron $count binarios SUID/SGID (umbral alto)." \
            "Audita los binarios y elimina permisos innecesarios."
    fi
}

evaluar_usuarios() {
    local user _ uid _ failed f

    while IFS=: read -r user _ uid _; do
        [ "$uid" = "0" ] || continue
        [ "$user" = "root" ] && continue
        registrar_hallazgo "CRITICO" "Usuario" \
            "Cuenta con UID 0: $user" \
            "Elimine o bloquee la cuenta no autorizada."
    done < /etc/passwd

    failed=0
    if command -v journalctl >/dev/null 2>&1; then
        failed=$(journalctl -u ssh -u sshd --no-pager -n 1000 2>/dev/null | grep -c 'Failed password')
    fi
    if [ "$failed" -eq 0 ]; then
        for f in /var/log/auth.log /var/log/secure; do
            [ -r "$f" ] && failed=$(grep -c 'Failed password' "$f" 2>/dev/null)
            [ "$failed" -gt 0 ] && break
        done
    fi
    if [ "$failed" -gt 10 ]; then
        registrar_hallazgo "MEDIO" "SSH" \
            "$failed intentos fallidos de autenticación recientes." \
            "Considere fail2ban y deshabilitar PasswordAuthentication."
    fi

    while IFS= read -r f; do
        [ -z "$f" ] && continue
        registrar_hallazgo "MEDIO" "SSH" \
            "authorized_keys modificado recientemente: $f" \
            "Verifique que la clave corresponda a un acceso legítimo."
    done < <(find /root /home -maxdepth 4 -path '*/.ssh/authorized_keys' -type f -mtime -7 2>/dev/null)
}

evaluar_kernel() {
    local taint mods count dmesg_output

    taint=$(cat /proc/sys/kernel/tainted 2>/dev/null)
    if [ -n "$taint" ] && [ "$taint" != "0" ]; then
        registrar_hallazgo "ALTO" "Kernel" \
            "Kernel tainted: $taint" \
            "Investiga la causa (módulos fuera del árbol, fallos de hardware o verificación)."
    fi

    mods=$(datos_modulos | grep 'no encontrado en /lib/modules' 2>/dev/null)
    if [ -n "$mods" ]; then
        count=$(printf '%s\n' "$mods" | wc -l)
        registrar_hallazgo "MEDIO" "Módulos" \
            "$count módulos cargados no están en /lib/modules/$(uname -r)." \
            "Verifica si son módulos legítimos de terceros."
        while IFS= read -r line; do
            [ -z "$line" ] && continue
            registrar_hallazgo "MEDIO" "Módulo" "$line" "Verifique el origen del módulo."
        done < <(printf '%s\n' "$mods" | head -n 5)
    fi

    dmesg_output=$(datos_dmesg)
    if printf '%s' "$dmesg_output" | grep -qiE 'rootkit|taint|verification failed|module verification'; then
        registrar_hallazgo "ALTO" "dmesg" \
            "dmesg contiene mensajes relacionados con taint, módulos o rootkits." \
            "Revise el log completo con: dmesg -T"
    fi

    [ "$(sysctl -n kernel.kptr_restrict 2>/dev/null)" = "0" ] && \
        registrar_hallazgo "BAJO" "Hardening" "kernel.kptr_restrict=0" \
            "Considera establecer kernel.kptr_restrict=1 o 2."

    [ "$(sysctl -n kernel.dmesg_restrict 2>/dev/null)" = "0" ] && \
        registrar_hallazgo "BAJO" "Hardening" "kernel.dmesg_restrict=0" \
            "Considera establecer kernel.dmesg_restrict=1."
}

evaluar_integridad() {
    local datos count
    INTEGRIDAD_OUTPUT=$(verificar_integridad_paquetes | grep -v '^(')
    datos="$INTEGRIDAD_OUTPUT"
    [ -z "$datos" ] && return

    count=$(printf '%s\n' "$datos" | wc -l)
    registrar_hallazgo "ALTO" "Integridad" \
        "$count líneas de integridad de paquetes con cambios." \
        "Revise los binarios modificados y reinstale los paquetes afectados."
}

# Convierte un informe de texto de PROC4ME en Markdown estructurado.
# Uso: convertir_informe_markdown ORIGEN [DESTINO]
convertir_informe_markdown() {
    local origen="$1"
    local destino="${2:-${1%.txt}.md}"

    [ -r "$origen" ] || return 1
    mkdir -p "$(dirname "$destino")" 2>/dev/null || return 1

    awk '
    function flush(   i, l, clave, valor) {
        if (seccion == "") { n = 0; return }
        if (seccion == "FIN DEL INFORME") {
            print "\n---\n"
            n = 0
            return
        }
        if (seccion == "HALLAZGOS") {
            if (n == 0) {
                print "\n_Sin hallazgos con los criterios actuales._\n"
            } else {
                print ""
                for (i = 1; i <= n; i++) {
                    l = buf[i]
                    if (l ~ /^\[(CRITICO|ALTO|MEDIO|BAJO)\]/) {
                        sub(/^\[/, "**[", l)
                        sub(/\] /, "]** — ", l)
                        print "- " l
                    } else if (l ~ /^[[:space:]]+Recomendación:/) {
                        sub(/^[[:space:]]+/, "", l)
                        clave = l
                        sub(/: .*/, "", clave)
                        valor = l
                        sub(/^[^:]+: /, "", valor)
                        print "  - **" clave ":** " valor
                    } else if (l != "") {
                        print "  " l
                    }
                }
                print ""
            }
        } else if (seccion == "RESUMEN DE RIESGO") {
            print ""
            for (i = 1; i <= n; i++) {
                l = buf[i]
                if (l ~ /^[^:]+: /) {
                    clave = l
                    sub(/: .*/, "", clave)
                    sub(/^[[:space:]]+/, "", clave)
                    gsub(/[[:space:]]+$/, "", clave)
                    valor = l
                    sub(/^[^:]+: /, "", valor)
                    print "- **" clave ":** " valor
                } else if (l != "") {
                    print l
                }
            }
            print ""
        } else {
            if (n == 0) {
                print "\n_Sin datos._\n"
            } else {
                print "\n~~~text"
                for (i = 1; i <= n; i++) print buf[i]
                print "~~~\n"
            }
        }
        n = 0
    }

    BEGIN { seccion = ""; primer = 1; n = 0 }

    /^={20,}$/ {
        flush()
        if ((getline t) > 0) seccion = t
        getline s
        if (seccion != "FIN DEL INFORME") print "\n## " seccion
        next
    }

    {
        if (seccion == "") {
            if (primer) {
                print "# " $0
                primer = 0
            } else if ($0 ~ /^[[:space:]]*═+[[:space:]]*$/) {
                next
            } else if ($0 ~ /^[[:space:]]*DETALLE DEL PROCESO PID [0-9]+[[:space:]]*$/) {
                l = $0
                sub(/^[[:space:]]+/, "", l)
                print "\n## " l
            } else if ($0 ~ /^[[:space:]]*(Árbol de procesos|Conexiones de red|Mapas de memoria sospechosos|Entorno relevante):/) {
                l = $0
                sub(/^[[:space:]]+/, "", l)
                print "\n### " l
            } else if ($0 ~ /^[^:]+: /) {
                clave = $0
                sub(/: .*/, "", clave)
                sub(/^[[:space:]]+/, "", clave)
                gsub(/[[:space:]]+$/, "", clave)
                valor = $0
                sub(/^[^:]+: /, "", valor)
                print "- **" clave ":** " valor
            } else if ($0 != "") {
                print $0
            }
        } else {
            buf[++n] = $0
        }
    }

    END { flush() }
    ' "$origen" > "$destino"

    chmod 640 "$destino" 2>/dev/null
    [ -s "$destino" ]
}

listar_informes() {
    find "$REPORT_DIR" -maxdepth 1 -type f -name 'proc4me_*.txt' \
        -printf '%TY-%Tm-%Td %TH:%TM %10s %f\n' 2>/dev/null | sort -r
}

preview_informe() {
    local nombre="${1##*/}"
    local ruta="$REPORT_DIR/$nombre"
    local total

    if [ ! -r "$ruta" ]; then
        echo "Informe no encontrado o sin permisos: $nombre"
        return 1
    fi

    echo -e "${CIAN}INFORME:${RESET} $nombre"
    echo -e "${CIAN}────────────────────────────────────────────────────────────${RESET}"
    head -n 80 "$ruta" 2>/dev/null
    total=$(wc -l < "$ruta" 2>/dev/null)
    if [ "${total:-0}" -gt 80 ]; then
        echo ""
        echo -e "${AMARILLO}... informe truncado en la vista previa ($total líneas).${RESET}"
        echo -e "${AZUL}Ábrelo desde el menú para verlo completo.${RESET}"
    fi
}

generar_informe() {
    local tipo="${1:-Auditoría}"
    local score nivel reporte
    score=$(calcular_riesgo)
    nivel=$(nivel_riesgo "$score")
    reporte="$REPORT_DIR/proc4me_$(date +%Y-%m-%d_%H-%M-%S)_$$.txt"

    {
        echo "PROC4ME v$V - Informe: $tipo"
        echo "Fecha: $(date '+%Y-%m-%d %H:%M:%S')"
        echo "Host: $(hostname 2>/dev/null)"
        echo "Kernel: $(uname -a 2>/dev/null)"
        echo "Usuario: ${USER:-$(id -un 2>/dev/null)}"
        echo "Sistema: $OS_ID (gestor: $Package)"
        echo ""
        echo "============================================================"
        echo "RESUMEN DE RIESGO"
        echo "============================================================"
        echo "Nivel: $nivel"
        echo "Puntuación: $score/100"
        echo "Hallazgos: ${#HALLAZGOS_SEV[@]}"
        echo ""
        echo "============================================================"
        echo "HALLAZGOS"
        echo "============================================================"
        if [ ${#HALLAZGOS_SEV[@]} -eq 0 ]; then
            echo "Sin hallazgos con los criterios actuales."
        else
            local i
            for i in "${!HALLAZGOS_SEV[@]}"; do
                echo "[${HALLAZGOS_SEV[$i]}] ${HALLAZGOS_MOD[$i]}: ${HALLAZGOS_DESC[$i]}"
                [ -n "${HALLAZGOS_REC[$i]}" ] && echo "  Recomendación: ${HALLAZGOS_REC[$i]}"
            done
        fi
        echo ""
        echo "============================================================"
        echo "PROCESOS SOSPECHOSOS"
        echo "============================================================"
        detectar_procesos_sospechosos
        echo ""
        echo "============================================================"
        echo "REVERSE SHELLS / SHELLS CON SOCKETS"
        echo "============================================================"
        detectar_reverse_shells
        echo ""
        echo "============================================================"
        echo "PROCESOS OCULTOS (/proc vs ps)"
        echo "============================================================"
        detectar_procesos_ocultos
        echo ""
        echo "============================================================"
        echo "PUERTOS EN ESCUCHA"
        echo "============================================================"
        ss -tulpn 2>/dev/null
        echo ""
        echo "============================================================"
        echo "PUERTOS PÚBLICOS"
        echo "============================================================"
        detectar_puertos_publicos
        echo ""
        echo "============================================================"
        echo "SOCKETS OCULTOS (ss vs /proc/net)"
        echo "============================================================"
        detectar_sockets_ocultos
        echo ""
        echo "============================================================"
        echo "PERSISTENCIA CRÍTICA"
        echo "============================================================"
        detectar_persistencia_critica
        echo ""
        echo "============================================================"
        echo "ARCHIVOS EN /tmp Y RAM"
        echo "============================================================"
        detectar_archivos_tmp
        echo ""
        echo "============================================================"
        echo "ARCHIVOS OCULTOS EN TEMPORALES"
        echo "============================================================"
        detectar_archivos_ocultos_tmp
        echo ""
        echo "============================================================"
        echo "ARCHIVOS BORRADOS ABIERTOS"
        echo "============================================================"
        detectar_archivos_borrados_abiertos
        echo ""
        echo "============================================================"
        echo "USUARIOS CON UID 0"
        echo "============================================================"
        datos_usuarios_uid0
        echo ""
        echo "============================================================"
        echo "USUARIOS CON SHELL"
        echo "============================================================"
        datos_usuarios_shell
        echo ""
        echo "============================================================"
        echo "SESIONES Y ÚLTIMOS ACCESOS"
        echo "============================================================"
        datos_sesiones
        datos_ultimos_accesos
        echo ""
        echo "============================================================"
        echo "REGISTROS SSH"
        echo "============================================================"
        datos_ssh_logs
        echo ""
        echo "============================================================"
        echo "AUTHORIZED_KEYS"
        echo "============================================================"
        datos_ssh_keys
        echo ""
        echo "============================================================"
        echo "SUDOERS"
        echo "============================================================"
        datos_sudoers
        echo ""
        echo "============================================================"
        echo "KERNEL Y MÓDULOS"
        echo "============================================================"
        datos_kernel_info
        datos_modulos
        echo ""
        echo "============================================================"
        echo "DMESG RECIENTE"
        echo "============================================================"
        datos_dmesg
        echo ""
        echo "============================================================"
        echo "HERRAMIENTAS ROOTKIT"
        echo "============================================================"
        datos_rootkit_tools
        if [ "$INCLUIR_INTEGRIDAD" = "si" ]; then
            echo ""
            echo "============================================================"
            echo "INTEGRIDAD DE PAQUETES"
            echo "============================================================"
            printf '%s\n' "$INTEGRIDAD_OUTPUT"
        fi
        echo ""
        echo "============================================================"
        echo "FIN DEL INFORME"
        echo "============================================================"
    } 2>&1 | sed -r 's/\x1B\[[0-9;]*[mK]//g' > "$reporte"

    chmod 640 "$reporte" 2>/dev/null
    ok "Informe guardado en: $reporte"
    registrar_log "$LOG_INFO" "Informe '$tipo' generado: $reporte (Riesgo $score/100, ${#HALLAZGOS_SEV[@]} hallazgos)"
}

# ==============================================================================
# --- EJECUCIÓN DE AUDITORÍAS ---
# ==============================================================================

escaneo_rapido() {
    local interactivo="${1:-si}"

    clear
    mostrar_logo_proc4me
    seccion "ESCANEO RÁPIDO DE AMENAZAS"
    echo -e "${AZUL}Analizando procesos, puertos, persistencia y accesos...${RESET}\n"

    limpiar_hallazgos
    INCLUIR_INTEGRIDAD="no"

    echo -e "${CIAN}[1/6] Procesos sospechosos...${RESET}"
    evaluar_procesos
    echo -e "${CIAN}[2/6] Reverse shells...${RESET}"
    evaluar_reverse_shells
    echo -e "${CIAN}[3/6] Procesos ocultos...${RESET}"
    evaluar_procesos_ocultos
    echo -e "${CIAN}[4/6] Puertos y sockets...${RESET}"
    evaluar_puertos
    echo -e "${CIAN}[5/6] Persistencia...${RESET}"
    evaluar_persistencia
    echo -e "${CIAN}[6/6] Usuarios y accesos...${RESET}"
    evaluar_usuarios

    mostrar_resumen_riesgo
    echo ""
    if [ "$interactivo" = "si" ]; then
        echo -ne "${AMARILLO}¿Guardar informe? (s/N): ${RESET}"
        read -r resp
        if [[ "$resp" =~ ^[sS]$ ]]; then
            generar_informe "Escaneo rápido"
        fi
        registrar_log "$LOG_INFO" "Escaneo rápido completado. Riesgo: $(calcular_riesgo)/100. Hallazgos: ${#HALLAZGOS_SEV[@]}"
        pausa
    else
        generar_informe "Escaneo rápido"
        registrar_log "$LOG_INFO" "Escaneo rápido completado. Riesgo: $(calcular_riesgo)/100. Hallazgos: ${#HALLAZGOS_SEV[@]}"
    fi
}

auditoria_completa() {
    local interactivo="${1:-si}"
    local resp

    clear
    mostrar_logo_proc4me
    seccion "AUDITORÍA COMPLETA"
    echo -e "${AZUL}Recopilando información de todos los módulos...${RESET}\n"

    limpiar_hallazgos
    INCLUIR_INTEGRIDAD="no"

    echo -e "${CIAN}[1/7] Procesos y memoria...${RESET}"
    evaluar_procesos
    echo -e "${CIAN}[2/7] Puertos, conexiones y reverse shells...${RESET}"
    evaluar_reverse_shells
    evaluar_procesos_ocultos
    evaluar_puertos
    echo -e "${CIAN}[3/7] Persistencia...${RESET}"
    evaluar_persistencia
    echo -e "${CIAN}[4/7] Archivos y binarios...${RESET}"
    evaluar_archivos
    echo -e "${CIAN}[5/7] Usuarios y accesos...${RESET}"
    evaluar_usuarios
    echo -e "${CIAN}[6/7] Kernel y rootkits...${RESET}"
    evaluar_kernel

    echo -e "${CIAN}[7/7] Integridad de paquetes...${RESET}"
    if [ "$interactivo" = "si" ]; then
        echo -ne "${AMARILLO}¿Incluir verificación de integridad? Puede tardar varios minutos. (s/N): ${RESET}"
        read -r resp
        if [[ "$resp" =~ ^[sS]$ ]]; then
            INCLUIR_INTEGRIDAD="si"
            evaluar_integridad
        fi
    else
        INCLUIR_INTEGRIDAD="si"
        evaluar_integridad
    fi

    mostrar_resumen_riesgo
    echo ""
    if [ "$interactivo" = "si" ]; then
        echo -ne "${AMARILLO}¿Guardar informe completo? (s/N): ${RESET}"
        read -r resp
        if [[ "$resp" =~ ^[sS]$ ]]; then
            generar_informe "Auditoría completa"
        fi
        registrar_log "$LOG_INFO" "Auditoría completa. Riesgo: $(calcular_riesgo)/100. Hallazgos: ${#HALLAZGOS_SEV[@]}"
        pausa
    else
        generar_informe "Auditoría completa"
        registrar_log "$LOG_INFO" "Auditoría completa. Riesgo: $(calcular_riesgo)/100. Hallazgos: ${#HALLAZGOS_SEV[@]}"
    fi
}

# ==============================================================================
# --- MENÚ PRINCIPAL ---
# ==============================================================================

proc4me_main_menu() {
    if command -v tput >/dev/null 2>&1; then
        trap 'tput cnorm 2>/dev/null; echo; exit 130' INT TERM
    else
        trap 'echo; exit 130' INT TERM
    fi

    while true; do
        clear

        local procesos puertos resumen
        procesos=$(ps -e --no-headers 2>/dev/null | wc -l)
        puertos=$(ss -tulnH 2>/dev/null | wc -l)
        resumen="PROCESOS: $procesos | PUERTOS: $puertos"

        local opciones="1. 🚨 | ESCANEO RÁPIDO       | Detección de amenazas en menos de 1 minuto
2. 🧠 | PROCESOS Y MEMORIA   | Procesos, RAM, binarios borrados, memfd
3. 🌐 | PUERTOS Y CONEXIONES | Sockets, conexiones, reverse shells
4. 🔁 | PERSISTENCIA         | Cron, systemd, rc.local, LD_PRELOAD
5. 📂 | ARCHIVOS Y TMP       | Ejecutables en /tmp, SUID, integridad
6. 👤 | USUARIOS Y ACCESOS   | Sesiones, SSH, UID 0, authorized_keys
7. 🧩 | KERNEL Y ROOTKITS    | Módulos, dmesg, herramientas opcionales
8. 📊 | AUDITORÍA COMPLETA   | Todos los checks + informe
9. 🕵️ | INSPECTOR DE PID     | Ver y actuar sobre un proceso
10. 📄 | INFORMES             | Ver y exportar a Markdown o .txt
11. ℹ️ | AYUDA Y LIMITACIONES
12. ↩ | SALIR"

        local sel
        sel=$(echo -e "$opciones" | proc4me_fzf_menu "Selección" "PANEL DE CONTROL - PROC4ME | $resumen" "~95%")
        [ -z "$sel" ] && { salir_proc4me; break; }

        case ${sel%%.*} in
            1) escaneo_rapido "si" ;;
            2) menu_procesos ;;
            3) menu_puertos ;;
            4) menu_persistencia ;;
            5) menu_archivos ;;
            6) menu_usuarios ;;
            7) menu_kernel ;;
            8) auditoria_completa "si" ;;
            9) inspector_pid ;;
            10) seleccionar_informe ;;
            11) menu_ayuda ;;
            12) salir_proc4me; break ;;
            *) ;;
        esac
    done
}

# ==============================================================================
# --- AYUDA CLI ---
# ==============================================================================

mostrar_ayuda_cli() {
    echo -e "${CIAN}PROC4ME v${V} - ${DESCRIPCION}${RESET}"
    echo -e "${BLANCO}Autor:${RESET} ${AUTOR}"
    echo ""
    echo -e "${BLANCO}Uso:${RESET} sudo $0 [OPCIÓN]"
    echo ""
    echo -e "${AMARILLO}Opciones de línea de comandos:${RESET}"
    echo -e "  ${VERDE}--quick${RESET}       Ejecuta el escaneo rápido y sale."
    echo -e "  ${VERDE}--full${RESET}        Ejecuta la auditoría completa y sale."
    echo -e "  ${VERDE}--pid PID${RESET}     Muestra el detalle forense de un proceso."
    echo -e "  ${VERDE}--version${RESET}     Muestra la versión y sale."
    echo -e "  ${VERDE}--help${RESET}        Muestra esta ayuda y sale."
    echo ""
    echo -e "${AMARILLO}Sin argumentos:${RESET} abre el menú interactivo con FZF."
    echo -e "  Selecciona una línea en las listas para ver su guía educativa y contexto."
    echo ""
    echo -e "${AZUL}Informes:${RESET} ${REPORT_DIR}"
    echo -e "${AZUL}Log de acciones:${RESET} ${LOG_FILE}"
    echo ""
    echo -e "${ROJO_BRILLANTE}PROC4ME no instala nada automáticamente.${RESET}"
}

# ==============================================================================
# --- PUNTO DE ENTRADA ---
# ==============================================================================

if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    case "$1" in
        --logo-header)
            # Uso interno: FZF lo invoca cada 5 s para refrescar la cabecera.
            detectar_sistema
            logo_texto
            exit 0
            ;;
        --preview-educativo)
            # Uso interno: panel de explicación de una línea seleccionada.
            detectar_sistema
            preview_educativo "$2" "${@:3}"
            exit 0
            ;;
        --preview-puerto)
            # Uso interno: explicación de puerto + detalle del proceso.
            detectar_sistema
            preview_puerto "$2"
            exit 0
            ;;
        --preview-informe)
            # Uso interno: vista previa de un informe guardado.
            preview_informe "$2"
            exit 0
            ;;
        --pid)
            verificar_root
            detalle_pid "$2"
            exit $?
            ;;
        --help|-h)
            detectar_sistema
            mostrar_ayuda_cli
            exit 0
            ;;
        --version|-v)
            echo "PROC4ME v$V"
            exit 0
            ;;
    esac

    detectar_sistema
    verificar_root
    comprobar_dependencias
    preparar_directorios

    case "$1" in
        --quick)
            escaneo_rapido "no"
            ;;
        --full)
            auditoria_completa "no"
            ;;
        "")
            proc4me_main_menu
            ;;
        *)
            echo -e "${ROJO}Opción no válida: $1${RESET}"
            echo ""
            mostrar_ayuda_cli
            exit 1
            ;;
    esac
fi
