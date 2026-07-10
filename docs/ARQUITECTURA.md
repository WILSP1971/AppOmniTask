# OmniTask — Documento de Arquitectura

**Preparado para:** Equipo de desarrollo — Clínica Campbell
**Rol:** Arquitectura de software · Full-stack móvil
**Fecha:** 10 de julio de 2026
**Estado:** Propuesta técnica v1

> Arquitectura de sistema, esquema de base de datos y guía de desarrollo por fases para una aplicación móvil de calendario, citas y tareas con notificaciones push y confirmaciones automáticas por WhatsApp Business.
>
> Versión con diseño completo (diagramas y tablas con estilo): [`docs/arquitectura.html`](./arquitectura.html) — ábrelo directo en el navegador, GitHub no lo renderiza inline.

## Índice

1. [Decisiones de stack](#1--decisiones-de-stack)
2. [Arquitectura del sistema](#2--arquitectura-del-sistema)
3. [Esquema de base de datos](#3--esquema-de-base-de-datos)
4. [Guía de desarrollo por fases](#4--guía-de-desarrollo-por-fases)
5. [Seguridad y cumplimiento](#5--seguridad-y-cumplimiento)
6. [Endpoints de la API — Fase 1](#6--endpoints-de-la-api--fase-1)
7. [Plantillas de WhatsApp](#7--plantillas-de-whatsapp)
8. [Fase 3 — Devices y scheduler de recordatorios](#8--fase-3--devices-y-scheduler-de-recordatorios)
9. [Modelos concretos — Fase 1](#9--modelos-concretos--fase-1)
10. [Servicio de auth: hashing, JWT y refresh](#10--servicio-de-auth-hashing-jwt-y-refresh)
11. [Estructura del proyecto FastAPI](#11--estructura-del-proyecto-fastapi)
12. [Frontend Flutter: Riverpod y vistas de calendario](#12--frontend-flutter-riverpod-y-vistas-de-calendario)
13. [CI/CD — Fase 7](#13--cicd--fase-7)
14. [Pantallas de detalle y edición de actividad](#14--pantallas-de-detalle-y-edición-de-actividad)
15. [Pantallas de login y registro](#15--pantallas-de-login-y-registro)

---

## §1 — Decisiones de stack

La propuesta original — Flutter, C#/FastAPI, MySQL, FCM y WhatsApp Cloud API — es una base sólida. Se ajustan dos piezas para que el sistema encaje mejor con el requisito más delicado del proyecto: *fechas y recordatorios correctos entre zonas horarias, con envío confiable a WhatsApp*.

### Frontend — Flutter (sin cambios)

Correcto para iOS y Android desde un solo código base. Para las vistas de calendario, usar `syncfusion_flutter_calendar` (vistas día/semana/mes con drag-and-drop listas de fábrica) o `table_calendar` si se prefiere una dependencia más ligera. Estado con **Riverpod**; más fácil de testear que Bloc para un equipo pequeño y evita el boilerplate de Provider clásico.

### Backend — FastAPI (Python), no C#

> **Recomendación:** consolidar en un solo stack de backend: **Python + FastAPI**. Descartar C#/.NET para esta app.

La razón no es preferencia de lenguaje: el núcleo del producto es *trabajo asíncrono e integraciones I/O-bound* — sondear recordatorios cada minuto, llamar a la API de Meta, escuchar webhooks de estado, enviar push. FastAPI + Celery + Redis cubre exactamente ese patrón con librerías maduras (`httpx`, `celery`, `firebase-admin`) y un solo lenguaje entre API y workers. Mantener C# en paralelo solo duplicaría infraestructura sin beneficio funcional. Si el equipo ya tiene fuerte inversión en .NET, ASP.NET Core + Hangfire es una alternativa igualmente válida — pero no mezclar ambos en el mismo servicio.

### Base de datos — PostgreSQL en vez de MySQL

> **Cambio propuesto:** PostgreSQL 16 en vez de MySQL.

El requisito de "actividades sin fecha" y recordatorios entre zonas horarias depende de manejar tiempo con precisión. PostgreSQL tiene `TIMESTAMPTZ` nativo y funciones de calendario más completas que MySQL; además su tipo `JSONB` indexable es ideal para guardar las variables de las plantillas de WhatsApp y los payloads de webhook sin crear una tabla nueva por cada variante. Si por política interna de la clínica MySQL ya es el motor estándar, el esquema de la §3 se traduce sin cambios estructurales — solo cambia el tipo de columna de fecha.

### Resumen del stack final

| Capa | Tecnología | Rol |
|---|---|---|
| Móvil | Flutter 3.x | App única iOS/Android, Riverpod, calendario nativo |
| API | FastAPI (Python 3.12) | REST + auth, orquesta integraciones |
| Cola / jobs | Redis + Celery Beat | Recordatorios programados, reintentos de envío |
| Datos | PostgreSQL 16 | Persistencia transaccional |
| Push | Firebase Cloud Messaging | Notificaciones nativas al dispositivo |
| Mensajería | WhatsApp Cloud API (Meta) | Confirmaciones y recordatorios por WhatsApp |

---

## §2 — Arquitectura del sistema

Cuatro capas: el cliente Flutter nunca habla directo con Meta ni con Firebase Admin — todo pasa por el backend, que es la única capa con credenciales de servicio. El dispositivo sí recibe el push directo de FCM (infraestructura de Google, no del backend).

```
 Cliente                 API                       Datos & cola                  Integraciones externas
 ──────────────────────────────────────────────────────────────────────────────────────────────────────
 Flutter App        →    FastAPI              →    PostgreSQL                    FCM
 (iOS · Android)         (Auth · CRUD ·             (users · activities ·         (Firebase Cloud
                          Webhooks)                  reminders)                    Messaging)
      │ HTTPS + JWT            │ SQLAlchemy               │ Redis (broker)              │ Admin SDK
      ▼                        ▼                          ▼                             ▼
 Registro de token   Celery Beat                    Redis                          Push nativo
 FCM (al iniciar     (escaneo de recordatorios       (cola + resultados)            (al dispositivo
 sesión)              cada 60s)                                                     del usuario)
                            │ dispara                     ↕
                            ▼                              │ webhook
                      Celery Workers          ─────────────┴────────────►    WhatsApp Cloud API
                      (envío + reintentos)                                    (Meta Business)
```

### Cómo fluye una cita con recordatorio por WhatsApp

1. El usuario crea una cita en Flutter → `POST /activities` con fecha/hora en su zona horaria local; el backend la normaliza a UTC antes de guardar.
2. El backend crea automáticamente uno o más registros en `reminders` (ej. 1 día antes, 1 hora antes) según la configuración del usuario.
3. Celery Beat revisa cada minuto qué recordatorios vencen; encola un job por cada uno.
4. El worker decide el canal: push vía Firebase Admin SDK, WhatsApp vía Cloud API, o ambos — y registra el resultado en `notification_log`.
5. Meta llama de vuelta al webhook del backend con el estado de entrega (enviado/entregado/leído/fallido); el backend actualiza el log y puede reintentar si falló.

### Actividades sin fecha

Se guardan en la misma tabla `activities` con `starts_at = NULL` y `status = 'unscheduled'`. Un job diario de Celery Beat agrupa las actividades sin fecha por usuario y dispara una notificación tipo "tienes 4 actividades pendientes por programar" — sin depender de una fecha que no existe.

---

## §3 — Esquema de base de datos

Siete tablas. Reuniones, citas, tareas y actividades comparten una sola tabla (`activities`) diferenciada por `type` — evita duplicar CRUD y notificaciones para cuatro conceptos que en la práctica son "algo con título, estado y quizá una fecha".

**Relaciones**

- `users` 1 ─── N `devices` (tokens FCM, multi-dispositivo)
- `users` 1 ─── N `contacts` (personas que reciben WhatsApp)
- `users` 1 ─── N `activities`
- `contacts` 1 ─── N `activities` (opcional)
- `activities` 1 ─── N `reminders`
- `reminders` 1 ─── N `notification_log`
- `whatsapp_templates` 1 ─── N `reminders` (solo canal whatsapp)

### `users`

| Columna | Tipo | Notas |
|---|---|---|
| id `PK` | uuid | |
| full_name | text | |
| email `UQ` | text | login |
| password_hash | text | bcrypt/argon2 |
| phone_e164 | text | formato +57... |
| timezone | text | IANA, ej. America/Bogota |
| role | enum | admin · profesional · asistente |
| created_at / updated_at | timestamptz | |

### `devices`

| Columna | Tipo | Notas |
|---|---|---|
| id `PK` | uuid | |
| user_id `FK → users` | uuid | |
| fcm_token | text | se rota al reinstalar la app |
| platform | enum | ios · android |
| last_seen_at | timestamptz | |

### `contacts`

| Columna | Tipo | Notas |
|---|---|---|
| id `PK` | uuid | |
| user_id `FK → users` | uuid | quién lo gestiona |
| full_name | text | |
| phone_e164 | text | destinatario del WhatsApp |
| notes | text `NULL` | |

### `activities` (reuniones · citas · tareas · actividades)

| Columna | Tipo | Notas |
|---|---|---|
| id `PK` | uuid | |
| user_id `FK → users` | uuid | |
| contact_id `FK → contacts` | uuid `NULL` | una tarea puede no tener contacto |
| type | enum | meeting · appointment · task · activity |
| title | text | |
| description | text `NULL` | |
| status | enum | unscheduled · scheduled · completed · cancelled |
| starts_at | timestamptz `NULL` | NULL = "sin fecha de calendario" |
| ends_at | timestamptz `NULL` | |
| timezone | text | tz al momento de crear, para render correcto |
| location | text `NULL` | |
| nudge_frequency_days | int `NULL` | cada cuánto recordar si sigue sin fecha |
| created_at / updated_at | timestamptz | |

### `reminders`

| Columna | Tipo | Notas |
|---|---|---|
| id `PK` | uuid | |
| activity_id `FK → activities` | uuid | |
| remind_at | timestamptz | calculado (ej. starts_at − 1h) |
| channel | enum | push · whatsapp · both |
| template_id `FK → whatsapp_templates` | uuid `NULL` | solo si channel incluye whatsapp |
| status | enum | pending · processing · sent · failed |
| sent_at | timestamptz `NULL` | |

### `notification_log`

| Columna | Tipo | Notas |
|---|---|---|
| id `PK` | uuid | |
| reminder_id `FK → reminders` | uuid `NULL` | NULL para avisos de sistema (ej. resumen de pendientes) |
| user_id `FK → users` | uuid | |
| channel | enum | push · whatsapp |
| provider_message_id | text `NULL` | wamid de Meta / message-id de FCM |
| status | enum | queued · sent · delivered · read · failed |
| error_detail | text `NULL` | |
| created_at | timestamptz | |

### `whatsapp_templates`

| Columna | Tipo | Notas |
|---|---|---|
| id `PK` | uuid | |
| meta_template_name | text | espejo del nombre en Meta Business Manager |
| language_code | text | ej. es_CO |
| category | enum | utility · marketing · authentication |
| approval_status | enum | espejo del estado de aprobación de Meta |
| variables_schema | jsonb | nombres/orden de las variables de la plantilla |

---

## §4 — Guía de desarrollo por fases

Ocho fases, cada una entregable de forma independiente. El orden importa: la integración de WhatsApp (fase 4) depende de tener verificado el número de negocio en Meta desde la fase 0, porque esa verificación puede tardar varios días hábiles.

### Fase 0 — Fundamentos y cuentas externas
*Todo lo que tiene tiempos de espera de terceros arranca aquí, no cuando ya se necesita.*
- Repositorios (móvil / backend), estándares de linting y commits
- Alta en Meta Business Manager + verificación del número de WhatsApp (puede tardar 3–5 días hábiles)
- Proyecto en Firebase (FCM) y credenciales de servicio
- Entornos: local, staging, producción; gestor de secretos

*Bloqueante para la fase 4.*

### Fase 1 — Backend núcleo: datos y autenticación
- Modelos SQLAlchemy + migraciones con Alembic
- Auth JWT (access + refresh token), manejo de `timezone` por usuario
- CRUD de `activities` y `contacts`, validación con Pydantic
- Documentación automática vía OpenAPI (gratis con FastAPI)

### Fase 2 — Frontend núcleo: calendario
- Esqueleto Flutter, Riverpod, cliente HTTP con manejo de refresh token
- Vistas de calendario (día/semana/mes) con CRUD de actividades
- Pantalla de "pendientes por programar" para actividades sin fecha

### Fase 3 — Notificaciones push
- Registro de `devices` (token FCM) al iniciar sesión
- Celery + Redis: Beat evalúa `reminders` cada 60s, workers envían
- Deep-link desde la notificación al detalle de la actividad

### Fase 4 — Integración WhatsApp Business
- Plantillas aprobadas en Meta (confirmación, reprogramación, recordatorio)
- Endpoint de envío vía Cloud API + manejo de la ventana de 24h de conversación
- Webhook de estados (enviado/entregado/leído/fallido) y de respuestas entrantes

*Depende de la fase 0.*

### Fase 5 — Alertas de pendientes sin programar
*La funcionalidad menos obvia de la propuesta original — actividades sin fecha que igual necesitan seguimiento.*
- Job diario que agrupa `activities` con `starts_at IS NULL` por usuario
- Notificación resumen ("tienes N actividades sin programar")
- Bandeja dedicada en el frontend, separada del calendario

### Fase 6 — Calidad y seguridad
- Rate limiting en auth y en endpoints de envío
- Pruebas unitarias e integración (pytest), pruebas de carga sobre el scheduler
- Verificación de firma de webhooks de Meta (`X-Hub-Signature-256`)

### Fase 7 — Despliegue y observabilidad
- Contenedores Docker, migraciones automatizadas en CI/CD
- Publicación en App Store / Google Play
- Logs estructurados, métricas de entrega de notificaciones, alertas de fallos en la cola

---

## §5 — Seguridad y cumplimiento

- **Datos personales:** el correo `@clinicacampbell.com.co` sugiere que esto puede terminar gestionando datos de pacientes. Si es así, el tratamiento de nombres y teléfonos en `contacts` cae bajo la **Ley 1581 de 2012 (Habeas Data)** en Colombia — se necesita autorización expresa del titular para contactarlo por WhatsApp, y un aviso de privacidad accesible desde la app.
- **Plantillas de WhatsApp:** Meta exige que las plantillas de categoría *utility* (confirmaciones, recordatorios) no incluyan contenido promocional; revisar la política de mensajería de salud de Meta si se usan para citas médicas.
- **Secretos:** tokens de Meta, credenciales de Firebase Admin y claves de firma JWT van en un gestor de secretos (no en variables de entorno planas en el repo).
- **Tiempo:** guardar siempre en UTC (`timestamptz`) y convertir solo en la capa de presentación, usando el `timezone` del usuario — nunca convertir antes de persistir.

---

## §6 — Endpoints de la API — Fase 1

Alcance de la fase 1: autenticación, `activities` y `contacts`. Los endpoints de `devices` (fase 3) y de envío de WhatsApp (fase 4) dependen de infraestructura que aún no existe en esta fase.

**Convenciones:** base `/api/v1`. Fechas en JSON siempre ISO 8601 UTC (`2026-07-14T20:00:00Z`) — el cliente convierte a la zona horaria local solo para mostrar. Errores con el mismo sobre: `{"error": {"code": "...", "message": "..."}}`. Todo endpoint salvo `/auth/*` requiere `Authorization: Bearer <access_token>`.

### Autenticación

| Método | Endpoint | Descripción |
|---|---|---|
| `POST` | `/auth/register` | Crea usuario y sesión. Body: `full_name, email, password, phone_e164, timezone`. `timezone` se valida como identificador IANA real. |
| `POST` | `/auth/login` | Devuelve `access_token` (15 min) y `refresh_token` (30 días, en Redis con posibilidad de revocación). |
| `POST` | `/auth/refresh` | Body: `refresh_token`. Si fue revocado, responde 401 y el cliente fuerza login. |
| `POST` | `/auth/logout` | Revoca el `refresh_token` actual (blacklist en Redis hasta su expiración natural). |
| `GET` | `/auth/me` | Perfil autenticado — usado al abrir la app para hidratar el estado de sesión. |

```json
// POST /auth/register → 201 Created
{
  "user": { "id": "...", "full_name": "...", "timezone": "America/Bogota" },
  "access_token": "eyJ...",
  "refresh_token": "eyJ..."
}
```

### Activities

| Método | Endpoint | Descripción |
|---|---|---|
| `POST` | `/activities` | Crea reunión, cita, tarea o actividad. Si `starts_at` es `null`, se fuerza `status = "unscheduled"`. Genera `reminders` automáticos según preferencias del usuario. |
| `GET` | `/activities?from=&to=&type=&status=&page=&limit=` | Listado para el calendario. `from`/`to` alimentan las vistas día/semana/mes. |
| `GET` | `/activities/unscheduled` | Atajo a `status=unscheduled` sin rango de fecha — alimenta la bandeja de pendientes. |
| `GET` | `/activities/{id}` | Detalle, incluye `reminders` embebidos. |
| `PATCH` | `/activities/{id}` | Actualización parcial. Reprogramar (`starts_at`) regenera los `reminders`. Pasar a `completed`/`cancelled` cancela los pendientes sin enviarse. |
| `DELETE` | `/activities/{id}` | Soft delete (`status = "cancelled"`), no borrado físico — conserva `notification_log`. |

```json
// POST /activities
{
  "type": "appointment",
  "title": "Control - María Fernanda Ríos",
  "contact_id": "c1a2...",
  "starts_at": "2026-07-14T20:00:00Z",
  "ends_at": "2026-07-14T20:30:00Z",
  "location": "Consultorio 3"
}
```

```json
// GET /activities?from=&to=... → 200 OK
{
  "items": [ { "id": "...", "type": "appointment", "starts_at": "2026-07-14T20:00:00Z" } ],
  "page": 1, "limit": 50, "total": 132
}
```

### Contacts

| Método | Endpoint | Descripción |
|---|---|---|
| `POST` | `/contacts` | Body: `full_name, phone_e164, notes`. `phone_e164` en formato internacional — es el mismo valor que viaja al campo `to` de la Cloud API en la fase 4. |
| `GET` | `/contacts?search=` | Listado / búsqueda por nombre. |
| `GET` | `/contacts/{id}` | Detalle. |
| `PATCH` | `/contacts/{id}` | Edición. |
| `DELETE` | `/contacts/{id}` | Elimina solo si no tiene actividades asociadas; si tiene, responde 409 para evitar dejar huérfanos los mensajes ya registrados. |

---

## §7 — Plantillas de WhatsApp

Meta no permite enviar texto libre para iniciar una conversación. Todo mensaje que abre o reabre el hilo con un contacto debe usar una **plantilla pre-aprobada** — de ahí la tabla `whatsapp_templates` de la §3, que es un espejo local del estado real en Meta Business Manager.

### Ciclo de vida de una plantilla

`Se crea en Business Manager (nombre + idioma + variables)` → `Meta revisa (pending, horas a días)` → `Aprobada o rechazada` → `Se espeja en la BD (whatsapp_templates)` → `Celery la usa para enviar (fase 4)`

Por eso la fase 0 incluye dar de alta el número de WhatsApp con tiempo: sin plantillas aprobadas, la fase 4 no tiene nada que enviar.

### Las tres plantillas que necesita OmniTask

**`appointment_confirmation`** · utility · es_CO
> "Hola {{1}}, tu cita en Clínica Campbell quedó agendada para el {{2}} a las {{3}}. Si necesitas reprogramar, responde este mensaje."
> `{{1}}` nombre del contacto · `{{2}}` fecha · `{{3}}` hora

**`appointment_reminder`** · utility · es_CO
> "Hola {{1}}, te recordamos tu cita el {{2}} a las {{3}} en Clínica Campbell."
> `{{1}}` nombre del contacto · `{{2}}` fecha · `{{3}}` hora

**`appointment_reschedule`** · utility · es_CO
> "Hola {{1}}, tu cita fue reprogramada. Nueva fecha: {{2}} a las {{3}}."
> `{{1}}` nombre del contacto · `{{2}}` fecha · `{{3}}` hora

Categoría `utility` porque son transaccionales, no promocionales — es lo que Meta exige para este tipo de mensaje y evita que se traten con las restricciones (y costos) de plantillas de marketing.

### Envío: del worker de Celery a la Cloud API

Este endpoint no lo llama Flutter — lo dispara internamente el worker que procesa `reminders` vencidos.

```json
POST https://graph.facebook.com/v20.0/{phone_number_id}/messages
{
  "messaging_product": "whatsapp",
  "to": "573001234567",
  "type": "template",
  "template": {
    "name": "appointment_reminder",
    "language": { "code": "es_CO" },
    "components": [{
      "type": "body",
      "parameters": [
        { "type": "text", "text": "María" },
        { "type": "text", "text": "14 de julio" },
        { "type": "text", "text": "3:00 p.m." }
      ]
    }]
  }
}
```

La respuesta trae un `wamid` (message id de Meta) que se guarda en `notification_log.provider_message_id` para poder cruzarlo después con el webhook de estado.

### Webhook: verificación, firma y estados

Meta llama de vuelta a un único endpoint público, `/webhooks/whatsapp`, para tres cosas distintas:

- **Verificación (una sola vez, al configurar):** Meta hace `GET` con `hub.mode`, `hub.verify_token` y `hub.challenge`; el backend responde el `challenge` tal cual si el token coincide con el configurado.
- **Estados de entrega:** cada `POST` trae un arreglo `statuses` con `id` (el `wamid`), `status` (`sent` · `delivered` · `read` · `failed`) y `timestamp` — el backend hace match por `provider_message_id` y actualiza `notification_log`.
- **Mensajes entrantes:** si el contacto responde, llega como mensaje inbound — se registra en `notification_log` y notifica al usuario dueño de la actividad para que responda manualmente; no hay bot conversacional en el alcance actual.

> **No omitir:** todo `POST` a este webhook debe validarse con el header `X-Hub-Signature-256` (HMAC-SHA256 del cuerpo crudo con el app secret) antes de procesarlo. Sin esta validación, cualquiera que adivine la URL puede inyectar estados de entrega falsos.

### La ventana de 24 horas

Si el contacto escribió por su cuenta en las últimas 24 horas, el backend puede responder con texto libre. Fuera de esa ventana — el caso normal para confirmaciones y recordatorios que *inician* la conversación — el mensaje tiene que ser una plantilla aprobada. Como los tres flujos de OmniTask siempre inician la conversación, todo se envía como plantilla por defecto.

---

## §8 — Fase 3: Devices y scheduler de recordatorios

Dos piezas nuevas: `devices` guarda el token FCM de cada instalación de la app, y un par de tareas de Celery Beat convierten filas de `reminders` en notificaciones reales. Un detalle de concurrencia importa aquí más que en cualquier otra fase: si dos workers levantan el mismo recordatorio vencido, el usuario recibe el mismo aviso duplicado — o peor, paga dos veces el mismo mensaje de WhatsApp cuando llegue la fase 4.

### Endpoints de devices

| Método | Endpoint | Descripción |
|---|---|---|
| `POST` | `/devices` | Registra o reasigna un token FCM. Upsert por `fcm_token` (no por usuario): si el dispositivo se reinstala o cambia de cuenta, el token se reasigna y se actualiza `last_seen_at`. |
| `GET` | `/devices` | Dispositivos activos de la cuenta — pantalla de "sesiones activas". |
| `DELETE` | `/devices/{id}` | Cierra sesión de push en ese dispositivo. También se limpia automáticamente cuando Firebase responde `UnregisteredError`. |

```python
class Device(Base):
    __tablename__ = "devices"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id"), index=True)
    fcm_token: Mapped[str] = mapped_column(unique=True, index=True)
    platform: Mapped[str] = mapped_column(Enum("ios", "android", name="device_platform"))
    last_seen_at: Mapped[datetime] = mapped_column(server_default=func.now(), onupdate=func.now())

    user: Mapped["User"] = relationship(back_populates="devices")
```

> **Addendum a §3:** el enum `status` de `reminders` gana un cuarto valor: `pending · processing · sent · failed`. `processing` es lo que evita el doble envío.

### El scheduler: dos tareas de Celery Beat

```python
# celeryconfig.py
beat_schedule = {
    "dispatch-due-reminders": {
        "task": "app.tasks.dispatch_due_reminders",
        "schedule": 60.0,
    },
    "dispatch-unscheduled-digest": {
        "task": "app.tasks.dispatch_unscheduled_digest",
        "schedule": crontab(hour=8, minute=0),
    },
}
```

La segunda tarea es el resumen diario de actividades sin fecha de la fase 5 — se agenda desde ya porque comparte la misma infraestructura de Beat.

### Reclamar recordatorios vencidos sin duplicar envíos

El paso crítico es `SELECT ... FOR UPDATE SKIP LOCKED`: bloquea las filas que toma un worker para que otro worker (u otra ejecución solapada de la misma tarea) simplemente las salte en vez de esperarlas y reprocesarlas.

```python
@celery_app.task
def dispatch_due_reminders():
    with SessionLocal() as db:
        due = db.execute(
            select(Reminder)
            .where(Reminder.remind_at <= func.now(), Reminder.status == "pending")
            .with_for_update(skip_locked=True)
            .limit(200)
        ).scalars().all()

        ids = [r.id for r in due]
        for r in due:
            r.status = "processing"
        db.commit()

    for reminder_id in ids:
        send_reminder.delay(str(reminder_id))
```

La tarea por recordatorio hace el envío real y decide el canal. La rama de WhatsApp queda protegida por un feature flag hasta que la fase 4 esté desplegada — así la fase 3 se puede entregar y probar en producción sin depender de que Meta ya haya aprobado las plantillas.

```python
@celery_app.task(autoretry_for=(Exception,), retry_backoff=True, max_retries=5)
def send_reminder(reminder_id: str):
    with SessionLocal() as db:
        reminder = db.get(Reminder, reminder_id)
        activity = reminder.activity

        if reminder.channel in ("push", "both"):
            _send_push(db, activity)

        if reminder.channel in ("whatsapp", "both"):
            if settings.WHATSAPP_ENABLED:
                _send_whatsapp(activity.contact, activity, reminder.template_id)
            else:
                _log_deferred(db, reminder, reason="whatsapp_not_yet_live")

        reminder.status = "sent"
        reminder.sent_at = func.now()
        db.commit()


def _send_push(db, activity):
    for device in activity.user.devices:
        try:
            messaging.send(messaging.Message(
                notification=messaging.Notification(
                    title="Recordatorio",
                    body=f"{activity.title} - {activity.starts_at:%H:%M}",
                ),
                data={"activity_id": str(activity.id), "type": "reminder"},
                token=device.fcm_token,
            ))
        except messaging.UnregisteredError:
            db.delete(device)
```

Si `send_reminder` agota los 5 reintentos (backoff exponencial de Celery), el recordatorio queda en `processing` indefinidamente sin una salvaguarda explícita — por eso conviene un `on_failure` que lo marque `failed` y escriba el detalle en `notification_log` en vez de dejarlo colgado.

---

## §9 — Modelos concretos — Fase 1

SQLAlchemy 2.0 (estilo `Mapped`) para persistencia, Pydantic v2 para los esquemas de entrada/salida de la API. Solo las cuatro tablas que toca la fase 1: `users`, `contacts`, `activities` y `reminders` (esta última se escribe pero aún no se procesa — eso llega en la §8).

### SQLAlchemy

```python
class Base(DeclarativeBase):
    pass


class User(Base):
    __tablename__ = "users"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    full_name: Mapped[str]
    email: Mapped[str] = mapped_column(unique=True, index=True)
    password_hash: Mapped[str]
    phone_e164: Mapped[str]
    timezone: Mapped[str]
    role: Mapped[str] = mapped_column(
        Enum("admin", "professional", "assistant", name="user_role"),
        default="professional",
    )
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(server_default=func.now(), onupdate=func.now())

    contacts: Mapped[list["Contact"]] = relationship(back_populates="owner")
    activities: Mapped[list["Activity"]] = relationship(back_populates="user")
    devices: Mapped[list["Device"]] = relationship(back_populates="user")


class Contact(Base):
    __tablename__ = "contacts"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id"), index=True)
    full_name: Mapped[str]
    phone_e164: Mapped[str]
    notes: Mapped[str | None]

    owner: Mapped["User"] = relationship(back_populates="contacts")
    activities: Mapped[list["Activity"]] = relationship(back_populates="contact")


class Activity(Base):
    __tablename__ = "activities"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("users.id"), index=True)
    contact_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("contacts.id"), index=True)
    type: Mapped[str] = mapped_column(
        Enum("meeting", "appointment", "task", "activity", name="activity_type")
    )
    title: Mapped[str]
    description: Mapped[str | None]
    status: Mapped[str] = mapped_column(
        Enum("unscheduled", "scheduled", "completed", "cancelled", name="activity_status"),
        default="scheduled",
    )
    starts_at: Mapped[datetime | None] = mapped_column(index=True)
    ends_at: Mapped[datetime | None]
    timezone: Mapped[str]
    location: Mapped[str | None]
    nudge_frequency_days: Mapped[int | None]
    created_at: Mapped[datetime] = mapped_column(server_default=func.now())
    updated_at: Mapped[datetime] = mapped_column(server_default=func.now(), onupdate=func.now())

    user: Mapped["User"] = relationship(back_populates="activities")
    contact: Mapped["Contact | None"] = relationship(back_populates="activities")
    reminders: Mapped[list["Reminder"]] = relationship(
        back_populates="activity", cascade="all, delete-orphan"
    )


class Reminder(Base):
    __tablename__ = "reminders"

    id: Mapped[uuid.UUID] = mapped_column(primary_key=True, default=uuid.uuid4)
    activity_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("activities.id"), index=True)
    remind_at: Mapped[datetime] = mapped_column(index=True)
    channel: Mapped[str] = mapped_column(Enum("push", "whatsapp", "both", name="reminder_channel"))
    template_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("whatsapp_templates.id"))
    status: Mapped[str] = mapped_column(
        Enum("pending", "processing", "sent", "failed", name="reminder_status"),
        default="pending",
    )
    sent_at: Mapped[datetime | None]

    activity: Mapped["Activity"] = relationship(back_populates="reminders")
```

### Pydantic — esquemas de Activity

Estos son los que más lógica de validación cargan, porque `starts_at` nulo es un estado de primera clase, no una omisión.

```python
class ActivityBase(BaseModel):
    type: Literal["meeting", "appointment", "task", "activity"]
    title: str
    description: str | None = None
    contact_id: uuid.UUID | None = None
    starts_at: datetime | None = None
    ends_at: datetime | None = None
    location: str | None = None
    nudge_frequency_days: int | None = None


class ActivityCreate(ActivityBase):
    @field_validator("ends_at")
    @classmethod
    def ends_after_starts(cls, v: datetime | None, info: ValidationInfo) -> datetime | None:
        starts = info.data.get("starts_at")
        if v and starts and v <= starts:
            raise ValueError("ends_at debe ser posterior a starts_at")
        return v


class ActivityUpdate(BaseModel):
    title: str | None = None
    description: str | None = None
    starts_at: datetime | None = None
    ends_at: datetime | None = None
    status: Literal["unscheduled", "scheduled", "completed", "cancelled"] | None = None
    location: str | None = None


class ActivityRead(ActivityBase):
    id: uuid.UUID
    user_id: uuid.UUID
    status: Literal["unscheduled", "scheduled", "completed", "cancelled"]
    timezone: str
    created_at: datetime
    updated_at: datetime

    model_config = ConfigDict(from_attributes=True)
```

La regla que fuerza `status = "unscheduled"` cuando `starts_at` es `None` vive en el service layer (no en el schema): el schema solo valida forma, la decisión de negocio queda en un solo lugar junto con la generación automática de `reminders` descrita en la §6.

---

## §10 — Servicio de auth: hashing, JWT y refresh

Tres decisiones concretas: **argon2** en vez de bcrypt para el hash, **refresh tokens de un solo uso** (rotación) en vez de reutilizables, y un `jti` por token que vive en Redis para poder revocar antes de que expire por sí solo.

### Hashing de contraseñas

Argon2 no tiene el límite de 72 bytes de bcrypt y es la recomendación actual de OWASP para contraseñas nuevas.

```python
# core/security.py
from passlib.context import CryptContext

pwd_context = CryptContext(schemes=["argon2"], deprecated="auto")

def hash_password(password: str) -> str:
    return pwd_context.hash(password)

def verify_password(password: str, password_hash: str) -> bool:
    return pwd_context.verify(password, password_hash)
```

### Emitir tokens

Cada token lleva `type` (para que un refresh token no pueda usarse donde se espera un access token) y `jti` (identificador único, la pieza que permite revocar).

```python
ACCESS_TOKEN_TTL = timedelta(minutes=15)
REFRESH_TOKEN_TTL = timedelta(days=30)

def _create_token(user_id: uuid.UUID, token_type: str, ttl: timedelta) -> tuple[str, str]:
    jti = str(uuid.uuid4())
    now = datetime.now(timezone.utc)
    payload = {
        "sub": str(user_id),
        "type": token_type,
        "jti": jti,
        "iat": now,
        "exp": now + ttl,
    }
    token = jwt.encode(payload, settings.JWT_SECRET, algorithm="HS256")
    return token, jti

def create_access_token(user_id: uuid.UUID) -> str:
    token, _ = _create_token(user_id, "access", ACCESS_TOKEN_TTL)
    return token

def create_refresh_token(user_id: uuid.UUID) -> tuple[str, str]:
    return _create_token(user_id, "refresh", REFRESH_TOKEN_TTL)
```

### Por qué el refresh token vive también en Redis

El JWT por sí solo es válido hasta su `exp` aunque el usuario cierre sesión — no hay forma de "borrarlo" del lado del cliente de forma confiable. Guardar el `jti` en Redis con el mismo TTL da un punto de revocación real: `logout` borra la llave, y a partir de ahí el token deja de servir aunque su firma siga siendo válida.

```python
# core/redis.py
def store_refresh_jti(user_id: uuid.UUID, jti: str, ttl: timedelta) -> None:
    redis.set(f"refresh:{jti}", str(user_id), ex=int(ttl.total_seconds()))

def is_refresh_valid(jti: str) -> bool:
    return redis.exists(f"refresh:{jti}") == 1

def revoke_refresh(jti: str) -> None:
    redis.delete(f"refresh:{jti}")
```

### Login, refresh con rotación y logout

Cada `/auth/refresh` exitoso revoca el refresh token que se acaba de usar y emite uno nuevo. Un refresh token nunca se reutiliza — si alguien lo intenta usar dos veces (por ejemplo, uno robado que el atacante reutiliza después de que el usuario legítimo ya refrescó), la segunda llamada ya no lo encuentra en Redis y falla.

```python
@router.post("/auth/login", response_model=TokenPair)
def login(payload: LoginRequest, db: Session = Depends(get_db)):
    user = db.scalar(select(User).where(User.email == payload.email))
    if not user or not verify_password(payload.password, user.password_hash):
        raise HTTPException(401, detail="Credenciales inválidas")

    access_token = create_access_token(user.id)
    refresh_token, refresh_jti = create_refresh_token(user.id)
    store_refresh_jti(user.id, refresh_jti, REFRESH_TOKEN_TTL)
    return TokenPair(access_token=access_token, refresh_token=refresh_token)


@router.post("/auth/refresh", response_model=TokenPair)
def refresh(payload: RefreshRequest):
    try:
        claims = jwt.decode(payload.refresh_token, settings.JWT_SECRET, algorithms=["HS256"])
    except jwt.PyJWTError:
        raise HTTPException(401, detail="Token inválido")

    if claims["type"] != "refresh" or not is_refresh_valid(claims["jti"]):
        raise HTTPException(401, detail="Sesión expirada, inicia sesión de nuevo")

    revoke_refresh(claims["jti"])  # de un solo uso: revocar antes de emitir el reemplazo

    user_id = uuid.UUID(claims["sub"])
    access_token = create_access_token(user_id)
    new_refresh_token, new_jti = create_refresh_token(user_id)
    store_refresh_jti(user_id, new_jti, REFRESH_TOKEN_TTL)
    return TokenPair(access_token=access_token, refresh_token=new_refresh_token)


@router.post("/auth/logout")
def logout(payload: RefreshRequest):
    claims = jwt.decode(payload.refresh_token, settings.JWT_SECRET, algorithms=["HS256"])
    revoke_refresh(claims["jti"])
    return {"detail": "Sesión cerrada"}
```

### Dependencia para rutas protegidas

```python
# deps.py
bearer_scheme = HTTPBearer()

def get_current_user(
    credentials: HTTPAuthorizationCredentials = Depends(bearer_scheme),
    db: Session = Depends(get_db),
) -> User:
    try:
        claims = jwt.decode(credentials.credentials, settings.JWT_SECRET, algorithms=["HS256"])
    except jwt.PyJWTError:
        raise HTTPException(401, detail="Token inválido o expirado")

    if claims.get("type") != "access":
        raise HTTPException(401, detail="Se requiere un access token")

    user = db.get(User, uuid.UUID(claims["sub"]))
    if user is None:
        raise HTTPException(401, detail="Usuario no encontrado")
    return user
```

Cada router de la §6 (`activities`, `contacts`, `devices`) declara `user: User = Depends(get_current_user)` y filtra siempre por `user.id` — nunca por un `user_id` que venga en el body o en la URL, para que un usuario no pueda leer ni modificar datos de otro simplemente cambiando un id.

> **Endurecimiento opcional, no bloqueante:** si `is_refresh_valid` falla pero el `jti` corresponde a un token ya usado (no solo expirado), es señal de un posible robo de token — vale la pena, más adelante, revocar todas las sesiones del usuario en ese caso en vez de solo rechazar la llamada. No es necesario para el lanzamiento inicial.

---

## §11 — Estructura del proyecto FastAPI

La idea central: los routers son delgados y solo orquestan; toda la lógica de negocio (generar `reminders` al crear una actividad, decidir el canal de un recordatorio) vive en `services/` — así el mismo código lo usan tanto un endpoint HTTP como una tarea de Celery, sin reescribirlo dos veces.

```
backend/
├── app/
│   ├── main.py                    # crea la app, monta routers, CORS, eventos de startup
│   ├── config.py                  # Settings (pydantic-settings) desde variables de entorno
│   ├── database.py                # engine, SessionLocal, dependencia get_db
│   │
│   ├── models/                    # SQLAlchemy — un archivo por tabla
│   │   ├── user.py
│   │   ├── contact.py
│   │   ├── activity.py
│   │   ├── reminder.py
│   │   ├── device.py
│   │   └── whatsapp_template.py
│   │
│   ├── schemas/                   # Pydantic — espejo de models/, nunca se importa desde ahí
│   │   ├── auth.py                 # LoginRequest, RefreshRequest, TokenPair
│   │   ├── activity.py
│   │   ├── contact.py
│   │   └── device.py
│   │
│   ├── api/v1/
│   │   ├── router.py               # agrupa los sub-routers bajo /api/v1
│   │   ├── auth.py
│   │   ├── activities.py
│   │   ├── contacts.py
│   │   └── devices.py
│   │
│   ├── services/                   # lógica de negocio — la reutilizan API y Celery por igual
│   │   ├── auth_service.py          # hash, verify, create/rotate tokens
│   │   ├── activity_service.py      # crea/regenera reminders al crear o reprogramar
│   │   └── notification_service.py  # arma y envía push / whatsapp, escribe notification_log
│   │
│   ├── tasks/                      # Celery — llaman a services/, no reimplementan lógica
│   │   ├── celery_app.py
│   │   ├── reminders.py             # dispatch_due_reminders, send_reminder
│   │   └── digest.py                # dispatch_unscheduled_digest (fase 5)
│   │
│   ├── core/
│   │   ├── security.py              # hash_password, create_access_token, etc.
│   │   └── redis.py                 # cliente redis + store/is_valid/revoke de refresh
│   │
│   └── deps.py                     # get_current_user, paginación común
│
├── alembic/
│   ├── versions/
│   └── env.py
│
├── tests/
│   ├── conftest.py                 # DB de test, fixtures de usuario autenticado
│   ├── test_auth.py
│   └── test_activities.py
│
├── alembic.ini
├── pyproject.toml
└── docker-compose.yml              # postgres · redis · api · celery worker · celery beat
```

Tres reglas que mantienen esto ordenado a medida que crece:

- **Los routers no tocan SQLAlchemy directamente** más allá de una consulta simple de lectura; cualquier escritura con reglas de negocio (crear una actividad, reprogramarla) pasa por `services/`.
- **`tasks/reminders.py` llama a `notification_service`**, el mismo módulo que usaría un futuro endpoint de "reenviar notificación manualmente" — el canal de entrega (push, WhatsApp) nunca se decide dos veces en dos archivos distintos.
- **`schemas/` nunca importa de `models/`** ni al revés; lo que los conecta es siempre un router o un service, para que un cambio de forma en la API no obligue a tocar el ORM y viceversa.

`docker-compose.yml` arranca los cinco procesos que corren en paralelo incluso en desarrollo local, porque el flujo de recordatorios no se puede probar de verdad con solo la API arriba:

```yaml
services:
  api:
    build: .
    command: uvicorn app.main:app --reload --host 0.0.0.0
    depends_on: [postgres, redis]

  worker:
    build: .
    command: celery -A app.tasks.celery_app worker --loglevel=info
    depends_on: [postgres, redis]

  beat:
    build: .
    command: celery -A app.tasks.celery_app beat --loglevel=info
    depends_on: [redis]

  postgres:
    image: postgres:16
  redis:
    image: redis:7
```

---

## §12 — Frontend Flutter: Riverpod y vistas de calendario

Riverpod 2 con generación de código (`@riverpod`), un provider por responsabilidad, y los repositorios como única puerta hacia el backend — ningún widget llama a `Dio` directamente. La pieza que conecta todo con las fases anteriores: la vista de calendario nunca dibuja actividades sin fecha, porque para eso existe la pantalla de backlog.

### Dependencias clave

| Paquete | Para qué |
|---|---|
| flutter_riverpod / riverpod_annotation | estado y DI, con codegen (`build_runner`) |
| dio | cliente HTTP + interceptores |
| freezed / json_serializable | modelos inmutables espejo de los schemas Pydantic de la §9 |
| go_router | navegación declarativa + deep link desde push |
| syncfusion_flutter_calendar | vistas día/semana/mes |
| firebase_messaging | token FCM y manejo del tap en la notificación |
| flutter_secure_storage | access/refresh token en el dispositivo |

### Estructura de `lib/`

```
lib/
├── main.dart                        # ProviderScope, Firebase.initializeApp, MaterialApp.router
├── core/
│   ├── network/dio_client.dart       # Dio + interceptor de auth y refresh
│   ├── storage/secure_token_storage.dart
│   └── router/app_router.dart        # go_router + deep link desde push
│
├── features/
│   ├── auth/
│   │   ├── data/auth_repository.dart
│   │   ├── application/auth_notifier.dart      # AsyncNotifier<AuthState>
│   │   └── presentation/login_screen.dart
│   │
│   ├── calendar/
│   │   ├── data/activity_repository.dart
│   │   ├── application/
│   │   │   ├── visible_range_provider.dart      # rango visible del calendario
│   │   │   └── activities_for_range_provider.dart
│   │   └── presentation/
│   │       ├── calendar_screen.dart              # SfCalendar día/semana/mes
│   │       └── activity_detail_screen.dart
│   │
│   ├── backlog/
│   │   ├── application/unscheduled_activities_provider.dart
│   │   └── presentation/backlog_screen.dart
│   │
│   └── notifications/
│       └── application/device_registration_notifier.dart
│
└── models/
    ├── activity.dart                  # freezed, espejo de ActivityRead (§9)
    └── auth_tokens.dart
```

### Modelo — espejo de `ActivityRead`

```dart
@freezed
class Activity with _$Activity {
  const factory Activity({
    required String id,
    required String type,
    required String title,
    String? description,
    String? contactId,
    DateTime? startsAt,
    DateTime? endsAt,
    required String status,
    String? location,
    required String timezone,
  }) = _Activity;

  factory Activity.fromJson(Map<String, dynamic> json) => _$ActivityFromJson(json);
}
```

`startsAt` nullable en el modelo Dart, igual que en la BD y en el schema Pydantic — la ausencia de fecha viaja intacta por las tres capas en vez de convertirse en un valor centinela en algún punto intermedio.

### Cliente HTTP: el interceptor habla con el auth de la §10

Cuando el backend responde 401, el interceptor no reintenta a ciegas: dispara el mismo flujo de `/auth/refresh` (rotación incluida) y solo reintenta la petición original si el refresh tuvo éxito.

```dart
class DioClient {
  DioClient(this._ref) {
    _dio.interceptors.add(
      InterceptorsWrapper(
        onRequest: (options, handler) async {
          final token = await _ref.read(secureTokenStorageProvider).readAccessToken();
          if (token != null) options.headers['Authorization'] = 'Bearer $token';
          handler.next(options);
        },
        onError: (error, handler) async {
          if (error.response?.statusCode == 401) {
            final refreshed = await _ref.read(authNotifierProvider.notifier).refreshSession();
            if (refreshed) {
              final retryRequest = await _dio.fetch(error.requestOptions);
              return handler.resolve(retryRequest);
            }
          }
          handler.next(error);
        },
      ),
    );
  }

  final Ref _ref;
  final Dio _dio = Dio(BaseOptions(baseUrl: ApiConfig.baseUrl));

  Dio get instance => _dio;
}

final dioClientProvider = Provider((ref) => DioClient(ref).instance);
```

### Repositorio de actividades

```dart
class ActivityRepository {
  ActivityRepository(this._dio);
  final Dio _dio;

  Future<List<Activity>> fetchActivities({
    required DateTime from,
    required DateTime to,
    String? type,
    String? status,
  }) async {
    final response = await _dio.get('/activities', queryParameters: {
      'from': from.toUtc().toIso8601String(),
      'to': to.toUtc().toIso8601String(),
      if (type != null) 'type': type,
      if (status != null) 'status': status,
    });
    return (response.data['items'] as List)
        .map((json) => Activity.fromJson(json))
        .toList();
  }

  Future<List<Activity>> fetchUnscheduled() async {
    final response = await _dio.get('/activities/unscheduled');
    return (response.data['items'] as List).map((j) => Activity.fromJson(j)).toList();
  }
}

final activityRepositoryProvider =
    Provider((ref) => ActivityRepository(ref.watch(dioClientProvider)));
```

### Providers: el rango visible maneja lo que se pide

`activitiesForRange` no tiene lógica propia de cuándo refrescar: simplemente observa `visibleRangeProvider`, y Riverpod recalcula solo cuando ese rango cambia.

```dart
@riverpod
class VisibleRange extends _$VisibleRange {
  @override
  DateTimeRange build() => _weekRangeContaining(DateTime.now());

  void setRange(DateTimeRange range) => state = range;
}

@riverpod
Future<List<Activity>> activitiesForRange(ActivitiesForRangeRef ref) {
  final range = ref.watch(visibleRangeProvider);
  final repo = ref.watch(activityRepositoryProvider);
  return repo.fetchActivities(from: range.start, to: range.end);
}
```

### Vista de calendario (Syncfusion, día/semana/mes)

El `DataSource` filtra por `startsAt != null` como salvaguarda explícita: una actividad sin fecha en la grilla del calendario sería un bug visible de inmediato.

```dart
class CalendarScreen extends ConsumerWidget {
  const CalendarScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activitiesAsync = ref.watch(activitiesForRangeProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Agenda'), actions: [
        IconButton(
          icon: const Icon(Icons.inbox_outlined),
          onPressed: () => context.push('/backlog'),
        ),
      ]),
      body: activitiesAsync.when(
        data: (activities) => SfCalendar(
          view: CalendarView.week,
          dataSource: _ActivityDataSource(activities),
          onViewChanged: (details) {
            final range = DateTimeRange(
              start: details.visibleDates.first,
              end: details.visibleDates.last,
            );
            ref.read(visibleRangeProvider.notifier).setRange(range);
          },
          onTap: (details) {
            final activity = details.appointments?.first as Activity?;
            if (activity != null) context.push('/activities/${activity.id}');
          },
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, _) => ErrorRetryView(onRetry: () => ref.invalidate(activitiesForRangeProvider)),
      ),
    );
  }
}

class _ActivityDataSource extends CalendarDataSource {
  _ActivityDataSource(List<Activity> activities) {
    appointments = activities.where((a) => a.startsAt != null).toList();
  }

  @override
  DateTime getStartTime(int index) => (appointments![index] as Activity).startsAt!;

  @override
  DateTime getEndTime(int index) =>
      (appointments![index] as Activity).endsAt ?? getStartTime(index).add(const Duration(minutes: 30));

  @override
  String getSubject(int index) => (appointments![index] as Activity).title;
}
```

### Backlog de actividades sin fecha

```dart
@riverpod
Future<List<Activity>> unscheduledActivities(UnscheduledActivitiesRef ref) {
  return ref.watch(activityRepositoryProvider).fetchUnscheduled();
}

class BacklogScreen extends ConsumerWidget {
  const BacklogScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final backlogAsync = ref.watch(unscheduledActivitiesProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Pendientes por programar')),
      body: backlogAsync.when(
        data: (items) => ListView.builder(
          itemCount: items.length,
          itemBuilder: (context, i) => ListTile(
            title: Text(items[i].title),
            subtitle: Text(items[i].description ?? ''),
            trailing: TextButton(
              child: const Text('Programar'),
              onPressed: () => context.push('/activities/${items[i].id}/schedule'),
            ),
          ),
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorRetryView(onRetry: () => ref.invalidate(unscheduledActivitiesProvider)),
      ),
    );
  }
}
```

"Programar" navega a la misma pantalla de edición de actividad, no a una nueva — asignar una fecha por primera vez y reprogramar una ya existente son, a propósito, el mismo flujo de `PATCH /activities/{id}`.

### Registro de dispositivo y deep link desde el push

Conecta directo con la §8: el token FCM se registra contra `POST /devices` justo después del login, y el payload `{"activity_id", "type": "reminder"}` que arma `_send_push` en el backend es lo que `go_router` usa para saltar directo al detalle.

```dart
@riverpod
class DeviceRegistration extends _$DeviceRegistration {
  @override
  FutureOr<void> build() {}

  Future<void> registerCurrentDevice() async {
    final token = await FirebaseMessaging.instance.getToken();
    if (token == null) return;
    final platform = Platform.isIOS ? 'ios' : 'android';
    await ref.read(deviceRepositoryProvider).register(fcmToken: token, platform: platform);
  }
}
```

```dart
// core/router/app_router.dart
FirebaseMessaging.onMessageOpenedApp.listen((message) {
  final activityId = message.data['activity_id'];
  if (activityId != null) router.push('/activities/$activityId');
});

FirebaseMessaging.instance.getInitialMessage().then((message) {
  final activityId = message?.data['activity_id'];
  if (activityId != null) router.push('/activities/$activityId');
});
```

Las dos suscripciones cubren los dos casos reales: `onMessageOpenedApp` cuando la app ya estaba en segundo plano, y `getInitialMessage` cuando el tap en la notificación es lo que abre la app desde cero (cold start) — omitir la segunda es el bug clásico de "el deep link solo funciona a veces".

---

## §13 — CI/CD — Fase 7

Un principio gobierna todo el pipeline: **la imagen que corre en producción es exactamente la misma que se probó en staging** — nunca se reconstruye para "promoverla". Lo que cambia entre ambientes es la configuración (variables de entorno, secretos), no el artefacto.

`PR abierto (lint + tests)` → `Merge a main (build + push imagen)` → `Deploy staging (automático)` → `Se crea tag vX.Y.Z` → `Aprobación manual (GitHub Environment)` → `Deploy producción (misma imagen, sin rebuild)`

### Backend — CI en cada pull request

Corre contra Postgres y Redis reales como *service containers*, no mocks — para este proyecto en particular, donde la corrección depende de `TIMESTAMPTZ` y de `SELECT ... FOR UPDATE SKIP LOCKED` (§8), probar contra un Postgres real no es opcional.

```yaml
# .github/workflows/ci.yml
name: CI
on:
  pull_request:
    paths: ["backend/**"]

jobs:
  test:
    runs-on: ubuntu-latest
    services:
      postgres:
        image: postgres:16
        env:
          POSTGRES_PASSWORD: test
          POSTGRES_DB: omnitask_test
        ports: ["5432:5432"]
        options: >-
          --health-cmd="pg_isready" --health-interval=5s --health-retries=5
      redis:
        image: redis:7
        ports: ["6379:6379"]
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-python@v5
        with: { python-version: "3.12" }
      - run: pip install poetry && poetry install
      - run: poetry run ruff check .
      - run: poetry run alembic upgrade head
        env:
          DATABASE_URL: postgresql://postgres:test@localhost:5432/omnitask_test
      - run: poetry run pytest --cov=app
        env:
          DATABASE_URL: postgresql://postgres:test@localhost:5432/omnitask_test
          REDIS_URL: redis://localhost:6379/0
```

### Backend — deploy automático a staging

Se ejecuta al hacer merge a `main`. Construye la imagen una sola vez, corre las migraciones antes de intercambiar el tráfico, y valida con un smoke test contra `/healthz` antes de dar por buena la corrida.

```yaml
# .github/workflows/cd-staging.yml
name: Deploy staging
on:
  push:
    branches: [main]
    paths: ["backend/**"]

jobs:
  build-and-push:
    runs-on: ubuntu-latest
    permissions: { contents: read, packages: write }
    steps:
      - uses: actions/checkout@v4
      - uses: docker/login-action@v3
        with:
          registry: ghcr.io
          username: ${{ github.actor }}
          password: ${{ secrets.GITHUB_TOKEN }}
      - uses: docker/build-push-action@v5
        with:
          context: backend
          push: true
          tags: ghcr.io/clinicacampbell/omnitask-api:${{ github.sha }}

  deploy:
    needs: build-and-push
    runs-on: ubuntu-latest
    environment: staging
    steps:
      - name: Migraciones
        run: ssh deploy@staging "docker run --rm --env-file /etc/omnitask/staging.env ghcr.io/clinicacampbell/omnitask-api:${{ github.sha }} alembic upgrade head"
      - name: Roll out
        run: ssh deploy@staging "cd /srv/omnitask && IMAGE_TAG=${{ github.sha }} docker compose up -d --no-deps api worker beat"
      - name: Smoke test
        run: curl --fail https://staging-api.omnitask.clinicacampbell.com.co/healthz
```

### Backend — promoción a producción (sin rebuild)

`github.sha` en un push de tag es el commit al que apunta ese tag — el mismo commit que ya se construyó y probó en staging. Por eso este workflow no tiene paso de build: reutiliza `ghcr.io/.../omnitask-api:${{ github.sha }}` tal cual. El `environment: production` con revisor obligatorio configurado en GitHub es el único gate manual de todo el pipeline.

```yaml
# .github/workflows/cd-production.yml
name: Deploy production
on:
  push:
    tags: ["v*.*.*"]

jobs:
  deploy:
    runs-on: ubuntu-latest
    environment: production   # requiere aprobación manual (regla de protección del environment)
    steps:
      - name: Backup antes de migrar
        run: ssh deploy@prod "pg_dump -Fc omnitask > /backups/omnitask-$(date +%Y%m%d%H%M).dump"
      - name: Migraciones
        run: ssh deploy@prod "docker run --rm --env-file /etc/omnitask/prod.env ghcr.io/clinicacampbell/omnitask-api:${{ github.sha }} alembic upgrade head"
      - name: Roll out
        run: ssh deploy@prod "cd /srv/omnitask && IMAGE_TAG=${{ github.sha }} docker compose up -d --no-deps api worker beat"
      - name: Smoke test
        run: curl --fail https://api.omnitask.clinicacampbell.com.co/healthz
```

> **Migraciones seguras de rollback:** si un despliegue falla el smoke test, el rollback es redesplegar el `IMAGE_TAG` anterior — pero eso solo funciona si las migraciones son compatibles hacia atrás por al menos un release (patrón expand/contract: agregar columnas nullable primero, dejar de escribir a las viejas en un release siguiente, borrarlas en un tercero). Nunca un `DROP COLUMN` en el mismo release que deja de usarla.

### Flutter — CI en cada pull request

```yaml
# .github/workflows/flutter-ci.yml
name: Flutter CI
on:
  pull_request:
    paths: ["mobile/**"]

jobs:
  analyze:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with: { flutter-version: "3.24.0", channel: "stable" }
      - run: flutter pub get
      - run: dart run build_runner build --delete-conflicting-outputs
      - run: flutter analyze
      - run: flutter test
```

### Flutter — release a las tiendas

Para firmar y publicar en las stores, en particular iOS, conviene **Codemagic** (o Bitrise) en vez de forzar runners macOS de GitHub Actions: manejan certificados, provisioning profiles y la subida a TestFlight/Play Console con mucho menos fricción que armarlo a mano con fastlane sobre GH Actions.

```yaml
# codemagic.yaml
workflows:
  release:
    name: OmniTask release
    triggering:
      events: [tag]
      tag_patterns: ["v*.*.*"]
    environment:
      flutter: stable
      groups: [app_store_credentials, play_store_credentials]
    scripts:
      - flutter pub get
      - dart run build_runner build --delete-conflicting-outputs
      - flutter build appbundle --release
      - flutter build ipa --release
    artifacts:
      - build/**/outputs/**/*.aab
      - build/ios/ipa/*.ipa
    publishing:
      google_play:
        credentials: $GCLOUD_SERVICE_ACCOUNT_CREDENTIALS
        track: internal
      app_store_connect:
        api_key: $APP_STORE_CONNECT_PRIVATE_KEY
        submit_to_testflight: true
```

El mismo tag `v*.*.*` dispara tanto el deploy del backend como el build móvil — versión de API y versión de app avanzan juntas, evitando que la app en las stores le hable a un backend con un contrato distinto.

### Observabilidad mínima para no volar a ciegas

- **`GET /healthz`** — verifica conexión a Postgres y Redis; lo usan tanto el smoke test del pipeline como el readiness probe del orquestador.
- **Logs estructurados** (JSON, `structlog`) con un `request_id` por petición, para poder seguir una sola llamada a través de API → Celery → webhook de Meta.
- **Métricas Prometheus**: latencia y tasa de error de la API (`prometheus-fastapi-instrumentator`), profundidad de la cola de Celery, y tasa de éxito/fallo por canal en `notification_log`.
- **Alertas** a Slack/PagerDuty: cola de recordatorios acumulada por más de 5 minutos (síntoma de que un worker está caído), tasa de fallos de WhatsApp por encima de un umbral, o un smoke test de despliegue que falla.

Esto no es exhaustivo — es lo mínimo con lo que una notificación de cita perdida se detecta en minutos y no cuando un paciente llama a preguntar por qué nunca le llegó el recordatorio.

---

## §14 — Pantallas de detalle y edición de actividad

Dos pantallas, no tres: **detalle** (solo lectura, con acciones) y **edición** (un único formulario que sirve para crear, editar y "programar" una actividad sin fecha). Reutilizar el mismo formulario para esos tres casos es intencional — asignar fecha por primera vez y reprogramar son, para el backend de la §6, el mismo `PATCH`.

> **Nota de consistencia con la §12:** la pantalla de backlog navegaba a `/activities/{id}/schedule`. Con el formulario ya definido aquí, esa ruta se colapsa en la misma `/activities/{id}/edit` — una sola pantalla de edición, sin una tercera ruta que hacía exactamente lo mismo con otro nombre.

### Rutas

```dart
GoRoute(
  path: '/activities/new',
  builder: (context, state) => const ActivityEditScreen(),
),
GoRoute(
  path: '/activities/:id',
  builder: (context, state) =>
      ActivityDetailScreen(activityId: state.pathParameters['id']!),
),
GoRoute(
  path: '/activities/:id/edit',
  builder: (context, state) =>
      ActivityEditScreen(activityId: state.pathParameters['id']),
),
```

### Modelo: los recordatorios llegan embebidos en el detalle

`GET /activities/{id}` (§6) trae los `reminders` embebidos — la pantalla de detalle no dispara una segunda llamada para mostrarlos. El modelo `Activity` de la §12 gana un campo más para eso.

```dart
@freezed
class ReminderSummary with _$ReminderSummary {
  const factory ReminderSummary({
    required String id,
    required DateTime remindAt,
    required String channel,
    required String status,
  }) = _ReminderSummary;

  factory ReminderSummary.fromJson(Map<String, dynamic> json) =>
      _$ReminderSummaryFromJson(json);
}

// Activity (§12) agrega:
// @Default(<ReminderSummary>[]) List<ReminderSummary> reminders,
```

### Provider y repositorio: traer una sola actividad

```dart
Future<Activity> fetchById(String id) async {
  final response = await _dio.get('/activities/$id');
  return Activity.fromJson(response.data);
}
```

```dart
@riverpod
Future<Activity> activityDetail(ActivityDetailRef ref, String activityId) {
  return ref.watch(activityRepositoryProvider).fetchById(activityId);
}
```

### Pantalla de detalle

Si `startsAt` es `null`, no se intenta formatear una fecha que no existe: se muestra el mismo banner de "pendiente por programar" que ya usa el backlog de la §12, con el mismo destino de navegación.

```dart
class ActivityDetailScreen extends ConsumerWidget {
  const ActivityDetailScreen({super.key, required this.activityId});
  final String activityId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activityAsync = ref.watch(activityDetailProvider(activityId));

    return Scaffold(
      appBar: AppBar(title: const Text('Detalle')),
      body: activityAsync.when(
        data: (activity) => _DetailBody(activity: activity),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) =>
            ErrorRetryView(onRetry: () => ref.invalidate(activityDetailProvider(activityId))),
      ),
      floatingActionButton: activityAsync.maybeWhen(
        data: (activity) => FloatingActionButton.extended(
          icon: const Icon(Icons.edit_outlined),
          label: Text(activity.startsAt == null ? 'Programar' : 'Editar'),
          onPressed: () => context.push('/activities/$activityId/edit'),
        ),
        orElse: () => null,
      ),
    );
  }
}
```

El cuerpo separa lo que es información de lo que dispara una acción — el estado (`status`) se muestra como un chip, no como texto plano, porque es lo primero que alguien necesita leer de un vistazo.

```dart
class _DetailBody extends StatelessWidget {
  const _DetailBody({required this.activity});
  final Activity activity;

  @override
  Widget build(BuildContext context) {
    final localFormat = DateFormat('EEEE d MMM · HH:mm', 'es_CO');

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _StatusChip(status: activity.status),
        Text(activity.title, style: Theme.of(context).textTheme.headlineSmall),
        if (activity.startsAt != null)
          Text(localFormat.format(activity.startsAt!.toLocal()))
        else
          _UnscheduledBanner(activityId: activity.id),
        if (activity.location != null) Text(activity.location!),
        if (activity.contactId != null) _ContactCard(contactId: activity.contactId!),
        const Divider(),
        _RemindersList(reminders: activity.reminders),
        const Divider(),
        _ActionRow(activity: activity),
      ],
    );
  }
}
```

### Acciones: completar y cancelar pasan por el mismo `PATCH`

Cancelar es destructivo para los recordatorios pendientes (se cancelan sin enviarse, según la regla de la §6), así que pide confirmación explícita antes de disparar la llamada.

```dart
@riverpod
class ActivityActionsController extends _$ActivityActionsController {
  @override
  FutureOr<void> build(String activityId) {}

  Future<void> markCompleted() => _patch({'status': 'completed'});
  Future<void> cancel() => _patch({'status': 'cancelled'});

  Future<void> _patch(Map<String, dynamic> body) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      await ref.read(activityRepositoryProvider).update(activityId, body);
      ref.invalidate(activityDetailProvider(activityId));
      ref.invalidate(activitiesForRangeProvider);
      ref.invalidate(unscheduledActivitiesProvider);
    });
  }
}
```

```dart
class _ActionRow extends ConsumerWidget {
  const _ActionRow({required this.activity});
  final Activity activity;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller =
        ref.watch(activityActionsControllerProvider(activity.id).notifier);

    return Wrap(spacing: 12, children: [
      if (activity.status != 'completed')
        FilledButton.tonal(
          onPressed: controller.markCompleted,
          child: const Text('Marcar como completada'),
        ),
      if (activity.status != 'cancelled')
        OutlinedButton(
          onPressed: () => _confirmCancel(context, controller),
          child: const Text('Cancelar'),
        ),
    ]);
  }

  Future<void> _confirmCancel(
    BuildContext context,
    ActivityActionsController controller,
  ) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('¿Cancelar esta actividad?'),
        content: const Text('Los recordatorios pendientes no se enviarán.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Volver'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Cancelar actividad'),
          ),
        ],
      ),
    );
    if (confirmed == true) controller.cancel();
  }
}
```

Deliberadamente no hay botón de "eliminar": la §6 ya define que el `DELETE` es un soft delete idéntico a cancelar (`status = "cancelled"`), así que exponer los dos como acciones separadas solo confundiría sin agregar capacidad real.

### Formulario único: crear, editar y "programar"

El estado del formulario (controladores de texto, fecha seleccionada) es estado efímero de UI — vive en un `State` normal de Flutter, no en Riverpod. Solo el *envío* (la llamada HTTP y su resultado) pasa por un provider, porque eso sí necesita sobrevivir a rebuilds y comunicar éxito/error al resto de la app.

```dart
class ActivityEditScreen extends ConsumerStatefulWidget {
  const ActivityEditScreen({super.key, this.activityId});
  final String? activityId;

  @override
  ConsumerState<ActivityEditScreen> createState() => _ActivityEditScreenState();
}

class _ActivityEditScreenState extends ConsumerState<ActivityEditScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();
  String _type = 'appointment';
  String? _contactId;
  bool _hasDate = true;
  DateTime? _startsAt;
  DateTime? _endsAt;

  @override
  void initState() {
    super.initState();
    final existing = widget.activityId == null
        ? null
        : ref.read(activityDetailProvider(widget.activityId!)).valueOrNull;
    if (existing != null) {
      _titleController.text = existing.title;
      _descriptionController.text = existing.description ?? '';
      _type = existing.type;
      _contactId = existing.contactId;
      _hasDate = existing.startsAt != null;
      _startsAt = existing.startsAt?.toLocal();
      _endsAt = existing.endsAt?.toLocal();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEditing = widget.activityId != null;

    return Scaffold(
      appBar: AppBar(title: Text(isEditing ? 'Editar actividad' : 'Nueva actividad')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            DropdownButtonFormField<String>(
              value: _type,
              items: const [
                DropdownMenuItem(value: 'meeting', child: Text('Reunión')),
                DropdownMenuItem(value: 'appointment', child: Text('Cita')),
                DropdownMenuItem(value: 'task', child: Text('Tarea')),
                DropdownMenuItem(value: 'activity', child: Text('Actividad')),
              ],
              onChanged: (value) => setState(() => _type = value!),
              decoration: const InputDecoration(labelText: 'Tipo'),
            ),
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Título'),
              validator: (v) =>
                  (v == null || v.trim().isEmpty) ? 'El título es obligatorio' : null,
            ),
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(labelText: 'Descripción'),
              maxLines: 3,
            ),
            ContactPickerField(
              selectedContactId: _contactId,
              onChanged: (id) => setState(() => _contactId = id),
            ),
            SwitchListTile(
              title: const Text('Sin fecha por ahora'),
              subtitle: const Text('Se guarda como pendiente por programar'),
              value: !_hasDate,
              onChanged: (noDate) => setState(() => _hasDate = !noDate),
            ),
            if (_hasDate) ...[
              _DateTimeField(
                label: 'Inicio',
                value: _startsAt,
                onChanged: (value) => setState(() => _startsAt = value),
              ),
              _DateTimeField(
                label: 'Fin',
                value: _endsAt,
                onChanged: (value) => setState(() => _endsAt = value),
              ),
            ],
          ],
        ),
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: FilledButton(
            onPressed: _submit,
            child: Text(isEditing ? 'Guardar cambios' : 'Crear'),
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (_hasDate &&
        _startsAt != null &&
        _endsAt != null &&
        !_endsAt!.isAfter(_startsAt!)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('La hora de fin debe ser posterior al inicio')),
      );
      return;
    }

    final draft = ActivityDraft(
      type: _type,
      title: _titleController.text.trim(),
      description: _descriptionController.text.trim().isEmpty
          ? null
          : _descriptionController.text.trim(),
      contactId: _contactId,
      startsAt: _hasDate ? _startsAt?.toUtc() : null,
      endsAt: _hasDate ? _endsAt?.toUtc() : null,
    );

    final controller = ref.read(activityFormControllerProvider.notifier);
    final saved = widget.activityId == null
        ? await controller.create(draft)
        : await controller.update(widget.activityId!, draft);

    if (saved != null && mounted) context.pop();
  }
}
```

La validación de "fin después de inicio" se repite aquí en el cliente aunque el backend ya la exige (§9, `ends_after_starts`) — a propósito: el cliente da el error al instante, sin esperar el viaje de ida y vuelta a la API para un 422 que ya se podía anticipar.

### Envío: un controller que sabe crear y actualizar

```dart
@riverpod
class ActivityFormController extends _$ActivityFormController {
  @override
  FutureOr<void> build() {}

  Future<Activity?> create(ActivityDraft draft) =>
      _submit(() => ref.read(activityRepositoryProvider).create(draft));

  Future<Activity?> update(String id, ActivityDraft draft) =>
      _submit(() => ref.read(activityRepositoryProvider).update(id, draft));

  Future<Activity?> _submit(Future<Activity> Function() action) async {
    state = const AsyncLoading();
    final result = await AsyncValue.guard(action);
    state = result;
    if (result.hasValue) {
      ref.invalidate(activitiesForRangeProvider);
      ref.invalidate(unscheduledActivitiesProvider);
    }
    return result.valueOrNull;
  }
}
```

Invalidar `activitiesForRangeProvider` y `unscheduledActivitiesProvider` juntos, siempre, es intencional: una edición puede mover una actividad de una lista a la otra (asignarle fecha por primera vez la saca del backlog; quitarle la fecha la mete) y no vale la pena tener lógica para decidir cuál invalidar cuando invalidar ambas es barato.

### Selector de fecha/hora

```dart
class _DateTimeField extends StatelessWidget {
  const _DateTimeField({required this.label, required this.value, required this.onChanged});
  final String label;
  final DateTime? value;
  final ValueChanged<DateTime> onChanged;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label),
      subtitle: Text(value == null
          ? 'Seleccionar'
          : DateFormat('d MMM yyyy · HH:mm').format(value!)),
      trailing: const Icon(Icons.edit_calendar_outlined),
      onTap: () async {
        final date = await showDatePicker(
          context: context,
          initialDate: value ?? DateTime.now(),
          firstDate: DateTime.now().subtract(const Duration(days: 1)),
          lastDate: DateTime.now().add(const Duration(days: 730)),
        );
        if (date == null || !context.mounted) return;
        final time = await showTimePicker(
          context: context,
          initialTime: TimeOfDay.fromDateTime(value ?? DateTime.now()),
        );
        if (time == null) return;
        onChanged(DateTime(date.year, date.month, date.day, time.hour, time.minute));
      },
    );
  }
}
```

`value` y el resultado de los pickers se manejan siempre en hora local del dispositivo — la conversión a UTC ocurre en un único lugar, justo antes de armar el `ActivityDraft` en `_submit()`, nunca dentro del propio picker.

### Selector de contacto

`ContactPickerField` es un `Autocomplete<Contact>` con debounce que llama a `GET /contacts?search=` (§6) según se escribe. No trae la lista completa de contactos al abrir el formulario — para una clínica con cientos de pacientes, cargarlos todos de una vez sería tanto lento como innecesario.

---

## §15 — Pantallas de login y registro

La pieza que ata todo esto: ninguna de las dos pantallas navega manualmente al entrar — el `redirect` de `go_router` reacciona al estado de `authNotifierProvider` y mueve a la persona a donde corresponde. Login y registro solo cambian ese estado; no deciden a dónde ir después.

### Modelos: User y AuthState

`timezone` viaja en el modelo de usuario desde el registro — es el mismo valor que la §9 exige como identificador IANA válido, y aquí nunca lo escribe la persona a mano (más abajo).

```dart
@freezed
class User with _$User {
  const factory User({
    required String id,
    required String fullName,
    required String email,
    required String timezone,
  }) = _User;

  factory User.fromJson(Map<String, dynamic> json) => _$UserFromJson(json);
}

@freezed
sealed class AuthState with _$AuthState {
  const factory AuthState.unknown() = _Unknown;
  const factory AuthState.unauthenticated() = _Unauthenticated;
  const factory AuthState.authenticated(User user) = _Authenticated;
}
```

### Repositorio: los cinco endpoints de `/auth` de la §6

```dart
class AuthRepository {
  AuthRepository(this._dio);
  final Dio _dio;

  Future<(User, String, String)> register({
    required String fullName,
    required String email,
    required String password,
    required String phoneE164,
    required String timezone,
  }) async {
    final response = await _dio.post('/auth/register', data: {
      'full_name': fullName,
      'email': email,
      'password': password,
      'phone_e164': phoneE164,
      'timezone': timezone,
    });
    return (
      User.fromJson(response.data['user']),
      response.data['access_token'] as String,
      response.data['refresh_token'] as String,
    );
  }

  Future<(String, String)> login(String email, String password) async {
    final response = await _dio.post('/auth/login', data: {
      'email': email,
      'password': password,
    });
    return (response.data['access_token'] as String, response.data['refresh_token'] as String);
  }

  Future<User> fetchMe() async {
    final response = await _dio.get('/auth/me');
    return User.fromJson(response.data);
  }

  Future<(String, String)> refresh(String refreshToken) async {
    final response = await _dio.post('/auth/refresh', data: {'refresh_token': refreshToken});
    return (response.data['access_token'] as String, response.data['refresh_token'] as String);
  }

  Future<void> logout(String refreshToken) {
    return _dio.post('/auth/logout', data: {'refresh_token': refreshToken});
  }
}
```

### AuthNotifier: la única puerta hacia el estado de sesión

Al arrancar la app, `build()` intenta restaurar la sesión con el refresh token guardado — el mismo `refreshSession()` que ya usa el interceptor de Dio de la §12 cuando un 401 lo dispara a mitad de una petición cualquiera. Es la misma función, dos disparadores distintos.

```dart
@riverpod
class AuthNotifier extends _$AuthNotifier {
  @override
  Future<AuthState> build() async {
    final refreshToken = await ref.watch(secureTokenStorageProvider).readRefreshToken();
    if (refreshToken == null) return const AuthState.unauthenticated();
    return _restoreSession();
  }

  Future<AuthState> _restoreSession() async {
    final refreshed = await refreshSession();
    if (!refreshed) return const AuthState.unauthenticated();

    final user = await ref.read(authRepositoryProvider).fetchMe();
    await ref.read(deviceRegistrationProvider.notifier).registerCurrentDevice();
    return AuthState.authenticated(user);
  }

  Future<void> login(String email, String password) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(authRepositoryProvider);
      final (accessToken, refreshToken) = await repo.login(email, password);
      await ref.read(secureTokenStorageProvider).saveTokens(accessToken, refreshToken);

      final user = await repo.fetchMe();
      await ref.read(deviceRegistrationProvider.notifier).registerCurrentDevice();
      return AuthState.authenticated(user);
    });
  }

  Future<void> register({
    required String fullName,
    required String email,
    required String password,
    required String phoneE164,
    required String timezone,
  }) async {
    state = const AsyncLoading();
    state = await AsyncValue.guard(() async {
      final repo = ref.read(authRepositoryProvider);
      final (user, accessToken, refreshToken) = await repo.register(
        fullName: fullName,
        email: email,
        password: password,
        phoneE164: phoneE164,
        timezone: timezone,
      );
      await ref.read(secureTokenStorageProvider).saveTokens(accessToken, refreshToken);
      await ref.read(deviceRegistrationProvider.notifier).registerCurrentDevice();
      return AuthState.authenticated(user);
    });
  }

  Future<bool> refreshSession() async {
    final storage = ref.read(secureTokenStorageProvider);
    final refreshToken = await storage.readRefreshToken();
    if (refreshToken == null) return false;

    try {
      final (accessToken, newRefreshToken) =
          await ref.read(authRepositoryProvider).refresh(refreshToken);
      await storage.saveTokens(accessToken, newRefreshToken);
      return true;
    } on DioException {
      await storage.clear();
      state = const AsyncData(AuthState.unauthenticated());
      return false;
    }
  }

  Future<void> logout() async {
    final storage = ref.read(secureTokenStorageProvider);
    final refreshToken = await storage.readRefreshToken();
    if (refreshToken != null) {
      await ref.read(authRepositoryProvider).logout(refreshToken).catchError((_) {});
    }
    await storage.clear();
    state = const AsyncData(AuthState.unauthenticated());
  }
}
```

Si `refreshSession()` falla (token revocado o reutilizado, §10), limpia el storage y pone el estado en `unauthenticated` directamente — no lanza una excepción para que cada pantalla la atrape a su manera.

```dart
class SecureTokenStorage {
  SecureTokenStorage(this._storage);
  final FlutterSecureStorage _storage;

  Future<void> saveTokens(String accessToken, String refreshToken) async {
    await _storage.write(key: 'access_token', value: accessToken);
    await _storage.write(key: 'refresh_token', value: refreshToken);
  }

  Future<String?> readAccessToken() => _storage.read(key: 'access_token');
  Future<String?> readRefreshToken() => _storage.read(key: 'refresh_token');

  Future<void> clear() async {
    await _storage.delete(key: 'access_token');
    await _storage.delete(key: 'refresh_token');
  }
}

final secureTokenStorageProvider =
    Provider((ref) => SecureTokenStorage(const FlutterSecureStorage()));
```

### El router redirige, las pantallas no

`GoRouterRefreshStream` adapta el `Stream` del provider a un `Listenable`, para que `go_router` reevalúe `redirect` cada vez que `AuthState` cambia — sin esto, pasar de `unauthenticated` a `authenticated` después de un login exitoso no movería a nadie de pantalla hasta la siguiente navegación manual.

```dart
class GoRouterRefreshStream extends ChangeNotifier {
  GoRouterRefreshStream(Stream<dynamic> stream) {
    notifyListeners();
    _subscription = stream.asBroadcastStream().listen((_) => notifyListeners());
  }

  late final StreamSubscription<dynamic> _subscription;

  @override
  void dispose() {
    _subscription.cancel();
    super.dispose();
  }
}

final goRouterProvider = Provider<GoRouter>((ref) {
  final authNotifier = ref.watch(authNotifierProvider.notifier);

  return GoRouter(
    refreshListenable: GoRouterRefreshStream(authNotifier.stream),
    redirect: (context, state) {
      final auth = ref.read(authNotifierProvider).valueOrNull;
      final isAuthRoute =
          state.matchedLocation == '/login' || state.matchedLocation == '/register';

      if (auth == null) return null; // aún restaurando la sesión, no redirigir todavía
      final isAuthenticated = auth is _Authenticated;

      if (!isAuthenticated && !isAuthRoute) return '/login';
      if (isAuthenticated && isAuthRoute) return '/';
      return null;
    },
    routes: [
      GoRoute(path: '/login', builder: (context, state) => const LoginScreen()),
      GoRoute(path: '/register', builder: (context, state) => const RegisterScreen()),
      // ...resto de rutas de la §12 y §14
    ],
  );
});
```

### Pantalla de login

El botón de "Entrar" queda deshabilitado mientras `authState.isLoading`, y los errores se muestran con el mensaje real que devuelve el backend (§6, `{"error": {"message": ...}}`) en vez de un genérico — "Credenciales inválidas" le dice más a alguien que "Error 401".

```dart
class LoginScreen extends ConsumerStatefulWidget {
  const LoginScreen({super.key});

  @override
  ConsumerState<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends ConsumerState<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);

    ref.listen(authNotifierProvider, (previous, next) {
      final error = next.errorOrNull;
      if (error != null) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(_mapAuthError(error))));
      }
    });

    return Scaffold(
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text('OmniTask', style: Theme.of(context).textTheme.headlineMedium),
                  const SizedBox(height: 8),
                  const Text('Inicia sesión para ver tu agenda'),
                  const SizedBox(height: 32),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    decoration: const InputDecoration(labelText: 'Correo'),
                    validator: (v) => (v == null || !v.contains('@')) ? 'Correo inválido' : null,
                  ),
                  const SizedBox(height: 16),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: _obscurePassword,
                    decoration: InputDecoration(
                      labelText: 'Contraseña',
                      suffixIcon: IconButton(
                        icon: Icon(_obscurePassword
                            ? Icons.visibility_outlined
                            : Icons.visibility_off_outlined),
                        onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                    ),
                    validator: (v) =>
                        (v == null || v.isEmpty) ? 'La contraseña es obligatoria' : null,
                  ),
                  const SizedBox(height: 24),
                  FilledButton(
                    onPressed: authState.isLoading ? null : _submit,
                    child: authState.isLoading
                        ? const SizedBox(
                            height: 18,
                            width: 18,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('Entrar'),
                  ),
                  TextButton(
                    onPressed: () => context.push('/register'),
                    child: const Text('¿No tienes cuenta? Regístrate'),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  void _submit() {
    if (!_formKey.currentState!.validate()) return;
    ref.read(authNotifierProvider.notifier)
        .login(_emailController.text.trim(), _passwordController.text);
  }
}

String _mapAuthError(Object error) {
  if (error is DioException) {
    final message = error.response?.data?['error']?['message'] as String?;
    if (message != null) return message;
  }
  return 'No pudimos iniciar sesión. Intenta de nuevo.';
}
```

Nótese que `_submit()` no navega a ningún lado tras el éxito — solo llama a `login(...)`. El `redirect` del router de arriba es quien saca a la persona de `/login` en cuanto `AuthState` pasa a `authenticated`.

### Pantalla de registro: la zona horaria nunca la escribe la persona

Pedirle a alguien que teclee un identificador IANA (`America/Bogota`) es invitar al error justo en el campo que la §9 exige válido. En vez de un selector, se detecta del dispositivo con `flutter_timezone` en el momento de enviar el formulario.

```dart
class RegisterScreen extends ConsumerStatefulWidget {
  const RegisterScreen({super.key});

  @override
  ConsumerState<RegisterScreen> createState() => _RegisterScreenState();
}

class _RegisterScreenState extends ConsumerState<RegisterScreen> {
  final _formKey = GlobalKey<FormState>();
  final _nameController = TextEditingController();
  final _emailController = TextEditingController();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  final _confirmController = TextEditingController();

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Crear cuenta')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                controller: _nameController,
                decoration: const InputDecoration(labelText: 'Nombre completo'),
                validator: (v) => (v == null || v.trim().isEmpty) ? 'Obligatorio' : null,
              ),
              TextFormField(
                controller: _emailController,
                keyboardType: TextInputType.emailAddress,
                decoration: const InputDecoration(labelText: 'Correo'),
                validator: (v) => (v == null || !v.contains('@')) ? 'Correo inválido' : null,
              ),
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                decoration: const InputDecoration(labelText: 'Celular', hintText: '+57 300 000 0000'),
                validator: (v) =>
                    (v == null || !v.startsWith('+')) ? 'Incluye el indicativo, ej. +57' : null,
              ),
              TextFormField(
                controller: _passwordController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Contraseña'),
                validator: (v) => (v == null || v.length < 8) ? 'Mínimo 8 caracteres' : null,
              ),
              TextFormField(
                controller: _confirmController,
                obscureText: true,
                decoration: const InputDecoration(labelText: 'Confirmar contraseña'),
                validator: (v) =>
                    (v != _passwordController.text) ? 'Las contraseñas no coinciden' : null,
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: authState.isLoading ? null : _submit,
                child: const Text('Crear cuenta'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    final timezone = await FlutterTimezone.getLocalTimezone();

    ref.read(authNotifierProvider.notifier).register(
          fullName: _nameController.text.trim(),
          email: _emailController.text.trim(),
          password: _passwordController.text,
          phoneE164: _phoneController.text.trim(),
          timezone: timezone,
        );
  }
}
```

Las validaciones de mínimo 8 caracteres y de "las contraseñas coinciden" son puramente de UX inmediata — el backend igual valida la forma del `password` en `UserCreate` (§9); el cliente solo evita el viaje de ida y vuelta para un error que ya se veía venir.

> **Fuera de alcance de esta fase:** recuperación de contraseña ("olvidé mi contraseña") no está en el alcance descrito hasta ahora — se puede sumar como un flujo adicional de `/auth` (token de un solo uso enviado por correo o WhatsApp) cuando el resto del auth esté estable en producción.

---

*Documento de arquitectura v1 · 10 de julio de 2026 · próximo paso sugerido: validar §1 y confirmar el motor de base de datos antes de iniciar la fase 0.*
