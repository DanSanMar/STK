# INVENTARIO CORREGIDO DE stk2.sh

**Archivo:** `/home/arch/STK/stk2.sh`  
**Versión:** 7.0.0  
**Total de líneas:** 3768  
**Funciones definidas en stk2.sh:** 78  
**Lenguaje:** Bash 4+  
**Licencia:** MIT  

---

## 📋 ESTRUCTURA GENERAL

El script está organizado en **5 submenús principales**:
1. **Hardware** (HARD4ME) - Análisis de disco y rendimiento
2. **Seguridad** - Procesos, auditoría, firewall UFW
3. **Software** - Actualización, instalación, gestión de paquetes
4. **Administración** - Usuarios, servicios, backups
5. **Mantenimiento** - Limpieza, logs, rotación

---

## 🎯 FUNCIONES PRINCIPALES DEL MENÚ (`menu`)

### Submenú 1: HARDWARE (HARD4ME)
| Función | Descripción |
|---------|-------------|
| `ejecutar_hard4me` | Análisis completo del disco y rendimiento |

### Submenú 2: SEGURIDAD
| Función | Descripción |
|---------|-------------|
| `ejecutar_proc4me` | Investigador de procesos y amenazas (PROC4ME) |
| `auditoria_seguridad` | Auditoría completa de seguridad del sistema |
| `ejecutar_stop4me` | Control del cortafuegos UFW (STOP4ME) |

### Submenú 3: SOFTWARE
| Función | Descripción |
|---------|-------------|
| `Actualizar_sistema` | Actualización automática del sistema |
| `ejecutar_install4me` | Instalador por categorías de aplicaciones |
| `instalar_programa` | Instalar/actualizar un programa por nombre |
| `desinstalar_programa` | Eliminar un programa existente |

### Submenú 4: ADMINISTRACIÓN
| Función | Descripción |
|---------|-------------|
| `gestionar_usuarios` | Gestión de cuentas (crear, listar, eliminar, modificar permisos) |
| `listar_usuarios` | Mostrar información detallada de usuarios humanos |
| `gestionar_servicios` | Panel de control de servicios systemd |
| `menu_operaciones_servicio` | Operaciones sobre un servicio específico |
| `hacer_backup` | Gestión integral de copias de seguridad |

### Submenú 5: MANTENIMIENTO
| Función | Descripción |
|---------|-------------|
| `stk_limpieza` (completa/auto/manual) | Limpieza de sistema |
| `stk_limpieza_manual_menu` | Menú interactivo de limpieza manual |
| `ver_logs` | Visualizar bitácora principal |
| `ver_logs_actualizaciones` | Ver logs filtrados de actualizaciones |
| `rotar_logs` | Rotación del archivo de bitácora |

### Modo Automático
| Función | Descripción |
|---------|-------------|
| `modo_auto` | Ejecución integral de mantenimiento (actualización + limpieza + auditoría + servicios) |

---

## 📚 FUNCIONES DE LIBRERÍAS (NO DEFINIDAS EN stk2.sh)

Estas funciones se cargan desde archivos externos y **no están definidas en stk2.sh**:

### De `stk_header.sh` (cargado con `source /home/arch/STK/stk_header.sh`)
| Función | Línea aproximada | Descripción |
|---------|------------------|-------------|
| `pintar()` | ~1 | Imprimir texto con color ANSI |
| `stk_detectar_columnas()` | ~5 | Detectar ancho de terminal en columnas |
| `stk_detectar_filas()` | ~10 | Detectar altura de terminal en filas |
| `stk_limpiar_ansi()` | ~15 | Limpiar secuencias ANSI del buffer |
| `stk_ancho_texto()` | ~20 | Calcular ancho de una cadena |
| `stk_recortar()` | ~25 | Recortar texto a N caracteres |
| `stk_repetir()` | ~30 | Repetir texto N veces |
| `stk_version_ge()` | ~35 | Comprobar versión >= (comparador) |
| `stk_avisar()` | 156 | Mostrar aviso/advertencia al usuario |
| `stk_resumen_avisos()` | 175 | Resumir avisos acumulados |
| `stk_term_valido()` | ~40 | Comprobar si el terminal es válido |
| `stk_term_sanitizar()` | ~45 | Sanitar nombre de terminal |
| `stk_elegir_tmp()` | ~50 | Elegir directorio temporal seguro |
| `stk_elegir_log()` | ~55 | Elegir archivo de log según nivel |
| `stk_caps_init()` | 251 | Inicializar capacidades de diagnóstico (GPU, etc.) |
| `stk_curl_soporta_unix()` | ~60 | Comprobar si curl soporta URLs unix:// |
| `stk_limpiar()` | 304 | Limpiar pantalla (clear) |
| `stk_alt_screen_on()` | ~65 | Activar alt buffer del terminal |
| `stk_alt_screen_off()` | ~70 | Desactivar alt buffer del terminal |
| `stk_cursor_off()` | ~75 | Ocultar cursor del terminal |
| `stk_fzf_ejecutar()` | 348 | Helper para ejecutar comandos desde fzf |
| `stk_diagnostico()` | 423 | Ejecutar diagnóstico completo del sistema |

