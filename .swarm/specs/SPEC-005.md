# SPEC-005 — Color por día, íconos de tipo, azul steel y rediseño del Login

- ID: SPEC-005
- Estado: PROPUESTA (pendiente aprobación explícita del Lead)
- Autor: DOCTOR STRANGE (la aprobación es del Lead humano, nunca del autor)
- Fecha: 2026-07-21
- Responsable de implementación: CAPTAIN AMERICA
- Colaboradores / revisores: DAREDEVIL (frontend), WOLVERINE (calidad), HAWKEYE (pruebas)
- Fuente: pedido directo del Lead ("Optimiza los siguientes modificaciones", puntos
  1, 2, 3, 4, 6, 8) + imágenes de referencia `docs/contexto/agenda2.jpg`,
  `docs/context/LoginApp.jpeg`, `docs/context/LoginAppFondo.jpeg`.

---

## 1. Objetivo

Cuatro ajustes visuales, 100% frontend (`omnitask_app/`), sin tocar backend ni BD:

1. El color del círculo del día en el calendario y el color de las tarjetas de
   "Mis citas" de ese día deben coincidir siempre — hoy solo coinciden si el día
   tiene un único tipo de actividad.
2. Un ícono pequeño por tipo (reunión/tarea/cita/cumpleaños) en una esquina de la
   tarjeta — reemplaza al color como forma de distinguir el tipo, ya que el color
   pasa a representar el día.
3. Reemplazar el azul `#4A6CF7` (hoy primary del tema oscuro Y color del tipo
   "reunión") por Steel Blue `#4682B4` en ambos usos.
4. Rediseñar `login_screen.dart` con un fondo de manchas de color difuminadas
   (estilo `LoginAppFondo.jpeg`) y una tarjeta de acceso centrada (estilo
   `LoginApp.jpeg`), usando la paleta propia de OmniTask.

## 2. Contexto

- `activity_colors.dart` (`colorForActivityType`) mapea tipo → color; usado en
  `month_calendar.dart` (círculo del día seleccionado y puntitos) y
  `appointment_card.dart` (color de la tarjeta completa).
- `month_calendar.dart::_dayAccent()` ya calcula "color del día" = color del tipo
  de la PRIMERA actividad de ese día — la pieza que falta es que las tarjetas usen
  ese mismo valor en vez de recalcular por su propio tipo.
- `app_theme.dart::_darkPrimary = Color(0xFF4A6CF7)` es el azul usado como
  `primary` del `ColorScheme` oscuro (botones, header, foco) — el mismo valor
  hexadecimal que `colorForActivityType('meeting')`.
- El punto 3 del pedido original ("Título y hora en la tarjeta") ya está cubierto
  por `appointment_card.dart` tal cual existe hoy — sin cambios en esta SPEC.

## 3. Requisitos funcionales

- **RF1 — Color por día, no por tarjeta individual.** `AppointmentCard` recibe el
  color del día como parámetro (calculado una sola vez por el padre —
  `calendar_screen.dart`/`appointments_section.dart` — con la misma lógica que ya
  usa `_dayAccent()`), en vez de derivarlo internamente de `activity.type`. Todas
  las tarjetas de "Mis citas" para el día seleccionado comparten el mismo color,
  igual al círculo de ese día en el calendario.
  - La sección "Pendientes por programar" (SPEC-004) no tiene día asignado — sus
    tarjetas usan el color de tipo tal cual hoy (sin cambio), ya que no hay un
    "día" del cual derivar un color.
- **RF2 — Ícono de tipo en la tarjeta.** Un ícono pequeño (Material Icons) en una
  esquina de `AppointmentCard`, uno distinto por tipo: reunión (`Icons.groups`),
  tarea (`Icons.task_alt`), cita (`Icons.event`), cumpleaños (`Icons.cake`, si
  SPEC-006 ya está implementada; si no, se agrega el `case` igual y queda listo).
- **RF3 — Azul Steel.** `app_theme.dart::_darkPrimary` y
  `activity_colors.dart::colorForActivityType('meeting')` pasan de `0xFF4A6CF7` a
  `0xFF4682B4` (Steel Blue). Mismo valor en los dos lugares, como hoy.
