# SPEC-001 — Rediseño visual real de Home (Agenda/Calendario) v1.0.9

- Estado: APROBADA (Lead humano, 2026-07-19)
- Autor: DOCTOR STRANGE (aprobación es del Lead humano, no del autor)
- Fecha: 2026-07-19

## Objetivo
Rediseñar de verdad la pantalla principal (Home = calendar_screen.dart) con el lenguaje
visual de los mockups agenda2.jpg / agenda3.jpg (calendario con selección en círculo +
puntitos/píldoras por actividad, lista/grid de tarjetas de citas, bottom nav flotante), y
propagar el mismo lenguaje al resto de pantallas listadas. El release v1.0.8 solo cambió
el tema; esta iteración reconstruye layout y componentes.

## Contexto
Flutter en `omnitask_app/`. Home usa SfCalendar (Syncfusion) con 4 vistas en tabs + Drawer
+ FAB. Paleta ya en `app_theme.dart` (fondos #1C2733/#202A38, tarjetas #26313F, primary
#4A6CF7). `activity_colors.dart` mapea meeting=#4A6CF7, task=#F5A623, appointment=#26C6A6.
Providers/repos son SOLO de consumo.

## 1. Decisión de arquitectura del calendario (ADR-001)
**Recomendación: migrar a `table_calendar`.** Justificación: el look objetivo (día
seleccionado en círculo de color, puntitos y píldoras multi-día por tipo) se logra
directamente con sus builders (`selectedBuilder`, `markerBuilder`/`calendarBuilders`) sin
pelear con el motor de tabla de SfCalendar; además elimina la fuente del bucle de refetch
(el guard `skipLoadingOnReload`/`_handleViewChanged` deja de ser necesario). Las vistas
Day/Week/Schedule pasan a ser la lista/grid inferior filtrada por día; la vista mensual la
da table_calendar. Riesgo controlado por C2.

## 2. Estructura de Home rediseñada (`features/calendar/presentation/`)
- `calendar_screen.dart` (orquestador): Scaffold + Drawer existente + bottom nav + FAB, monta las secciones.
- `widgets/agenda_header.dart`: mes en azul con ‹ ···, campana con punto rojo (→ /notifications), lupa (búsqueda). Reusa acciones actuales del AppBar.
- `widgets/month_calendar.dart`: wrapper de `table_calendar`; selección en círculo (color por acento), markers = puntitos por tipo (agenda2) o píldoras de rango (agenda3, fase 2 opcional).
- `widgets/appointments_section.dart`: encabezado "Mis citas" + "+ Add" (→ /activities/new).
- `widgets/appointment_card.dart`: fila con badge de fecha coloreado por tipo (día grande + mes) + título/lugar/hora + menú 3 puntos (editar/borrar/detalle).
- `core/navigation/app_bottom_nav.dart`: barra flotante redondeada, 5 slots → tema, calendario (/), FAB central "+" (/activities/new), inbox (/notifications), compartir/ajustes (/settings). Convive con el Drawer (atajo, no lo reemplaza).
- Estado: consumir `activitiesForRangeProvider` (rango = mes visible) filtrando por día seleccionado en cliente; `unscheduledActivitiesProvider` para el badge de backlog.

## 3. Colores
- Reutilizar `colorForActivityType()` tal cual (meeting/task/appointment) para badges, puntitos y píldoras.
- Agregar en `app_theme.dart` (o `activity_colors.dart`) DOS acentos de UI (NO de tipo):
  `kAccentPink = #EC4899` y `kAccentPurpleFab = #5B6EF5` (color del FAB central). No se añaden tipos de actividad nuevos.

## 4. Criterios de aceptación (checkpoints verificables)
- C1: `flutter analyze` sin errores nuevos y `flutter build apk --debug` compila.
- C2: sin refetch infinito al cambiar de mes/día — demostrado con log/test (contador de llamadas al repo estable) o guard equivalente si se conserva SfCalendar.
- C3: las 6 pantallas del alcance (ver §5) comparten fondo, radio de esquina y tipografía provistos por el tema (sin colores hardcodeados divergentes).
- C4: la lista de "Mis citas" muestra badge de fecha coloreado por tipo; el calendario muestra puntitos por día con actividad.
- C5: el bottom nav navega a rutas ya existentes del router sin crear rutas nuevas ni duplicar la navegación del Drawer.
- C6: localización en español intacta (nombres de mes/días y textos).
- C7: CERO cambios en `APIOmniTask/**`, `db/**`, ni firmas en `*/data/**` y `*/application/**`.
- C8: contraste texto/fondo ≈ WCAG AA sobre los fondos oscuros.

## 5. Alcance
**Fase 1 (esta iteración):** Home completo (§2) + re-vestido ligero de tema (C3) en las 6
pantallas: `activity_detail_screen.dart`, `activity_edit_screen.dart`, `backlog_screen.dart`,
`notifications_inbox_screen.dart`, `login_screen.dart`, `settings_screen.dart`.
Píldoras multi-día (agenda3) = opcional dentro de Fase 1; si no da tiempo, puntitos (agenda2).
**Fase 2 (siguiente):** grid 2-columnas con íconos pastel de agenda3, subpantallas de settings
(profile/notification_preferences/devices), refinamiento de píldoras de rango y animaciones.

## Riesgos y dependencias
- R1: migrar a table_calendar puede alterar UX de Week/Day → mitigar dejando lista filtrada por día.
- R2: table_calendar añade dependencia (pubspec) → aprobación del Lead.
- R3: doble navegación (Drawer + bottom nav) → C5 evita rutas duplicadas.
- Dependencia: aprobación del Lead antes de implementar (CAPTAIN AMERICA / SPIDER-MAN).