### De `stk_auto_lib.sh` (cargado en modo automático)
| Función | Descripción |
|---------|-------------|
| `stk_detectar_gestor()` | Detectar gestor de paquetes del sistema |
| `stk_timeout()` | Configurar timeout para operaciones |
| `stk_lock_adquirir()` | Adquirir lock para evitar ejecuciones simultáneas |
| `stk_lock_liberar()` | Liberar lock del modo automático |
| `stk_gestor_ocupado()` | Comprobar si el gestor de paquetes está ocupado |
| `stk_preflight()` | Comprobación pre-ejecución (red, espacio, gestor) |
| `stk_snapshot()` | Crear punto de recuperación previo a actualización |
| `stk_extraer_incidencias()` | Extraer incidencias del log de actualización |
| `stk_actualizar()` | Ejecutar actualización del sistema con timeout y reparaciones |
| `stk_limpieza()` | Limpieza automática o completa del sistema |
| `stk_auditoria()` | Ejecutar auditoría de seguridad en modo automático |
| `stk_servicios()` | Analizar servicios fallidos y estado de reinicio |

---

## 🔧 FUNCIONES AUXILIARES DE UTILIDAD (DEFINIDAS EN stk2.sh)

### Gestión de Terminal y UI
| Función | Descripción |
|---------|-------------|
| `mostrar_logo()` | Mostrar arte ASCII del logo |
| `pedir_nombre()` | Pedir nombre de usuario con validación |
| `fzf_estilo()` | Ejecutar fzf con estilo personalizado |
| `mostrar_spinner()` | Mostrar spinner de carga |

### Gestión de Usuarios y Permisos
| Función | Descripción |
|---------|-------------|
| `obtener_grupo_sudo()` | Obtener grupo administrativo (sudo/wheel) |
| `modificar_permisos_usuario()` | Cambiar rol de usuario (estándar/admin) |

### Información de Red
| Función | Descripción |
|---------|-------------|
| `formato_bytes()` | Formatear bytes a KB/MB/GB |
| `tipo_interfaz()` | Identificar tipo de interfaz (Ethernet/Wi-Fi/VPN/Virtual) |
| `wifi_detalle()` | Obtener detalles Wi-Fi (SSID, señal, frecuencia) |
| `mostrar_interfaz_red()` | Mostrar información detallada de una interfaz |
| `prioridad_interfaz()` | Asignar prioridad a interfaces para ordenamiento |
| `campo_red()` | Helper para imprimir campos de red con formato |
| `mostrar_info_red()` | Información completa del sistema de red |

### Gestión de Backups (COPY4ME)
| Función | Descripción |
|---------|-------------|
| `init_copy4me_config()` | Inicializar configuración JSON de perfiles |
| `obtener_perfiles_json()` | Listar perfiles guardados en config.json |
| `guardar_perfil_json()` | Guardar nuevo perfil de sincronización |
| `eliminar_perfil_json()` | Eliminar perfil guardado |
| `verificar_espacio()` | Comprobar espacio disponible antes de backup |
| `rotar_backups()` | Rotación automática de backups (máx 5 por subcarpeta) |
| `obtener_puntos_montaje_externos()` | Detectar unidades USB/mounts externos |
| `ver_backups_existentes()` | Inspeccionar backups existentes (.tar.gz) |
| `eliminar_backups()` | Eliminar backups seleccionados |
| `restaurar_backup()` | Restaurar backup comprimido a ruta original o /tmp |
| `autocopy_atomatic()` | Respaldo local automático (.tar.gz) |
| `copy4me_tui_main()` | TUI engine para COPY4ME (rsync con perfiles) |
| `ejecutar_sincronizacion_bash()` | Ejecutar rsync con modo incremental/espejo/bidireccional |

