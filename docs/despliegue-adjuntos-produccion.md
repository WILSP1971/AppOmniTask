# Despliegue de adjuntos (SPEC-002) en producción — checklist

Este documento es el checklist operativo para habilitar el almacenamiento de
adjuntos de actividades (imágenes/PDF, ver `.swarm/specs/SPEC-002.md`) en el
servidor Windows/IIS de producción descrito en `docs/ARQUITECTURA.md` §18-19
(`https://appsintranet.esculapiosis.com/APIOmniTask`).

La API guarda en PostgreSQL solo metadatos y ruta relativa del adjunto
(tabla `activity_attachments`); el binario vive en el sistema de archivos del
servidor. Esta ruta es un valor de configuración (`Attachments:RootPath`), no
está hardcodeada en el código — el checklist de abajo es lo único que falta
para que funcione en producción.

## 1. Crear la carpeta de almacenamiento

En PowerShell, como Administrador, en el servidor de producción:

```powershell
New-Item -Path "D:\OmniTaskData\attachments" -ItemType Directory -Force
```

**Por qué esta ruta:**
- Fuera de `C:\inetpub` y de la sub-aplicación IIS `/APIOmniTask` — no debe
  quedar dentro de ningún árbol servido como sitio o sub-aplicación.
- En un volumen de datos (`D:\`) separado del sistema operativo/IIS (`C:\`).
- Los archivos solo se acceden vía la API
  (`GET /api/v1/activities/{id}/attachments/{attachmentId}`), nunca
  directamente desde el navegador.

## 2. Dar permisos de escritura al Application Pool

1. Abrir **Gestor de IIS** → Grupos de aplicaciones.
2. Ubicar el pool que ejecuta `OmniTask.Api` y anotar su nombre exacto.
3. Ejecutar (reemplazando `<NombreDelPool>`):

```powershell
icacls "D:\OmniTaskData\attachments" /grant "IIS AppPool\<NombreDelPool>:(OI)(CI)F"
```

`(OI)(CI)F` = herencia de objetos y contenedores, control total.

**Verificación:** Propiedades de la carpeta → pestaña Seguridad → el pool
debe aparecer con "Control total".

## 3. Configurar la ruta real (sin tocar el repo)

El valor por defecto en `APIOmniTask/src/OmniTask.Api/appsettings.json`
(`Attachments:RootPath` = `C:\omnitask\attachments`) es solo para desarrollo
local. En producción, usar una de estas dos opciones:

**Opción A — variable de entorno del Application Pool (recomendada):**
1. IIS Manager → Application Pool → "Advanced Settings" → "Environment".
2. Agregar `Attachments__RootPath` (doble guion bajo) = `D:\OmniTaskData\attachments`.
3. Reciclar el Application Pool.

**Opción B — `appsettings.Production.json`** (debe estar en `.gitignore`,
nunca commitear rutas/secretos de producción al repo):

```json
{
  "Attachments": {
    "RootPath": "D:\\OmniTaskData\\attachments"
  }
}
```

## 4. Validar

Subir un archivo de prueba desde la app contra una actividad de prueba.
Si aparece en la lista y es descargable, ruta y permisos son correctos.

## 5. Confirmar que la ruta no es servida por IIS

Intentar acceder por navegador a una URL directa sobre esa carpeta (fuera de
los endpoints de la API) y confirmar que da 404 o acceso denegado — nunca un
listado de archivos ni una descarga directa sin pasar por la autorización de
la API.

## 6. Incluir en el plan de respaldos

**Pendiente de confirmar con el Lead:** ¿cuál es hoy el plan de backup del
servidor (herramienta, frecuencia, volúmenes cubiertos)? `D:\OmniTaskData\attachments`
debe quedar incluido con la misma frecuencia que el backup de PostgreSQL —
los adjuntos son parte de la actividad tanto como sus filas en la base de
datos; sin ellos un restore queda incompleto.

## Resumen en orden

1. Crear `D:\OmniTaskData\attachments`.
2. Dar permisos al Application Pool con `icacls`.
3. Configurar `Attachments__RootPath` (env var o `appsettings.Production.json`).
4. Reciclar el Application Pool.
5. Probar subida/descarga real desde la app.
6. Confirmar que la ruta no se sirve por HTTP directo.
7. Agregar la ruta al plan de respaldos existente.
