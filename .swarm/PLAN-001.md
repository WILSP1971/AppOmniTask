# PLAN-001 — Varios contactos por actividad + recordatorio WhatsApp a todos

- **Estado:** APROBADO (Lead humano, 2026-07-24: "APROBADO PLAN-001")
- **Autor:** DOCTOR STRANGE
- **Fecha:** 2026-07-24
- **Fuente:** `docs/contexto/tarea-multi-contacto-whatsapp.md`
- **SPECs candidatas:** SPEC-008, SPEC-009 (y posible SPEC-010 — ver Fase 3)

---

## 1. Objetivo

Permitir que una actividad tenga **varios contactos** (hoy es uno solo) y que el recordatorio por
WhatsApp (`appointment_reminder`, es_CO) se envíe **a todos** los contactos asociados, sin romper las
actividades ya existentes (que hoy tienen a lo sumo un `contact_id`).

---

## 2. Alcance (qué cambia en las 3 capas)

Diagnóstico ya realizado en la tarea; aquí se resume el impacto por capa.

### 2.1 Base de datos (nueva migración versionada, p.ej. `db/09_activity_contacts.sql`)
- Nueva **tabla puente muchos-a-muchos** `activity_contacts (activity_id, contact_id)` con PK
  compuesta y `ON DELETE CASCADE` en ambas FKs.
- **Migración de datos**: volcar los `activities.contact_id` no nulos actuales a `activity_contacts`.
- Decisión a fijar en la SPEC: `activities.contact_id` se **deprecia** (deja de ser fuente de verdad;
  la tabla puente pasa a serlo). Recomendación: no borrar la columna en esta migración para no romper
  rollbacks; marcarla deprecada y dejar de escribirla/leerla.
- Funciones (`db/03` + `db/06`) a actualizar:
  - `fn_create_activity` / `fn_update_activity`: aceptar `p_contact_ids UUID[]` y sincronizar la tabla
    puente (en update: reemplazar el conjunto completo).
  - `fn_get_reminder_dispatch_info`: pasar de devolver una fila a **`SETOF`** (todos los contactos con
    id / nombre / `phone_e164`).
  - `fn_list_activities` / `fn_get_activity_by_id`: exponer la lista de contactos por actividad.
- `GRANT` a `omnitask_api` sobre la tabla y funciones nuevas (mismo patrón que `db/04..08`).
- El job de CI de backend (`backend-ci.yml`) debe aplicar `db/09` contra el Postgres real del job
  (igual que se hizo con `db/07` y `db/08`).

### 2.2 Backend (C#/.NET 8, sin ORM)
- DTOs: `ActivityCreateRequest` / `ActivityUpdateRequest` → `ContactIds` (`List<Guid>`);
  `ActivityResponse` → lista `contacts` (o `contact_ids`), en snake_case en el JSON.
- `ActivityService`: pasar el array a las funciones y mapear la lista en la respuesta.
- `ReminderDispatchJob.SendReminderAsync`: **recorrer TODOS** los contactos devueltos por
  `fn_get_reminder_dispatch_info` y enviar la plantilla a cada `phone_e164`; registrar un
  `notification_log` **por contacto** (estado por destinatario). El push al usuario dueño sigue siendo
  una sola vez.

### 2.3 App (Flutter)
- `ContactPickerField`: de selección única a **multi-selección** (buscar + agregar varios; chips con
  botón de quitar). Mantiene el autocompletar contra `GET /contacts?search=`.
- Modelo `Activity`: `contactId` (`String?`) → `contactIds` (`List<String>`) o lista de contactos.
- Formulario de crear/editar (`activity_edit_screen.dart`) y pantalla de detalle
  (`activity_detail_screen.dart`): manejar y mostrar varios contactos.

---

## 3. Fases propuestas y entregables

### Fase 1 — SPEC-008: Base de datos + Backend (multi-contacto y dispatch a todos)
Entregables:
- `db/09_activity_contacts.sql` (tabla, migración de datos, GRANTs).
- `db/03` / `db/06` actualizados (funciones `fn_create_activity`, `fn_update_activity`,
  `fn_get_reminder_dispatch_info` SETOF, `fn_list_activities`, `fn_get_activity_by_id`).
- DTOs + `ActivityService` + `ReminderDispatchJob` con envío a todos y un `notification_log` por
  contacto.
- `backend-ci.yml` aplicando `db/09`; `dotnet build` y `dotnet test` en verde.
- Documento de migración para producción (estilo `db/04..08` / `docs/despliegue-*.md`).