### Gestión de Logs y Mantenimiento
| Función | Descripción |
|---------|-------------|
| `registrar_log()` | Registrar entrada en bitácora (LOG_INFO/LOG_WARN/LOG_ERR) |
| `rotar_logs()` | Rotación del log principal cuando supera 500 KB |

### Gestión de Servicios Systemd
| Función | Descripción |
|---------|-------------|
| `menu_operaciones_servicio()` | Reiniciar, detener, logs, estado, enable/disable servicio |

---

## 🛡️ FUNCIONES DE SEGURIDAD Y AUDITORÍA (DEFINIDAS EN stk2.sh)

| Función | Descripción |
|---------|-------------|
| `auditoria_seguridad()` | Auditoría completa de seguridad (usuarios, red, SUID, firewall, MAC) |
| `reverse_shell_alerta()` | Detectar posibles reverse shells por conexiones sospechosas |
| `comprobar_firewall()` | Verificar estado del cortafuegos (UFW/firewalld/nftables) |

**Nota:** Las funciones `sysctl_check` y `super_limpieza` **NO EXISTEN** en el repositorio. Han sido eliminadas del inventario.

---

## 🔄 FUNCIONES DEL MODO AUTOMÁTICO (`stk_auto_lib.sh`)

Estas funciones se cargan desde `/home/arch/STK/stk_auto_lib.sh`:

| Función | Descripción |
|---------|-------------|
| `stk_lock_adquirir()` | Adquirir lock para evitar ejecuciones simultáneas |
| `stk_lock_liberar()` | Liberar lock del modo automático |
| `stk_preflight()` | Comprobación pre-ejecución (red, espacio, gestor) |
| `stk_snapshot()` | Crear punto de recuperación previo a actualización |
| `stk_actualizar()` | Ejecutar actualización del sistema con timeout y reparaciones |
| `stk_auditoria()` | Ejecutar auditoría de seguridad en modo automático |
| `stk_servicios()` | Analizar servicios fallidos y estado de reinicio |
| `stk_limpieza()` | Limpieza automática o completa del sistema |

---

## 📦 GESTORES DE PAQUETES SOPORTADOS

El script detecta automáticamente el gestor de paquetes del sistema:

| Gestor | Variable | Comandos principales |
|--------|----------|---------------------|
| **APT** (Debian/Ubuntu/Kali) | `apt` | `apt-get update`, `apt-get upgrade`, `adduser`, `deluser` |
| **DNF** (Fedora/COSMIC Atomic) | `dnf` | `dnf upgrade`, `dnf autoremove` |
| **PACMAN** (Arch Linux) | `pacman` | `pacman -Syu`, `pacman -S`, `pacman -Rs` |
| **ZYPPER** (openSUSE) | `zypper` | `zypper refresh`, `zypper update` |
| **RPM-OSTREE** (Fedora Silverblue/Kinoite) | `rpm-ostree` | `rpm-ostree upgrade`, `rpm-ostree install/uninstall` |

---

## 📊 FUNCIONES DE DIAGNÓSTICO (DEFINIDAS EN stk2.sh)

| Función | Descripción |
|---------|-------------|
| `stk_caps_init()` | Inicializar capacidades de diagnóstico (GPU, etc.) - **mover a stk_header.sh** |
| `stk_diagnostico()` | Ejecutar diagnóstico completo del sistema - **mover a stk_header.sh** |

---

## 🎨 FUNCIONES DE INFORMACIÓN DE RED DETALLADA (DEFINIDAS EN stk2.sh)

| Función | Descripción |
|---------|-------------|
| `comprobar_salida_internet()` | Verificar conexión a internet y obtener latencia |
| `SALIDA_RED` | Variable global con información de la salida (ej: "Google 12ms") |

