# SPEC-003 — Link de reunión (Meet/Teams) en actividades — Punto 8

- ID: SPEC-003
- Estado: APROBADA (Lead humano, 2026-07-20)
- Autor: DOCTOR STRANGE (la aprobación es del Lead humano, nunca del autor)
- Fecha: 2026-07-20
- Responsable de implementación: CAPTAIN AMERICA
- Colaboradores / revisores:
  - SPIDER-MAN — UX del selector de proveedor (Meet/Teams/Otro) y de las acciones
    copiar / abrir / compartir
  - BLACK PANTHER — backend .NET (extensión de DTO/modelo de actividad, migración SQL)
  - DAREDEVIL — frontend Flutter (campos, validación de URL, share sheet)
  - WOLVERINE — calidad (revisión de código, validación de URL, manejo de errores)
  - HAWKEYE — pruebas (unit/integración API + widget/flutter test)
- Fuente (insumo XAVIER): `prompt-lab/prompts/p7-p8-adjuntos-y-reuniones.md`

---

## 1. Objetivo

Permitir que sobre una actividad/cita el usuario registre manualmente (pegando) un
link de reunión Meet/Teams/otro proveedor, lo vea en el detalle, y pueda copiarlo,
abrirlo y compartirlo con el contacto participante mediante el share sheet del
dispositivo. Sin integración con APIs de terceros y sin envío por WhatsApp.

## 2. Contexto

- La tabla `activities` (`db/schema.sql` L73) NO tiene campos de reunión. Cada
  actividad tiene un único `contact_id` (FK, ON DELETE SET NULL); el contacto tiene
  `full_name` y `phone_e164`.
- El endpoint es `api/v1/activities` con `PATCH /{id}` (`ActivityUpdateRequest`) para
  actualizar, y `POST` (`ActivityCreateRequest`) para crear. Los campos nuevos se
  añaden a esos DTOs y al `ActivityResponse`, reusando los endpoints existentes (NO
  se crean endpoints nuevos para el link).
- Existe infraestructura de WhatsApp (`WhatsAppCloudApiClient`) en el repo, pero por
  decisión del Lead (2026-07-20) NO se usa aquí (ver §9).

### Decisión arquitectónica (registrada aquí, resuelta por el Lead 2026-07-20)

- **NO integración OAuth con Google Meet / Microsoft Teams.** El link se ingresa
  manualmente (el usuario crea la reunión fuera de la app y pega la URL). Integrar
  las APIs de terceros requeriría OAuth, consentimiento de la clínica y gestión de
  secretos = cambio de infraestructura que solo el Lead puede aprobar; sería una SPEC
  aparte. Se documenta como decisión dentro de esta SPEC (no se abre ADR separado).
- **NO envío por WhatsApp.** Descartado explícitamente por el Lead. El único canal de
  compartir es el share sheet / copiar del dispositivo.

## 3. Requisitos funcionales

- **RF1 — Campos nuevos en la actividad.** `meeting_url` (URL) y `meeting_provider`
  (`meet` | `teams` | `other`). Nulos permitidos (actividad sin reunión).
- **RF2 — Crear/editar con link.** En crear y editar actividad, el usuario puede
  pegar `meeting_url` y elegir `meeting_provider` desde un selector. La app valida el
  formato de URL (http/https) antes de enviar; el servidor valida también (defensa en
  profundidad). URL inválida se rechaza con mensaje claro.
- **RF3 — Mostrar en detalle.** El detalle de la actividad muestra el link (y el
  proveedor con su etiqueta/ícono) cuando existe.
- **RF4 — Acción copiar.** Botón que copia `meeting_url` al portapapeles y confirma
  con feedback (snackbar).
- **RF5 — Acción abrir.** Botón que abre `meeting_url` en el navegador/app externa
  (`url_launcher`).
- **RF6 — Acción compartir.** Botón que abre el share sheet del dispositivo
  (`share_plus`) con un texto que incluye el link (y opcionalmente título/hora de la
  cita y nombre del contacto). Es el mecanismo para "enviarle el link al participante".
- **RF7 — Acciones condicionadas.** Si la actividad NO tiene `meeting_url`, las
  acciones copiar/abrir/compartir están deshabilitadas u ocultas.
- **RF8 — Modelo Freezed.** Extender `Activity` en `omnitask_app/` con `meetingUrl`
  y `meetingProvider`.

## 4. Requisitos no funcionales

