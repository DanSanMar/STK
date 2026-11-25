# INVENTARIO DE STK (estado actual)

**Archivo principal:** `/home/arch/STK/stk.sh`
**Versión:** `V="7.0.0"` · marcador visual del nuevo ciclo: `System Tool Kit` en el marco del menú
**Fuente de verdad histórica:** `stk2.sh` (intacto, `sha256 0f58edd5f53835fb201f6b8fcbfb6c4c86b697bda3a030499beea65d70e285d7`)
**Funciones totales:** 88 = 70 en `stk.sh` + 13 en `stk_ui_lib.sh` + 5 en `stk_menu_lib.sh`
**Líneas:** `stk.sh` 3266 · `stk_ui_lib.sh` 184 · `stk_menu_lib.sh` 320

> Los números de línea son orientativos (corresponden al estado tras el commit `fd630e7`).

---

## 1. Archivos y responsabilidades

| Archivo | Rol | Root |
|---|---|---|
| `stk.sh` | Orquestador: configuración, utilidades, módulos de acción, arranque y flags CLI | Sí |
| `stk_ui_lib.sh` | Capa de UI: colores, logo, selector `stk_fzf`, mensajes y pausas | No (se cargan desde `stk.sh`) |
| `stk_menu_lib.sh` | Los cinco submenús, extraídos de `menu()` | No (ídem) |
| `stk_header.sh` | Compatibilidad de terminal/TTY/fzf, `stk_limpiar`, `stk_fzf_ejecutar`, `stk_avisar`, `stk_diagnostico` | No |
| `stk_auto_lib.sh` | Modo automático: lock, preflight, snapshot, actualización, limpieza, auditoría, servicios | No |
| `verificar_stk.sh` | Comprobación estática sin root: sintaxis, paridad, bloques, estilo e integridad de `stk2.sh` | No |
| `stk2.sh` | Versión original, **nunca se modifica** | Sí |
| `stk_cron.sh`, `stop4me.sh`, `dash4me.sh` | Herramientas independientes (aún con estilo propio) | Según cada una |

`stk.sh` carga las librerías **después** de `stk_header.sh` para que sus definiciones de
`pintar()` y `stk_fzf_menu()` sobreescriban las del header.

---

## 2. Contrato de UI (instaurado en el Bloque 2)

- **Colores:** solo variables del Bloque 1; imprimir con `pintar "$COLOR" "mensaje"`.
- **Separador:** línea de `━` en `AMARILLO` + `RESET`.
- **Logo:** `mostrar_logo()` al entrar en un módulo; `logo_texto()` dentro de `fzf`.
- **Menús:** opciones `N. Texto`; la última siempre `↩ Volver`; parseo con `${seleccion%%.*}`.
- **Selector:** único `stk_fzf` con tres estilos: `marco` (menú principal),
  `preview` (submenús) y `simple` (listas). `fzf_estilo()` y `stk_fzf_menu()` son wrappers.
- **Cancelación:** `$? != 0`, selección vacía o “Volver” → volver al nivel anterior.
  `exit` solo en `-m`/`-v` y en `salir()`.
- **Pausas:** `stk_volver_menu()`, sin `read -p` suelto en código nuevo.
- **Arranque de módulo:** `stk_iniciar_modulo()` (convención documentada; hoy se aplica
  patrón `trap` + `stk_limpiar` + `mostrar_logo` en los módulos existentes).
- **Bitácora:** `registrar_log` con `LOG_INFO` / `LOG_WARN` / `LOG_ERR` para toda acción
  que modifique el sistema.
- **Estilo defensivo:** sin `set -e` ni `set -u`; comprobaciones explícitas y fallbacks.

---

## 3. Estructura de `stk.sh`

