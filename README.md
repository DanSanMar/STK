<div align="center">
 <img width="500" height="300" alt="image" src=https://github.com/DanSanMar/STK/blob/main/img/Pasted%20Image.png />
 </div>

# 🛠️ STK - System Tool Kit (v5.9.4) Estamos probando y afinando para sacar la V.6

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

# 🛠️ STK - System Tool Kit (v5.9.4)

</div>

**System Tool Kit** es una potente herramienta de mantenimiento para sistemas basados en Linux (probada en Debian/Ubuntu/Kali/Fedora y las mismas distros en WSL2). Proporciona una interfaz visual intuitiva gracias a los menús creados con FZF para gestionar el mantenimiento/actualización, monitorización y administración del sistema.

## 🚀 Características Principales

* **Abstracción de Paquetes:** Motor de detección inteligente que unifica la sintaxis de `apt`, `dnf`, `pacman` y `zypper`.
* **Interfaz Dinámica:** Menús interactivos potenciados por `fzf` con previsualizaciones en tiempo real.
* **Monitor de Rendimiento:** Tablero visual en tiempo real con barras de estado para **CPU**, **RAM** y **Disco**.
* **Gestión de Backups Pro:** Sistema de copias de seguridad con verificación de espacio, integridad **SHA256** y rotación automática.
* **Seguridad y Auditoría:** Registro de actividad (Logs) persistente y comprobación estricta de privilegios.
* **Funciones de la v.5.8.1:** Se añade una opción para restaurar los Backups y una pequeña Auditoria de Seguridad. 
* **Funciones de la v.5.9.1:** Se añade un Modo Auto al menú principal, una forma directa de actualizar, limpiar, auditar la seguridad y revisar los servicios fallidos. 
* **Nuevas funciones de la v.5.9.4:** Se añade una opción de gestión de Firewall con UFW dentro del menú de Auditoria de Seguridad.
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

<div align="center">
<img width="500" height="300" alt="image" src="https://github.com/user-attachments/assets/2725cd00-bcd5-4e7a-b3db-23a2a7a6da94" />
</div>

### 📦 Gestión de Software
* Actualización integral del sistema con un solo comando.
* Instalación/Desinstalación de programas validando caracteres especiales para prevenir **inyecciones de comandos**.

### ⚙️ Administración y Servicios
* **Usuarios:** Creación y eliminación de usuarios "humanos" (UID >= 1000) con gestión de directorios home.
* **Servicios (Systemd):** Panel de control para filtrar servicios activos, fallidos o buscar específicos. Permite reiniciar, detener y auditar logs con `journalctl`.

<div align="center">
  <img width="500" height="300" alt="image" src="https://github.com/user-attachments/assets/c6d49f8c-6827-4d8f-b43b-417d2200395e" />
</div>

### 🧹 Mantenimiento y Backups
* **Super Limpieza:** Purga de cachés de paquetes, huérfanos y limpieza de la papelera del sistema.
* **Backups:** Soporta rutas predefinidas (`/etc`, `/var/www`, `/home`) y rutas manuales. Incluye un explorador de backups existentes y función de **borrado seguro**.

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

## 📝 Registro de Cambios (v5.7)
* **Nuevo:** Función de borrado manual de backups desde la interfaz.
* **Mejora:** Menús `fzf` con previsualización de información del sistema.
* **Optimización:** Refactorización del código de detección de IP pública para evitar bloqueos por DNS.
* **Seguridad:** Implementación de rotación de logs por tamaño.

## 📝 Registro de Cambios (v5.8.5)
* **Nuevo:** Función de creación de usuarios con persmisos y modificación de los mismos.
* **Mejora:** Menús `fzf` para los dos sistemas de backups
* **Optimización:** Mejoras visuales y robusted para distintas distros.
* **Seguridad:** Implementación de auditoria de seguridad más completa.

## 📝 Registro de Cambios (v5.9.1)
* **Nuevo:** Integración del ejecutor rápido `modo_auto` para mantenimiento automatizado y auditoría integral del sistema.
* **Mejora:** Detección inteligente de gestores de paquetes principales (`apt`, `pacman`, `dnf`, `zypper`) y secundarios (`flatpak`, `snap`).
* **Optimización:** Limpieza profunda con cálculo dinámico de espacio en disco recuperado y gestión de `journalctl`.
* **Seguridad:** Evaluación de seguridad con sistema de puntuación porcentual y verificación del estado de servicios en `systemd`.

## 📝 Registro de Cambios (v5.9.4) (Actual)
* **Nuevo:** Integración completa de UFW Firewall Manager.
* **Mejora:** Menús optimizados para gestión de reglas y auditoría de tráfico.
* **Seguridad:** Detección de escaneos de puertos y fuerza bruta.
---
**Autor:** [DanSanMar](https://github.com/DanSanMar)  
**Descripción:** Herramienta integral de mantenimiento para Linux.

> **Nota:** Este script se distribuye "tal cual", con el objetivo de facilitar la administración, pero siempre se recomienda revisar las rutas de backup personalizadas antes de procesos masivos.
