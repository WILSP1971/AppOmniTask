# PROMPT OPTIMIZADO — Puntos 7 y 8 (adjuntos + link de reunión)

> Autor: XAVIER (Professor X, estratega de prompts). Destino: DOCTOR STRANGE (SPEC).
> Marco: C.R.A.F.T. Basado en el estado REAL del repo (verificado 2026-07-20), no en supuestos.

---

## 0. Hallazgos que condicionan el alcance (verificados en el repo)

- **Stack**: Flutter (`omnitask_app/`, modelos Freezed) + API .NET (`APIOmniTask/`, arquitectura por capas Domain/Application/Infrastructure/Api, acceso a datos con Npgsql/SQL) + **PostgreSQL** (`db/schema.sql`).
- **`activities`** NO tiene columnas de adjuntos ni de link de reunión. `contacts` tiene `id, full_name, phone_e164, notes`.
- **YA EXISTE canal de "enviar"** (esto corrige el supuesto del encargo): la API tiene `WhatsAppCloudApiClient` (WhatsApp Cloud API, envío por **plantillas** aprobadas — `SendTemplateMessageAsync`), `FirebasePushSender` (push), tablas `reminders`/`notification_log` y enums de canal `push`/`whatsapp`. Es decir, "enviar el link al participante" tiene una vía backend factible sin OAuth de Google/Microsoft.
- **NO existe** almacenamiento de archivos, endpoint de subida, ni integración OAuth con Google/Microsoft. Añadir OAuth es petición de infraestructura/secretos que **requiere aprobación explícita del Lead** (regla del proyecto).

---

## 1. Objetivo (Acción)

Permitir que, sobre una actividad/cita, el usuario **(P7)** adjunte y consulte documentos e imágenes, y **(P8)** registre un link de reunión (Meet/Teams) pegado manualmente, lo vea en el detalle y lo comparta/envíe al contacto participante. Todo con **alcance mínimo verificable**, sin depender de credenciales OAuth de terceros.

---

## 2. Alcance INCLUIDO

### Punto 7 — Adjuntos (documentos e imágenes)
- Adjuntar 1..N archivos a una actividad desde la app (imágenes de galería/cámara y documentos como PDF).
- Subir el archivo a la API, persistir metadatos y recuperar la lista de adjuntos de una actividad.
- En el detalle de actividad: **listar** adjuntos (nombre, tipo, tamaño), **abrir/descargar**, y **eliminar** un adjunto.
- Validaciones de servidor: tipos permitidos (imágenes comunes + PDF) y **límite de tamaño por archivo** (valor a fijar en la SPEC, sugerido 10 MB).

### Punto 8 — Link de reunión + envío
- Campos nuevos en la actividad: **`meeting_url`** (URL) y **`meeting_provider`** (`meet` | `teams` | `other`).
- Crear/editar actividad permite **pegar** el link; validación de URL. (Opcional deseable: botón "generar" que abra el flujo manual de crear reunión en la web de Meet/Teams y el usuario pega el resultado — NO integración API.)
- Mostrar el link en el detalle, con acciones **copiar** y **abrir**.
- **Enviar/compartir** el link al contacto participante. Dado el estado del repo, la SPEC debe elegir/combinar entre estas dos vías, en este orden de preferencia:
  - **(A) Compartir vía dispositivo (share sheet / copiar)** — alcance mínimo garantizado, sin backend nuevo, funciona siempre.
  - **(B) Enviar por WhatsApp usando la infraestructura existente** (`WhatsAppCloudApiClient` + `phone_e164` del contacto) — SOLO si existe/se aprueba una **plantilla de WhatsApp** que admita una variable con el link (la API envía por plantillas, no texto libre). Si no hay plantilla aprobada, (B) queda fuera y se entrega (A).

---

## 3. Alcance EXCLUIDO (explícito, para evitar sobre-alcance)

- **Integración automática con Google Calendar/Meet o Microsoft Graph/Teams** (crear la reunión por API, invitar por calendario, sincronizar): FUERA. Requiere OAuth + consentimiento de la clínica + secretos = aprobación de infraestructura del Lead. Solo entra si el Lead lo pide y aprueba las credenciales explícitamente (sería una SPEC aparte).
- Para P7: versionado de archivos, previsualización inline enriquecida (visor embebido de PDF/office), edición de documentos, OCR, antivirus, thumbnails generados en servidor, compartir adjuntos entre actividades.
- Envío de **adjuntos** por WhatsApp/push (solo se comparte el link de reunión, no los archivos).
- Multi-participante: el modelo actual liga la actividad a **un** `contact_id`. Enviar a múltiples participantes queda FUERA salvo que la SPEC amplíe el modelo (no recomendado en esta iteración).

---

## 4. Impacto por capa (alto nivel — el diseño detallado es de DOCTOR STRANGE)

