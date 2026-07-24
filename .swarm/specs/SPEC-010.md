# SPEC-010 — Color del día en "Actividades por fecha"

- ID: SPEC-010
- Estado: APROBADA (Lead humano, 2026-07-24: "APROBADO SPEC-008/009/010")
- Autor: DOCTOR STRANGE (la aprobación es del Lead humano, nunca del autor)
- Fecha: 2026-07-24
- Responsable de implementación: CAPTAIN AMERICA
- Colaboradores / revisores: DAREDEVIL (frontend), WOLVERINE (calidad),
  HAWKEYE (pruebas)
- Fuente: `docs/contexto/tarea-multi-contacto-whatsapp.md` → PLAN-001 (APROBADO
  por el Lead, 2026-07-24), Fase 3 (confirmada por el Lead).

---

## 1. Objetivo

Que las tarjetas de la pantalla "Actividades por fecha" usen el **color del día
unificado** (el mismo `colorForDay()` que ya introdujo SPEC-005 para "Mis citas"),
en vez del color por tipo de actividad que usan hoy. Como esa pantalla consulta un
único día de referencia (el elegido en el selector), todas sus tarjetas comparten
ese color, igual que "Mis citas". Es una SPEC pequeña, solo frontend e
independiente de SPEC-008/009.

## 2. Contexto

- Archivo/widget confirmados en el código real (Glob/Grep, no aproximado):
  - Pantalla: `omnitask_app/lib/features/calendar/presentation/activities_by_date_screen.dart`
    (`ActivitiesByDateScreen`). El nombre coincide con el que anotó el plan.
  - Tarjeta: clase privada `_ActivityTile` (L103 del mismo archivo). En su
    `build` (L118-134) pinta la barra lateral (`Container` de `width: 4`) con
    `color: colorForActivityType(activity.type)` (L124) — es decir, **color por
    tipo**, no por día.
  - La pantalla ya importa `activity_colors.dart` (L9) y obtiene la lista del día
    vía `ref.watch(activitiesByDateProvider(_selectedDay))` (L45).
- Referencia de lo ya resuelto (SPEC-005) que se replica:
  - `activity_colors.dart` (L46) define
    `Color colorForDay(List<Activity> dayActivities, Color fallback)` → color del
    tipo de la primera actividad del día, o `fallback` si no hay ninguna. Un solo
    lugar para esta regla.
  - `calendar_screen.dart` (L124) calcula `dayColor = colorForDay(byDay[selectedKey]
    ?? const [], Theme.of(context).colorScheme.primary)` y lo pasa a
    `AppointmentsSection(dayColor: ...)` → `AppointmentCard(color: dayColor)`.

## 3. Requisitos funcionales

- **RF1 — Calcular el color del día una vez.** En `ActivitiesByDateScreen`, tras
  obtener la lista de actividades del día seleccionado (`activitiesAsync` con
  datos), calcular `final dayColor = colorForDay(activities,
  Theme.of(context).colorScheme.primary);` — misma función y mismo `fallback`
  que "Mis citas" (SPEC-005), para que el color coincida entre pantallas.
- **RF2 — Pasar el color del día a la tarjeta.** `_ActivityTile` recibe el
  `dayColor` como parámetro (`required this.dayColor` o similar) y lo usa en la
  barra lateral (`Container` de `width: 4`, L120-127) **en vez de**
  `colorForActivityType(activity.type)`. Todas las tarjetas de esa lista comparten
  el mismo color (el del día consultado).
- **RF3 — Fallback.** Si el día no tiene actividades, la lista está vacía y no se
  renderiza ninguna tarjeta (empty-state existente "No hay actividades programadas
  ese día"), así que el `fallback` de `colorForDay` solo aplica formalmente; no se
  cambia el empty-state.

## 4. Requisitos no funcionales

- **RNF1 — Reutilización, no duplicación.** Usar la función `colorForDay()` ya
  existente; no crear una copia de la lógica de color en esta pantalla.
- **RNF2 — Independiente de SPEC-008/009.** No depende del contrato de contactos
  ni de cambios de backend; puede implementarse en cualquier orden.
- **RNF3 — Sin cambios de paleta ni de tema.** Solo cambia de qué color se pinta
  la barra lateral de la tarjeta en esta pantalla; no se agregan colores nuevos.
- **RNF4 — No regresión.** Cero cambios en "Mis citas" (`calendar_screen.dart` /
  `appointments_section.dart` / `month_calendar.dart`), en el ícono por tipo
  (`iconForActivityType`), ni en la navegación al detalle (`context.push`) desde la
  tarjeta.
- **RNF5 — Calidad.** `flutter analyze` sin issues; `flutter test` en verde.

## 5. Criterios de aceptación verificables

- [ ] CA1: En "Actividades por fecha", al elegir un día con actividades, todas las
      tarjetas comparten el mismo color (el del día), derivado con `colorForDay()`.
- [ ] CA2: Ese color coincide con el que "Mis citas" (SPEC-005) muestra para el
      mismo día (misma función, mismo `fallback`).
- [ ] CA3: La navegación al detalle al tocar una tarjeta sigue funcionando igual.
- [ ] CA4 (transversal): `flutter analyze` sin issues; `flutter test` en verde.
- [ ] C-NR (no regresión): "Mis citas", el círculo del día en el calendario y el
      ícono por tipo no cambian de comportamiento.

## 6. Riesgos y dependencias

- **R1 — Semántica del color.** Antes la barra indicaba el **tipo** de la
  actividad; ahora indica el **día**. Es exactamente lo pedido (unificar con "Mis
  citas"), pero implica que el tipo deja de distinguirse por ese color en esta
  pantalla. Si en el futuro se quiere conservar el tipo, se haría con el ícono
  (`iconForActivityType`), fuera del alcance de esta SPEC.
- **R2 — Validación visual.** Sin dispositivo real, la coincidencia de color se
  valida por lectura (misma función/fallback) + `flutter test`; la revisión visual
  final queda al Lead.

## 7. Alcance EXCLUIDO (explícito)

- Cambiar "Mis citas" o el calendario: fuera (ya resueltos por SPEC-005).
- Agregar el ícono por tipo a las tarjetas de esta pantalla: fuera — solo se
  cambia el color de la barra lateral; el ícono es otra petición si se quisiera.
- Cualquier cambio de backend, contrato o multi-contacto: fuera (SPEC-008/009).
- Cambiar el selector de fecha, el empty-state o el layout de la pantalla: fuera.
