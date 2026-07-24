# SPEC-008 — Base de datos + Backend: varios contactos por actividad, WhatsApp a todos

- ID: SPEC-008
- Estado: APROBADA (Lead humano, 2026-07-24: "APROBADO SPEC-008/009/010")
- Autor: DOCTOR STRANGE (la aprobación es del Lead humano, nunca del autor)
- Fecha: 2026-07-24
- Responsable de implementación: CAPTAIN AMERICA
- Colaboradores / revisores: BLACK PANTHER (backend/BD), WOLVERINE (calidad),
  HAWKEYE (pruebas), BLACK WIDOW (autorización por dueño de contactos)
- Fuente: `docs/contexto/tarea-multi-contacto-whatsapp.md` → PLAN-001 (APROBADO
  por el Lead, 2026-07-24), Fase 1.

---

## 1. Objetivo

Permitir que una actividad tenga **varios contactos** (hoy `activities.contact_id`
admite a lo sumo uno) y que el recordatorio por WhatsApp (`appointment_reminder`,
`es_CO`) se envíe **a todos** los contactos asociados, con un registro en
`notification_log` por destinatario. Esta SPEC cubre la capa de datos y backend
(BD + C#/.NET 8); la app Flutter se aborda en SPEC-009 contra el contrato que
aquí se define.

## 2. Contexto

- `db/schema.sql`:
  - `activities` (L73) tiene `contact_id UUID REFERENCES contacts (id) ON DELETE
    SET NULL` e índice `idx_activities_contact_id` (L92).
  - `contacts` (L53): `id`, `user_id` (FK `ON DELETE CASCADE`), `full_name`,
    `phone_e164`, `notes`.
  - `notification_log` (L112): `reminder_id` (FK `ON DELETE SET NULL`), `user_id`,
    `channel`, `provider_message_id`, `status`, `summary`, ...
- Funciones vigentes:
  - `fn_create_activity` / `fn_update_activity`: **última definición en
    `db/06_stored_procedures_attachments_and_meeting.sql`** (L115 / L182), con
    `DROP FUNCTION IF EXISTS` de la firma vieja antes de recrear — porque cambiar
    la aridad con solo `CREATE OR REPLACE` genera una sobrecarga en vez de
    reemplazar. `fn_create_activity` inserta la actividad, genera reminders a
    partir de `notification_preferences->reminder_offsets_minutes` y devuelve
    `SETOF activities`.
  - `fn_list_activities`: **última definición en `db/06` (L293)**, `RETURNS TABLE`
    con columnas explícitas (incluye `contact_id`, `meeting_url`,
    `meeting_provider`, `total_count`).
  - `fn_get_activity_by_id` (`db/03` L192) y `fn_list_unscheduled_activities`
    (`db/03` L187): `RETURNS SETOF activities` + `SELECT *` (traen columnas
    nuevas de `activities` automáticamente, pero NO una lista de contactos, que
    no es columna de la tabla).
  - `fn_get_reminder_dispatch_info` (`db/03` L487): hoy `RETURNS TABLE(...)` de
    **una fila**, con `LEFT JOIN contacts c ON c.id = a.contact_id`.
- Backend:
  - DTOs (`APIOmniTask/src/OmniTask.Application/Dtos.cs`): `ActivityCreateRequest`
    (L38, campo `Guid? ContactId`), `ActivityUpdateRequest` (L55, **no expone
    contacto hoy**), `ActivityResponse` (L72, campo `Guid? ContactId`).
  - `ActivityService` (`.../Infrastructure/Services/ActivityService.cs`): pasa
    `@contact_id` a `fn_create_activity`; `MapActivity` (L155) lee la columna
    `contact_id`. `UpdateAsync` (L109) **no** envía ningún contacto.
  - `ReminderDispatchJob.SendReminderAsync`
    (`.../Infrastructure/BackgroundJobs/ReminderDispatchJob.cs` L47): lee UNA fila
    de `fn_get_reminder_dispatch_info`, y si el canal incluye WhatsApp y hay
    `contact_id`, envía la plantilla a ese único `phone_e164` y registra UN
    `notification_log`.
- CI: `.github/workflows/backend-ci.yml` aplica `db/schema.sql` + `db/02..08` con
  `psql` contra un Postgres real del job (L44-51), y luego corre `dotnet test`.

## 3. Requisitos funcionales

- **RF1 — Tabla puente `activity_contacts` (`db/09_activity_contacts.sql`).**
  Nueva migración versionada e idempotente:
  ```sql
  CREATE TABLE IF NOT EXISTS activity_contacts (
      activity_id UUID NOT NULL REFERENCES activities (id) ON DELETE CASCADE,
      contact_id  UUID NOT NULL REFERENCES contacts (id)   ON DELETE CASCADE,
      PRIMARY KEY (activity_id, contact_id)
  );
  CREATE INDEX IF NOT EXISTS idx_activity_contacts_contact_id
      ON activity_contacts (contact_id);
  ```
  (La PK compuesta ya crea índice por `activity_id`; se agrega el índice por
  `contact_id` para el borrado en cascada y para consultas por contacto.)

- **RF2 — Migración de datos existentes (idempotente).** Volcar los
  `activities.contact_id` **no nulos** actuales a `activity_contacts`, dentro del
  mismo `db/09`:
  ```sql
  INSERT INTO activity_contacts (activity_id, contact_id)
  SELECT id, contact_id FROM activities WHERE contact_id IS NOT NULL
  ON CONFLICT DO NOTHING;
  ```
  Reaplicar el script no duplica ni pierde filas.

- **RF3 — Decisión sobre `activities.contact_id` (fijada por esta SPEC, no es
  una pregunta abierta).** La columna `activities.contact_id` y su índice **se
  conservan** (no se borran en esta migración) para no romper un rollback ni las
  lecturas legadas, pero **se deprecian como fuente de verdad**: a partir de esta
  SPEC, la fuente de verdad de "los contactos de una actividad" es
  `activity_contacts`. `fn_create_activity` / `fn_update_activity` dejan de
  escribir `activities.contact_id`; las lecturas de contactos salen de la tabla
  puente. La columna queda documentada como deprecada (comentario en `db/09` y en
  el documento de migración). Su limpieza definitiva (drop) es una SPEC futura,
  fuera de alcance aquí.

- **RF4 — `fn_create_activity` acepta `p_contact_ids UUID[]`.** En `db/09` (para
  respetar el patrón "DROP de la firma vieja antes de recrear" de `db/06`):
  reemplazar el parámetro `p_contact_id UUID` por `p_contact_ids UUID[]` (los
  demás parámetros y la generación de reminders quedan igual). Tras insertar la
  actividad, sincronizar `activity_contacts` con el conjunto recibido (ignorando
  ids nulos/duplicados). No escribir `activities.contact_id` (RF3). Se hace `DROP
  FUNCTION IF EXISTS` de la firma vigente (la de `db/06`, 10 parámetros con
  `p_contact_id UUID`) antes del `CREATE`.

- **RF5 — `fn_update_activity` acepta `p_contact_ids UUID[]` + flag de
  sincronización.** Reemplazar el conjunto **completo** de contactos de la
  actividad por el recibido (delete + insert dentro de la función). Como un array
  `NULL` es ambiguo ("no tocar los contactos" vs. "quitar todos"), se agrega un
  flag explícito `p_sync_contacts BOOLEAN`: cuando es `false`, los contactos no se
  tocan (mismo criterio "NULL = no lo toques" que ya usan title/meeting_url);
  cuando es `true`, se reemplaza el conjunto por `p_contact_ids` (que puede venir
  vacío para dejar la actividad sin contactos). `DROP FUNCTION IF EXISTS` de la
  firma vigente de `db/06` antes del `CREATE`.

- **RF6 — Lecturas devuelven la lista de contactos.**
  - `fn_get_activity_by_id`: dejar de ser `SELECT * FROM activities` puro; pasar a
    `RETURNS TABLE(...)` con todas las columnas de `activities` **más** una
    columna agregada `contacts JSONB` = arreglo de objetos
    `{id, full_name, phone_e164}` de los contactos de la actividad (vía
    `jsonb_agg` sobre `activity_contacts JOIN contacts`, `'[]'::jsonb` si no hay).
  - `fn_list_activities`: agregar la misma columna `contacts JSONB` al final del
    `RETURNS TABLE` (antes o después de `total_count` — documentar el orden), sin
    romper el orden de las columnas existentes que `MapActivity` lee por nombre.
  - `fn_list_unscheduled_activities`: misma columna `contacts JSONB` (pasa a
    `RETURNS TABLE`).
  - Se mantiene la columna `contact_id` en las salidas mientras exista, por
    compatibilidad de lectura, pero ya no es la fuente de verdad (RF3).

- **RF7 — `fn_get_reminder_dispatch_info` pasa a `SETOF` (una fila por
  contacto).** Devolver **todas** las filas de contacto de la actividad del
  reminder (id, `full_name`, `phone_e164`), en vez de una sola. Un reminder de una
  actividad sin contactos devuelve **cero filas de WhatsApp** pero el backend debe
  poder enviar el push igual (ver RF10): por eso la fila debe seguir trayendo
  `reminder_id`, `channel`, `activity_id`, `activity_title`,
  `activity_starts_at`, `user_id` aunque no haya contacto. Diseño: o bien un
  `LEFT JOIN` a `activity_contacts` (una fila con `contact_*` en NULL cuando no
  hay contactos), o dos funciones (una para datos de actividad, otra `SETOF` para
  contactos). Se **recomienda el `LEFT JOIN`** para mantener una sola llamada; el
  job trata `contact_id IS NULL` como "sin destinatario de WhatsApp".

- **RF8 — GRANTs.** `GRANT` a `omnitask_api` sobre `activity_contacts` (SELECT,
  INSERT, DELETE) y `EXECUTE` sobre las funciones recreadas, mismo patrón que
  `db/04..08`.

- **RF9 — DTOs (contrato de API).**
  - `ActivityCreateRequest`: agregar `List<Guid>? ContactIds`. **Mantener** el
    campo legado `Guid? ContactId` durante la ventana de transición (ver RF12).
  - `ActivityUpdateRequest`: agregar `List<Guid>? ContactIds` (null = no tocar los
    contactos; lista, incluso vacía, = reemplazar el conjunto). Traducido a
    `p_contact_ids` + `p_sync_contacts = (ContactIds != null)` (RF5).
  - `ActivityResponse`: agregar `List<ContactResponse> Contacts` (usar el
    `ContactResponse` ya existente en `Dtos.cs` L104, que tiene `Id`, `FullName`,
    `PhoneE164`, `Notes`; `Notes` puede ir null si `fn_*` no lo trae). Se **conserva**
    `Guid? ContactId` en la respuesta (compatibilidad, RF12); su valor será el
    primer contacto de la lista, o null. JSON en snake_case (`contact_ids`,
    `contacts`, `contact_id`), como el resto de la API.

- **RF10 — `ActivityService` mapea el array y la lista.**
  - `CreateAsync`/`UpdateAsync`: pasar el array de contactos a las funciones. En
    create, combinar `ContactIds` con `ContactId` legado (RF12) en un solo array
    de-duplicado.
  - `MapActivity`: leer la nueva columna `contacts JSONB` y materializar
    `List<ContactResponse>`; derivar `ContactId` = primer contacto o null.

- **RF11 — `ReminderDispatchJob` envía a TODOS los contactos.**
  `SendReminderAsync` recorre las filas de `fn_get_reminder_dispatch_info`:
  - El push al usuario dueño (`SendPushAsync`) se ejecuta **una sola vez** por
    reminder (no una por contacto).
  - Para cada contacto con `phone_e164` no nulo y canal WhatsApp/Both: enviar la
    plantilla `appointment_reminder`/`es_CO` a ese `phone_e164` y registrar **un
    `notification_log` por contacto** (estado por destinatario, con su
    `provider_message_id`). Si el envío a un contacto falla, se registra su
    `notification_log` como fallido y se continúa con los demás; el reminder solo
    se marca `failed` si falla de forma que ameriten reintento de Hangfire (misma
    política de excepción/retry que hoy), no por un único destinatario inválido.
  - **Corregir de paso** el bug de precedencia de la condición actual
    (`channel is ReminderChannel.Whatsapp or ReminderChannel.Both && contactId is
    not null`, L86): `&&` liga más fuerte que `or`, así que hoy no evalúa lo
    esperado. Rehacer la condición con paréntesis explícitos al reestructurar el
    bucle.

- **RF12 — Ventana de compatibilidad del contrato (breaking manejado, no
  ambiguo).** Backend y app se despliegan por separado (la app vía GitHub
  Release/APK que el usuario instala cuando quiere; el backend manualmente al
  servidor Windows/IIS). Para no romper una app vieja ya instalada que todavía
  envía `contact_id` (un solo id) y no conoce `contact_ids`, el backend **acepta
  ambos campos** durante la ventana de transición:
  - En entrada (`ActivityCreateRequest`): si llega `ContactIds`, se usa; si solo
    llega `ContactId` (app vieja), se trata como una lista de un elemento; si
    llegan ambos, se unen y de-duplican.
  - En salida (`ActivityResponse`): se devuelven **ambos**, `contacts`/`contact_ids`
    (nuevo) y `contact_id` (primer contacto, legado), para que la app vieja siga
    leyendo el único contacto que sabe mostrar.
  - Retirar `contact_id` del contrato es una SPEC futura, una vez que el APK nuevo
    (SPEC-009) esté suficientemente difundido; se deja anotado como deuda técnica.

## 4. Requisitos no funcionales

- **RNF1 — CI aplica `db/09`.** Agregar en `backend-ci.yml`, tras la línea de
  `db/08`, `psql ... -f db/09_activity_contacts.sql`, para validar el SQL contra
  el Postgres real del job (mismo patrón que `db/07`/`db/08`). `dotnet build` y
  `dotnet test` deben quedar en verde.
- **RNF2 — Autorización por dueño.** Un usuario solo puede asociar a una actividad
  contactos que le pertenezcan (`contacts.user_id` = dueño de la actividad). Las
  funciones deben ignorar/rechazar ids de contacto de otro usuario (filtrar por
  `user_id` al sincronizar la tabla puente), nunca filtrar contactos ajenos en las
  lecturas.
- **RNF3 — Migración sin pérdida de datos.** El volcado (RF2) debe conservar el
  contacto de toda actividad que hoy tenga `contact_id` no nulo; verificar
  conteos antes/después en el documento de migración.
- **RNF4 — Coherencia con SPEC-007 (limpiar notificaciones).** Como ahora habrá
  varias filas de `notification_log` por reminder (una por contacto), la bandeja y
  el borrado de historial (SPEC-007) deben seguir funcionando; `sp_clear_notifications`
  ya borra por `user_id`, así que no cambia, pero se verifica en pruebas que
  múltiples filas por recordatorio se listan y se limpian correctamente.
- **RNF5 — No regresión.** Cero cambios en la lógica de generación de reminders
  (offsets), en el resto de endpoints de `/activities`, ni en el push
  (`SendPushAsync` sigue una sola vez por reminder). Sin cambios en el patrón de
  claim atómico (`fn_claim_due_reminders`).
- **RNF6 — Documento de migración para producción.** Estilo `db/04..08` /
  `docs/despliegue-*.md`: pasos para aplicar `db/09` en el servidor Windows/IIS y
  verificación de conteos. Lo ejecuta el Lead, igual que en SPECs previas.

## 5. Manejo de errores

- Enviar `contact_ids` con un id que no existe o que pertenece a otro usuario: se
  ignora ese id (no se asocia), sin devolver 500. Documentar en `docs/pruebas-api.html`.
- Actividad sin contactos: válida — se crea/edita sin filas en `activity_contacts`;
  su recordatorio de WhatsApp simplemente no tiene destinatario (el push sí sale).
- Un `phone_e164` inválido para un contacto no debe impedir el envío a los demás
  contactos de la misma actividad (RF11); su `notification_log` queda como fallido.

## 6. Criterios de aceptación verificables

- [ ] CA1: Se puede crear una actividad con 0, 1 y N `contact_ids` desde la API;
      el conjunto se persiste en `activity_contacts` y `GET /activities/{id}`
      devuelve `contacts` con todos.
- [ ] CA2: `PATCH /activities/{id}` con `contact_ids` reemplaza el conjunto
      completo; omitir el campo no toca los contactos; enviar lista vacía deja la
      actividad sin contactos.
- [ ] CA3: Las actividades que existían antes de la migración conservan su
      contacto tras aplicar `db/09` (conteo `activity_contacts` = conteo de
      `activities.contact_id` no nulos; sin pérdida).
- [ ] CA4: `fn_list_activities`, `fn_list_unscheduled_activities` y
      `fn_get_activity_by_id` devuelven la columna `contacts`; la API la expone en
      list/get sin 500.
- [ ] CA5: `fn_get_reminder_dispatch_info` devuelve una fila por contacto de la
      actividad (verificado en SQL/prueba de integración con una actividad de 2+
      contactos), y cero filas de contacto (pero datos de actividad) cuando no hay
      contactos.
- [ ] CA6: Al despachar un reminder WhatsApp/Both de una actividad con 2+
      contactos, se registra un `notification_log` por contacto y un solo push al
      dueño (verificable por lectura del código + prueba con `IWhatsAppClient`
      simulado que cuente invocaciones por número).
- [ ] CA7 (compatibilidad, RF12): una petición vieja que solo envía `contact_id`
      (un id) sigue creando/actualizando la actividad con ese contacto; la
      respuesta incluye tanto `contact_id` como `contacts`/`contact_ids`.
- [ ] CA8 (autorización, RNF2): un `contact_id` de otro usuario enviado en
      `contact_ids` no se asocia a la actividad.
- [ ] CA9 (transversal): `dotnet build`/`dotnet test` en verde; `backend-ci.yml`
      aplica `db/09` contra Postgres real sin error.
- [ ] C-NR (no regresión): `list`/`get`/`create`/`update`/`cancel` de actividades,
      generación de reminders, push, y la bandeja/limpieza de notificaciones
      (SPEC-007) siguen funcionando sin cambios de comportamiento observable
      (más allá de los campos nuevos aditivos).

## 7. Riesgos y dependencias

- **R1 — Cambio de aridad de `fn_create_activity`/`fn_update_activity`.** Cambiar
  `p_contact_id UUID` por `p_contact_ids UUID[]` requiere `DROP FUNCTION IF EXISTS`
  de la firma vigente (la de `db/06`) antes del `CREATE`, como ya se hizo en `db/06`
  para las firmas de `db/03`; si no, Postgres crea una sobrecarga y `ActivityService`
  llama con ambigüedad. `db/09` debe aplicarse **después** de `db/06` (garantizado
  por el prefijo numérico).
- **R2 — Breaking change de contrato de API.** Mitigado por la ventana de
  compatibilidad (RF12): backend acepta y devuelve `contact_id` (legado) y
  `contact_ids`/`contacts` (nuevo) a la vez; ninguna app instalada se rompe al
  desplegar el backend antes que el APK.
- **R3 — `activities.contact_id` deprecado pero presente.** Cualquier lectura
  externa que aún dependa de esa columna dejará de reflejar cambios (las escrituras
  van a la tabla puente). Mitigación: fuente de verdad única (`activity_contacts`),
  columna documentada como deprecada, no borrada, drop en SPEC futura (RF3).
- **R4 — Volumen de `notification_log`.** Un reminder de N contactos genera N
  filas de WhatsApp. Verificar que la bandeja y la limpieza (SPEC-007) siguen
  coherentes (RNF4).
- **R5 — WhatsApp real no verificable en el sandbox.** El envío efectivo requiere
  la config de Meta (Phone Number ID, token, App Secret, plantilla aprobada). El
  bucle por contacto se valida por lectura + pruebas con cliente simulado; la
  entrega real queda a verificación manual del Lead. No se crea ni edita ninguna
  credencial en esta SPEC.

## 8. Alcance EXCLUIDO (explícito)

- Cambios en la app Flutter: fuera — es SPEC-009 (esta SPEC solo define el
  contrato al que apuntará la app).
- Borrar la columna `activities.contact_id` o retirar `contact_id` del contrato de
  API: fuera — deuda técnica documentada, SPEC futura tras difundir el APK nuevo
  (RF3/RF12).
- Roles por contacto en la actividad (organizador/invitado, etc.), orden de
  contactos, o metadatos por relación: fuera — la tabla puente solo asocia, sin
  atributos adicionales.
- Plantilla de WhatsApp distinta por contacto o personalización más allá de las
  variables actuales (`full_name`, fecha, hora): fuera.
- Notificar/enviar a los contactos por otro canal (correo, SMS): fuera.