| Bloque | Línea | Contenido |
|---|---|---|
| 1. CONFIGURACIÓN Y CONSTANTES | 4 | Versión, colores, `FZF_COLORES`, logs, `SCRIPT_DIR`, carga de librerías |
| 2. CAPA DE UI & HELPERS | 73 | Métricas visuales y dashboard rápido (el resto de UI está en `stk_ui_lib.sh`) |
| 3. CAPA DE UTILIDADES (CORE) | 156 | Logs, dependencias, validaciones, convertidores de red |
| 4. MÓDULOS DE ACCIÓN | 645 | Monitorización, seguridad, actualización, usuarios, servicios, backups |
| 5. ORQUESTACIÓN | 2878 | Señales, ejecutores externos, `menu()` |
| 5.4 Arranque | 3026 | Root check, bitácora, distro/`Package`, OSTree, dependencias, constantes, flags |

### Funciones en `stk.sh` (70)

- **Bloque 2 (3):** `_metrica_color`, `uptime_legible`, `mostrar_dashboard_rapido`.
- **Bloque 3 (16):** `registrar_log`, `rotar_logs`, `ver_logs`, `ver_logs_actualizaciones`,
  `get_package_name`, `crear_enlace_js`, `install_tools`, `mostrar_instrucciones`,
  `check_dependencies`, `comprobar_firewall`, `comprobar_salida_internet`,
  `actualizar_colores_logo`, `formato_bytes`, `tipo_interfaz`, `prioridad_interfaz`, `campo_red`.
- **Bloque 4 (43):** `temperatura_maxima`, `carga_sistema`, `memoria_ram`, `uso_disco_raiz`,
  `reverse_shell_alerta`, `mostrar_dashboard_seguridad`, `_cache_vigente`, `_cache_guardar`,
  `_cache_seguridad_refrescar`, `dashboard_cacheado`, `stk_limpieza_manual_menu`,
  `mostrar_info_red`, `wifi_detalle`, `mostrar_interfaz_red`, `auto_checklist`, `modo_auto`,
  `auditoria_seguridad`, `Actualizar_sistema`, `instalar_programa`, `desinstalar_programa`,
  `obtener_grupo_sudo`, `modificar_permisos_usuario`, `gestionar_usuarios`, `listar_usuarios`,
  `pedir_nombre`, `gestionar_servicios`, `menu_operaciones_servicio`, `init_copy4me_config`,
  `obtener_perfiles_json`, `guardar_perfil_json`, `eliminar_perfil_json`, `verificar_espacio`,
  `rotar_backups`, `obtener_puntos_montaje_externos`, `fzf_seleccionar_directorio`,
  `ver_backups_existentes`, `eliminar_backups`, `restaurar_backup`, `autocopy_atomatic`,
  `ejecutar_sincronizacion_bash`, `copy4me_tui_main`, `hacer_backup`, `ejecutar_dash4me`.
- **Bloque 5 (8):** `salir`, `ejecutar_stop4me`, `ejecutar_proc4me`, `ejecutar_jobs4me`,
  `ejecutar_hard4me`, `ejecutar_install4me`, `ejecutar_localscan4me`, `menu`.

### Funciones en `stk_ui_lib.sh` (13)

`pintar`, `stk_mostrar_error`, `stk_mostrar_info`, `stk_mostrar_exito`, `stk_volver_menu`,
`logo_barra`, `logo_texto`, `mostrar_logo`, `stk_fzf`, `fzf_estilo`, `stk_fzf_menu`,
`mostrar_spinner`, `mostrar_ayuda`.

### Funciones en `stk_menu_lib.sh` (5)

`menu_monitoreo`, `menu_seguridad`, `menu_software`, `menu_administracion`, `menu_mantenimiento`.
`menu()` en `stk.sh` es el despacho (53 líneas).

---

## 4. Orden de arranque de `stk.sh`