**Base de datos (`db/`, PostgreSQL)**
- P7: nueva tabla `activity_attachments` (id, activity_id FK ON DELETE CASCADE, file_name, content_type, size_bytes, storage_path/blob, uploaded_at). Decidir estrategia de almacenamiento (sistema de archivos del servidor Windows vs. columna binaria) — es decisión de arquitectura.
- P8: `ALTER TABLE activities ADD meeting_url TEXT, meeting_provider TEXT` (+ script incremental estilo `db/02_*.sql`).

**API (.NET)**
- P7: endpoints subir / listar / descargar / eliminar adjunto (multipart), con validación tipo+tamaño y autorización por dueño de la actividad; servicio en `Infrastructure/Services`.
- P8: extender modelo/DTO de actividad con los campos de reunión; endpoint (o reusar update) para guardarlos; endpoint para "enviar link por WhatsApp" solo si se elige la vía (B) con plantilla.

**Flutter (`omnitask_app/`)**
- Modelos Freezed: `Activity` (añadir `meetingUrl`, `meetingProvider`) y nuevo `Attachment`.
- UI en detalle/edición: selector de archivos (image_picker/file_picker), lista de adjuntos con abrir/eliminar, campos de link con validación, y acciones copiar/abrir/compartir (share_plus) y/o botón "enviar por WhatsApp".

---

## 5. Supuestos

1. Un solo participante por actividad (modelo actual `contact_id` único).
2. "Enviar" al participante se cubre con share sheet/copiar (A); WhatsApp (B) solo si hay plantilla aprobada.
3. El usuario crea la reunión Meet/Teams manualmente fuera de la app y pega el link; la app no la crea.
4. Almacenamiento de adjuntos en la infraestructura existente del proyecto (a confirmar con el Lead si implica cambios en el servidor Windows/IIS).

---

## 6. Preguntas abiertas para el Lead (máx. 3, críticas)

1. **Enviar link (P8)**: ¿basta con compartir vía dispositivo/copiar (A), o se requiere envío automático por WhatsApp (B)? Si (B), ¿hay una plantilla de WhatsApp aprobada que acepte el link como variable, o hay que solicitarla?
2. **Almacenamiento de adjuntos (P7)**: ¿se permite guardar archivos en el servidor Windows/IIS de producción (ruta/volumen) o se prefiere guardarlos en la base de datos? (afecta infraestructura).
3. **Límites P7**: ¿confirmas tamaño máx. por archivo (sugerido 10 MB) y tipos permitidos (imágenes + PDF)? ¿algún otro formato obligatorio (Word/Excel)?

---

## 7. Criterios de aceptación medibles

### Punto 7 — Adjuntos
- [ ] Desde el detalle/edición de una actividad, el usuario adjunta una imagen y un PDF; ambos aparecen en la lista con nombre, tipo y tamaño.
- [ ] Al reabrir la actividad, los adjuntos persisten (GET los devuelve).
- [ ] Abrir/descargar un adjunto entrega el archivo correcto (bytes íntegros).
- [ ] Eliminar un adjunto lo quita de la lista y del almacenamiento; al borrar la actividad se borran sus adjuntos (CASCADE).
- [ ] Subir un archivo > límite o de tipo no permitido devuelve error controlado (HTTP 4xx) y la app muestra mensaje claro; no hay 500.
- [ ] Un usuario no puede leer/borrar adjuntos de actividades de otro usuario (autorización).

### Punto 8 — Link de reunión + envío
- [ ] En crear/editar actividad se puede pegar un `meeting_url` y elegir `meeting_provider`; una URL inválida se rechaza con mensaje.
- [ ] El link persiste y se muestra en el detalle con botones "copiar" y "abrir" funcionales.
- [ ] Existe una acción "compartir/enviar link al participante": vía (A) abre el share sheet / copia; y/o vía (B) — si aprobada — envía por WhatsApp al `phone_e164` del contacto y queda registro en `notification_log`.
- [ ] Sin link registrado, las acciones de compartir/enviar están deshabilitadas u ocultas.

### Transversal
- [ ] `flutter analyze` y `flutter test` en verde; pruebas de la API (`APIOmniTask/tests`) en verde.
- [ ] No se rompe la lógica existente del calendario, backlog ni reprogramación.
- [ ] No se introducen credenciales OAuth de Google/Microsoft (fuera de alcance).

---

## 8. Recomendación de XAVIER (alcance recomendado para la SPEC)

- **P7**: adjuntar/listar/abrir/eliminar imágenes + PDF, límite 10 MB, sin previsualización avanzada ni versionado.
- **P8**: campos `meeting_url` + `meeting_provider` pegados manualmente + compartir vía dispositivo (A) como base garantizada; WhatsApp (B) como incremento condicionado a plantilla aprobada. Integración API Meet/Teams: NO, hasta aprobación de credenciales por el Lead.

Entregar este prompt a **DOCTOR STRANGE** para redactar SPEC(s). Sugerencia: **dos SPEC separadas** (SPEC-P7 adjuntos, SPEC-P8 reunión) porque el riesgo, el impacto en BD y las dependencias externas son distintos.
