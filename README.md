# tfg-dsc-windows-automation

Repositorio asociado al Trabajo Final de Grado de **Felipe H.C.**.

El proyecto recoge los ficheros utilizados para automatizar el despliegue y la configuración de un entorno Windows Server sobre Proxmox, empleando principalmente **Terraform**, **Cloudbase-Init**, **PowerShell Desired State Configuration (DSC)** y scripts de apoyo para la aplicación de configuraciones de seguridad basadas en guías **CCN-CERT**.

El objetivo del repositorio es centralizar el código, los ficheros de configuración y los scripts necesarios para reproducir el flujo desarrollado en el TFG: creación de una imagen base, generación de una plantilla reutilizable, despliegue de máquinas virtuales y configuración posterior de los roles del laboratorio.

---

## Estructura del repositorio

```text
tfg-dsc-windows-automation/
│
├── 01-ISO/
│   └── WS2025-UEFI/
│       ├── autounattend.xml
│       ├── AUTOUNATTEND.TAG
│       ├── Setup.ps1
│       └── files/
│           ├── cloudbase-init/
│           ├── drivers/
│           ├── modules/
│           ├── providers/
│           ├── qemu-guest-agent/
│           └── update/
│
├── 02-Terraform/
│   ├── 01-create-template-autoun/
│   └── 02-cloudinit-create/
│
├── 03-DSC-CCN/
│   ├── 01-Template/
│   ├── 02-ADDC/
│   ├── 03-FS/
│   ├── 04-CLI/
│   └── 05-ADDC-CCN/
│
└── README.md
```

---

## Directorio `01-ISO/`

Este directorio contiene los ficheros utilizados para preparar la imagen personalizada de instalación de **Windows Server 2025** en modo UEFI.

### `01-ISO/WS2025-UEFI/`

Contiene la estructura base empleada para generar la ISO personalizada.

- `autounattend.xml`: fichero de instalación desatendida de Windows. Define parámetros de instalación, configuración inicial y ejecución automática de scripts durante el despliegue.
- `AUTOUNATTEND.TAG`: fichero marcador utilizado para identificar el medio personalizado durante la instalación.
- `Setup.ps1`: script de preparación ejecutado durante la instalación. Se encarga de copiar componentes, instalar herramientas y dejar el sistema preparado para su uso posterior como imagen base.

### `01-ISO/WS2025-UEFI/files/`

Contiene los recursos adicionales que se integran en la ISO personalizada.

- `cloudbase-init/`: instalador y ficheros de configuración de Cloudbase-Init. Permite que las máquinas Windows desplegadas desde plantilla puedan recibir parámetros de inicialización desde Proxmox Cloud-Init, como nombre de host, contraseña, red o metadatos de instancia.
- `drivers/`: controladores necesarios para el correcto funcionamiento de Windows Server en Proxmox/KVM. Incluye controladores VirtIO para red y almacenamiento.
- `modules/`: módulos de PowerShell/DSC incluidos en la imagen para permitir configuraciones offline o sin dependencia inmediata de Internet.
- `providers/`: proveedores adicionales necesarios para la automatización o gestión del entorno.
- `qemu-guest-agent/`: instalador del agente QEMU Guest Agent, utilizado para mejorar la integración entre la máquina virtual y Proxmox.
- `update/`: recursos auxiliares relacionados con actualizaciones o preparación del sistema base.

Este bloque representa la primera fase del flujo del TFG: construir un medio de instalación que permita desplegar Windows Server de forma desatendida y con las dependencias principales ya disponibles.

---

## Directorio `02-Terraform/`

Este directorio contiene la infraestructura como código utilizada para interactuar con Proxmox y automatizar la creación de máquinas virtuales.

### `02-Terraform/01-create-template-autoun/`

Contiene la configuración de Terraform utilizada para crear la máquina virtual inicial a partir de la ISO personalizada.

- `mainTemplate.tf`: definición principal de la máquina virtual base que se instala desde la ISO desatendida.
- `provider.tf`: configuración del proveedor de Terraform utilizado para conectarse a Proxmox.
- `vars.tf`: variables empleadas por la configuración de Terraform.

Esta fase permite automatizar la creación de la primera VM base, que posteriormente se prepara, se generaliza con Sysprep y se convierte en plantilla reutilizable dentro de Proxmox.

### `02-Terraform/02-cloudinit-create/`

Contiene la configuración de Terraform utilizada para crear máquinas virtuales a partir de la plantilla previamente generada.

- `main.tf`: definición de las máquinas virtuales finales del laboratorio.
- `provider.tf`: configuración del proveedor de Terraform para Proxmox.
- `vars.tf`: variables necesarias para parametrizar el despliegue.

Esta fase se corresponde con el aprovisionamiento de las máquinas del entorno final, como el controlador de dominio, el servidor de ficheros y el cliente de pruebas.

---

## Directorio `03-DSC-CCN/`

Este directorio contiene los scripts de configuración del sistema mediante PowerShell y DSC, así como los scripts relacionados con la aplicación de configuraciones de seguridad.

### `03-DSC-CCN/01-Template/`

Contiene la configuración inicial aplicada sobre la máquina base antes de convertirla en plantilla.

- `01-Base.ps1`: script de configuración base. Prepara el sistema con los ajustes comunes necesarios antes de su reutilización como plantilla.

