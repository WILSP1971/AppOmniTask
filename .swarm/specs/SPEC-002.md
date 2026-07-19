# SPEC-002 — Adjuntos en actividades (documentos e imágenes) — Punto 7

- ID: SPEC-002
- Estado: APROBADA (Lead humano, 2026-07-20)
- Autor: DOCTOR STRANGE (la aprobación es del Lead humano, nunca del autor)
- Fecha: 2026-07-20
- Responsable de implementación: CAPTAIN AMERICA
- Colaboradores / revisores:
  - BLACK PANTHER — backend .NET (endpoints multipart, servicio de almacenamiento, SQL)
  - DAREDEVIL — frontend Flutter (UI de adjuntos, image_picker/file_picker)
  - BLACK WIDOW — seguridad (validación de upload, autorización por dueño, path traversal)
  - WOLVERINE — calidad (revisión de código, manejo de errores, análisis)
  - HAWKEYE — pruebas (unit/integración API + widget/flutter test)
- Fuente (insumo XAVIER): `prompt-lab/prompts/p7-p8-adjuntos-y-reuniones.md`

---

## 1. Objetivo

Permitir que sobre una actividad/cita el usuario adjunte, liste, abra/descargue y
elimine archivos (imágenes comunes y PDF), con persistencia de metadatos en
PostgreSQL y almacenamiento del binario en el sistema de archivos del servidor
(Windows/IIS de producción). Alcance mínimo verificable, sin previsualización
avanzada, versionado ni antivirus.

## 2. Contexto

- Stack: Flutter (`omnitask_app/`) + API .NET por capas (`APIOmniTask/`, Domain/
  Application/Infrastructure/Api, acceso a datos con Npgsql) + PostgreSQL (`db/`).
- La tabla `activities` (ver `db/schema.sql` L73) NO tiene adjuntos. Cada actividad
  pertenece a un `user_id` (FK a `users`, ON DELETE CASCADE). Ese `user_id` es la
  base de la autorización por dueño.
- El endpoint de actividades es `api/v1/activities` (`ActivitiesController`), con
  `[Authorize]` y `User.GetUserId()` como identidad. Los nuevos endpoints deben
  seguir ese mismo patrón de identidad y ruta.
- NO existe hoy almacenamiento de archivos, endpoint de subida ni servicio de
  storage: se crean desde cero en esta SPEC.

### Decisión arquitectónica (registrada aquí, resuelta por el Lead 2026-07-20)

- **Almacenamiento en filesystem, no en BD.** El binario se guarda en el sistema
  de archivos del servidor (Windows/IIS); la base de datos guarda SOLO metadatos y
  la ruta relativa. Motivo: evitar inflar la BD con blobs, permitir streaming
  eficiente en descarga y facilitar backups diferenciados. Se documenta como
  decisión de arquitectura dentro de esta SPEC (no se abre ADR separado porque no
  cambia el motor de calendario ni otra decisión troncal).
- La raíz de almacenamiento es configurable (p. ej. `Attachments:RootPath` en
  configuración de la API, fuera del árbol servido por IIS como estático). El
  nombre físico del archivo se genera por el servidor (GUID), NUNCA con el nombre
  original del cliente (defensa contra path traversal / colisiones).

## 3. Requisitos funcionales

- **RF1 — Subir adjunto.** `POST /api/v1/activities/{activityId}/attachments`
  (multipart/form-data, campo `file`). El servidor valida que la actividad exista y
  pertenezca al usuario autenticado, valida tipo y tamaño, guarda el binario en
  filesystem con nombre GUID, persiste metadatos y devuelve `201 Created` con el DTO
  del adjunto (`id`, `activityId`, `fileName` original, `contentType`, `sizeBytes`,
  `uploadedAt`). Se permite subir 1..N archivos (un archivo por request; el cliente
  itera).
- **RF2 — Listar adjuntos.** `GET /api/v1/activities/{activityId}/attachments`
  devuelve `200` con la lista de adjuntos (metadatos, sin bytes) de esa actividad,
  solo si pertenece al usuario.