1. Configuración y carga de `stk_header.sh`, `stk_ui_lib.sh` y `stk_menu_lib.sh`.
2. Directorio temporal privado (`stk_elegir_tmp`) y `stk_caps_init` (sondeo TTY/fzf/curl).
3. Comprobación de `EUID 0` (salida si no es root).
4. Inicialización/permisos de `/var/log/stk_mantenimiento.log` (`0640`).
5. Detección de distro y `Package` (`apt`/`dnf`/`pacman`/`zypper`) y de OSTree (`IMMUTABLE`).
6. `trap salir SIGINT SIGTERM`.
7. Dependencias (13 herramientas, ping a `8.8.8.8`) y oferta de instalación.
8. Constantes del logo/dashboard y del modo automático; `source stk_auto_lib.sh`.
9. `CONFIG_JSON` / `DESTINO_DEF` y `rotar_logs "silencioso"`.
10. `case "$1"`; sin argumentos, `menu`.

> `-h` y `-v` no son ligeros: pasan por los pasos 3–9 antes de mostrar ayuda/versión.

---

## 5. Rutas de estado

| Ruta | Contenido | Permisos |
|---|---|---|
| `/var/log/stk_mantenimiento.log` | Bitácora principal (STK y STOP4ME) | `0640` |
| `/var/log/stk_cron.log` | Ejecuciones del wrapper de cron | `0640` |
| `/var/log/stk_cron_resumen.log` | Resúmenes por ejecución | `0640` |
| `/etc/stk/cron/tasks.json` | Tareas programadas | `0600` |
| `/usr/local/bin/stk_auto_wrapper.sh` | Wrapper generado por `stk_cron.sh` | ejecutable |
| `/var/backups/stk_backups/` | Backups `.tar.gz` y `config.json` | dir `0700`, JSON `0600` |

---

## 6. Verificación

```bash
bash -n stk.sh stk_ui_lib.sh stk_menu_lib.sh verificar_stk.sh
./verificar_stk.sh
```

`verificar_stk.sh` comprueba: sintaxis de los cuatro archivos, hash de `stk2.sh`,
78/78 funciones originales presentes, sin duplicados, 5 bloques + `5.4`, sin huecos
de 3+ líneas vacías, sin comentarios huérfanos, `↩ Volver` uniforme, sin llamadas
directas a `fzf`, sin `set -e`/`set -u` y espacio final en cero.

**Prueba de humo segura:** `bash stk.sh -v` como usuario normal (el check de root
termina antes de modificar el sistema).

---

## 7. Gotchas

- Los scripts modifican el sistema real: no ejecutarlos completos como root desde el agente.
- `stk_header.sh` también define `pintar()` y `stk_fzf_menu()`; el orden de carga importa.
- El wrapper de cron es un heredoc gigante dentro de `crear_wrapper_cron` (`stk_cron.sh`).
- En OSTree, `install_tools` usa `rpm-ostree install --idempotent --allow-inactive --apply-live`;
  si falla la aplicación en vivo, marca `REINICIO_REQUERIDO=true`.
- `super_limpieza` en OSTree solo ejecuta `rpm-ostree cleanup -m` (nunca `-p`).
- `stop4me.sh` puede instalar UFW; en Fedora, `firewalld` puede entrar en conflicto.
- `dash4me.sh` arranca el monitor al cargarse; no tiene flags ni modo de una pasada.
- `stk.sh` hace `ping -c 1 8.8.8.8` al arrancar (puede añadir latencia sin Internet).
- README: título y badge en `v7.0.0`; enlaza `DanSanMar/System-Tool-Kit` pero el remoto es `DanSanMar/STK`.

---

## 8. Historial de la refactorización

| Commit | Descripción |
|---|---|
| `01d9907` | Reorganizar `stk.sh` en bloques y unificar estilo de menús |
| `47f0234` | Extraer UI y submenús a librerías compartidas |
| `fd630e7` | Quitar espacios finales heredados de `stk.sh` y `stk_ui_lib.sh` |

`inventario_stk2.sh.md` se conserva como referencia histórica de la fuente original.