- **RF4 — Rediseño del Login.** `login_screen.dart`:
  - Fondo con 2-3 manchas de color difuminadas (`CustomPaint`/círculos con
    `ImageFilter.blur`, NO una imagen estática ni SVG a mano) usando los acentos
    ya existentes de OmniTask (steel blue, teal `#26C6A6`, naranja `#F5A623`,
    rosa `#EC4899`) sobre el fondo oscuro de la app — evoca `LoginAppFondo.jpeg`
    sin copiar sus colores genéricos.
  - Tarjeta centrada con avatar circular (ícono de persona), campos de
    correo/contraseña, checkbox u opción "Recordarme" si ya existe en el formulario
    actual (no se agrega si no estaba), botón de acceso destacado, y enlace
    "¿No tienes cuenta? Crear cuenta" — mismo lenguaje que `LoginApp.jpeg`.
  - `register_screen.dart` NO se toca en esta SPEC (fuera de alcance, ver §7).

## 4. Requisitos no funcionales

- **RNF1 — No regresión.** CERO cambios en `APIOmniTask/**`, `db/**`, ni en
  `allowedViews`/`initialDisplayDate`/`skipLoadingOnReload`/
  `_handleMonthChanged`/`table_calendar` ni los guards `Firebase.apps.isEmpty`.
- **RNF2 — Contraste (WCAG AA).** El nuevo Steel Blue y los íconos sobre las
  tarjetas deben mantener contraste ≥3:1 (texto/ícono grande) o ≥4.5:1 (texto
  normal) sobre su fondo, mismo criterio que ya se validó en SPEC-001 C8.
- **RNF3 — Localización.** Textos en español (es_CO).
- **RNF4 — Rendimiento del fondo del Login.** Las manchas difuminadas se dibujan
  una vez (sin animación continua) para no gastar batería en una pantalla que ya
  compite con el arranque de la app.

## 5. Criterios de aceptación verificables

- [ ] CA1: Un día con 2+ actividades de tipos distintos muestra el mismo color en
      su círculo del calendario y en TODAS sus tarjetas de "Mis citas".
- [ ] CA2: Cada tarjeta muestra un ícono distinto según el tipo, visible en una
      esquina, sin tapar el texto.
- [ ] CA3: El azul `#4682B4` reemplaza a `#4A6CF7` en el tema oscuro (botones,
      header) y en el color del tipo "reunión" — no quedan dos azules distintos.
- [ ] CA4: `login_screen.dart` muestra el fondo de manchas de color y la tarjeta
      de acceso rediseñada; el formulario sigue funcionando igual (mismos
      validadores, mismo flujo de error, mismo `authNotifierProvider`).
- [ ] CA5 (transversal): `flutter analyze` y `flutter test` en verde;
      `flutter build apk --release` compila y firma con el keystore existente.
- [ ] C-NR (no regresión): `git diff` confirma cero cambios en `APIOmniTask/**`,
      `db/**`, y en la lógica de bucle/anti-refetch del calendario.

## 6. Riesgos y dependencias

- **R1 — No verificable visualmente en un dispositivo real** desde este entorno
  (sin emulador/celular) — se valida con `flutter analyze`/`flutter test`/build
  real, y por inspección de código; la validación visual final queda en manos
  del Lead tras instalar el release.
- **R2 — Ícono de cumpleaños depende de SPEC-006** (agrega el tipo). Si SPEC-006
  no está aprobada aún, el ícono/color de "birthday" se agrega igual en el
  `switch` (no rompe nada) pero no habrá forma de crear una actividad de ese tipo
  hasta que SPEC-006 se implemente.

## 7. Alcance EXCLUIDO (explícito)

- `register_screen.dart` y cualquier otra pantalla de auth: fuera, solo
  `login_screen.dart`.
- Animación del fondo del Login (parallax, movimiento continuo): fuera —
  estático por RNF4.
- Selector de tema claro/oscuro real (el bottom nav ya tiene un ícono
  "próximamente" sin función, SPEC-001 §6): sigue fuera de alcance.