- **RF3 — Descargar/abrir adjunto.**
  `GET /api/v1/activities/{activityId}/attachments/{attachmentId}` devuelve el
  binario con `Content-Type` correcto y `Content-Disposition` con el `fileName`
  original; bytes íntegros. Solo el dueño.
- **RF4 — Eliminar adjunto.**
  `DELETE /api/v1/activities/{activityId}/attachments/{attachmentId}` borra el
  registro y el archivo físico; devuelve `204`. Solo el dueño.
- **RF5 — Borrado en cascada.** Al eliminar/cancelar la actividad, sus adjuntos se
  borran (FK `ON DELETE CASCADE` en BD). El binario físico se limpia mediante el
  servicio de storage cuando la eliminación pase por la app (best-effort; se
  documenta si el soft-delete de actividad no dispara limpieza física).
- **RF6 — UI Flutter (detalle/edición de actividad).**
  - Selector de archivos: imágenes (galería/cámara vía `image_picker`) y documentos
    PDF (vía `file_picker`).
  - Lista de adjuntos con nombre, tipo y tamaño legible (KB/MB), acción abrir
    (descarga + apertura con visor del sistema) y acción eliminar (con confirmación).
  - Estados de carga (subiendo/descargando), y mensajes de error claros ante 4xx.
  - Nuevo modelo Freezed `Attachment` en `omnitask_app/`.
- **RF7 — Validaciones de servidor.**
  - Tipos permitidos: `image/jpeg`, `image/png`, `image/heic`, `application/pdf`.
    Validar por `Content-Type` Y por extensión/firma coherente cuando sea viable.
  - Tamaño máximo por archivo: **10 MB** (10 * 1024 * 1024 bytes).
  - Rechazos con HTTP 4xx (ver §5 manejo de errores), nunca 500.

## 4. Requisitos no funcionales

- **RNF1 — Seguridad / autorización.** Todo endpoint bajo `[Authorize]`. Cada
  operación verifica que `activity.user_id == User.GetUserId()`. Si no coincide o
  no existe: `404 Not Found` (no revelar existencia de recursos ajenos). Nombre
  físico del archivo generado por el servidor (GUID); jamás concatenar el nombre del
  cliente a una ruta (anti path traversal). Validación de tipo/tamaño en servidor
  (no confiar en el cliente).
- **RNF2 — Límite de request.** El pipeline de la API debe aceptar multipart de
  hasta 10 MB para estos endpoints (ajustar `MaxRequestBodySize` / límites del
  form solo en la ruta de adjuntos, sin degradar el resto de la API).
- **RNF3 — Integridad.** La descarga entrega los mismos bytes que se subieron
  (verificable por tamaño/hash en pruebas).
- **RNF4 — No regresión.** CERO cambios en la lógica existente del calendario:
  `allowedViews`, `initialDisplayDate`, `skipLoadingOnReload`, `appointmentBuilder`,
  el drawer y `table_calendar`. Si la implementación no requiere tocar esas áreas,
  NO se tocan (ver CHECKPOINT C-NR más abajo).
- **RNF5 — Localización.** Textos de UI en español (es_CO), coherentes con la app.
- **RNF6 — Consistencia de capas.** Backend respeta Domain/Application/
  Infrastructure/Api: interfaz `IAttachmentService` (Application), implementación y
  `IFileStorage` (Infrastructure/Services), controlador delgado en Api.

## 5. Manejo de errores (contrato 4xx)

- `401` sin token válido.
- `404` actividad o adjunto inexistente, o perteneciente a otro usuario.
- `413 Payload Too Large` (o `400` con código claro) si el archivo supera 10 MB.
- `415 Unsupported Media Type` (o `400`) si el `Content-Type`/extensión no está en
  la lista permitida.
- `400 Bad Request` si falta el campo `file` o el multipart es inválido.
- La app Flutter mapea cada caso a un mensaje en español; nunca muestra un 500 crudo.

## 6. Modelo de datos (PostgreSQL)

Script incremental nuevo, estilo `db/02_*.sql` (p. ej. `db/04_activity_attachments.sql`):