### Fase 2 — SPEC-009: Frontend Flutter (multi-selección de contactos)
Entregables:
- `ContactPickerField` multi-selección con chips.
- `Activity` con lista de contactos; serialización acorde al nuevo contrato de API.
- Formulario y detalle mostrando/gestionando varios contactos.
- `flutter analyze` sin issues y `flutter test` en verde.
- Release por tag `app-vX.Y.Z` una vez en `main` y con CI verde.

### Fase 3 — SPEC-010 (CONFIRMADA por el Lead): color del día en "Actividades por fecha"
La tarea pide "colocar en las Card de actividades el color de fondo el color del día del calendario".
**Investigado:**
- **Ya resuelto por SPEC-005** en "Mis citas" (Home): `appointments_section.dart` calcula `dayColor`
  vía `colorForDay()` y lo pasa a `AppointmentCard(color: dayColor)`; el badge de fecha usa ese color.
- **NO cubierto todavía:** `activities_by_date_screen.dart` → `_ActivityTile` (línea ~124) usa
  `colorForActivityType(activity.type)` por actividad, **no** el color unificado del día.
- **Confirmado por el Lead:** la petición apunta a "Actividades por fecha". Se crea SPEC-010, pequeña,
  solo frontend: aplicar `colorForDay()` (misma función ya usada por SPEC-005) a las tarjetas de esa
  pantalla, ya que ahí SÍ hay un único día de referencia (el elegido en la consulta).

---

## 4. Riesgos

- **Retrocompatibilidad de `activities.contact_id`**: al deprecarla, cualquier lectura antigua que
  dependa de ella deja de reflejar cambios. Mitigación: sincronizar/documentar y hacer la tabla puente
  la única fuente de verdad; no borrar la columna en esta migración.
- **Migración de datos existentes**: el volcado inicial debe ser idempotente y cubrir sólo contactos no
  nulos; verificar conteos antes/después.
- **Cambio de contrato de API (breaking)**: `ContactId` → `ContactIds` / `contacts`. Un cliente Flutter
  viejo que aún envíe `contact_id` fallaría. Mitigación: coordinar el release de app con el backend, o
  aceptar temporalmente ambos campos en los DTOs durante una ventana de transición.
- **WhatsApp real no verificable en el sandbox**: el envío efectivo requiere la config de Meta (Phone
  Number ID, token, App Secret, plantilla `appointment_reminder` aprobada). El código y el bucle por
  contacto se validan por lectura + tests; la entrega real queda a verificación manual del Lead.
- **`notification_log` por contacto**: cambia el volumen y el modelo de estados de notificación; hay que
  asegurar que la bandeja/limpieza (SPEC-007) siga coherente con múltiples filas por recordatorio.
- **Patrón anti-bucle del calendario** y localización en español deben mantenerse intactos.

---

## 5. Criterios de aceptación de alto nivel

1. Una actividad puede crearse y editarse con 0..N contactos; el conjunto se persiste en
   `activity_contacts`.
2. Las actividades existentes conservan su contacto tras la migración (sin pérdida de datos).
3. El recordatorio de WhatsApp se envía a **cada** contacto de la actividad, con un `notification_log`
   por destinatario; el push al dueño sigue siendo único.
4. `fn_list_activities` / `fn_get_activity_by_id` y la API devuelven la lista de contactos.
5. La app permite buscar, agregar y quitar varios contactos (chips) y muestra todos en el detalle.
6. `dotnet build`/`dotnet test` y `flutter analyze`/`flutter test` en verde; migración `db/09`
   aplicada en CI y documentada para producción.
7. (Si aplica Fase 3) las cards de actividades de la vista objetivo usan el color del día unificado.

---

## 6. Orden de implementación sugerido

1. **SPEC-008 (BD + backend)** primero: define el contrato de datos y el dispatch. Sin esto el
   frontend no tiene a qué apuntar.
2. **SPEC-009 (Flutter)** después, contra el contrato ya definido; luego release por tag.
3. **SPEC-010 (color del día en "Actividades por fecha")** — confirmada; independiente y pequeña,
   puede ir en cualquier momento (no depende de SPEC-008/009).

**Aprobaciones de infraestructura fuera del repo:** ninguna requerida. Todo es código + migración
versionada (`db/09`) + CI, dentro de este repositorio. La config de Meta para WhatsApp ya existe y es
conocida; no se crea ni edita ninguna credencial en este trabajo. El despliegue de la migración a
producción (servidor Windows/IIS) lo ejecuta el Lead siguiendo el documento de migración, igual que en
`db/04..08`.