Esta fase está orientada a dejar una imagen homogénea y reutilizable para el resto de máquinas del laboratorio.

### `03-DSC-CCN/02-ADDC/`

Contiene los scripts y plantillas relacionados con la configuración del controlador de dominio de Active Directory.

- `AD-Promo-DC-Config.ps1`: script de configuración para promover el servidor a controlador de dominio.
- `AD-OUsObjectsV2.ps1`: script para crear la estructura lógica del dominio, incluyendo unidades organizativas, grupos y objetos necesarios.

Para crear el fichero `01-AD-Promo-DC-Config.ps1` hemos usado Jinja, por eso este directorio no incluye solo los dos ficheros de configuración. Los ficheros finales se encuentran en la carpeta RENDERED.

Este bloque automatiza una de las partes centrales del TFG: la creación del dominio, su estructura organizativa y los elementos necesarios para integrar posteriormente otros servidores y clientes.

### `03-DSC-CCN/03-FS/`

Contiene los scripts relacionados con el servidor de ficheros.

- `FS-JoinDomain.ps1`: une el servidor de ficheros al dominio de Active Directory.
- `FS-Shares.ps1`: configura recursos compartidos, permisos y estructura de carpetas del servidor de ficheros.

Esta fase permite validar que el dominio no solo se crea correctamente, sino que también puede ser utilizado por servicios de infraestructura adicionales.

### `03-DSC-CCN/04-CLI/`

Contiene la configuración del equipo cliente del laboratorio.

- `CLI-Base.ps1`: script de configuración base para el cliente. Permite preparar el equipo para su integración en el dominio y para las pruebas funcionales del entorno.

El cliente se utiliza como máquina de validación para comprobar el funcionamiento del dominio, la resolución DNS, el inicio de sesión y el acceso a recursos compartidos.

### `03-DSC-CCN/05-ADDC-CCN/`

Contiene scripts relacionados con la aplicación de configuraciones de seguridad basadas en guías CCN-CERT.

- `Apply-CCN570A25.ps1`: script asociado a la aplicación de configuraciones de seguridad para Windows Server/controlador de dominio.
- `Apply-CCN573-25.ps1`: script asociado a la configuración de seguridad del servidor de ficheros.
- `Apply-CCN599AB23.ps1`: script asociado a la configuración de seguridad de clientes Windows.
- `Invoke-CCN-Guides-DSC.ps1`: script de orquestación para lanzar la aplicación de las guías.
- `ComprobarLinks.ps1`: script auxiliar para comprobar enlaces o vinculaciones de directivas.
- `CopyZips.ps1`: script auxiliar para copiar los paquetes necesarios.
- `CCN-STIC-570A25-Scripts.zip`, `CCN-STIC-573-25-Scripts.zip`, `CCN-STIC-599AB23-Scripts.zip`: paquetes utilizados por los scripts de aplicación de guías.

Este directorio representa la fase de bastionado del entorno, en la que se aplican configuraciones de seguridad sobre la infraestructura desplegada.

---

## Flujo general del proyecto

El contenido del repositorio sigue el mismo orden lógico que el proceso desarrollado en el TFG:

1. **Preparación de la ISO personalizada**  
   Se genera un medio de instalación de Windows Server con instalación desatendida, controladores, Cloudbase-Init, QEMU Guest Agent y módulos DSC.

2. **Creación de la máquina base con Terraform**  
   Terraform crea la primera máquina virtual desde la ISO personalizada en Proxmox.

3. **Preparación de la plantilla reutilizable**  
   La máquina base se configura, se generaliza mediante Sysprep y se convierte en plantilla dentro de Proxmox.

4. **Despliegue de máquinas desde plantilla**  
   Terraform crea las máquinas virtuales finales del laboratorio usando la plantilla y parámetros Cloud-Init.

5. **Configuración mediante DSC y PowerShell**  
   Se configuran los roles principales: controlador de dominio, servidor de ficheros y cliente.

6. **Aplicación de configuraciones de seguridad**  
   Se aplican configuraciones basadas en guías CCN-CERT y se comprueba el estado resultante del entorno.

---

## Requisitos principales

Para utilizar o adaptar este repositorio se requiere un entorno con:

- Proxmox VE como plataforma de virtualización.
- Terraform instalado en el equipo de administración.
- Acceso a la API de Proxmox con credenciales o token configurado.
- Windows Server 2025 como sistema base de las máquinas servidor.
- PowerShell en los sistemas Windows gestionados.
- Módulos DSC necesarios para la configuración del dominio y servicios.
- Cloudbase-Init para la inicialización de máquinas Windows clonadas desde plantilla.

---

## Estado del repositorio

Este repositorio tiene finalidad académica y documenta el proceso de automatización desarrollado en el TFG. Los scripts pueden requerir adaptación a cada entorno, especialmente en lo relativo a:

- nombres de nodos de Proxmox;
- identificadores de máquinas virtuales;
- rutas de almacenamiento;
- direccionamiento IP;
- nombres de dominio;
- credenciales;
- rutas locales de scripts y paquetes.

---

## Licencia y uso

El contenido de este repositorio se proporciona con fines académicos y de documentación del Trabajo Final de Grado. Cualquier reutilización debe revisar previamente las licencias de los componentes externos incluidos, especialmente instaladores, módulos, controladores y paquetes de terceros.
