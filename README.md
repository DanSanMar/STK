# 🛠️ STK - System Tool Kit (v5.7)

**System Tool Kit** es una potente herramienta de mantenimiento para sistemas basados en Linux (probada en Debian/Ubuntu/Kali/Fedora y las mismas distros en WSL2). Proporciona una interfaz visual intuitiva gracias a los menús creados con FZF para gestionar el mantenimiento/actualización, monitorización y administración del sistema.

<img width="350" height="200" alt="image" src="https://github.com/user-attachments/assets/3e5bde56-aa01-45b0-b722-b413ab39968a" />


## 🚀 Características Principales

* **Abstracción de Paquetes:** Motor de detección inteligente que unifica la sintaxis de `apt`, `dnf`, `pacman` y `zypper`.
* **Interfaz Dinámica:** Menús interactivos potenciados por `fzf` con previsualizaciones en tiempo real.
* **Monitor de Rendimiento:** Tablero visual en tiempo real con barras de estado para **CPU**, **RAM** y **Disco**.
* **Gestión de Backups Pro:** Sistema de copias de seguridad con verificación de espacio, integridad **SHA256** y rotación automática.
* **Seguridad y Auditoría:** Registro de actividad (Logs) persistente y comprobación estricta de privilegios.

---

## 🏗️ Arquitectura y Robustez Técnica

### 1. Motor de Detección de Distribuciones
El script utiliza la carga de variables de `/etc/os-release` y lógica de caída escalonada (*fallback*) para garantizar la funcionalidad incluso en distros no estándar o derivados.
* **Soportadas:** Debian, Ubuntu, Linux Mint, Kali, Fedora, RHEL, CentOS, Rocky Linux, Arch Linux, Manjaro, openSUSE y más.

### 2. Gestión Inteligente de Dependencias
A diferencia de scripts básicos, STK:
* **Verifica** la existencia de herramientas críticas antes de la ejecución.
* Ofrece **instalación automática** gestionando dependencias de bajo nivel (ej. `build-essential` para gemas de Ruby o motores `snapd`).
* Configura enlaces simbólicos y actualiza el `$PATH` en tiempo de ejecución.

### 3. Optimización de Rendimiento
* **Mínimo Overhead:** Uso intensivo de herramientas nativas del sistema (`awk`, `sed`, `grep`, `du`).
* **Refresco Inteligente:** El monitor de sistema utiliza `tput` y secuencias de escape ANSI para actualizar la pantalla sin parpadeos, minimizando el uso de CPU.

---

## 🛡️ Medidas de Seguridad y Fiabilidad

* **Control de Privilegios:** Verificación obligatoria de `EUID 0` (root) para prevenir fallos de permisos a mitad de procesos críticos.
* **Gestión de Señales (Traps):** Captura `SIGINT` (Ctrl+C) y `SIGTERM` para garantizar una salida limpia, restaurando el cursor del terminal y cerrando procesos en segundo plano (*spinners*).
* **Logs y Auditoría:**
    * Bitácora centralizada en `/var/log/stk_mantenimiento.log`.
    * **Rotación automática:** El log se reinicia al alcanzar los **500KB** para evitar el llenado del disco.
* **Fiabilidad en Backups:**
    * **Verificación Previa:** Calcula el tamaño del origen frente al espacio disponible en el destino antes de iniciar.
    * **Preservación de Permisos:** Uso de flags `-p` en `tar` para mantener atributos de archivos.
    * **Integridad:** Generación de hashes **SHA256** para cada copia realizada.

---

## 📋 Módulos del Sistema

### 📊 Monitorización
* Información detallada del hardware (Modelo de CPU, hilos, frecuencias).
* Visualización de carga de sistema mediante **barras de colores dinámicas**.
* **Diagnóstico de red:** Obtención de IP local, IP pública (vía API con fallback de DNS) e información de interfaces.

### 📦 Gestión de Software
* Actualización integral del sistema con un solo comando.
* Instalación/Desinstalación de programas validando caracteres especiales para prevenir **inyecciones de comandos**.

### ⚙️ Administración y Servicios
* **Usuarios:** Creación y eliminación de usuarios "humanos" (UID >= 1000) con gestión de directorios home.
* **Servicios (Systemd):** Panel de control para filtrar servicios activos, fallidos o buscar específicos. Permite reiniciar, detener y auditar logs con `journalctl`.

### 🧹 Mantenimiento y Backups
* **Super Limpieza:** Purga de cachés de paquetes, huérfanos y limpieza de la papelera del sistema.
* **Backups:** Soporta rutas predefinidas (`/etc`, `/var/www`, `/home`) y rutas manuales. Incluye un explorador de backups existentes y función de **borrado seguro**.

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

## 📝 Registro de Cambios (v5.7)
* **Nuevo:** Función de borrado manual de backups desde la interfaz.
* **Mejora:** Menús `fzf` con previsualización de información del sistema.
* **Optimización:** Refactorización del código de detección de IP pública para evitar bloqueos por DNS.
* **Seguridad:** Implementación de rotación de logs por tamaño.

---
**Autor:** [DanSanMar](https://github.com/DanSanMar)  
**Descripción:** Herramienta integral de mantenimiento para Linux.

> **Nota:** Este script se distribuye "tal cual", con el objetivo de facilitar la administración, pero siempre se recomienda revisar las rutas de backup personalizadas antes de procesos masivos.