```sql
CREATE TABLE activity_attachments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    activity_id UUID NOT NULL REFERENCES activities (id) ON DELETE CASCADE,
    file_name TEXT NOT NULL,          -- nombre original mostrado al usuario
    content_type TEXT NOT NULL,       -- MIME validado
    size_bytes BIGINT NOT NULL,
    storage_path TEXT NOT NULL,       -- ruta relativa dentro de RootPath (GUID)
    uploaded_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_activity_attachments_activity_id ON activity_attachments (activity_id);
```

## 7. Criterios de aceptación verificables

- [ ] CA1: Desde el detalle/edición de una actividad se adjunta una imagen y un PDF;
      ambos aparecen en la lista con nombre, tipo y tamaño.
- [ ] CA2: Al reabrir la actividad, los adjuntos persisten (GET los devuelve).
- [ ] CA3: Abrir/descargar un adjunto entrega el archivo correcto (bytes íntegros:
      tamaño/hash igual al original) — probado en API.
- [ ] CA4: Eliminar un adjunto lo quita de la lista y borra el archivo físico;
      al eliminar la actividad se borran sus adjuntos (CASCADE verificado).
- [ ] CA5: Subir un archivo > 10 MB devuelve 4xx (413/400) y la app muestra mensaje
      claro; no hay 500.
- [ ] CA6: Subir un tipo no permitido (p. ej. `.exe`, `.docx`) devuelve 4xx
      (415/400) con mensaje claro; no hay 500.
- [ ] CA7: Un usuario NO puede listar/descargar/eliminar adjuntos de actividades de
      otro usuario (devuelve 404) — probado en API.
- [ ] CA8: El nombre físico en disco es un GUID, distinto del nombre del cliente
      (verificable inspeccionando `storage_path`).
- [ ] CA9 (transversal): `flutter analyze` y `flutter test` en verde; pruebas de la
      API (`APIOmniTask/tests`) en verde.
- [ ] C-NR (no regresión): `git diff` demuestra CERO cambios en la lógica del
      calendario (`allowedViews`, `initialDisplayDate`, `skipLoadingOnReload`,
      `appointmentBuilder`, drawer, `table_calendar`). Si algún archivo de esas áreas
      aparece en el diff sin justificación, la SPEC no se da por cumplida.

## 8. Riesgos y dependencias

- **R1 — Escritura en filesystem de producción (IIS/Windows).** Requiere una ruta
  con permisos de escritura para el usuario del app pool y backup incluido en el
  plan de respaldos. Es un cambio de infraestructura fuera del repo → **necesita
  confirmación operativa del Lead** antes del deploy (QUICKSILVER coordina). El
  código debe funcionar con `RootPath` configurable para no acoplarse a una ruta fija.
- **R2 — Nuevas dependencias Flutter** (`image_picker`, `file_picker`, y librería de
  apertura tipo `open_filex`/`url_launcher`): agregan a `pubspec.yaml` y permisos de
  plataforma (Android: lectura de media/cámara). Requiere aprobación del Lead para
  las dependencias y revisión de permisos por BLACK WIDOW.
- **R3 — Validación de tipo por MIME es evadible** si solo se mira `Content-Type`.
  Mitigación: validar también extensión y, si es viable, firma (magic bytes).
  BLACK WIDOW revisa.
- **R4 — Sin antivirus/OCR/thumbnails** (fuera de alcance): documentar que los
  archivos no se escanean; aceptable para uso interno de la clínica en esta iteración.
- **R5 — Límite de request en el pipeline .NET** puede requerir ajuste de
  `Kestrel`/`FormOptions`; hacerlo acotado a la ruta de adjuntos.
- **Dependencia:** SPEC-002 y SPEC-003 son independientes; pueden implementarse en
  paralelo. Ambas tocan el detalle/edición de actividad (coordinar merges con DAREDEVIL).

## 9. Alcance excluido

- Versionado de archivos, previsualización inline enriquecida, edición de documentos,
  OCR, antivirus, thumbnails en servidor, compartir adjuntos entre actividades.
- Envío de adjuntos por WhatsApp/push (los adjuntos no se envían por ningún canal).
