# OmniTask — Documento de Arquitectura

**Preparado para:** Equipo de desarrollo — Clínica Campbell
**Rol:** Arquitectura de software · Full-stack móvil
**Fecha:** 10 de julio de 2026
**Estado:** Propuesta técnica v1

> Arquitectura de sistema, esquema de base de datos y guía de desarrollo por fases para una aplicación móvil de calendario, citas y tareas con notificaciones push y confirmaciones automáticas por WhatsApp Business.
>
> Versión con diseño completo (diagramas y tablas con estilo): [`docs/arquitectura.html`](./arquitectura.html) — ábrelo directo en el navegador, GitHub no lo renderiza inline.
>
> **Nota de lectura:** el backend real es **C#/ASP.NET Core** (§1, §22), no FastAPI/Python. Los fragmentos en Python de las §6-§18 documentan el diseño y las reglas de negocio originales — el contrato (endpoints, JSON, esquema) sigue vigente, pero el código de referencia es el de [`APIOmniTask/`](../APIOmniTask/) y la §22.

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
16. [Configuración y perfil de usuario](#16--configuración-y-perfil-de-usuario)
17. [Notificaciones y bandeja de entrada](#17--notificaciones-y-bandeja-de-entrada)
18. [PostgreSQL y conexión: mismo servidor Windows con IIS](#18--postgresql-y-conexión-mismo-servidor-windows-con-iis)
19. [La app y la API en producción](#19--la-app-y-la-api-en-producción)
20. [Crear el proyecto de Firebase](#20--crear-el-proyecto-de-firebase)
21. [Integración de WhatsApp Business API, paso a paso](#21--integración-de-whatsapp-business-api-paso-a-paso)
22. [Backend real: C#/.NET (`APIOmniTask/`)](#22--backend-real-cnet-apiomnitask)
23. [Stored procedures y functions de PostgreSQL](#23--stored-procedures-y-functions-de-postgresql)
24. [App móvil real: Flutter (`omnitask_app/`)](#24--app-móvil-real-flutter-omnitask_app)

---

## §1 — Decisiones de stack

La propuesta original — Flutter, C#/FastAPI, MySQL, FCM y WhatsApp Cloud API — es una base sólida. Se ajustan dos piezas para que el sistema encaje mejor con el requisito más delicado del proyecto: *fechas y recordatorios correctos entre zonas horarias, con envío confiable a WhatsApp*.

### Frontend — Flutter (sin cambios)

Correcto para iOS y Android desde un solo código base. Para las vistas de calendario, usar `syncfusion_flutter_calendar` (vistas día/semana/mes con drag-and-drop listas de fábrica) o `table_calendar` si se prefiere una dependencia más ligera. Estado con **Riverpod**; más fácil de testear que Bloc para un equipo pequeño y evita el boilerplate de Provider clásico.

### Backend — actualizado a ASP.NET Core / C#

> **Decisión final (reemplaza la recomendación original de este apartado):** el backend se construye en **ASP.NET Core / C#**, no FastAPI. Ver el código real en [`APIOmniTask/`](../APIOmniTask/) y el detalle en la §22.

La recomendación original de este apartado era FastAPI, por el peso de trabajo asíncrono e integraciones I/O-bound del proyecto (scheduler, webhooks, llamadas a Meta). Esa lógica seguía siendo válida en abstracto, pero el factor que termina decidiendo un stack en producción no es "qué encaja mejor en el papel" sino **quién lo va a operar**: el equipo que mantiene este servidor ya trabaja en C#/.NET, IIS aloja aplicaciones ASP.NET Core de forma nativa (sin el rodeo de `httpPlatformHandler` que describía la §18 para Python), y ya hay otras APIs corriendo ahí con ese mismo patrón. Cambiar de lenguaje no cambia el contrato: los endpoints, los JSON de request/response y el esquema de base de datos de las §3, §6, §7, §9, §16 y §17 siguen siendo los mismos — lo que cambia es la implementación, documentada en la §22.

### Base de datos — PostgreSQL en vez de MySQL

> **Cambio propuesto:** PostgreSQL 16 en vez de MySQL.

El requisito de "actividades sin fecha" y recordatorios entre zonas horarias depende de manejar tiempo con precisión. PostgreSQL tiene `TIMESTAMPTZ` nativo y funciones de calendario más completas que MySQL; además su tipo `JSONB` indexable es ideal para guardar las variables de las plantillas de WhatsApp y los payloads de webhook sin crear una tabla nueva por cada variante. Si por política interna de la clínica MySQL ya es el motor estándar, el esquema de la §3 se traduce sin cambios estructurales — solo cambia el tipo de columna de fecha.

### Resumen del stack final

| Capa | Tecnología | Rol |
|---|---|---|
| Móvil | Flutter 3.x | App única iOS/Android, Riverpod, calendario nativo |
| API | ASP.NET Core / C# (.NET 8) | REST + auth, orquesta integraciones (§22) |
| Cola / jobs | Hangfire sobre PostgreSQL | Recordatorios programados, reintentos de envío — sin Redis |
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
  final Dio _dio = Dio(BaseOptions(baseUrl: ApiConfig.baseUrl)); // valor real: §19

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

Ya es un archivo real, [`.github/workflows/backend-ci.yml`](../.github/workflows/backend-ci.yml) — reemplaza por completo el ejemplo en Python/Poetry/pytest que tenía esta sección (obsoleto desde que el backend pasó a C#/.NET, §22/§23). `dotnet build` se verificó de verdad: una reconstrucción limpia (sin `bin/`/`obj/` previos) de `APIOmniTask/OmniTask.sln` termina en **0 warnings, 0 errores**.

El job también aplica `db/schema.sql`, `db/02_add_refresh_tokens_table.sql` y `db/03_stored_procedures_and_functions.sql` contra un Postgres real como *service container*, y luego corre `dotnet test --no-build` contra ese mismo Postgres (§25) — un `dotnet build` limpio no detecta que las funciones/procedimientos se desincronizaron de lo que el C# espera, así que validar el SQL y las pruebas de integración en el mismo job importa tanto como compilar.

**Verificado en GitHub Actions, no solo localmente**: se corrió el pipeline real tres veces sobre `main` hasta quedar en verde —
1. Primer run: 28/29 pruebas, 1 falla real por precisión (`DateTimeOffset` en ticks de 100ns comparado contra el mismo valor después de un round-trip por `timestamptz`, que Postgres solo guarda en microsegundos).
2. Segundo run (tras corregir lo anterior): 28/29, otra falla real — la prueba asumía que reprogramar una actividad borraba los reminders viejos, pero `fn_update_activity` los marca `failed` e inserta los nuevos `pending` en la misma lista.
3. Tercer run: **29/29 en verde**, con las pruebas de integración corriendo de verdad contra el Postgres del service container, no saltándose.

Esto es exactamente el tipo de bug que una revisión manual del SQL no iba a atrapar — solo apareció al ejecutar el pipeline real en GitHub Actions.

```yaml
# .github/workflows/backend-ci.yml
name: Backend CI
on:
  pull_request:
    paths: ["APIOmniTask/**", "db/**"]
  push:
    branches: [main]
    paths: ["APIOmniTask/**", "db/**"]

jobs:
  build:
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
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-dotnet@v4
        with: { dotnet-version: "8.0.x" }
      - name: Restaurar y compilar
        working-directory: APIOmniTask
        run: |
          dotnet restore
          dotnet build --no-restore
      - name: Aplicar esquema y stored procedures contra Postgres
        env:
          PGPASSWORD: test
        run: |
          psql -h localhost -U postgres -d omnitask_test -f db/schema.sql
          psql -h localhost -U postgres -d omnitask_test -f db/02_add_refresh_tokens_table.sql
          psql -h localhost -U postgres -d omnitask_test -f db/03_stored_procedures_and_functions.sql
      - name: Ejecutar pruebas
        working-directory: APIOmniTask
        env:
          TEST_DATABASE_URL: "Host=localhost;Port=5432;Database=omnitask_test;Username=postgres;Password=test"
        run: dotnet test --no-build
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

Ya es un archivo real: [`.github/workflows/flutter-ci.yml`](../.github/workflows/flutter-ci.yml), no solo el ejemplo de esta sección — con `working-directory: omnitask_app` (el nombre real del paquete, §24) y `flutter-version: "3.44.6"`, la misma con la que se verificaron `flutter analyze` y las 21 pruebas de la sección anterior.

**Verificado en GitHub Actions, no solo localmente**: los triggers `pull_request`/`push` están acotados a cambios bajo `omnitask_app/**`, así que el workflow nunca se había disparado realmente en el repo — ningún commit hasta ahora había tocado esa carpeta. Se agregó `workflow_dispatch` para poder correrlo manualmente contra `main` y confirmarlo de punta a punta en GitHub Actions: **`flutter analyze` → "No issues found!" y `flutter test` → 🎉 21 tests passed, en verde a la primera corrida**, sin necesidad de corregir nada en el código Flutter.

```yaml
# .github/workflows/flutter-ci.yml
name: Flutter CI
on:
  pull_request:
    paths: ["omnitask_app/**"]
  push:
    branches: [main]
    paths: ["omnitask_app/**"]
  workflow_dispatch: {}

jobs:
  analyze-and-test:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: omnitask_app
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with: { flutter-version: "3.44.6", channel: "stable" }
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
      - flutter build appbundle --release --dart-define=API_BASE_URL=https://appsintranet.esculapiosis.com/APIOmniTask/api/v1
      - flutter build ipa --release --dart-define=API_BASE_URL=https://appsintranet.esculapiosis.com/APIOmniTask/api/v1
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

## §16 — Configuración y perfil de usuario

Antes de las pantallas, un cabo suelto: desde la §8 se viene mencionando que los recordatorios se crean "según las preferencias por defecto del usuario", pero nunca se definió dónde viven esas preferencias. Se cierra aquí, porque es exactamente lo que esta pantalla necesita para tener algo real que mostrar y editar.

> **Addendum a §3, §6 y §9:** `users` gana una columna `notification_preferences` (JSONB): `{"default_channel": "both", "reminder_offsets_minutes": [1440, 60]}`. `activity_service` (§8) la lee al crear los `reminders` automáticos de una actividad nueva, en vez del valor fijo que había quedado implícito.

### Backend: lo mínimo para soportarlo

```python
# models/user.py — addendum a la §9
notification_preferences: Mapped[dict] = mapped_column(
    JSONB,
    server_default='{"default_channel": "both", "reminder_offsets_minutes": [1440, 60]}',
)
```

```python
# schemas/auth.py
class NotificationPreferences(BaseModel):
    default_channel: Literal["push", "whatsapp", "both"] = "both"
    reminder_offsets_minutes: list[int] = [1440, 60]

class UserUpdate(BaseModel):
    full_name: str | None = None
    phone_e164: str | None = None
    timezone: str | None = None
    notification_preferences: NotificationPreferences | None = None
```

```python
# api/v1/auth.py — addendum a la §6
@router.patch("/auth/me", response_model=UserRead)
def update_me(
    payload: UserUpdate,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    for field, value in payload.model_dump(exclude_unset=True).items():
        setattr(user, field, value)
    db.commit()
    return user
```

Solo afecta a los `reminders` que se crean de aquí en adelante — cambiar la preferencia no reescribe los recordatorios de actividades que ya existían. Es una decisión deliberada, no una limitación olvidada: reabrir recordatorios ya calculados para actividades pasadas no tiene un caso de uso claro.

### Pantalla de ajustes: un menú, no un formulario

Perfil, notificaciones, dispositivos y cerrar sesión son cuatro cosas de naturaleza distinta — mezclarlas en un solo formulario largo sería peor que un menú con cuatro destinos claros.

```dart
class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final auth = ref.watch(authNotifierProvider).valueOrNull;
    final user = auth is _Authenticated ? auth.user : null;

    return Scaffold(
      appBar: AppBar(title: const Text('Ajustes')),
      body: ListView(
        children: [
          if (user != null)
            ListTile(
              leading: const CircleAvatar(child: Icon(Icons.person_outline)),
              title: Text(user.fullName),
              subtitle: Text(user.email),
              onTap: () => context.push('/settings/profile'),
            ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.notifications_outlined),
            title: const Text('Notificaciones'),
            subtitle: const Text('Canal y anticipación de los recordatorios'),
            onTap: () => context.push('/settings/notifications'),
          ),
          ListTile(
            leading: const Icon(Icons.devices_outlined),
            title: const Text('Dispositivos'),
            subtitle: const Text('Sesiones activas de push'),
            onTap: () => context.push('/settings/devices'),
          ),
          const Divider(),
          ListTile(
            leading: Icon(Icons.logout, color: Theme.of(context).colorScheme.error),
            title: Text(
              'Cerrar sesión',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
            onTap: () => _confirmLogout(context, ref),
          ),
        ],
      ),
    );
  }

  Future<void> _confirmLogout(BuildContext context, WidgetRef ref) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('¿Cerrar sesión?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Cerrar sesión')),
        ],
      ),
    );
    if (confirmed == true) ref.read(authNotifierProvider.notifier).logout();
  }
}
```

Al cerrar sesión no hay navegación manual — el mismo `redirect` de la §15 detecta que `AuthState` volvió a `unauthenticated` y devuelve a `/login` por su cuenta.

### Perfil: el correo no se edita aquí

Nombre, celular y zona horaria sí se editan libremente; el correo, deliberadamente, no — es la identidad de login, y cambiarlo debería ser un flujo separado con re-verificación, no una casilla más de un formulario casual (el mismo criterio que en la §14 decidió no exponer un botón de "eliminar" junto a "cancelar").

```dart
class ProfileScreen extends ConsumerStatefulWidget {
  const ProfileScreen({super.key});

  @override
  ConsumerState<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends ConsumerState<ProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _nameController;
  late final TextEditingController _phoneController;
  late String _timezone;

  @override
  void initState() {
    super.initState();
    final user = (ref.read(authNotifierProvider).valueOrNull as _Authenticated).user;
    _nameController = TextEditingController(text: user.fullName);
    _phoneController = TextEditingController(text: user.phoneE164);
    _timezone = user.timezone;
  }

  @override
  Widget build(BuildContext context) {
    final authState = ref.watch(authNotifierProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Perfil')),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            TextFormField(
              controller: _nameController,
              decoration: const InputDecoration(labelText: 'Nombre completo'),
              validator: (v) => (v == null || v.trim().isEmpty) ? 'Obligatorio' : null,
            ),
            TextFormField(
              controller: _phoneController,
              decoration: const InputDecoration(labelText: 'Celular'),
              validator: (v) =>
                  (v == null || !v.startsWith('+')) ? 'Incluye el indicativo, ej. +57' : null,
            ),
            ListTile(
              title: const Text('Zona horaria'),
              subtitle: Text(_timezone),
              trailing: TextButton(
                onPressed: _redetectTimezone,
                child: const Text('Detectar de nuevo'),
              ),
              onTap: _pickTimezoneManually,
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: authState.isLoading ? null : _submit,
              child: const Text('Guardar cambios'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _redetectTimezone() async {
    final detected = await FlutterTimezone.getLocalTimezone();
    setState(() => _timezone = detected);
  }

  Future<void> _pickTimezoneManually() async {
    final selected = await showTimezonePicker(context, initial: _timezone);
    if (selected != null) setState(() => _timezone = selected);
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    await ref.read(authNotifierProvider.notifier).updateProfile(
          fullName: _nameController.text.trim(),
          phoneE164: _phoneController.text.trim(),
          timezone: _timezone,
        );
    if (mounted) context.pop();
  }
}
```

El botón "Detectar de nuevo" cubre el caso normal (alguien viajó y su dispositivo ya está en otra zona horaria); el selector manual queda como respaldo para cuando el dispositivo detecta mal o alguien agenda para una sede en otra ciudad.

### Preferencias de notificación

El canal y la anticipación son las dos preguntas reales que `notification_preferences` responde. Un detalle de guarda: el botón de guardar se deshabilita si la persona desmarca todas las opciones de anticipación — de lo contrario, sería fácil terminar sin ningún recordatorio configurado sin darse cuenta.

```dart
class NotificationPreferencesScreen extends ConsumerStatefulWidget {
  const NotificationPreferencesScreen({super.key});

  @override
  ConsumerState<NotificationPreferencesScreen> createState() =>
      _NotificationPreferencesScreenState();
}

class _NotificationPreferencesScreenState
    extends ConsumerState<NotificationPreferencesScreen> {
  late String _channel;
  late Set<int> _offsets;

  static const _offsetOptions = {
    1440: '1 día antes',
    60: '1 hora antes',
    15: '15 minutos antes',
  };

  @override
  void initState() {
    super.initState();
    final user = (ref.read(authNotifierProvider).valueOrNull as _Authenticated).user;
    _channel = user.notificationPreferences.defaultChannel;
    _offsets = user.notificationPreferences.reminderOffsetsMinutes.toSet();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Notificaciones')),
      body: ListView(
        children: [
          const _SectionLabel('Canal por defecto'),
          RadioListTile(
            value: 'push', groupValue: _channel, title: const Text('Solo push'),
            onChanged: (v) => setState(() => _channel = v!),
          ),
          RadioListTile(
            value: 'whatsapp', groupValue: _channel, title: const Text('Solo WhatsApp'),
            onChanged: (v) => setState(() => _channel = v!),
          ),
          RadioListTile(
            value: 'both', groupValue: _channel, title: const Text('Push y WhatsApp'),
            onChanged: (v) => setState(() => _channel = v!),
          ),
          const Divider(),
          const _SectionLabel('¿Con cuánta anticipación?'),
          for (final entry in _offsetOptions.entries)
            CheckboxListTile(
              value: _offsets.contains(entry.key),
              title: Text(entry.value),
              onChanged: (checked) => setState(() {
                checked! ? _offsets.add(entry.key) : _offsets.remove(entry.key);
              }),
            ),
          const SizedBox(height: 16),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: FilledButton(
              onPressed: _offsets.isEmpty ? null : _submit,
              child: const Text('Guardar'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _submit() async {
    await ref.read(authNotifierProvider.notifier).updateProfile(
          preferences: NotificationPreferences(
            defaultChannel: _channel,
            reminderOffsetsMinutes: _offsets.toList()..sort(),
          ),
        );
    if (mounted) context.pop();
  }
}
```

`updateProfile` es el mismo método de `AuthNotifier` que usa la pantalla de perfil — un solo punto de escritura sobre el `User` guardado en `AuthState`, para que el nombre en la `AppBar` o el saludo de la agenda nunca queden desincronizados con lo que la persona acaba de cambiar.

### Dispositivos: no dejar que alguien se desconecte a sí mismo por error

Reutiliza `GET`/`DELETE` `/devices` de la §8 tal cual. El único detalle no obvio: el dispositivo actual se marca con una etiqueta en vez de mostrar un botón de cerrar sesión — quitarlo de la lista sería fácil de tocar sin querer y dejaría a la persona sin push en el mismo teléfono que está usando.

```dart
class DevicesScreen extends ConsumerWidget {
  const DevicesScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final devicesAsync = ref.watch(myDevicesProvider);
    final currentToken = ref.watch(currentFcmTokenProvider).valueOrNull;

    return Scaffold(
      appBar: AppBar(title: const Text('Dispositivos')),
      body: devicesAsync.when(
        data: (devices) => ListView(
          children: [
            for (final device in devices)
              ListTile(
                leading: Icon(
                  device.platform == 'ios' ? Icons.phone_iphone : Icons.phone_android,
                ),
                title: Text(device.platform == 'ios' ? 'iPhone' : 'Android'),
                subtitle: Text(
                  'Última actividad: '
                  '${DateFormat('d MMM, HH:mm').format(device.lastSeenAt.toLocal())}',
                ),
                trailing: device.fcmToken == currentToken
                    ? const Chip(label: Text('Este dispositivo'))
                    : IconButton(
                        icon: const Icon(Icons.logout),
                        onPressed: () => _signOut(ref, device.id),
                      ),
              ),
          ],
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorRetryView(onRetry: () => ref.invalidate(myDevicesProvider)),
      ),
    );
  }

  Future<void> _signOut(WidgetRef ref, String deviceId) async {
    await ref.read(deviceRepositoryProvider).delete(deviceId);
    ref.invalidate(myDevicesProvider);
  }
}
```

### Rutas nuevas

```dart
GoRoute(path: '/settings', builder: (context, state) => const SettingsScreen()),
GoRoute(path: '/settings/profile', builder: (context, state) => const ProfileScreen()),
GoRoute(
  path: '/settings/notifications',
  builder: (context, state) => const NotificationPreferencesScreen(),
),
GoRoute(path: '/settings/devices', builder: (context, state) => const DevicesScreen()),
```

---

## §17 — Notificaciones y bandeja de entrada

> **No confundir con la §12:** esta es una **segunda bandeja**, distinta a la de "pendientes por programar". Aquella es un backlog de actividades sin fecha; esta es un historial de lo que ya se envió — confirmaciones, recordatorios, WhatsApp — con su estado de entrega.

`notification_log` (§3) ya registra cada envío, pero le faltan dos cosas para servir como bandeja de entrada real: el texto que se mandó (para no depender de una actividad que puede haber cambiado o desaparecido) y si la persona ya lo vio *dentro de la app* — algo distinto de si Meta reporta el WhatsApp como "leído".

> **Addendum a §3 y §6:** `notification_log` gana `summary` (texto tal como se envió, capturado en el momento) y `acknowledged_at` (cuándo la persona lo abrió en la app). `status` sigue siendo el estado de entrega del proveedor (sent/delivered/read/failed) — son dos señales distintas para dos audiencias distintas: el contacto que recibe el WhatsApp, y la persona que revisa su bandeja en la app.

### Backend: endpoints de `/notifications`

```python
# models/notification_log.py — addendum a la §3
summary: Mapped[str]
acknowledged_at: Mapped[datetime | None]
```

```python
# api/v1/notifications.py
@router.get("/notifications", response_model=Page[NotificationRead])
def list_notifications(
    unread_only: bool = False,
    page: int = 1,
    limit: int = 20,
    user: User = Depends(get_current_user),
    db: Session = Depends(get_db),
):
    query = select(NotificationLog).where(NotificationLog.user_id == user.id)
    if unread_only:
        query = query.where(NotificationLog.acknowledged_at.is_(None))
    query = query.order_by(NotificationLog.created_at.desc())
    return paginate(db, query, page=page, limit=limit)


@router.get("/notifications/unread-count")
def unread_count(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    count = db.scalar(
        select(func.count())
        .select_from(NotificationLog)
        .where(NotificationLog.user_id == user.id, NotificationLog.acknowledged_at.is_(None))
    )
    return {"count": count}


@router.patch("/notifications/{id}/ack")
def acknowledge(id: str, user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    notification = db.get(NotificationLog, id)
    if notification is None or notification.user_id != user.id:
        raise HTTPException(404)
    notification.acknowledged_at = func.now()
    db.commit()


@router.post("/notifications/ack-all")
def acknowledge_all(user: User = Depends(get_current_user), db: Session = Depends(get_db)):
    db.execute(
        update(NotificationLog)
        .where(NotificationLog.user_id == user.id, NotificationLog.acknowledged_at.is_(None))
        .values(acknowledged_at=func.now())
    )
    db.commit()
```

`/notifications/unread-count` es deliberadamente su propio endpoint, separado del listado completo: es lo que alimenta el badge de la campana en la `AppBar` del calendario, y no tiene sentido traer la lista entera solo para contar cuántos faltan por leer.

### Modelo y repositorio en Flutter

```dart
@freezed
class NotificationItem with _$NotificationItem {
  const factory NotificationItem({
    required String id,
    required String channel,
    required String status,
    required String summary,
    String? activityId,
    required DateTime createdAt,
    DateTime? acknowledgedAt,
  }) = _NotificationItem;

  factory NotificationItem.fromJson(Map<String, dynamic> json) =>
      _$NotificationItemFromJson(json);
}
```

```dart
class NotificationRepository {
  NotificationRepository(this._dio);
  final Dio _dio;

  Future<List<NotificationItem>> fetchAll({bool unreadOnly = false, int page = 1}) async {
    final response = await _dio.get('/notifications', queryParameters: {
      'unread_only': unreadOnly,
      'page': page,
    });
    return (response.data['items'] as List)
        .map((j) => NotificationItem.fromJson(j))
        .toList();
  }

  Future<int> fetchUnreadCount() async {
    final response = await _dio.get('/notifications/unread-count');
    return response.data['count'] as int;
  }

  Future<void> acknowledge(String id) => _dio.patch('/notifications/$id/ack');
  Future<void> acknowledgeAll() => _dio.post('/notifications/ack-all');
}

@riverpod
Future<int> unreadNotificationsCount(UnreadNotificationsCountRef ref) {
  return ref.watch(notificationRepositoryProvider).fetchUnreadCount();
}

@riverpod
Future<List<NotificationItem>> notificationsInbox(NotificationsInboxRef ref) {
  return ref.watch(notificationRepositoryProvider).fetchAll();
}
```

### La campana en el calendario (addendum a la §12)

```dart
IconButton(
  icon: Badge(
    label: Text('${ref.watch(unreadNotificationsCountProvider).valueOrNull ?? 0}'),
    isLabelVisible: (ref.watch(unreadNotificationsCountProvider).valueOrNull ?? 0) > 0,
    child: const Icon(Icons.notifications_outlined),
  ),
  onPressed: () => context.push('/notifications'),
),
```

### Pantalla de bandeja de entrada

Tocar un ítem hace dos cosas, no una: lo marca como reconocido (si estaba sin leer) y, si trae `activityId`, navega al detalle — el mismo destino al que ya llega el deep link de un push (§12), así que abrir la notificación desde la campana o desde el sistema operativo termina en el mismo lugar.

```dart
class NotificationsInboxScreen extends ConsumerWidget {
  const NotificationsInboxScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final notificationsAsync = ref.watch(notificationsInboxProvider);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Notificaciones'),
        actions: [
          TextButton(
            onPressed: () async {
              await ref.read(notificationRepositoryProvider).acknowledgeAll();
              ref.invalidate(notificationsInboxProvider);
              ref.invalidate(unreadNotificationsCountProvider);
            },
            child: const Text('Marcar todas'),
          ),
        ],
      ),
      body: notificationsAsync.when(
        data: (items) => items.isEmpty
            ? const _EmptyInbox()
            : ListView.separated(
                itemCount: items.length,
                separatorBuilder: (_, __) => const Divider(height: 1),
                itemBuilder: (context, i) => _NotificationTile(item: items[i]),
              ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (e, _) => ErrorRetryView(onRetry: () => ref.invalidate(notificationsInboxProvider)),
      ),
    );
  }
}

class _NotificationTile extends ConsumerWidget {
  const _NotificationTile({required this.item});
  final NotificationItem item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isUnread = item.acknowledgedAt == null;

    return ListTile(
      tileColor: isUnread
          ? Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3)
          : null,
      leading: Icon(
        item.channel == 'whatsapp' ? Icons.chat_outlined : Icons.notifications_outlined,
      ),
      title: Text(
        item.summary,
        style: TextStyle(fontWeight: isUnread ? FontWeight.w600 : FontWeight.normal),
      ),
      subtitle: Text(_relativeTime(item.createdAt)),
      trailing: _StatusDot(status: item.status),
      onTap: () async {
        if (isUnread) {
          await ref.read(notificationRepositoryProvider).acknowledge(item.id);
          ref.invalidate(notificationsInboxProvider);
          ref.invalidate(unreadNotificationsCountProvider);
        }
        if (item.activityId != null && context.mounted) {
          context.push('/activities/${item.activityId}');
        }
      },
    );
  }
}
```

`_StatusDot` pinta el `status` de entrega — pero en la práctica solo es informativo para el canal WhatsApp: FCM no le reporta al backend cuándo un push se entregó o se leyó, así que en push casi siempre se queda en `sent`. Vale la pena que el color no prometa una precisión que el canal no tiene.

### Por qué hace falta un listener aparte para el primer plano

FCM no muestra una notificación de sistema mientras la app está abierta en primer plano — en ninguna de las dos plataformas. Sin este puente, alguien con la app abierta simplemente no vería el recordatorio llegar.

```dart
@Riverpod(keepAlive: true)
class PushMessageListener extends _$PushMessageListener {
  @override
  void build() {
    FirebaseMessaging.onMessage.listen(_handleForegroundMessage);
  }

  void _handleForegroundMessage(RemoteMessage message) {
    ref.read(localNotificationsServiceProvider).show(message);
    ref.invalidate(unreadNotificationsCountProvider);
    ref.invalidate(notificationsInboxProvider);
  }
}

class LocalNotificationsService {
  LocalNotificationsService(this._plugin);
  final FlutterLocalNotificationsPlugin _plugin;

  Future<void> show(RemoteMessage message) {
    return _plugin.show(
      message.hashCode,
      message.notification?.title ?? 'OmniTask',
      message.notification?.body ?? '',
      const NotificationDetails(
        android: AndroidNotificationDetails('reminders', 'Recordatorios'),
      ),
      payload: message.data['activity_id'],
    );
  }
}
```

`PushMessageListener` se marca `keepAlive: true` a propósito y se lee una sola vez en `main.dart` (`ref.read(pushMessageListenerProvider)`) justo después de levantar el `ProviderScope` — es un servicio de proceso completo, no algo ligado al ciclo de vida de una pantalla en particular. Invalidar `unreadNotificationsCountProvider` y `notificationsInboxProvider` en el mismo callback es lo que hace que el badge de la campana y la lista se actualicen solos con la app abierta, sin que la persona tenga que deslizar para refrescar.

---

## §18 — PostgreSQL y conexión: mismo servidor Windows con IIS

Con el backend y la base de datos en la misma máquina, la conexión es **local** (127.0.0.1), no remota — eso simplifica bastante: no hay que abrir el puerto 5432 hacia afuera. Lo que sí cambia respecto al §11/§13 es cómo se ejecuta el proceso: IIS no corre Python de forma nativa, así que necesita un puente hacia Uvicorn, y Celery (que no habla HTTP) no puede vivir dentro de IIS en absoluto.

### Script SQL completo

Es el DDL literal del esquema de la §3, más los addenda de `notification_preferences` (§16) y `summary`/`acknowledged_at` (§17) ya incorporados. También está disponible como archivo ejecutable en [`db/schema.sql`](../db/schema.sql) (y [`db/00_create_role_and_database.sql`](../db/00_create_role_and_database.sql) para el rol y la base). Los índices parciales al final no son de relleno: cada uno corresponde a una consulta que el documento ya describe como frecuente.

```sql
-- Extensión para generar UUIDs
CREATE EXTENSION IF NOT EXISTS "pgcrypto";

-- Enums
CREATE TYPE user_role AS ENUM ('admin', 'professional', 'assistant');
CREATE TYPE device_platform AS ENUM ('ios', 'android');
CREATE TYPE activity_type AS ENUM ('meeting', 'appointment', 'task', 'activity');
CREATE TYPE activity_status AS ENUM ('unscheduled', 'scheduled', 'completed', 'cancelled');
CREATE TYPE reminder_channel AS ENUM ('push', 'whatsapp', 'both');
CREATE TYPE reminder_status AS ENUM ('pending', 'processing', 'sent', 'failed');
CREATE TYPE notification_channel AS ENUM ('push', 'whatsapp');
CREATE TYPE notification_status AS ENUM ('queued', 'sent', 'delivered', 'read', 'failed');
CREATE TYPE template_category AS ENUM ('utility', 'marketing', 'authentication');
CREATE TYPE template_approval_status AS ENUM ('pending', 'approved', 'rejected');

-- users
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    full_name TEXT NOT NULL,
    email TEXT NOT NULL UNIQUE,
    password_hash TEXT NOT NULL,
    phone_e164 TEXT NOT NULL,
    timezone TEXT NOT NULL,
    role user_role NOT NULL DEFAULT 'professional',
    notification_preferences JSONB NOT NULL DEFAULT
        '{"default_channel": "both", "reminder_offsets_minutes": [1440, 60]}',
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now()
);

-- devices
CREATE TABLE devices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    fcm_token TEXT NOT NULL UNIQUE,
    platform device_platform NOT NULL,
    last_seen_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_devices_user_id ON devices (user_id);

-- contacts
CREATE TABLE contacts (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    full_name TEXT NOT NULL,
    phone_e164 TEXT NOT NULL,
    notes TEXT
);
CREATE INDEX idx_contacts_user_id ON contacts (user_id);

-- whatsapp_templates
CREATE TABLE whatsapp_templates (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    meta_template_name TEXT NOT NULL,
    language_code TEXT NOT NULL,
    category template_category NOT NULL,
    approval_status template_approval_status NOT NULL DEFAULT 'pending',
    variables_schema JSONB NOT NULL DEFAULT '{}'
);

-- activities
CREATE TABLE activities (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    contact_id UUID REFERENCES contacts (id) ON DELETE SET NULL,
    type activity_type NOT NULL,
    title TEXT NOT NULL,
    description TEXT,
    status activity_status NOT NULL DEFAULT 'scheduled',
    starts_at TIMESTAMPTZ,
    ends_at TIMESTAMPTZ,
    timezone TEXT NOT NULL,
    location TEXT,
    nudge_frequency_days INTEGER,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    updated_at TIMESTAMPTZ NOT NULL DEFAULT now(),
    CONSTRAINT chk_ends_after_starts
        CHECK (ends_at IS NULL OR starts_at IS NULL OR ends_at > starts_at)
);
CREATE INDEX idx_activities_user_id ON activities (user_id);
CREATE INDEX idx_activities_contact_id ON activities (contact_id);
CREATE INDEX idx_activities_starts_at ON activities (starts_at);
-- La bandeja de "pendientes por programar" (§4/§12) filtra por esto constantemente
CREATE INDEX idx_activities_unscheduled ON activities (user_id) WHERE starts_at IS NULL;

-- reminders
CREATE TABLE reminders (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    activity_id UUID NOT NULL REFERENCES activities (id) ON DELETE CASCADE,
    remind_at TIMESTAMPTZ NOT NULL,
    channel reminder_channel NOT NULL,
    template_id UUID REFERENCES whatsapp_templates (id),
    status reminder_status NOT NULL DEFAULT 'pending',
    sent_at TIMESTAMPTZ
);
CREATE INDEX idx_reminders_activity_id ON reminders (activity_id);
-- El índice que hace barato el SELECT ... FOR UPDATE SKIP LOCKED de la §8
CREATE INDEX idx_reminders_due ON reminders (remind_at) WHERE status = 'pending';

-- notification_log
CREATE TABLE notification_log (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    reminder_id UUID REFERENCES reminders (id) ON DELETE SET NULL,
    user_id UUID NOT NULL REFERENCES users (id) ON DELETE CASCADE,
    channel notification_channel NOT NULL,
    provider_message_id TEXT,
    status notification_status NOT NULL DEFAULT 'queued',
    summary TEXT NOT NULL,
    error_detail TEXT,
    acknowledged_at TIMESTAMPTZ,
    created_at TIMESTAMPTZ NOT NULL DEFAULT now()
);
CREATE INDEX idx_notification_log_user_id ON notification_log (user_id, created_at DESC);
CREATE INDEX idx_notification_log_provider_message_id ON notification_log (provider_message_id);
-- Alimenta /notifications/unread-count (§17) sin escanear toda la tabla
CREATE INDEX idx_notification_log_unread ON notification_log (user_id) WHERE acknowledged_at IS NULL;

-- updated_at al día aunque algo distinto a la API toque la fila directamente
CREATE OR REPLACE FUNCTION set_updated_at()
RETURNS TRIGGER AS $$
BEGIN
    NEW.updated_at = now();
    RETURN NEW;
END;
$$ LANGUAGE plpgsql;

CREATE TRIGGER trg_users_updated_at BEFORE UPDATE ON users
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
CREATE TRIGGER trg_activities_updated_at BEFORE UPDATE ON activities
    FOR EACH ROW EXECUTE FUNCTION set_updated_at();
```

El `CHECK` de `ends_at > starts_at` repite, a nivel de base de datos, la misma regla que ya valida el formulario de Flutter (§14) y el schema Pydantic (§9). No es redundancia perdida: son tres capas independientes, y la de la base de datos es la única que también protege contra un acceso directo a SQL que se salte la API por completo.

> **Este script es para arrancar, no para mantener:** una vez ejecutado, marca el esquema como la base de Alembic con `alembic stamp head` (usando una migración inicial que refleje este mismo DDL) — así las migraciones futuras del §11/§13 se aplican encima sin que Alembic intente recrear tablas que ya existen.

### PostgreSQL: rol, base y acceso local

```sql
-- Como superusuario (psql -U postgres)
CREATE ROLE omnitask_api WITH LOGIN PASSWORD 'una-contraseña-fuerte-aquí';
CREATE DATABASE omnitask OWNER omnitask_api;
```

En `postgresql.conf`, `listen_addresses = 'localhost'` basta — no hace falta `'*'`, porque nada fuera de esta misma máquina necesita hablarle a Postgres directamente. En `pg_hba.conf`, una sola línea cubre el caso real:

```
# pg_hba.conf
host    omnitask    omnitask_api    127.0.0.1/32    scram-sha-256
```

Tras tocar cualquiera de los dos archivos, reiniciar el servicio (`services.msc` → PostgreSQL, o `net stop postgresql-x64-16` seguido de `net start postgresql-x64-16`). Luego, cargar el script:

```
psql -U omnitask_api -d omnitask -f schema.sql
```

### Cadena de conexión de FastAPI

Como es tráfico de loopback que nunca sale de la máquina, `sslmode` no es necesario aquí — sí lo sería el día que la base de datos se mueva a otro servidor.

```
# .env — fuera del webroot, permisos NTFS restringidos a la identidad del app pool
DATABASE_URL=postgresql+psycopg://omnitask_api:una-contraseña-fuerte-aquí@127.0.0.1:5432/omnitask
```

Evitar poner esta cadena directo en `web.config` en texto plano — la §5 ya pedía un gestor de secretos, y un `.env` con permisos NTFS restringidos (solo lectura para la identidad del Application Pool, sin acceso para `IIS_IUSRS` en general) cumple ese mismo propósito sin depender de herramientas específicas de .NET como `aspnet_regiis`.

### IIS como puente hacia Uvicorn (httpPlatformHandler)

IIS no ejecuta Python de forma nativa. El módulo **httpPlatformHandler** (descarga aparte de Microsoft, no viene instalado por defecto) es el mecanismo estándar de IIS para este caso: arranca, monitorea y reinicia el proceso Python él mismo — el mismo enfoque que se usa para hospedar apps de Node.js bajo IIS. No hace falta Application Request Routing (ARR) para esto; ARR entraría en juego solo si más adelante se necesita balancear varias instancias.

```xml
<!-- web.config, en la raíz del sitio de IIS -->
<configuration>
  <system.webServer>
    <handlers>
      <add name="PythonHandler" path="*" verb="*"
           modules="httpPlatformHandler" resourceType="Unspecified" />
    </handlers>
    <httpPlatform processPath="C:\omnitask\venv\Scripts\python.exe"
                   arguments="-m uvicorn app.main:app --host 127.0.0.1 --port %HTTP_PLATFORM_PORT%"
                   startupTimeLimit="60"
                   stdoutLogEnabled="true"
                   stdoutLogFile="C:\omnitask\logs\stdout.log">
    </httpPlatform>
  </system.webServer>
</configuration>
```

`%HTTP_PLATFORM_PORT%` lo asigna IIS dinámicamente por cada arranque del Application Pool — Uvicorn escucha ahí, nunca en un puerto fijo elegido a mano. El sitio de IIS se enlaza a 443 con el certificado del servidor; IIS termina TLS y reenvía en HTTP plano hacia Uvicorn, que solo escucha en `127.0.0.1` y por lo tanto no es alcanzable desde fuera de la máquina ni siquiera si alguien lo intentara.

El Application Pool del sitio debe crearse en modo **"No Managed Code"** — no es una app .NET, y decirle a IIS que gestione un runtime .NET que no se usa solo agrega una capa sin propósito.

### Celery worker y beat: no viven en IIS

IIS únicamente sabe hablar HTTP. Los procesos de Celery (§8) no exponen un puerto HTTP — son demonios de fondo, así que `web.config` no aplica en absoluto. Se instalan como **servicios de Windows** con **NSSM** (Non-Sucking Service Manager), independientes del sitio de IIS y de su ciclo de vida.

```
nssm install OmniTaskWorker "C:\omnitask\venv\Scripts\python.exe" ^
  "-m celery -A app.tasks.celery_app worker --loglevel=info --pool=solo"

nssm install OmniTaskBeat "C:\omnitask\venv\Scripts\python.exe" ^
  "-m celery -A app.tasks.celery_app beat --loglevel=info"
```

`--pool=solo` no es opcional en Windows: el pool *prefork* por defecto de Celery depende de `os.fork()`, que no existe en este sistema operativo. `solo` procesa una tarea a la vez por worker — para el volumen de recordatorios de una clínica, correcto y suficiente; si el volumen creciera, la alternativa sería correr varias instancias de `OmniTaskWorker` en vez de cambiar de pool.

### Redis: en Windows, mejor Memurai que Redis "oficial"

Redis dejó de mantener builds oficiales para Windows hace años. En vez de depender de un puerto no soportado, **Memurai** es compatible con el protocolo Redis, se mantiene activamente para Windows y tiene una edición de desarrollo gratuita — se instala como servicio de Windows igual que PostgreSQL, escuchando también en `127.0.0.1:6379`. Si el servidor ya tiene Docker Desktop/WSL2 disponible por otra razón, correr la imagen `redis:7` ahí es una alternativa igual de válida.

### Addendum al §13: el pipeline de CI/CD asumía Linux

Los pasos `ssh deploy@staging "docker ..."` del §13 no aplican tal cual a este servidor. El reemplazo más directo es instalar un **GitHub Actions self-hosted runner** en esta misma máquina Windows: el job de despliegue corre localmente con PowerShell (copiar los archivos nuevos, reiniciar el Application Pool de IIS y los servicios `OmniTaskWorker`/`OmniTaskBeat` con NSSM) en vez de empujar una imagen Docker a un host remoto. Es un ajuste de mecanismo, no de principio — el gate manual de `environment: production` y la idea de nunca reconstruir para producción siguen aplicando igual.

---

## §19 — La app y la API en producción

Para que quede explícito: esto es una app móvil (Flutter, §12) que **nunca toca la base de datos directamente**. Todo dato — crear una cita, ver el calendario, marcar una notificación como leída — sale del teléfono como una petición HTTPS hacia la API (ASP.NET Core / C#, §22), y es la API la única que le habla a PostgreSQL, en el mismo servidor Windows del §18. Ese diseño no cambia con esta pregunta; lo que faltaba era la URL real.

```
Celular (Flutter)  ──HTTPS──►  https://appsintranet.esculapiosis.com/APIOmniTask/api/v1  ──local──►  PostgreSQL
                                (IIS → ASP.NET Core Module, §22)                (127.0.0.1:5432, §18)
```

`/APIOmniTask` es una sub-aplicación de IIS — el mismo patrón que ya usan las otras APIs de este servidor —, no un sitio propio; IIS antepone y quita ese segmento de forma transparente, la API nunca necesita saber que existe.

Con la red pública y el certificado público confirmados, no hace falta nada especial de confianza de certificados ni VPN en la app — Android e iOS ya confían en un certificado de Let's Encrypt o comercial a través de su almacén de certificados del sistema, sin tocar `network_security_config.xml` ni nada equivalente en iOS.

### Lo que sí cambia: la URL deja de ser un placeholder

En la §12, `DioClient` apuntaba a `ApiConfig.baseUrl` sin que `ApiConfig` se hubiera definido todavía. Ahora tiene un valor real de producción, y uno de desarrollo local, elegidos en tiempo de compilación — así el mismo código corre contra un backend local en el emulador y, en el build de release, contra el servidor real, sin tocar una sola línea.

```dart
// core/config/api_config.dart
class ApiConfig {
  static const _prodBaseUrl = 'https://appsintranet.esculapiosis.com/APIOmniTask/api/v1';

  // Emulador Android: 10.0.2.2 es el alias que Android usa para "el localhost
  // de la máquina anfitriona". En el simulador de iOS, en cambio, se usa
  // localhost directo porque comparte la red del Mac.
  static const _devBaseUrl = 'http://10.0.2.2:8000/api/v1';

  static const baseUrl = String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: _devBaseUrl,
  );
}
```

```bash
# desarrollo local — no hace falta pasar nada, _devBaseUrl ya es el default
flutter run

# para probar el build de un dispositivo contra el servidor real
flutter run --dart-define=API_BASE_URL=https://appsintranet.esculapiosis.com/APIOmniTask/api/v1
```

`String.fromEnvironment` resuelve en tiempo de compilación, no en tiempo de ejecución — por eso el build de release necesita recibir `--dart-define` explícitamente; ya quedó cableado en el pipeline de Codemagic de la §13:

```yaml
# codemagic.yaml — addendum a la §13
    scripts:
      - flutter pub get
      - dart run build_runner build --delete-conflicting-outputs
      - flutter build appbundle --release --dart-define=API_BASE_URL=https://appsintranet.esculapiosis.com/APIOmniTask/api/v1
      - flutter build ipa --release --dart-define=API_BASE_URL=https://appsintranet.esculapiosis.com/APIOmniTask/api/v1
```

### Un detalle de Android en desarrollo, no en producción

El servidor real es HTTPS, así que en release no hay nada que ajustar. Pero `http://10.0.2.2:8000` en desarrollo es HTTP plano, y Android bloquea tráfico sin cifrar por defecto desde la API 28 — hay que habilitarlo únicamente en el manifest de *debug*, nunca en el de release, para no aflojar esa protección en producción por accidente.

```xml
<!-- android/app/src/debug/AndroidManifest.xml -->
<application android:usesCleartextTraffic="true" />
```

Al vivir en `src/debug/` (no en `src/main/`), Flutter lo aplica solo a los builds de depuración — el `flutter build appbundle --release` de la §13 nunca lo incluye.

> **Algo que no aplica aquí:** CORS no es un problema para esta app: es una restricción que imponen los navegadores, no los clientes HTTP nativos. Dio, corriendo dentro de la app Flutter en el teléfono, no está sujeto a esa política — el backend no necesita configurar cabeceras CORS por la app móvil (solo tendría sentido si más adelante se agrega un cliente web).

---

## §20 — Crear el proyecto de Firebase

Tarea de la **Fase 0** (§4) — se puede hacer en paralelo con la verificación de WhatsApp en Meta, no depende de nada más del proyecto. El resultado son tres archivos: dos para el cliente Flutter (Android e iOS) y una credencial de servicio para el backend.

### 1. Crear el proyecto

1. Entrar a **console.firebase.google.com** con la cuenta de Google de la clínica (no una cuenta personal — quien administre el proyecto después debe poder acceder).
2. "Agregar proyecto" → nombre, por ejemplo `omnitask-clinicacampbell`.
3. Google Analytics es opcional aquí — no hace falta para Cloud Messaging, se puede omitir sin perder nada de lo que este documento describe.

### 2. Registrar la app Android

1. Dentro del proyecto: "Agregar app" → Android.
2. El **nombre del paquete** tiene que coincidir exactamente con el `applicationId` de `android/app/build.gradle` (ej. `com.clinicacampbell.omnitask`) — si no coinciden, el token FCM nunca llega.
3. Descargar `google-services.json` y colocarlo en `android/app/google-services.json`.
4. Agregar el plugin de Google Services al build de Gradle:

```groovy
// android/build.gradle
dependencies {
    classpath 'com.google.gms:google-services:4.4.2'
}

// android/app/build.gradle
apply plugin: 'com.google.gms.google-services'
```

### 3. Registrar la app iOS

1. "Agregar app" → iOS. El **Bundle ID** debe coincidir con el configurado en Xcode (`ios/Runner.xcodeproj`).
2. Descargar `GoogleService-Info.plist` y agregarlo **desde Xcode** (arrastrarlo al grupo `Runner` del navegador de proyecto) — copiarlo solo al sistema de archivos no basta, Xcode necesita referenciarlo explícitamente en el `.xcodeproj`.
3. En Xcode, habilitar la capability **Push Notifications** para el target `Runner`.
4. En Apple Developer, generar una **APNs Authentication Key** (`.p8`) y subirla en Firebase Console → Configuración del proyecto → Cloud Messaging → APNs Authentication Key.

> **Por qué hace falta la key de Apple:** en iOS, FCM no entrega directo al teléfono — internamente reenvía a través de APNs, el servicio de notificaciones de Apple. Sin esa key, Firebase puede aceptar el mensaje del backend pero nunca lo entrega a un iPhone.

### 4. Credencial de servicio para el backend

1. Firebase Console → Configuración del proyecto → **Cuentas de servicio** → "Generar nueva clave privada" → descarga un archivo JSON.
2. Ese JSON es lo que inicializa el Firebase Admin SDK del lado del servidor — la pieza que `_send_push` (§8) usa para mandar el mensaje.

```python
# backend — inicialización una sola vez, al arrancar la app
import firebase_admin
from firebase_admin import credentials

cred = credentials.Certificate(settings.FIREBASE_CREDENTIALS_PATH)
firebase_admin.initialize_app(cred)
```

> **Esto sí es un secreto:** el JSON de la cuenta de servicio da acceso completo para enviar mensajes en nombre del proyecto — nunca al repositorio. En el servidor Windows (§18), va junto al `.env` con permisos NTFS restringidos a la identidad del Application Pool, igual que `DATABASE_URL`. `google-services.json` y `GoogleService-Info.plist` son distintos: identifican la app, no son credenciales de acceso, así que son de menor riesgo — pero igual es buena práctica no publicarlos en un repositorio público.

### 5. Inicializar Firebase en Flutter

```dart
// main.dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp();
  runApp(const ProviderScope(child: OmniTaskApp()));
}
```

Requiere el paquete `firebase_core` además de `firebase_messaging` (ya listado en la §12). Sin esta línea, cualquier llamada a `FirebaseMessaging.instance` — el registro de token de la §8 o el listener de primer plano de la §17 — falla al arrancar.

### 6. Verificar antes de conectar todo el pipeline

Antes de depender de Celery y del backend completo (§8), conviene confirmar que la entrega funciona de forma aislada: Firebase Console → Cloud Messaging → "Enviar mensaje de prueba", pegando el token FCM que imprime la app en un dispositivo real (los emuladores/simuladores no siempre reciben push de forma confiable). Si ese mensaje de prueba llega, el problema de cualquier fallo posterior está en el backend o en la lógica de recordatorios — no en la configuración de Firebase.

---

## §21 — Integración de WhatsApp Business API, paso a paso

Es la tarea de la **Fase 0** (§4) con más tiempo de espera de todo el proyecto — la verificación de la empresa puede tardar días hábiles, así que conviene arrancarla antes que casi cualquier otra cosa. Se usa la **Cloud API de Meta directamente** (la misma de la §7), sin intermediario (BSP) de por medio.

### 1. Business Manager y verificación de la empresa

1. Crear (o usar la existente) cuenta de negocio en **business.facebook.com**.
2. Configuración del negocio → **Verificación de la empresa**: nombre legal, NIT, dirección y documento de registro de la clínica.
3. Meta revisa esto en horas o varios días hábiles — es el paso que justifica arrancarlo desde la Fase 0 y no cuando ya se necesita enviar el primer mensaje real.

### 2. Cuenta de WhatsApp Business (WABA) y el número

1. Dentro del Business Manager: Cuentas de WhatsApp → crear una.
2. Agregar el número que va a enviar los mensajes. Tiene que estar **libre de cualquier otra cuenta de WhatsApp** — si ya está activo en la app personal o en WhatsApp Business App, hay que eliminarlo de ahí primero, o Meta no deja registrarlo aquí.
3. Verificar el número por SMS o llamada.

### 3. Crear la app en Meta for Developers

1. **developers.facebook.com/apps** → Crear app → tipo "Business".
2. Agregar el producto **WhatsApp** → seleccionar el Business Manager y el WABA del paso 2.
3. Esto entrega tres cosas de una vez: el **Phone Number ID** (el que ya aparece en la URL de envío de la §7, `/{phone_number_id}/messages`), el **WABA ID**, y un token de acceso temporal de 24 horas — solo sirve para las primeras pruebas, no para producción.

### 4. Token de acceso permanente (System User)

1. Business Settings → Users → System Users → crear uno con rol **Admin**.
2. Asignarle acceso al WABA y a la app del paso 3.
3. Generar el token con los permisos `whatsapp_business_messaging` y `whatsapp_business_management`, de larga duración — este es el que usa el backend en producción, nunca el temporal de 24h del paso anterior.

### 5. Probar el envío antes de tocar el backend

Meta da una plantilla de muestra ya aprobada, `hello_world`, pensada exactamente para esto: confirmar que el número y el token funcionan antes de esperar la aprobación de las plantillas propias.

```bash
curl -X POST "https://graph.facebook.com/v20.0/{phone_number_id}/messages" \
  -H "Authorization: Bearer {token_temporal}" \
  -H "Content-Type: application/json" \
  -d '{
    "messaging_product": "whatsapp",
    "to": "573001234567",
    "type": "template",
    "template": {"name": "hello_world", "language": {"code": "en_US"}}
  }'
```

Si este mensaje llega, cualquier falla después está en el backend o en las plantillas — no en la cuenta ni en el número.

### 6. Crear y enviar a aprobación las plantillas de la §7

1. WhatsApp Manager → Message Templates → Create Template.
2. Crear las tres: `appointment_confirmation`, `appointment_reminder`, `appointment_reschedule` — categoría **Utility**, mismo cuerpo y variables ya definidos en la §7.
3. Enviar a revisión. La aprobación toma de horas a días; hasta entonces, `dispatch_due_reminders` (§8) no tiene ninguna plantilla real para enviar, solo `hello_world` de prueba.

### 7. Configurar el webhook

1. developers.facebook.com → la app → WhatsApp → Configuration → Webhook.
2. Callback URL: `https://appsintranet.esculapiosis.com/APIOmniTask/webhooks/whatsapp` — el dominio real confirmado en la §19.
3. Verify token: un valor propio (no lo genera Meta) que el backend compara en el handshake `GET` descrito en la §7.
4. Suscribirse al campo `messages` — cubre estados de entrega y mensajes entrantes en un solo webhook, tal como se diseñó en la §7.

> **Orden que importa:** este paso exige que el backend ya esté desplegado (§18) y respondiendo el handshake **antes** de guardar la configuración del webhook — Meta verifica la URL en el momento de guardar, no después. No se puede configurar el webhook antes de tener el servidor arriba.

### 8. Guardar las credenciales

Mismo patrón que `DATABASE_URL` (§18) y la credencial de Firebase (§20): en el `.env` protegido del servidor Windows, nunca en el repositorio.

```
# .env
WHATSAPP_PHONE_NUMBER_ID=...
WHATSAPP_ACCESS_TOKEN=...
WHATSAPP_APP_SECRET=...          # el que valida X-Hub-Signature-256 (§7)
WHATSAPP_WEBHOOK_VERIFY_TOKEN=...
```

### 9. Límite de mensajería y calidad del número

Meta empieza con un límite de cuántas conversaciones se pueden *iniciar* en 24 horas, que sube automáticamente con el volumen, la calidad de las conversaciones y la verificación completa de la empresa del paso 1. WhatsApp Manager muestra un indicador de calidad del número (verde/amarillo/rojo); si cae a rojo, Meta puede pausar el envío. Vale la pena vigilarlo junto con las demás métricas de la §13, no es algo que se configure una sola vez y se olvide.

> **Costos:** la Cloud API cobra por conversación de 24 horas según categoría y país, y Meta ajusta estas tarifas con cierta frecuencia — conviene revisar el valor vigente para Colombia en Business Manager → Facturación en el momento de presupuestar, en vez de asumir una cifra fija aquí que puede quedar desactualizada.

---

## §22 — Backend real: C#/.NET (`APIOmniTask/`)

El código vive en [`APIOmniTask/`](../APIOmniTask/) en la raíz del repo, junto a `docs/` y `db/`. Es la implementación real de los endpoints, reglas de negocio y esquema que ya describen las §3, §6, §7, §9, §16 y §17 — ese contrato no cambió, solo el lenguaje. IIS ya aloja otras APIs en este servidor con el mismo patrón de sub-aplicación, así que esa parte de la configuración no se repite aquí.

### Estructura (Clean Architecture, 4 proyectos)

```
APIOmniTask/
├── OmniTask.sln
├── src/
│   ├── OmniTask.Domain/           # Solo enums — sin dependencias externas (§23: sin entidades ORM)
│   │   └── Enums.cs
│   │
│   ├── OmniTask.Application/       # Casos de uso — DTOs, interfaces (sin implementación)
│   │   ├── Dtos.cs
│   │   ├── Interfaces.cs           # IAuthService, IActivityService, IWhatsAppClient, IPasswordHasher...
│   │   └── ApiException.cs
│   │
│   ├── OmniTask.Infrastructure/    # Implementación real — SQL, Hangfire, clientes externos (§23)
│   │   ├── Services/               # AuthService, ActivityService, ContactService, DeviceService,
│   │   │                            # NotificationService — ADO.NET puro, sin ORM
│   │   ├── ExternalServices/       # WhatsAppCloudApiClient, FirebasePushSender
│   │   └── BackgroundJobs/         # ReminderDispatchJob, UnscheduledDigestJob
│   │
│   └── OmniTask.Api/               # Controllers, Program.cs, seguridad, config
│       ├── Controllers/            # Auth, Activities, Contacts+Devices, Notifications, WhatsAppWebhook
│       ├── Security.cs             # Argon2PasswordHasher, JwtTokenFactory, ApiExceptionMiddleware
│       ├── Program.cs
│       ├── appsettings.json        # solo placeholders — secretos reales fuera del repo
│       └── web.config
```

### Endpoints → controlador

| Recurso | Controlador | Endpoints |
|---|---|---|
| Auth | `AuthController` | `POST /auth/register`, `/login`, `/refresh`, `/logout`, `GET /auth/me`, `PATCH /auth/me` |
| Activities | `ActivitiesController` | CRUD completo + `GET /activities/unscheduled` |
| Contacts | `ContactsController` | CRUD completo |
| Devices | `DevicesController` | `POST/GET/DELETE /devices` |
| Notifications | `NotificationsController` | `GET /notifications`, `/unread-count`, `PATCH /{id}/ack`, `POST /ack-all` |
| WhatsApp | `WhatsAppWebhookController` | `GET`/`POST /webhooks/whatsapp` |

Todas menos `AuthController` (login/registro) y el webhook llevan `[Authorize]` — el `userId` sale siempre del claim `sub` del JWT (`User.GetUserId()`), nunca de un parámetro que llegue en la URL o el body.

### Tres decisiones que simplifican el despliegue en este servidor

- **Hangfire reemplaza Celery + Redis** (`ReminderDispatchJob`, `UnscheduledDigestJob`): mismo `SELECT ... FOR UPDATE SKIP LOCKED` para no duplicar envíos, pero corriendo dentro del propio proceso de IIS — sin un worker ni un scheduler aparte que mantener.
- **Los refresh tokens viven en la tabla `refresh_tokens`** (Postgres), no en Redis — aplicar [`db/02_add_refresh_tokens_table.sql`](../db/02_add_refresh_tokens_table.sql) sobre la base ya existente antes de desplegar esta API.
- **Sin Redis/Memurai en absoluto**: entre Hangfire y los refresh tokens, PostgreSQL es el único motor de datos que este backend necesita.

### Paquetes NuGet principales

`Npgsql` (ADO.NET directo — ver addendum de la §23, ya no hay ORM de por medio), `Hangfire.AspNetCore` + `Hangfire.PostgreSql`, `Microsoft.AspNetCore.Authentication.JwtBearer`, `Konscious.Security.Cryptography.Argon2` (mismo hashing que ya estaba decidido), `FirebaseAdmin`, `Swashbuckle.AspNetCore`.

### Antes de desplegar

1. Correr, en este orden, `db/02_add_refresh_tokens_table.sql` y `db/03_stored_procedures_and_functions.sql` contra la base existente.
2. Completar `appsettings.Production.json` (gitignored) o las variables de entorno del Application Pool con `ConnectionStrings:Default`, `Jwt:Secret`, `WhatsApp:*` y `Firebase:CredentialsPath` — nunca los valores reales en `appsettings.json`.
3. Publicar (`dotnet publish -c Release`) y copiar el resultado a la sub-aplicación `/APIOmniTask` de IIS, con el mismo procedimiento que ya usan las otras APIs de este servidor.

---

## §23 — Stored procedures y functions de PostgreSQL

Toda la lógica de negocio de la API — antes repartida entre EF Core/LINQ y el código C# de los servicios — se movió a PostgreSQL: [`db/03_stored_procedures_and_functions.sql`](../db/03_stored_procedures_and_functions.sql) define **funciones** (`fn_*`, invocadas con `SELECT`, para lecturas y escrituras que devuelven datos) y **procedimientos** (`sp_*`, invocados con `CALL`, para efectos secundarios puros: revocar, borrar, marcar). Los servicios de `APIOmniTask/src/OmniTask.Infrastructure/Services/` ya no usan Entity Framework — llaman directo vía ADO.NET (`NpgsqlDataSource`/`NpgsqlCommand`) a estas funciones y procedimientos. El contrato de la API (§6) no cambió.

### Convención de errores

Cada función/procedimiento que necesita señalar un error de negocio usa `RAISE EXCEPTION ... USING ERRCODE = '...'` con un código propio, para que C# traduzca sin depender del texto del mensaje:

| SQLSTATE | Significado | HTTP |
|---|---|---|
| `OT001` | recurso no encontrado | 404 |
| `OT002` | conflicto | 409 |
| `OT003` | validación inválida | 422 |

`SqlServiceBase` (Infrastructure) centraliza esta traducción en un solo lugar — ningún servicio individual tiene su propio `try/catch` de `PostgresException`.

### Mapeo endpoint → función/procedimiento

| Endpoint | Objeto SQL |
|---|---|
| `POST /auth/register` | `fn_register_user` — chequeo de unicidad + INSERT en el mismo statement, cierra la carrera que tenía la versión anterior |
| `POST /auth/login` | `fn_get_user_by_email` |
| `POST /auth/refresh` | `fn_rotate_refresh_token` — valida y revoca en un solo UPDATE atómico |
| `POST /auth/logout` | `sp_revoke_refresh_token` |
| `GET`/`PATCH /auth/me` | `fn_get_user_by_id` / `fn_update_user_profile` |
| `POST /activities` | `fn_create_activity` — inserta y genera los reminders automáticos en la misma transacción |
| `GET /activities` | `fn_list_activities` — filtros + paginación + conteo total en una sola llamada (`COUNT(*) OVER()`) |
| `GET /activities/unscheduled` | `fn_list_unscheduled_activities` |
| `GET /activities/{id}` | `fn_get_activity_by_id` + `fn_list_reminders_for_activity` |
| `PATCH`/`DELETE /activities/{id}` | `fn_update_activity` — la más cargada de reglas: reprogramar, cerrar, regenerar reminders |
| `POST`/`GET`/`PATCH`/`DELETE /contacts` | `fn_create_contact`, `fn_list_contacts`, `fn_update_contact`, `sp_delete_contact` |
| `POST`/`GET`/`DELETE /devices` | `fn_upsert_device` (UPSERT nativo), `fn_list_devices`, `sp_delete_device` |
| `GET /notifications`, `/unread-count` | `fn_list_notifications`, `fn_unread_notification_count` |
| `PATCH /notifications/{id}/ack`, `POST /ack-all` | `sp_acknowledge_notification`, `sp_acknowledge_all_notifications` |
| Webhook de WhatsApp | `sp_update_notification_delivery_status` |
| `ReminderDispatchJob` (Hangfire) | `fn_claim_due_reminders`, `fn_get_reminder_dispatch_info`, `fn_log_notification`, `sp_mark_reminder_sent`/`failed` |
| `UnscheduledDigestJob` (Hangfire) | `fn_unscheduled_digest_counts` |

### Lo que se corrigió al bajar la lógica a la base

Escribir `fn_update_activity` obligó a resolver dos huecos que tenía la versión anterior del endpoint:

- **`p_clear_starts_at`/`p_clear_ends_at` explícitos**: antes, un valor `NULL` en el request no se podía distinguir de "campo no enviado", así que nunca se podía devolver una actividad al backlog quitándole la fecha. Ahora el cliente lo pide con un flag propio.
- **El `status` se resincroniza con la fecha** cuando el cliente no lo especifica: asignar fecha por primera vez pasa a `scheduled`; quitarla, a `unscheduled` — antes, "Programar" (§14) dejaba el status desincronizado con la fecha real.

Además, mover el UPSERT de `devices` y el registro de `users` a la base (`fn_upsert_device`, `fn_register_user`) cierra dos carreras que existían al hacerlo en dos pasos desde la aplicación (verificar y luego escribir): ahora la restricción `UNIQUE`/`ON CONFLICT` de Postgres es la única palabra.

### Addendum a la §22: sin ORM

`OmniTask.Infrastructure` ya no depende de `Microsoft.EntityFrameworkCore` ni de un `DbContext` — el único punto de acceso a la base es el `NpgsqlDataSource` (el mismo que ya mapeaba los ENUM nativos de Postgres a enums de C#, §22), inyectado como singleton en `Program.cs`. Cada servicio abre una conexión, llama a su función/procedimiento y mapea el `NpgsqlDataReader` directo al DTO de respuesta.

---

## §24 — App móvil real: Flutter (`omnitask_app/`)

El código vive en [`omnitask_app/`](../omnitask_app/) en la raíz del repo, junto a `APIOmniTask/`, `db/` y `docs/`. Es la implementación real de todo lo diseñado en las §12, §14, §15, §16, §17, §19 y §20 — el mismo Riverpod + go_router + Dio ya documentados, ahora como archivos de verdad, apuntando a la API real de la §22/§23.

### Estructura

```
omnitask_app/
├── pubspec.yaml
├── build.yaml                      # json_serializable en snake_case global (§6, §23) —
│                                    # una sola configuración en vez de anotar cada modelo
├── lib/
│   ├── main.dart                    # ProviderContainer manual: inicializa notificaciones
│   │                                # locales y el listener de push antes de runApp
│   ├── core/
│   │   ├── config/api_config.dart    # baseUrl real (§19)
│   │   ├── network/dio_client.dart   # interceptor de refresh
│   │   ├── storage/secure_token_storage.dart
│   │   └── router/app_router.dart    # GoRouterRefreshStream + redirect + deep link
│   ├── models/                      # 10 modelos freezed — Activity, User, Contact,
│   │                                # Device, NotificationItem, AuthState (sealed), etc.
│   └── features/
│       ├── auth/                     # AuthNotifier, login, registro
│       ├── calendar/                 # SfCalendar, detalle, edición (crear/editar/programar)
│       ├── backlog/                  # pendientes por programar
│       ├── contacts/                 # repositorio para el picker con debounce
│       ├── notifications/            # registro de dispositivo, push en primer plano, bandeja
│       └── settings/                 # perfil, preferencias, dispositivos
```

### Lo que exigió el cambio de la §23 en el lado del cliente

El endpoint `PATCH /activities/{id}` ganó `clear_starts_at`/`clear_ends_at` explícitos al bajar la lógica a `fn_update_activity` (§23) — `ActivityRepository.update()` y la pantalla de edición ya se actualizaron para mandarlos: el switch "Sin fecha por ahora" activado envía `clear_starts_at: true` en vez de simplemente omitir `starts_at`, que antes no tenía forma de distinguirse de "no tocar este campo".

### Detalles de implementación que vale la pena señalar

- **`main.dart` usa un `ProviderContainer` manual** (`UncontrolledProviderScope`) en vez del `ProviderScope` simple del diseño original — hace falta para poder `await` la inicialización de `flutter_local_notifications` y leer `pushMessageListenerProvider` antes de `runApp`, algo que un `ProviderScope` declarativo no permite expresar directamente.
- **`ContactPickerField`** no usa el widget `Autocomplete` de Flutter (su `optionsBuilder` es síncrono) — es un `TextField` con `Timer` de debounce propio y una lista desplegable simple, para poder buscar contra `GET /contacts?search=` de forma asíncrona.
- **Validación agregada en el formulario de actividad**: si "Sin fecha por ahora" queda desactivado pero no se selecciona ninguna fecha, ahora avisa explícitamente en vez de enviar un PATCH que no cambia nada en silencio.

### Verificado con `flutter analyze` — tres bugs reales que salieron al compilar de verdad

`flutter pub get`, `dart run build_runner build --delete-conflicting-outputs` y `flutter analyze` ya se corrieron contra el código (Flutter 3.44.6 estable) — no se quedó solo en revisión manual. Salieron tres errores reales, ya corregidos:

- **Error de sintaxis en `dio_client.dart`**: un ternario anidado con `as String?` justo antes del `:` confundía al parser (`mapApiError` ahora usa `if` explícitos en vez de una expresión anidada).
- **`GoRouterRefreshStream` asumía que `authNotifierProvider` exponía un `.stream`** — `AsyncNotifierProvider` no tiene ese getter. Se reemplazó por `GoRouterRefreshNotifier`, un `ChangeNotifier` alimentado por `ref.listen(...)`, la forma correcta de conectar un provider de Riverpod al `refreshListenable` de go_router.
- **`ActivityFormController.update(...)` chocaba con el método `update(cb)`** que `AsyncNotifierBase` ya define — se renombró a `updateActivity`.

`flutter analyze` termina en cero problemas. Sigue pendiente `flutterfire configure` (genera `lib/firebase_options.dart` contra el proyecto de Firebase real, §20) y el build de producción con `flutter build appbundle`/`build ipa --release --dart-define=API_BASE_URL=...` (§13, §19), que sí dependen de credenciales y del toolchain de Android/iOS reales.

## §25 — Proyecto de pruebas del backend (`APIOmniTask/tests/OmniTask.Tests/`)

Vive en [`APIOmniTask/tests/OmniTask.Tests/`](../APIOmniTask/tests/OmniTask.Tests/), agregado a `OmniTask.sln`. Usa xUnit + `Xunit.SkippableFact`, con una `ProjectReference` a `OmniTask.Api.csproj` (que arrastra a `Application` e `Infrastructure`).

### Dos categorías de prueba, con requisitos distintos

- **Unitarias puras** (`Security/Argon2PasswordHasherTests.cs`, `Security/JwtTokenFactoryTests.cs`, `Infrastructure/PostgresExceptionMapperTests.cs`) — no tocan Postgres. La última fue posible al descubrir que `Npgsql.PostgresException` expone un constructor público de 4 parámetros (`messageText, severity, invariantSeverity, sqlState`), lo que permite construir una excepción con el SQLSTATE deseado y verificar que `PostgresExceptionMapper` (§23) la traduce al código HTTP correcto — incluyendo el caso en que un SQLSTATE no reconocido debe devolver `null` para que `SqlServiceBase` relance el error original en vez de disfrazarlo.
- **De integración real** (`Infrastructure/AuthServiceTests.cs`, `Infrastructure/ActivityServiceTests.cs`, `Infrastructure/ContactServiceTests.cs`) — instancian `AuthService`/`ActivityService`/`ContactService` de verdad contra un Postgres real, ejercitando las funciones y procedimientos de la §23 sin mocks: si el SQL y el C# se desincronizan, esto es lo primero que debería fallar, no un usuario reportándolo en producción.

### `DatabaseFixture`: por qué las de integración se saltan en vez de fallar

`Infrastructure/DatabaseFixture.cs` implementa `IAsyncLifetime`, arma el mismo `NpgsqlDataSourceBuilder` con los 10 mapeos de enum que `Program.cs`, y en `InitializeAsync()` intenta abrir una conexión real usando la variable de entorno `TEST_DATABASE_URL` (con un `localhost` por defecto para desarrollo local). Si la conexión falla, `IsAvailable` queda en `false` en vez de propagar la excepción. Cada prueba de integración empieza con `Skip.IfNot(_fixture.IsAvailable, ...)` — así el proyecto compila y corre igual en una máquina sin Postgres (como este sandbox de desarrollo, que no tiene Postgres/Docker/sudo disponibles) sin reportar fallos que en realidad son "no hay base de datos aquí".

Casos cubiertos por las pruebas de integración, todos ejercitando reglas que viven en el SQL de la §23:

- **Auth**: registro emite ambos tokens; correo duplicado → 409 (`fn_register_user`); login con contraseña incorrecta → 401; rotación de refresh token de un solo uso — reutilizar un token ya rotado debe fallar con 401, no emitir un par nuevo (`fn_rotate_refresh_token`); logout revoca el token; actualizar perfil persiste el cambio.
- **Activities**: crear con fecha genera reminders `pending` y queda `scheduled`; crear sin fecha fuerza `unscheduled` sin reminders; reprogramar cancela (`failed`) los reminders viejos y crea los nuevos; `clear_starts_at` regresa la actividad al backlog; cancelar marca los reminders pendientes como `failed` sin enviarlos; acceder a la actividad de otro usuario → 404 (`fn_get_activity_by_id` filtra por `user_id`).
- **Contacts**: crear contacto; borrar un contacto sin actividades asociadas; borrar un contacto con actividades asociadas → 409 (`sp_delete_contact`), para no dejar actividades con un `contact_id` colgante.

### Verificado dos veces: local (con skip) y en GitHub Actions (de verdad, sin skip)

Localmente, `dotnet build`/`dotnet test` sobre `OmniTask.sln` dan **13 pruebas unitarias pasando, 16 de integración saltadas** (0 fallos) — este entorno de desarrollo no tiene Postgres/Docker/sudo disponibles, así que `DatabaseFixture.IsAvailable` queda en `false` y las de integración se saltan en vez de fallar.

En **GitHub Actions**, donde `backend-ci.yml` sí trae su propio contenedor de Postgres (§13), las 29 pruebas corren de verdad — nada se salta. Le tomó tres corridas reales sobre `main` llegar a verde, y las dos primeras fallas fueron bugs genuinos en las pruebas mismas, no en el backend:
1. Comparar un `DateTimeOffset` (precisión de tick, 100ns) contra el mismo valor después de un round-trip por `timestamptz` de Postgres, que solo guarda microsegundos — se corrigió truncando el valor esperado a microsegundos antes de comparar.
2. Asumir que reprogramar una actividad borra los reminders viejos — en realidad `fn_update_activity` los marca `failed` e inserta los nuevos `pending` en la misma lista, así que la prueba esperaba `Assert.All(..., "pending")` sobre una colección que legítimamente mezcla ambos estados; se corrigió separando la aserción en dos grupos.

Tercera corrida: **29/29 en verde**. Es la prueba de que "compila y las pruebas pasan localmente" no es lo mismo que "el pipeline de CI pasa" — ambos bugs solo salieron a la luz al ejecutar contra un Postgres real dentro del propio workflow.

## §26 — Primer release de Android instalable

Hasta ahora `omnitask_app/` solo se había verificado con `flutter analyze`/`flutter test` y como app de escritorio Linux (§24) — nunca se había compilado como app móvil real, porque la carpeta `android/` nunca se generó del todo. Esta sección documenta el primer APK instalable en un celular real, y los problemas — reales, no hipotéticos — que solo aparecieron al intentarlo.

### Herramientas que hicieron falta

Compilar Android requiere un toolchain que no estaba disponible: JDK 17 y el Android SDK (`platform-tools`, `build-tools`, una plataforma, el NDK). Se instalaron en espacio de usuario, sin root, igual que se hizo con el propio Flutter (§24) — `flutter doctor` quedó en verde para el toolchain de Android después.

Con eso, `flutter create --platforms=android --org com.clinicacampbell .` generó el `android/` que faltaba, con cuidado de no tocar `lib/`, `pubspec.yaml` ni las pruebas existentes (se descartó el `test/widget_test.dart` boilerplate que trae la plantilla, que no aplica a esta app).

### Bug real: la app crasheaba sin Firebase configurado

`firebase_options.dart` no existe todavía (falta `flutterfire configure` contra un proyecto Firebase real, §20 — pendiente porque requiere una cuenta/consola de Firebase que este entorno no tiene). El código ya sabía esto y dejaba `Firebase.initializeApp()` comentado en `main.dart` — pero cuatro lugares seguían llamando a `FirebaseMessaging` sin comprobar si había una app de Firebase inicializada: el listener de push en primer plano, el registro de dispositivo (llamado justo después de login/registro), los deep links del router, y el provider del token FCM en Configuración. Sin el guard, cualquiera de esos falla en el primer frame o en el primer login. Se corrigió agregando `if (Firebase.apps.isEmpty) return;` (o equivalente) en los cuatro — el resto de la app funciona igual, y el push queda inactivo hasta que exista un proyecto Firebase real.

### Bugs reales de dependencias, solo visibles al compilar release

Ninguno de estos tres lo atrapó `flutter analyze` ni `flutter test` — los tres son incompatibilidades que solo aparecen en la compilación AOT completa de `flutter build apk --release`:

- **`syncfusion_flutter_calendar` 26.2.14** define su propia clase `SelectionDetails`, que quedó ambigua contra una clase del mismo nombre que el framework Flutter agregó en una versión posterior a cuando se pineó esa dependencia. Se subió a `^34.1.31` (arrastrando `intl` a `^0.20.2`, que `flutter_localizations` exige a partir de esa versión de Syncfusion).
- **`flutter_local_notifications` 17→22** movió `initialize()` y `show()` de parámetros posicionales a nombrados, y a partir de la v17 exige *core library desugaring* habilitado en Gradle (`isCoreLibraryDesugaringEnabled = true` + dependencia `desugar_jdk_libs`).
- **`flutter_timezone` 1.0.8→5.1.0** cambió `getLocalTimezone()` de devolver un `String` a devolver un `TimezoneInfo` (con `.identifier` para el nombre IANA) — afectaba a `register_screen.dart` y `profile_screen.dart`.

Después de los tres upgrades, `flutter analyze` sigue en cero problemas y las 21 pruebas del §24 siguen pasando — y `flutter-ci.yml` (§13) corrió en GitHub Actions sobre este mismo commit y confirmó lo mismo en verde.

### Firma: un keystore propio, no la clave de debug compartida

El primer build de prueba quedó firmado con la clave de debug genérica de Flutter — la misma en cualquier máquina con Flutter instalado, útil solo para probar en un único dispositivo propio. Para algo que se va a compartir con más de una persona del equipo, se generó un keystore dedicado de OmniTask (`keytool -genkeypair`, RSA 2048, validez 10.000 días) y se conectó en `android/app/build.gradle.kts` vía `android/key.properties` — ni el `.jks` ni `key.properties` van al repo (`android/.gitignore` ya los excluía por defecto); si `key.properties` no existe, el build cae de vuelta a la firma de debug para que `flutter run --release` siga funcionando en un checkout nuevo sin esas credenciales.

> **Importante — este keystore vive solo en el entorno donde se generó.** Android exige la misma firma para instalar una "actualización" sobre una app ya instalada; si este `.jks` se pierde, cualquier build futuro necesitará desinstalar y reinstalar en cada celular en vez de actualizar en el sitio. Guardar `android/app/omnitask-release.jks` y `android/key.properties` en un lugar seguro (gestor de contraseñas o vault del equipo) antes de que este entorno de trabajo deje de existir.

### El APK, publicado como GitHub Release

```
flutter build apk --release \
  --dart-define=API_BASE_URL=https://appsintranet.esculapiosis.com/APIOmniTask/api/v1
```

Build verificado con `aapt dump badging` (application ID `com.clinicacampbell.omnitask_app`, label "OmniTask", `minSdk 24`/`targetSdk 36`, permisos `INTERNET`/`POST_NOTIFICATIONS` presentes) y `apksigner verify` (confirma la firma con el certificado propio de OmniTask, no el de debug). **No se pudo instalar en un dispositivo o emulador Android real dentro de este entorno de trabajo** — no hay `/dev/kvm` para un emulador ni un teléfono físico conectado, así que la instalación real en un celular queda pendiente de que alguien la haga fuera de este entorno.

El `.apk` (55.4 MB) se publicó como asset del release [`app-v1.0.0`](https://github.com/WILSP1971/AppOmniTask/releases/tag/app-v1.0.0) en GitHub — no se comitea al repo (es un binario grande, y un Release da una URL de descarga estable sin inflar el historial de git). La página [`docs/descarga-app.html`](descarga-app.html) trae el botón de descarga directo, los pasos para habilitar "fuentes desconocidas" (necesario porque esta build no está en Play Store), y el hash SHA-256 para verificar la descarga.

### El keystore, respaldado y disponible para CI vía GitHub Actions secrets

El `.jks` generado más arriba y su contraseña se sacaron de este entorno de trabajo hacia un lugar seguro fuera de git, y además se guardaron cifrados como secrets del repositorio para que un workflow de CI pueda firmar sin que nadie tenga que copiar el archivo a mano en cada release:

- `ANDROID_KEYSTORE_BASE64` — el `.jks` codificado en base64.
- `ANDROID_KEYSTORE_PASSWORD` — la contraseña (misma para store y key, por ser PKCS12).
- `ANDROID_KEY_ALIAS` — `omnitask`.

GitHub cifra estos valores en reposo y los enmascara automáticamente en cualquier log de Actions — ni siquiera con acceso de administrador al repo se puede volver a leer su contenido, solo sobrescribirlos.

### `android-release.yml`: firma y publica automáticamente en cada tag

[`.github/workflows/android-release.yml`](../.github/workflows/android-release.yml) dispara con cualquier tag `app-v*.*.*` y reproduce a mano alzada exactamente los pasos de esta sección: `flutter analyze`/`flutter test` primero (nunca firmar un build que no pasa lo mínimo que ya corre en cada PR, §13), reconstruye el keystore a partir de los tres secrets, compila con `--build-name`/`--build-number` derivados del tag y del número de corrida, y publica (o actualiza, si el workflow se vuelve a correr sobre el mismo tag) un GitHub Release con cuatro assets: el `.apk` con nombre de versión y su `.sha256`, más una copia fija `omnitask-latest.apk`/`.sha256` — esta última es la que enlaza `docs/descarga-app.html`, así que la página de descarga no necesita editarse en cada release nuevo.

```yaml
# .github/workflows/android-release.yml
name: Android Release
on:
  push:
    tags: ["app-v*.*.*"]
permissions:
  contents: write
jobs:
  build-sign-release:
    runs-on: ubuntu-latest
    defaults:
      run:
        working-directory: omnitask_app
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
        with: { flutter-version: "3.44.6", channel: "stable" }
      - run: flutter pub get
      - run: dart run build_runner build --delete-conflicting-outputs
      - run: flutter analyze
      - run: flutter test
      - name: Reconstruir el keystore desde los secrets
        env:
          ANDROID_KEYSTORE_BASE64: ${{ secrets.ANDROID_KEYSTORE_BASE64 }}
          ANDROID_KEYSTORE_PASSWORD: ${{ secrets.ANDROID_KEYSTORE_PASSWORD }}
          ANDROID_KEY_ALIAS: ${{ secrets.ANDROID_KEY_ALIAS }}
        run: |
          echo "$ANDROID_KEYSTORE_BASE64" | base64 -d > android/app/omnitask-release.jks
          cat > android/key.properties <<EOF
          storePassword=$ANDROID_KEYSTORE_PASSWORD
          keyPassword=$ANDROID_KEYSTORE_PASSWORD
          keyAlias=$ANDROID_KEY_ALIAS
          storeFile=omnitask-release.jks
          EOF
      - id: version
        run: echo "name=${GITHUB_REF_NAME#app-v}" >> "$GITHUB_OUTPUT"
      - run: |
          flutter build apk --release \
            --build-name="${{ steps.version.outputs.name }}" \
            --build-number="${{ github.run_number }}" \
            --dart-define=API_BASE_URL=https://appsintranet.esculapiosis.com/APIOmniTask/api/v1
      - if: always()
        run: rm -f android/app/omnitask-release.jks android/key.properties
      # ... empaqueta omnitask-<versión>.apk + omnitask-latest.apk y sus .sha256,
      # y los publica con `gh release create`/`gh release upload --clobber`.
```

No se pudo disparar este workflow de verdad en este entorno (crear un tag y esperar a que GitHub Actions lo corra excede lo que se puede verificar aquí) — quedó revisado línea por línea contra lo que ya se hizo a mano en esta misma sección, pero su primera ejecución real será el próximo tag `app-v*.*.*` que se empuje.

## §27 — Calendario: vistas Día/Semana/Mes/Agenda, scroll a la hora actual

Motivado por fallas reales reportadas ya en producción (v1.0.4): solo existía la vista de semana, una cita de la tarde/noche quedaba enterrada al fondo de la rejilla porque la vista siempre abría arriba, y la caja de la cita en la última columna se veía recortada/poco legible.

- **Selector de vistas**: `allowedViews: [day, week, month, schedule]` en `SfCalendar` — el propio header de Syncfusion ofrece el switcher, no hizo falta un control propio.
- **Agenda** (`CalendarView.schedule`) como forma principal de ver "qué tengo hoy/próximo": lista agrupada por día.
- **Apertura centrada en la hora actual**: `initialDisplayDate: DateTime.now()` en vez de dejar que la vista abra en la parte de arriba de la rejilla.
- **Caja de la cita rehecha** vía `appointmentBuilder` propio (color por tipo de actividad, texto con elipsis, límites explícitos) en vez del render por defecto de Syncfusion, que es lo que se veía recortado.

Dos cuidados explícitos para no reintroducir el bucle de recarga que ya se había corregido antes (v1.0.4, `skipLoadingOnReload: true` + `if (range != actual) setRange(...)`):
- Agenda no reporta un rango visible en `onViewChanged` como las demás vistas — reporta un solo `visibleDates` (el día ancla). Pedir `from == to` habría dejado la lista vacía, así que en su lugar se pide una ventana de 3 meses hacia adelante, redondeada a inicio de mes — la misma guarda "solo actualizar si el rango cambió" sigue funcionando porque la ventana no cambia con cada micro-scroll dentro del mismo mes.
- `ActivityRepository.fetchActivities` ahora pagina de verdad (100 por página) hasta juntar el `total` que reporta el backend, en vez de quedarse con los 50 del límite por defecto del endpoint — necesario porque Mes/Agenda cubren rangos donde fácilmente hay más de 50 actividades.

Verificado con `flutter analyze` (limpio) y 26/26 pruebas (2 nuevas de paginación). El release `app-v1.0.5` se compiló y firmó con el mismo keystore — no se pudo instalar en un dispositivo real dentro de este entorno para confirmar visualmente el resultado.

## §28 — Menú lateral, regla de autorización permanente, y un bug de locale encontrado de paso

### Menú lateral (Calendario / Consultas / Cerrar sesión)

`AppDrawer` (`lib/core/navigation/app_drawer.dart`) se agregó a las tres pantallas que el propio menú enlaza — Calendario, Backlog y la nueva pantalla de consulta — para que moverse entre ellas sea consistente, sin duplicar el menú en pantallas más profundas (detalle, edición, ajustes) que ya tienen su propia navegación:

- **Calendario** → `/` (donde la app ya iniciaba).
- **Consultas** (submenú):
  - **Actividades calendario según fecha** → pantalla nueva, `/consultas/por-fecha` (`activities_by_date_screen.dart` + `activitiesByDateProvider`, family por día): elegir un día puntual y ver esa lista, en vez de navegar la rejilla del calendario.
  - **Actividades sin programar** → `/backlog`, ya existente.
- **Cerrar sesión** → mismo diálogo de confirmación que ya tenía Ajustes (§16), factorizado a `core/auth/logout_action.dart` para no duplicarlo entre el menú y Ajustes.

### Bug real encontrado de paso: `DateFormat` con locale sin inicializar

Al construir la pantalla de consulta por fecha con un `DateFormat('...', 'es_CO')` (igual al que ya usaba el detalle de actividad, §14), se confirmó con un script Dart aislado que **`activity_detail_screen.dart` ya estaba roto**: sin `initializeDateFormatting()`, cualquier `DateFormat` con locale explícito lanza `LocaleDataException` — el detalle de cualquier actividad programada crasheaba al abrirse. Se corrigió agregando `await initializeDateFormatting('es_CO');` en `main()` antes de `runApp`, cubriendo tanto el detalle de actividad como la pantalla nueva.

### Regla de autorización permanente (`CLAUDE.md`)

A partir de esta conversación, y confirmado explícitamente por el usuario, ya no se pide confirmación antes de escribir código, actualizar la documentación, o hacer `commit`/`push` a `main` en este repositorio — reemplaza el patrón de "¿confirmas commit y push?" usado en el resto de esta conversación. Sigue pidiéndose confirmación para lo genuinamente difícil de revertir: force-push, `reset --hard`, borrar ramas/tags, o tocar secretos/infraestructura fuera de este repo. La regla completa vive en [`CLAUDE.md`](../CLAUDE.md) en la raíz del proyecto.

## §29 — Adjuntos, link de reunión, rediseño real, y guía de pruebas de la API

Entre §28 y esta sección, otra sesión trabajó en paralelo usando el flujo de agentes de `.swarm/` (DOCTOR STRANGE/CAPTAIN AMERICA/WOLVERINE/BLACK WIDOW/DAREDEVIL/HAWKEYE) y llevó la app de v1.0.6 a v1.0.9: **SPEC-002** (adjuntos de documentos/imágenes en actividades) y **SPEC-003** (link de reunión Meet/Teams/otro, con copiar/abrir/compartir) quedaron `IMPLEMENTADA`, y **SPEC-001** reemplazó por completo el calendario de Syncfusion por `table_calendar` (círculo de selección + puntitos por tipo, tarjetas de "Mis citas", bottom nav flotante) con un tema oscuro Material 3 propagado a toda la app. El detalle completo de criterios de aceptación, checkpoints y limitaciones de cada SPEC vive en `.swarm/CHECKPOINTS.md` y `.swarm/specs.json` — no se duplica aquí.

Un hallazgo real de esa etapa: `app-v1.0.10` quedó con el **build de release roto** en GitHub Actions (`flutter analyze`/`flutter test` pasaban, pero `flutter build apk --release` no) — `file_picker ^11.0.2` deja de aplicar el plugin de Gradle `org.jetbrains.kotlin.android` cuando detecta AGP≥9, asumiendo el soporte de "Built-in Kotlin" que Flutter 3.44.6 todavía no tiene para ese plugin, así que sus fuentes `.kt` quedaban sin compilar y `GeneratedPluginRegistrant.java` fallaba con `cannot find symbol: class FilePickerPlugin`. Se corrigió fijando `file_picker: 10.3.10` (que siempre aplica el plugin sin esa detección condicional) — confirmado con un `flutter build apk --release` real, mismo keystore. Publicado como `app-v1.0.11`.

### Guía de pruebas de la API (`docs/pruebas-api.html`)

Página nueva, independiente de este documento (no es arquitectura, es una referencia operativa): los 26 endpoints reales que invoca `omnitask_app` — extraídos de los repositorios (`lib/features/*/data/*.dart`), no de esta documentación — agrupados por Auth/Actividades/Adjuntos/Contactos/Dispositivos/Notificaciones, cada uno con datos de ejemplo y un snippet `fetch()` listo para pegar en la consola del navegador (F12), más su equivalente en `curl`. Pensada para que el Lead pueda validar la API real sin instalar Postman ni nada aparte — subir un adjunto es la única excepción que necesita un selector de archivo real en vez de un `fetch` de una línea, y el propio snippet lo crea al vuelo.

## §30 — SPEC-004: push end-to-end y actividades sin fecha visibles

Firebase quedó configurado con `flutterfire configure` contra el proyecto real **`omnitask-agenda`** (el mismo que ya usaba `firebase-admin.json` del backend, confirmado explícitamente por el Lead tras descubrir que dos cuentas de Google distintas veían dos proyectos Firebase distintos — un desajuste que habría dejado el push apuntando a un proyecto equivocado sin ningún error visible). `lib/firebase_options.dart` se commitea (no es secreto, solo `android/app/google-services.json` se reconstruye en CI desde un secret base64); `main.dart` ya llama `Firebase.initializeApp(...)` de verdad, ya no está comentado.

Con la infraestructura activa, esta SPEC agregó la UX que faltaba:

- **Permiso de notificaciones**: `FirebaseMessaging.instance.requestPermission()` antes de pedir el token FCM, disparado en `device_registration_notifier.dart::registerCurrentDevice()`.
- **Pantalla de Dispositivos ya no queda vacía sin salida**: `devices_screen.dart` agrega `_EmptyDevicesState` con un botón "Activar notificaciones en este dispositivo" cuando `myDevicesProvider` devuelve lista vacía.
- **Botón de menú en el header del calendario**: `agenda_header.dart` es un `PreferredSizeWidget` a medida, no un `AppBar` real, así que Flutter nunca agregó solo el ícono ☰ — se agregó a mano llamando a `Scaffold.of(context).openDrawer()`.
- **"Pendientes por programar" visible en el Home**: antes solo se llegaba a las actividades sin fecha desde el Drawer/Backlog; ahora `calendar_screen.dart` reutiliza `AppointmentsSection` (con otro `title`) para mostrarlas también debajo de "Mis citas", sin duplicar el componente.

Detalle de criterios de aceptación y limitaciones (sin dispositivo real para confirmar la entrega efectiva de un push) en `.swarm/CHECKPOINTS.md`.

## §31 — SPEC-005/006/007: color por día, tipo Cumpleaños y limpiar notificaciones

Tercer lote de trabajo bajo el mismo flujo de `.swarm/` (SPEC-005/006/007, las tres `APROBADA` → implementadas en la misma sesión), a partir de un pedido directo del Lead con imágenes de referencia (`docs/contexto/agenda2.jpg`, `docs/context/LoginApp.jpeg`, `docs/context/LoginAppFondo.jpeg`).

**SPEC-005 — color por día, íconos de tipo, azul steel, Login rediseñado** (100% frontend):

- El color de las tarjetas de "Mis citas" ya no lo deriva cada tarjeta de su propio `activity.type` — ahora `CalendarScreen` calcula una sola vez el color del día seleccionado (`colorForDay()`, nueva función en `activity_colors.dart`) usando la MISMA lista (`byDay[selectedKey]`) que ya usa `MonthCalendar._dayAccent()` para el círculo del día, y lo pasa hacia abajo (`AppointmentsSection.dayColor` → `AppointmentCard.color`). Así un día con reunión + tarea siempre pinta el círculo del calendario y todas sus tarjetas del mismo color — antes solo coincidían por casualidad en días de un único tipo. La sección "Pendientes por programar" no tiene día, así que sigue coloreando por tipo (no se le pasa `dayColor`).
- Como el color ahora representa el día y no el tipo, cada `AppointmentCard` agrega un ícono pequeño de tipo (`iconForActivityType()`) en la esquina inferior derecha: reunión = `Icons.groups`, tarea = `Icons.task_alt`, cita = `Icons.event`, cumpleaños = `Icons.cake`.
- El azul `#4A6CF7` (primary del tema oscuro y color del tipo "reunión") pasa a Steel Blue `#4682B4` en los dos lugares (`app_theme.dart::_darkPrimary`, `activity_colors.dart::colorForActivityType('meeting')`) — un solo azul en toda la app.
- `login_screen.dart` se rediseñó: fondo de manchas de color difuminadas (`LoginBackgroundPainter`, un `CustomPainter` con `MaskFilter.blur` pintado una sola vez, sin animación, para no gastar batería) con los acentos ya existentes de OmniTask, y una tarjeta centrada con avatar circular, campos con bordes de píldora y botón de acceso destacado — mismos validadores, mismo `authNotifierProvider`, mismo flujo de error que antes. `register_screen.dart` quedó fuera de alcance a propósito.

**SPEC-006 — tipo de actividad "Cumpleaños"** (BD + backend + frontend): `db/07_activity_type_birthday.sql` agrega `'birthday'` al enum `activity_type` con `ALTER TYPE ... ADD VALUE` — en su propio script, porque Postgres no deja usar un valor de enum recién agregado en la misma transacción en la que se agrega. `ActivityType.Birthday` se agregó al enum de C# (`OmniTask.Domain/Enums.cs`); como `Program.cs` ya mapea el enum completo vía `NpgsqlDataSourceBuilder.MapEnum<ActivityType>`, no hizo falta tocar nada más del backend. En Flutter, `activity_edit_screen.dart` agrega "Cumpleaños" al dropdown de tipo.

**SPEC-007 — limpiar historial de notificaciones**: hasta ahora solo existía "marcar todas como leídas", no un borrado real. `db/08_clear_notifications.sql` agrega `sp_clear_notifications(p_user_id)` (`DELETE FROM notification_log WHERE user_id = ...` — `reminder_id` tiene `ON DELETE SET NULL`, así que esto nunca toca `reminders` ni `activities`). Nuevo `DELETE /api/v1/notifications` en `NotificationsController` + `ClearAllAsync` en `NotificationService`. En `notifications_inbox_screen.dart`, un botón "Limpiar historial" junto a "Marcar todas" pide confirmación explícita antes de llamar al endpoint — es irreversible y no hay papelera, así que la única salvaguarda es esa confirmación.

Verificación de las tres SPECs en esta sesión: `flutter analyze` sin issues, `flutter test` 49/49, `dotnet build` sin errores/warnings, `dotnet test` 49 passed (32 de integración se saltan sin Postgres real, igual que en corridas anteriores), `flutter build apk --release` compila y firma con el mismo keystore. `.github/workflows/backend-ci.yml` se actualizó para aplicar también `db/07_*.sql` y `db/08_*.sql` contra el Postgres real del job. Detalle completo de criterios de aceptación en `.swarm/CHECKPOINTS.md` y `.swarm/specs/SPEC-005.md`/`SPEC-006.md`/`SPEC-007.md`.

---

*Documento de arquitectura v1 · 11 de julio de 2026 · próximo paso sugerido: validar §1 y confirmar el motor de base de datos antes de iniciar la fase 0.*