---

## 📝 FUNCIONES DE REGISTRO Y LOGGING (DEFINIDAS EN stk2.sh)

| Función | Descripción |
|---------|-------------|
| `registrar_log()` | Registrar mensaje en `/var/log/stk_mantenimiento.log` con niveles INFO/WARN/ERR |
| `rotar_logs()` | Rotar log cuando supera 500 KB (guarda .1, .2, etc.) |

---

## 🧩 FUNCIONES DE UTILIDAD Y HELPERS (DEFINIDAS EN stk2.sh)

| Función | Descripción |
|---------|-------------|
| `comprobar_salida_internet()` | Verificar conexión a internet y obtener latencia |
| `SALIDA_RED` | Variable global con información de la salida (ej: "Google 12ms") |

---

## 📁 RUTAS DE ESTADO Y CONFIGURACIÓN

| Ruta | Contenido | Permisos |
|------|-----------|----------|
| `/var/log/stk_mantenimiento.log` | Bitácora principal | `0640` |
| `/var/log/stk_cron.log` | Logs del wrapper de cron | `0640` |
| `/var/log/stk_cron_resumen.log` | Resúmenes por ejecución | `0640` |
| `/etc/stk/cron/tasks.json` | Tareas programadas y estado | `0600` |
| `/usr/local/bin/stk_auto_wrapper.sh` | Wrapper generado por stk_cron.sh | ejecutable |
| `/var/backups/stk_backups/` | Backups locales .tar.gz | dir `0700` |
| `/var/backups/stk_backups/config.json` | Configuración de perfiles COPY4ME | JSON `0600` |

---

## 🚩 VARIABLES GLOBALES IMPORTANTES

| Variable | Descripción | Valor por defecto |
|----------|-------------|-------------------|
| `V` | Versión del script | `7.0.0` |
| `Package` | Gestor de paquetes detectado | `apt`, `dnf`, `pacman`, `zypper` |
| `IMMUTABLE` | Sistema inmutable (OSTree) | `false`/`true` |
| `LOG_FILE` | Ruta del log principal | `/var/log/stk_mantenimiento.log` |
| `SCRIPT_DIR` | Directorio del script | Detectado automáticamente |
| `DESTINO_DEF` | Destino por defecto de backups | `/var/backups/stk_backups` |
| `CONFIG_JSON` | Archivo de configuración JSON | `/var/backups/stk_backups/config.json` |

---

## ⚠️ GOTCHAS Y PUNTOS DE ATENCIÓN

1. **`dash4me.sh` arranca el monitor al cargarse**: No tiene `--help`, flags ni modo de una sola pasada
2. **El wrapper de cron es un heredoc gigante** dentro de `crear_wrapper_cron`
3. **`stk2.sh` hace `ping -c 1 8.8.8.8`** al arrancar (puede añadir latencia en entornos sin salida a Internet)
4. **Dependencia `js`:** Si falta, se instalan enlaces simbólicos en `/usr/local/bin/js` y `/usr/bin/js`
5. **`stop4me.sh` puede instalar UFW** al entrar al menú si no está presente
6. **Rotación de backups:** Máximo 5 `.tar.gz` por subcarpeta; los más antiguos se borran
7. **Los logs son compartidos** entre `stk2.sh` y `stop4me.sh`
8. **`trap`:** `stk2.sh` captura `SIGINT`/`SIGTERM` con `salir`; `dash4me.sh` los usa para restaurar terminal
9. **AGENTS.md está gitignored** en `dash4ia` y `rsync4me` (convención: archivos de agentes no se versionan)

---

## 📜 CONVENCIONES DE CÓDIGO

- **Idioma:** Comentarios, mensajes de UI, logs, README y mensajes de commit **en español**
- **Un archivo por herramienta.** No dividir en módulos, paquetes ni librerías
- **Sin `set -e` / `set -u`.** Estilo defensivo: comprobaciones explícitas, `2>/dev/null`, fallbacks
- **Colores:** Declarados al inicio (`RESET`, `VERDE_BRILLANTE`, `AMARILLO`, `CIAN`, `ROJO`...)
- **UI `fzf`:** Patrón común `mostrar_logo()` + separador `━` + `fzf_estilo`
- **Nombres de funciones:** `snake_case` en español (`gestionar_usuarios`, `ver_logs_actualizaciones`)
- **Paquetes:** Abstracción con variable `Package` y `get_package_name`
- **JSON:** Uso de `jq` y escritura atómica (`mktemp` → `mv` → `chmod 600`)

