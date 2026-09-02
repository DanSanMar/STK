<div align="center">

<!-- BANNER PRINCIPAL -->
<img width="500" height="300" alt="STK Banner" src="https://github.com/DanSanMar/STK/blob/main/img/Pasted%20Image.png" />

<!-- ETIQUETAS ESENCIALES -->
![Version](https://img.shields.io/badge/versión-5.9.4-blue?style=flat-square&logo=github)
![Estado](https://img.shields.io/badge/estado-En%20Desarrollo-yellow?style=flat-square&logo=github)
![Linux](https://img.shields.io/badge/plataforma-Linux-success?style=flat-square&logo=linux)
![Bash](https://img.shields.io/badge/bash-4.0+-brightgreen?style=flat-square&logo=gnu-bash)
![Licencia](https://img.shields.io/badge/licencia-MIT-orange?style=flat-square&logo=opensourceinitiative)

![GitHub stars](https://img.shields.io/github/stars/DanSanMar/System-Tool-Kit?style=flat-square&logo=github)
![GitHub last commit](https://img.shields.io/github/last-commit/DanSanMar/System-Tool-Kit?style=flat-square&logo=github)

# 🛠️ STK - System Tool Kit (v5.9.7) casi tenemos la 6...

</div>

**System Tool Kit (STK)** es una solución integral de administración y mantenimiento para sistemas Linux (probada en Debian, Ubuntu, Kali, Arch Linux, Fedora, openSUSE y entornos WSL2). Diseñada para ofrecer la máxima flexibilidad, permite la gestión rápida del sistema mediante **banderas por línea de comandos (CLI flags),** mediante una interfaz gráfica de terminal interactiva potenciada por **FZF** o con tareas programadas con Cron.

## 🚀 Características Principales

* **Abstracción de Paquetes:** Motor de detección inteligente que unifica la sintaxis de `apt`, `dnf`, `pacman` y `zypper`.
* **Interfaz Dinámica:** Menús interactivos potenciados por `fzf` con previsualizaciones en tiempo real.
* **Monitor de Rendimiento:** Tablero visual en tiempo real con barras de estado para **CPU**, **RAM** y **Disco**.
* **Gestión de Backups Pro:** Sistema de copias de seguridad con verificación de espacio, integridad **SHA256** y rotación automática.
* **Seguridad y Auditoría:** Registro de actividad (Logs) persistente y comprobación estricta de privilegios.
* **Funciones de la v.5.8.1:** Se añade una opción para restaurar los Backups y una pequeña Auditoria de Seguridad. 
* **Funciones de la v.5.9.1:** Se añade un Modo Auto al menú principal, una forma directa de actualizar, limpiar, auditar la seguridad y revisar los servicios fallidos. 
* **Nuevas funciones de la v.5.9.4:** Se añade una opción de gestión de Firewall con UFW dentro del menú de Auditoria de Seguridad.
* **Nuevas funciones de la v.5.9.5:** Se añade menú de gestión de tareas programadas con Cron.
* **Nuevas funciones de la v.5.9.7:** Se añaden flags para la utilización directa de las funciones más habituales y una ayuda para recordarlas.
---

## 🏗️ Arquitectura y Robustez Técnica

### 1. Motor de Detección de Distribuciones
El script lee las variables de `/etc/os-release` con lógica de caída escalonada (*fallback*) para garantizar compatibilidad completa en distros basadas en Debian, Arch, RedHat y SUSE.
* **Sistemas Compatibles:** Debian, Ubuntu, Linux Mint, Kali Linux, Fedora, RHEL, CentOS, Rocky Linux, Arch Linux, Manjaro, openSUSE y entornos integrados bajo **WSL2**.

### 2. Gestión Inteligente de Dependencias y Entornos
* **Verificación de Herramientas:** Comprueba automáticamente la disponibilidad de las 13 utilidades esenciales del sistema (`fzf`, `xsltproc`, `host`, `tput`, `free`, `curl`, `wget`, `tar`, `hostname`, `jq`, `rsync`, `crontab`).
* **Sintaxis y Compatibilidad JS:** Detecta dinámicamente el motor de JavaScript disponible en la máquina (`js`, `js128`, `js115`, `qjs`, `gjs`, `node`, `nodejs`) y genera un enlace simbólico de compatibilidad en `/usr/local/bin/js` cuando es necesario.
* **Resolución Automática:** Ofrece la instalación guiada de herramientas faltantes adaptándose al gestor de paquetes de la distribución detectada.

### 3. Optimización de Rendimiento
* **Mínimo Overhead:** Basado en herramientas nativas de administración del sistema (`awk`, `sed`, `grep`, `du`, `jq`).
* **Refresco Visual Eficiente:** Uso de `tput` y secuencias de escape ANSI en el monitor de rendimiento (intervalos de 5 segundos) para actualizar el tablero en pantalla sin parpadeos ni consumo innecesario de procesador.
---

## 🛡️ Medidas de Seguridad y Fiabilidad

* **Control de Privilegios:** Verificación obligatoria de `EUID 0` (`root`) al iniciar el script para evitar fallos de ejecución a mitad de tareas del sistema.
* **Gestión de Señales (Traps):** Captura de interrupciones `SIGINT` (Ctrl+C) y `SIGTERM` para garantizar una salida limpia, restaurando las propiedades del terminal y finalizando los procesos en segundo plano (*spinners*).
* **Logs y Auditoría del Sistema:**
  * **Bitácora Principal:** Almacenada en `/var/log/stk_mantenimiento.log` con permisos restringidos `0640`.
  * **Registro de Tareas Programadas:** Salida del módulo cron en `/var/log/stk_cron.log`.
  * **Rotación Automática:** Truncado e inicio limpio del log central al superar los **500 KB** de tamaño.
* **Fiabilidad en Backups (Local y COPY4ME):**
  * **Verificación Espacial:** Cálculo del tamaño del directorio origen frente al espacio en disco disponible antes de iniciar la copia o sincronización.
  * **Protección de Archivos:** Asignación de permisos `0600` en las copias comprimidas (`.tar.gz`) para restringir lecturas no autorizadas.
  * **Integridad Garantizada:** Generación y verificación de suma de comprobación **SHA256** para los respaldos empaquetados.
  * **Rotación y Perfiles:** Límite máximo de 5 ficheros por subcarpeta de respaldo en `/var/backups/stk_backups/` y almacenamiento seguro de la configuración de perfiles en `config.json`.
---

## 📋 Módulos del Sistema

### 📊 Monitorización y Auditoría
* **Hardware y Carga:** Monitor en tiempo real con refresco de 5s para uso de CPU, memoria RAM y almacenamiento con **barras de estado en color**.
* **Diagnóstico de Red:** Lectura de IP local, interfaces activas e IP pública mediante API externa con consulta DNS de contingencia.
* **Seguridad y Firewall:** Control del cortafuegos (`ufw`), verificación de permisos SUID, cuentas con UID 0, firmas y análisis de accesos no autorizados.

<div align="center">
<img width="500" height="300" alt="Monitorización STK" src="https://github.com/user-attachments/assets/2725cd00-bcd5-4e7a-b3db-23a2a7a6da94" />
</div>

### 📦 Gestión de Software
* **Sincronización Multidistro:** Actualización centralizada para `apt`, `pacman`, `dnf`, `zypper`, además de gestores secundarios como `flatpak` y `snap`.
* **Instalación Segura:** Instalación y purga completa de aplicaciones con validación estricta de entradas para prevenir inyecciones de comandos.

### ⚙️ Administración y Servicios
* **Gestión de Usuarios:** Creación, edición y eliminación interactiva mediante `fzf` de usuarios estándar (UID >= 1000) con asignación dinámica de grupos administrativos (`sudo`/`wheel`).
* **Control de Systemd:** Explorador visual de servicios del sistema (activos, fallidos o búsqueda manual) con acciones para iniciar, detener, reiniciar y revisar la bitácora con `journalctl`.

<div align="center">
  <img width="500" height="300" alt="Administración STK" src="https://github.com/user-attachments/assets/c6d49f8c-6827-4d8f-b43b-417d2200395e" />
</div>

### 🧹 Mantenimiento, Tareas y Copias de Seguridad
* **Súper Limpieza:** Liberación profunda de espacio en disco purgando paquetes huérfanos, cachés, papelera del sistema y limitando retención de logs a 3 días.
* **Motor COPY4ME & Backups:** 
  * **Empaquetado Local:** Respaldos compresión `.tar.gz` de directorios clave (`/etc`, `/var/www`, `/home`) o personalizados, con cálculo de hash **SHA256** y rotación de un máximo de 5 ficheros.
  * **Sincronización Avanzada:** Sincronización incremental, espejo o bidireccional mediante `rsync`, con perfiles persistentes en `/var/backups/stk_backups/config.json`.
* **Programador (Cron):** Integración con `stk_cron.sh` para la automatización y consulta de tareas programadas en el sistema.


<div align="center">
   <img width="500" height="300" alt="image" src="https://github.com/user-attachments/assets/723ff72c-16ce-4cc6-8bf8-7ffa3b35522c" />
   </div>

---

## 🛠️ Instalación y Uso

1.  **Clona el proyecto:**
    ```bash
    git clone [https://github.com/DanSanMar/System-Tool-Kit.git](https://github.com/DanSanMar/System-Tool-Kit.git)
    cd System-Tool-Kit
    ```
2.  **Ejecuta el script con privilegios:**
    ```bash
    sudo ./stk2.sh
    ```

---

## 📝 Registro de Cambios

### 📝 v5.9.7 (Actual)
* **Nuevo:** Soporte para ejecución directa por línea de comandos mediante banderas CLI (`-m`, `-a`, `-u`, `-c`, `-l`, `-b`, `-A`, `-v`, `-h`).
* **Mejora:** Sistema interactivo de ayuda (`--help`) para recordar el uso de las flags desde la terminal.
* **Optimización:** Resolución dinámica y creación de enlace simbólico de compatibilidad para el intérprete de JavaScript (`js`).

### 📝 v5.9.4
* **Nuevo:** Integración completa de UFW Firewall Manager dentro del menú de auditoría.
* **Mejora:** Menús optimizados para la gestión de reglas y auditoría de tráfico en tiempo real.
* **Seguridad:** Detección de escaneos de puertos y bloqueos ante intentos de fuerza bruta.

### 📝 v5.9.1
* **Nuevo:** Integración del ejecutor rápido `modo_auto` para mantenimiento automatizado y auditoría integral del sistema.
* **Mejora:** Detección inteligente de gestores de paquetes principales (`apt`, `pacman`, `dnf`, `zypper`) y secundarios (`flatpak`, `snap`).
* **Optimización:** Limpieza profunda con cálculo dinámico de espacio en disco recuperado y gestión de `journalctl`.
* **Seguridad:** Evaluación de seguridad con sistema de puntuación porcentual y verificación del estado de servicios en `systemd`.

### 📝 v5.8.5
* **Nuevo:** Función de creación de usuarios con gestión de permisos y modificación de perfiles.
* **Mejora:** Menús `fzf` unificados para los dos sistemas de backups (Local y COPY4ME).
* **Optimización:** Mejoras visuales y mayor robustez para la detección de distros.
* **Seguridad:** Implementación de auditoría de seguridad del sistema extendida.

### 📝 v5.7
* **Nuevo:** Función de borrado manual de backups directamente desde la interfaz.
* **Mejora:** Menús `fzf` con previsualización de información del sistema en tiempo real.
* **Optimización:** Refactorización del código de detección de IP pública para evitar bloqueos por DNS.
* **Seguridad:** Implementación de rotación automática de logs por tamaño.

---
**Autor:** [DanSanMar](https://github.com/DanSanMar)  
**Descripción:** Herramienta integral de mantenimiento para Linux.

> **Nota:** Este script se distribuye "tal cual", con el objetivo de facilitar la administración, pero siempre se recomienda revisar las rutas de backup personalizadas antes de procesos masivos.
