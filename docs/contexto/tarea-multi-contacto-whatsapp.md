# Tarea: notificar a VARIOS contactos por WhatsApp por actividad (hoy es 1 solo)

## Contexto / estado actual (ya diagnosticado)
Hoy una actividad tiene UN solo contacto:
- BD: `activities.contact_id UUID REFERENCES contacts(id)` (single, nullable) — schema.sql.
- Funciones: `fn_create_activity`/`fn_update_activity` reciben `p_contact_id UUID` (uno);
  `fn_get_reminder_dispatch_info(@id)` devuelve un contacto (contact_id/full_name/phone).
- Backend: `ActivityCreateRequest.ContactId` / `ActivityUpdateRequest.ContactId` (Guid?),
  `ActivityResponse` expone `contact_id`. `ReminderDispatchJob.SendReminderAsync` envía UN
  WhatsApp al `contact_phone_e164` (plantilla `appointment_reminder`, es_CO, params
  [nombre, fecha, hora]) SOLO si `contact_id` no es null y el canal es whatsapp/both.
- App: `ContactPickerField` es de selección ÚNICA (`Contact? selectedContact`); `Activity.contactId`
  es un solo String.

## Objetivo
Que una actividad pueda tener **varios contactos** y que el recordatorio por WhatsApp se envíe
**a todos** ellos (cada uno recibe la plantilla `appointment_reminder`).

## Cambios requeridos (3 capas)

### 1) Base de datos (nueva migración, p.ej. db/09_activity_contacts.sql)
- Crear tabla puente **muchos-a-muchos**:
  `activity_contacts (activity_id UUID REFERENCES activities(id) ON DELETE CASCADE,
   contact_id UUID REFERENCES contacts(id) ON DELETE CASCADE, PRIMARY KEY (activity_id, contact_id))`.
- **Migrar** los datos existentes: insertar en `activity_contacts` los `activities.contact_id`
  actuales que no sean null. Decidir en la SPEC si `activities.contact_id` se deja (sincronizado /
  deprecado) o se elimina; recomendado: dejar de usarlo y que la fuente de verdad sea la tabla puente.
- Actualizar funciones (db/03 + 06):
  - `fn_create_activity` / `fn_update_activity`: aceptar `p_contact_ids UUID[]` y sincronizar la
    tabla puente (en update: reemplazar el set de contactos). Mantener compatibilidad hacia atrás si
    se puede (un solo id sigue funcionando).
  - `fn_get_reminder_dispatch_info`: devolver **SETOF** (todos los contactos con id/nombre/phone_e164)
    de la actividad, no uno.
  - `fn_list_activities` / `fn_get_activity_by_id`: devolver la lista de contactos de cada actividad
    (o exponer un endpoint/consulta para traerlos).
- Permisos: GRANT a `omnitask_api` sobre la tabla/funciones nuevas (como en migraciones previas).

### 2) Backend (C#)
- DTOs: `ActivityCreateRequest`/`ActivityUpdateRequest` → `ContactIds` (List<Guid>) en vez de/además
  de `ContactId`; `ActivityResponse` → lista `Contacts` (o `contact_ids`). snake_case en el JSON.
- `ActivityService`: pasar el array a las funciones y mapear la lista de contactos en la respuesta.
- **`ReminderDispatchJob.SendReminderAsync`**: en vez de un contacto, **recorrer TODOS** los contactos
  devueltos por `fn_get_reminder_dispatch_info` y enviar la plantilla a cada `phone_e164`; registrar
  un `notification_log` por contacto (estado por destinatario). Push al usuario sigue igual (1 vez).

### 3) App (Flutter)
- `ContactPickerField` → **multi-selección** (buscar y agregar varios; mostrar chips con opción de
  quitar). Mantener el autocompletar contra `GET /contacts?search=`.
- Modelo `Activity`: `contactId` (String?) → `contactIds` (List<String>) o lista de contactos.
- Formulario crear/editar y pantalla de detalle: manejar y mostrar **varios** contactos.
- Colocar en las Card de actividades el color de fondo el color del dia del calendario con actividades programadas.
  
## Restricciones
- No romper actividades existentes (migrar el contacto actual a la tabla puente).
- snake_case; mantener el patrón anti-bucle del calendario; localización en español.
- Mantener el diseño/colores actuales (paleta colorida; ver docs/contexto/agenda2.jpg, agenda3.jpg).
- WhatsApp: sigue usando la plantilla `appointment_reminder` (es_CO, 3 params). El envío real requiere
  la config de Meta ya conocida (Phone Number ID, token, App Secret, plantilla aprobada).

## Entrega
- Presenta PLAN + SPEC y espera aprobación del Lead. Migración de BD documentada para producción
  (como db/04..08). flutter analyze + test verdes. Release por tag (siguiente app-vX.Y.Z).