---

## 🔄 ORDEN DE EJECUCIÓN AL CARGAR `stk2.sh`

1. Comprobación de `EUID 0` (requiere root)
2. Inicialización/permisos de `/var/log/stk_mantenimiento.log`
3. Detección de distro y `Package` (`apt`, `dnf`, `pacman`, `zypper`)
4. Comprobación de las 13 dependencias (y posible oferta de instalación)
5. `rotar_logs "silencioso"`
6. Ejecución del `case "$1"` con los flags; sin argumentos, `menu`

---

## 📦 ARCHIVOS RELACIONADOS

| Archivo | Descripción |
|---------|-------------|
| `stk2.sh` | Script principal (menú + funciones principales) - 78 funciones |
| `stk_header.sh` | Librería de UI y utilidades - cargada con `source` |
| `stk_auto_lib.sh` | Biblioteca del modo automático - funciones de actualización/limpieza |
| `stk_cron.sh` | Gestor de tareas programadas independiente |
| `stop4me.sh` | Módulo de cortafuegos UFW independiente |
| `dash4me.sh` | Monitor de rendimiento en bucle (no requiere root) |

---

## 📝 NOTAS FINALES

- El script **no tiene tests, lint, CI ni lockfiles**
- Verificación de sintaxis: `bash -n script.sh`
- `shellcheck` no está instalado; verificación manual
- Entorno: Arch Linux (`pacman`), usuario `arch`, home `/home/arch`
- El README enlaza al repo como `DanSanMar/System-Tool-Kit`, pero el remoto real es `https://github.com/DanSanMar/STK`

---

## 📊 TABLA DE MAPEO DE FUNCIONES (VALIDACIÓN FASE 1)

Este inventario sirve como tabla de mapeo que valida la Fase 1 del reordenado:

### Funciones en stk2.sh (78 totales, agrupadas en 5 bloques):
- **Bloque 1:** `menu`, `salir`, `case "$1"` - Menú principal y flags
- **Bloque 2:** Funciones de HARDWARE, SEGURIDAD, SOFTWARE
- **Bloque 3:** Funciones de ADMINISTRACIÓN (usuarios, servicios, backups)
- **Bloque 4:** Funciones de MANTENIMIENTO (limpieza, logs, rotación)
- **Bloque 5:** Funciones auxiliares y helpers

### Funciones en stk_header.sh (18 totales):
- UI: `pintar`, `stk_limpiar`, `mostrar_logo`, `fzf_estilo`, `stk_fzf_ejecutar`
- Terminal: `stk_detectar_columnas`, `stk_detectar_filas`, `stk_term_valido`, `stk_term_sanitizar`
- Utilidades: `stk_ancho_texto`, `stk_recortar`, `stk_repetir`, `stk_version_ge`
- Avisos: `stk_avisar`, `stk_resumen_avisos`
- Cursor/Alt screen: `stk_alt_screen_on`, `stk_alt_screen_off`, `stk_cursor_off`
- Log/tmp: `stk_elegir_tmp`, `stk_elegir_log`
- Red: `stk_caps_init`, `stk_diagnostico`

### Funciones en stk_auto_lib.sh (12 totales):
- Lock: `stk_lock_adquirir`, `stk_lock_liberar`
- Preflight/snapshot: `stk_detectar_gestor`, `stk_timeout`, `stk_preflight`, `stk_snapshot`
- Actualización: `stk_gestor_ocupado`, `stk_extraer_incidencias`, `stk_actualizar`
- Limpieza/auditoría/servicios: `stk_limpieza`, `stk_auditoria`, `stk_servicios`

### Funciones inexistentes (eliminadas):
- `sysctl_check` - NO EXISTE
- `super_limpieza` - NO EXISTE

---

*Inventario saneado para validación de la Fase 1 del reordenado.*