- **RNF1 — Seguridad / autorización.** La lectura y escritura del link va por los
  endpoints existentes bajo `[Authorize]`, con la autorización por dueño ya vigente
  en `ActivitiesController`. No se añade superficie de ataque nueva de red.
- **RNF2 — Validación de URL.** Cliente y servidor validan esquema http/https y
  formato razonable de URL. Se rechaza contenido no-URL para evitar guardar basura.
- **RNF3 — No regresión.** CERO cambios en la lógica existente del calendario:
  `allowedViews`, `initialDisplayDate`, `skipLoadingOnReload`, `appointmentBuilder`,
  el drawer y `table_calendar`. Si la implementación no requiere tocar esas áreas, NO
  se tocan (ver CHECKPOINT C-NR).
- **RNF4 — Localización.** Textos de UI en español (es_CO).
- **RNF5 — Compatibilidad de datos.** La migración es aditiva (columnas nullables);
  actividades existentes no se ven afectadas.

## 5. Manejo de errores (contrato 4xx)

- `400 Bad Request` si `meeting_url` no es una URL http/https válida (mensaje claro
  en la app).
- `400` si `meeting_provider` no está en el conjunto permitido (`meet`/`teams`/`other`).
- `401` sin token; `404` si la actividad no existe o es de otro usuario (comportamiento
  ya existente del controlador).

## 6. Modelo de datos (PostgreSQL)

Script incremental aditivo, estilo `db/02_*.sql` (p. ej. `db/05_activity_meeting.sql`):

```sql
ALTER TABLE activities ADD COLUMN meeting_url TEXT;
ALTER TABLE activities ADD COLUMN meeting_provider TEXT;
-- meeting_provider: 'meet' | 'teams' | 'other' (validado en la aplicación)
```

## 7. Criterios de aceptación verificables

- [ ] CA1: En crear/editar actividad se puede pegar `meeting_url` y elegir
      `meeting_provider`; una URL inválida se rechaza con mensaje.
- [ ] CA2: El link y el proveedor persisten y se muestran en el detalle tras
      reabrir la actividad (GET los devuelve).
- [ ] CA3: El botón "copiar" copia el link al portapapeles con feedback visible.
- [ ] CA4: El botón "abrir" abre el link en navegador/app externa.
- [ ] CA5: El botón "compartir" abre el share sheet del dispositivo con el texto que
      incluye el link.
- [ ] CA6: Sin `meeting_url`, las acciones copiar/abrir/compartir están
      deshabilitadas u ocultas.
- [ ] CA7: La migración es aditiva y las actividades existentes siguen funcionando
      (no rompe list/get/patch).
- [ ] CA8 (transversal): `flutter analyze` y `flutter test` en verde; pruebas de la
      API (`APIOmniTask/tests`) en verde.
- [ ] C-NR (no regresión): `git diff` demuestra CERO cambios en la lógica del
      calendario (`allowedViews`, `initialDisplayDate`, `skipLoadingOnReload`,
      `appointmentBuilder`, drawer, `table_calendar`).

## 8. Riesgos y dependencias

- **R1 — Dependencias Flutter** (`share_plus`, `url_launcher`): agregan a
  `pubspec.yaml`. Requiere aprobación del Lead para las dependencias.
- **R2 — Un solo participante por actividad** (`contact_id` único). Compartir a
  múltiples participantes queda FUERA de alcance; no se amplía el modelo en esta
  iteración.
- **R3 — El share sheet depende del dispositivo/OS**; el envío efectivo lo completa
  el usuario en la app que elija (WhatsApp, correo, etc.), no lo automatiza OmniTask.
- **Dependencia:** independiente de SPEC-002; ambas tocan el detalle/edición de
  actividad, coordinar merges con DAREDEVIL.

## 9. Alcance EXCLUIDO (explícito)

- **Integración con APIs de Google Meet / Microsoft Teams / Microsoft Graph** (crear
  la reunión por API, invitar por calendario, sincronizar): FUERA. Requeriría OAuth y
  aprobación de credenciales aparte del Lead → sería otra SPEC.
- **Envío por WhatsApp** (Cloud API / `WhatsAppCloudApiClient`): DESCARTADO por el
  Lead (2026-07-20). No se implementa ninguna vía WhatsApp para el link.
- **Generación automática del link** desde la app: fuera; el usuario lo crea
  manualmente y lo pega.
- **Envío por push u otro canal automático**: fuera; solo share sheet / copiar.
