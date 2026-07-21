# SPEC-007 — Limpiar historial de notificaciones

- ID: SPEC-007
- Estado: PROPUESTA (pendiente aprobación explícita del Lead)
- Autor: DOCTOR STRANGE (la aprobación es del Lead humano, nunca del autor)
- Fecha: 2026-07-21
- Responsable de implementación: CAPTAIN AMERICA
- Colaboradores / revisores: BLACK PANTHER (backend/BD), DAREDEVIL (frontend),
  BLACK WIDOW (autorización por dueño), WOLVERINE (calidad), HAWKEYE (pruebas)
- Fuente: pedido directo del Lead ("Optimiza los siguientes modificaciones",
  punto 7).

---

## 1. Objetivo

Permitir borrar por completo el historial de notificaciones del usuario
autenticado — hoy solo existe "marcar todas como leídas"
(`sp_acknowledge_all_notifications`), no un borrado real.

## 2. Contexto

- `notification_log` (`db/schema.sql` L112): `id`, `reminder_id` (FK
  `ON DELETE SET NULL`, no bloquea el borrado de una notificación), `user_id`
  (FK `ON DELETE CASCADE` desde `users`), `channel`, `status`, `summary`,
  `acknowledged_at`, `created_at`.
- `NotificationsController` (`APIOmniTask/src/OmniTask.Api/Controllers/`) ya
  tiene `GET /notifications`, `GET /notifications/unread-count`,
  `PATCH /notifications/{id}/ack`, `POST /notifications/ack-all` — falta el
  borrado.
- `notifications_inbox_screen.dart` ya tiene un botón "Marcar todas" en el
  `AppBar` — el de "Limpiar historial" se agrega al lado.

## 3. Requisitos funcionales

- **RF1 — Endpoint de borrado.** `DELETE /api/v1/notifications` — borra TODAS
  las filas de `notification_log` del usuario autenticado. `204 No Content`.
  Sin parámetros (borra todo el historial, no un rango ni un id individual —
  ya existe `PATCH /{id}/ack` para lo puntual).
- **RF2 — SQL.** `db/08_*.sql`: procedimiento `sp_clear_notifications(p_user_id
  UUID)` → `DELETE FROM notification_log WHERE user_id = p_user_id`.
- **RF3 — Backend.** `INotificationService.ClearAllAsync(Guid userId)` +
  implementación en `NotificationService` (mismo patrón que
  `AcknowledgeAllAsync`) + acción `ClearAll()` en el controlador.
- **RF4 — Frontend.** Botón "Limpiar historial" en el `AppBar` de
  `notifications_inbox_screen.dart`, junto a "Marcar todas" — con diálogo de
  confirmación explícito (es destructivo e irreversible: "¿Borrar todo el
  historial de notificaciones? Esta acción no se puede deshacer"). Al confirmar,
  llama al nuevo endpoint e invalida `notificationsInboxProvider` +
  `unreadNotificationsCountProvider`.

## 4. Requisitos no funcionales

- **RNF1 — Autorización por dueño.** El `DELETE` solo borra filas del
  `user_id` autenticado (vía `User.GetUserId()`), nunca de otro usuario —
  mismo patrón que el resto de la API.
- **RNF2 — Irreversible, con confirmación.** La UI SIEMPRE confirma antes de
  llamar al endpoint — nunca un borrado de un solo toque accidental.
- **RNF3 — No regresión.** Cero cambios en `PATCH /{id}/ack` ni
  `POST /ack-all`; ambos siguen funcionando igual.
- **RNF4 — Localización.** Textos en español (es_CO).

## 5. Manejo de errores

- `401` sin token válido (igual que el resto de `/notifications`).
- `204` incluso si el historial ya estaba vacío (idempotente, no es un error
  borrar una lista vacía).

## 6. Criterios de aceptación verificables

- [ ] CA1: Con notificaciones existentes, tocar "Limpiar historial" y confirmar
      deja la bandeja vacía (`GET /notifications` devuelve lista vacía).
- [ ] CA2: Cancelar el diálogo de confirmación NO borra nada.
- [ ] CA3: Un usuario no puede borrar el historial de otro (verificado en API:
      solo afecta filas de `user_id` = el del token).
- [ ] CA4: Borrar el historial no afecta `reminders` ni `activities` — solo
      `notification_log` (el reminder que originó una notificación sigue
      existiendo con su propio ciclo de vida).
- [ ] CA5 (transversal): `dotnet test`/`flutter test`/`flutter analyze` en
      verde.
- [ ] C-NR (no regresión): `PATCH /{id}/ack` y `POST /ack-all` sin cambios de
      comportamiento.

## 7. Riesgos y dependencias

- **R1 — Irreversibilidad.** No hay papelera ni deshacer — una vez confirmado,
  el historial se pierde. Mitigado con el diálogo de confirmación explícito
  (RF4/RNF2), no con soft-delete (el Lead no pidió conservar el historial
  borrado en ningún lado).

## 8. Alcance EXCLUIDO (explícito)

- Borrado selectivo/por rango de fechas: fuera — todo o nada, como pidió el
  Lead ("limpiar el historial").
- Exportar el historial antes de borrarlo: fuera, no se pidió.
- Deshacer/papelera de notificaciones borradas: fuera (ver R1).
