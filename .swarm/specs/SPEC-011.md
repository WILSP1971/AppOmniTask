# SPEC-011 — Fondo de tarjeta con color del día + fix de búsqueda de contactos atascada

- ID: SPEC-011
- Estado: APROBADA (Lead humano, 2026-07-25: "APROBADO SPEC-011")
- Autor: DOCTOR STRANGE
- Fecha: 2026-07-24
- Responsable de implementación: CAPTAIN AMERICA
- Colaboradores / revisores: DAREDEVIL (frontend), SPIDER-MAN (UX),
  WOLVERINE (calidad), HAWKEYE (pruebas)
- Fuente: `docs/contexto/tarea-cards-color-y-multicontacto-ux.md` (puntos A y B),
  PLAN aprobado por el Lead (2026-07-24). Solo frontend (`omnitask_app/**`).

---

## 1. Objetivo

Dos cambios independientes, ambos solo de frontend:

- **A (visual):** que la tarjeta `AppointmentCard` pinte su **fondo** con el color
  del día (`typeColor`) — al estilo de `docs/contexto/agenda2.jpg` /
  `agenda3.jpg` — en vez del gris fijo `colorScheme.surfaceContainerLow`, con
  texto legible (contraste WCAG) sobre ese fondo sólido. Aplica tanto a "Mis
  citas" como a "Pendientes por programar".
- **B (bug):** que la búsqueda de contactos en el campo "Contactos" deje de
  quedarse en spinner infinito cuando `search()` lanza una excepción, y que
  muestre en pantalla el **mensaje de error real** para poder diagnosticarlo sin
  `adb`; además, reforzar el parseo de la respuesta en `ContactRepository.search`
  y diferenciar "sin resultados" de "error".

## 2. Contexto

Confirmado leyendo el código real (no aproximado):

**Punto A**
- `.../calendar/presentation/widgets/appointment_card.dart`:
  - L30: `final typeColor = color ?? colorForActivityType(activity.type);` — el
    color del día llega por el parámetro `color` (SPEC-005 RF1). Cuando es null,
    cae al color por tipo. En **ambos** casos `typeColor` es un color válido no
    nulo.
  - L43-50: el `Container` raíz usa
    `decoration: BoxDecoration(color: colorScheme.surfaceContainerLow, ...)` — gris
    fijo. `typeColor` hoy solo se usa en el badge de fecha (`_DateBadge`, con
    `alpha 0.18`) y en el ícono de tipo de la esquina (`alpha 0.7`).
  - Textos: título (L108-116) usa `colorScheme.onSurface`; lugar/hora e íconos
    (L122-149) usan `colorScheme.onSurfaceVariant`; el badge (`_DateBadge`,
    L173-204) usa `typeColor` como color de texto; el menú de 3 puntos
    (`_AppointmentMenu`, L215-216) usa `onSurfaceVariant`. Todos están calculados
    para contraste sobre el gris `surfaceContainerLow`, no sobre `typeColor`.
- `.../calendar/presentation/widgets/appointments_section.dart`: pasa
  `AppointmentCard(activity: ..., color: dayColor)` (L71); `dayColor` es opcional
  y por defecto null.
- `.../calendar/presentation/calendar_screen.dart`:
  - L124-125: `dayColor = colorForDay(byDay[selectedKey] ?? const [], colorScheme.primary)`.
  - L140-146: "Mis citas" → `AppointmentsSection(dayColor: dayColor, ...)` (color
    del día).
  - L149-153: "Pendientes por programar" → `AppointmentsSection(...)` **sin**
    `dayColor` (queda null) → cada tarjeta cae al color **por tipo**
    (`colorForActivityType`). Por eso ambas secciones ya entregan un `typeColor`
    no nulo a cada tarjeta; pintar el fondo con `typeColor` funciona en las dos
    sin recalcular nada.
- Precedente de contraste (checkpoint C8, SPEC-005): `month_calendar.dart`
  `_dayCircle` (L53-56) elige el color de texto sobre un fondo de color con
  `ThemeData.estimateBrightnessForColor(accent) == Brightness.light ?
  Colors.black87 : Colors.white`. Es el mismo criterio a reutilizar aquí.

**Punto B**
- `.../calendar/presentation/widgets/contact_picker_field.dart`
  (`ContactPickerField`, multi-selección de SPEC-009):
  - `_onQueryChanged` (L38-56): el callback del `Timer` (L44-55) hace
    `setState(_isSearching = true)`, luego
    `await ref.read(contactRepositoryProvider).search(query.trim())`
    **sin try/catch**. Si `search()` lanza, el `await` corta antes del `setState`
    que apaga el spinner (L48-54) → `_isSearching` queda `true` para siempre y
    `_results` nunca se llena. Es exactamente el síntoma reportado (spinner
    infinito, sin lista).
  - No hay estado de "error" en el widget; la UI solo distingue
    `_isSearching` (spinner, L92-97) y `_results.isNotEmpty` (lista, L101-117).
    "Sin resultados" y "error" hoy se ven igual (nada).
- `.../contacts/data/contact_repository.dart` `search` (L20-25):
  `(response.data as List).map((j) => Contact.fromJson(j as Map<String, dynamic>))`.
  Si `response.data` no es una `List` (p. ej. viene envuelto en un objeto, o es
  null), el `as List` lanza; y `Contact.fromJson` con un `j` inesperado también.
  Cualquiera de esos casos es un candidato a la excepción que atasca el spinner.
- `.../core/network/dio_client.dart` `mapApiError` (L44-53): ya extrae el mensaje
  del sobre `{"error": {"message"}}` de una `DioException`; si no lo reconoce,
  devuelve el genérico `'Algo falló. Intenta de nuevo.'`. Es el patrón a reutilizar
  y extender para el mensaje de diagnóstico.

## 3. Requisitos funcionales

### Punto A — Fondo de la tarjeta con el color del día

- **RF1 — Fondo sólido con `typeColor`.** En `AppointmentCard.build`, el
  `Container` raíz (L43-50) debe pintar su fondo con `typeColor` (color sólido o
  tinte fuerte al estilo de `agenda2.jpg`/`agenda3.jpg`) en vez de
  `colorScheme.surfaceContainerLow`. El `borderRadius` (18) se mantiene; el borde
  (`outlineVariant`) se ajusta o retira según se vea mejor sobre el fondo de color
  (a criterio de DAREDEVIL/SPIDER-MAN, sin cambiar la paleta). Aplica a las
  tarjetas de "Mis citas" (fondo = color del día) y de "Pendientes por programar"
  (fondo = color por tipo), sin recalcular color: se usa el `typeColor` que la
  tarjeta ya computa (RF de contexto §2).

- **RF2 — Color de texto por contraste (WCAG).** Calcular una sola vez el color de
  primer plano sobre el fondo con el mismo criterio del precedente C8:
  `final onCard = ThemeData.estimateBrightnessForColor(typeColor) ==
  Brightness.light ? Colors.black87 : Colors.white;`. Aplicarlo al título
  (hoy `onSurface`, L113) en negrita, y a los textos/íconos secundarios de
  lugar/hora y al ícono del menú de 3 puntos (hoy `onSurfaceVariant`) con una
  variante atenuada del mismo `onCard` (p. ej. `onCard.withValues(alpha: 0.75)`)
  para conservar jerarquía sin perder legibilidad. No usar `onSurface`/
  `onSurfaceVariant` fijos sobre el fondo de color.

- **RF3 — Badge de fecha e ícono de tipo legibles sobre el nuevo fondo.**
  `_DateBadge` (L173-204) hoy usa `typeColor` con `alpha 0.18` de fondo y
  `typeColor` de texto; sobre un fondo del mismo `typeColor` eso quedaría
  ilegible. Ajustar el badge para que contraste (p. ej. fondo semitransparente
  claro/oscuro derivado de `onCard`, y texto `onCard`), manteniendo el número de
  día grande y el mes abreviado en español. El ícono de tipo de la esquina
  (L62-69) debe seguir siendo visible sobre el fondo (usar `onCard` con alpha en
  vez de `typeColor` con alpha).

- **RF4 — Sin recálculo de color ni cambios fuera de la tarjeta.** No se toca
  `colorForDay`, ni `calendar_screen.dart`, ni `appointments_section.dart`, ni
  `month_calendar.dart`: el color sigue llegando por el parámetro `color` (o el
  fallback por tipo). El cambio vive dentro de `appointment_card.dart`.

### Punto B — Búsqueda de contactos atascada

- **RF5 — try/catch/finally que SIEMPRE apaga el spinner (fix principal).** En
  `_onQueryChanged` (`contact_picker_field.dart`), envolver la llamada a
  `search(...)` en `try/catch/finally`:
  - `finally`: `if (mounted) setState(() => _isSearching = false);` — el spinner
    se apaga pase lo que pase (éxito o excepción). Este es el arreglo que resuelve
    el síntoma reportado con certeza.
  - `try` (éxito): comportamiento actual (filtrar contactos ya seleccionados y
    poblar `_results`).
  - `catch (e)`: guardar en estado un mensaje de error para la UI (RF6) y dejar
    `_results` vacío.

- **RF6 — Mostrar el MENSAJE DE ERROR REAL en pantalla (diagnóstico sin adb).** El
  widget gana un campo de estado `String? _errorMessage`. En `catch`, el mensaje
  se obtiene con una función de mapeo que:
  1. si es `DioException` con sobre `{"error":{"message"}}` reconocible, usa ese
     mensaje (reutilizando/llamando a `mapApiError`);
  2. **en cualquier otro caso** (parse, tipo, timeout, error inesperado), muestra
     el texto real de la excepción — p. ej. `e.toString()` (opcionalmente con el
     `runtimeType`) — **no** el genérico "Algo falló". Así, si vuelve a fallar en
     el celular del Lead, el texto en pantalla ES el diagnóstico exacto.
  Para lograrlo sin degradar el resto de la app, extender el patrón de
  `dio_client.dart`: mantener `mapApiError` como está para el resto de la app y
  añadir un helper de diagnóstico (p. ej. `describeSearchError(Object e)`), o un
  parámetro/variante que devuelva el detalle crudo cuando no se reconoce el sobre.
  El helper vive junto a `mapApiError` (o en el picker) y se documenta como "modo
  diagnóstico".

- **RF7 — Diferenciar "sin resultados" de "error" en la UI.** El `build` del picker
  distingue tres estados bajo el `TextField`:
  - buscando: spinner (como hoy);
  - error (`_errorMessage != null`): fila/recuadro visible con el mensaje real
    (RF6), en un estilo de error (p. ej. `colorScheme.error`), no un spinner;
  - resultados: si la consulta terminó bien con lista vacía (y hay ≥2 caracteres),
    un texto tenue "Sin coincidencias" (estado normal, no error); si hay
    resultados, la lista actual (L101-117).
  Al volver a teclear (`_onQueryChanged`) se limpia `_errorMessage` antes de
  reintentar, para no dejar un error viejo pegado.

- **RF8 — Reforzar el parseo en `ContactRepository.search` (mejor esfuerzo).** En
  `search` (`contact_repository.dart` L20-25), endurecer la conversión de
  `response.data`:
  - aceptar que `response.data` sea `List` (caso esperado) y devolver `[]` de forma
    controlada (o lanzar un error descriptivo) si no lo es, en vez de un
    `as List`/`as Map` crudo que produce un `_TypeError` opaco;
  - mapear cada elemento con validación de tipo antes de `Contact.fromJson`.
  Nota: sin dispositivo no se puede confirmar cuál es la causa exacta; esto es
  endurecimiento de mejor esfuerzo y, combinado con RF6, garantiza que la próxima
  falla real quede visible.

- **RF9 — Verificar el flujo multi-contacto completo por lectura/tests.** Confirmar
  (lectura + `flutter test`) que, con la búsqueda arreglada, el flujo de SPEC-009
  sigue intacto: escribir un nombre → ver resultados → tocar para agregar varios
  como chips → guardar. No se cambia la firma de `ContactPickerField` ni el
  contrato de multi-selección.

## 4. Requisitos no funcionales

- **RNF1 — Solo frontend.** Cambios únicamente en `omnitask_app/**`
  (`appointment_card.dart`, `contact_picker_field.dart`,
  `contact_repository.dart` y, si aplica, `dio_client.dart`). No se toca backend,
  BD ni contrato de API.
- **RNF2 — Paleta y tema sin cambios.** No se agregan colores nuevos a
  `activity_colors.dart` ni al tema; el fondo usa el `typeColor` ya existente y el
  texto se deriva por brillo (blanco/negro), como el precedente C8.
- **RNF3 — Contraste (WCAG).** El texto sobre el fondo de color debe ser legible;
  se reutiliza el criterio de `estimateBrightnessForColor` ya usado en el
  calendario (C8). Es el mismo cuidado, no una regla nueva.
- **RNF4 — No regresión.** Cero cambios de comportamiento en: patrón anti-bucle
  del calendario (`calendar_screen.dart`/`month_calendar.dart`/`table_calendar`),
  color por día (SPEC-005), tipos incl. Cumpleaños (SPEC-006), multi-contacto
  (SPEC-009: firma y chips), navegación al detalle y menú de 3 puntos de la
  tarjeta, "Actividades por fecha" (SPEC-010).
- **RNF5 — Localización.** Todo texto nuevo en español (es_CO): "Sin
  coincidencias", el rótulo del estado de error, etc. (El mensaje de diagnóstico
  crudo de RF6 puede ser técnico en cualquier idioma por su naturaleza.)
- **RNF6 — Calidad.** `flutter analyze` sin issues; `flutter test` en verde
  (agregar tests donde aplique: al menos que una excepción en `search()` deje
  `_isSearching == false` y `_errorMessage != null`).
- **RNF7 — Release.** Una vez en `main` con CI en verde, cortar release por tag
  `app-vX.Y.Z` (dispara `android-release.yml`), como en SPECs previas.

## 5. Criterios de aceptación verificables

- [ ] CA1 (A): En "Mis citas", cada tarjeta tiene el **fondo** pintado con el
      color del día (`typeColor`), no el gris `surfaceContainerLow`; el título y
      los textos son legibles (contraste) sobre ese fondo.
- [ ] CA2 (A): En "Pendientes por programar", cada tarjeta tiene el fondo pintado
      con su color por tipo, también con texto legible.
- [ ] CA3 (A): El color de texto se elige por brillo del fondo
      (`estimateBrightnessForColor`), coherente con el círculo del día del
      calendario (C8/SPEC-005); el badge de fecha y el ícono de tipo siguen
      visibles.
- [ ] CA4 (B): Si `search()` lanza una excepción, el spinner **siempre** se apaga
      (`_isSearching` vuelve a `false`) — sin spinner infinito.
- [ ] CA5 (B): Ante una excepción no reconocida como sobre de API, la UI muestra
      el **mensaje de error real** (texto de la excepción), no un genérico "Algo
      falló".
- [ ] CA6 (B): "Sin resultados" (consulta OK, lista vacía) se muestra distinto de
      un "error" (búsqueda fallida): el primero como texto tenue, el segundo con
      estilo de error.
- [ ] CA7 (B): Al volver a teclear tras un error, el mensaje de error anterior se
      limpia antes del nuevo intento.
- [ ] CA8 (B): El flujo multi-contacto (buscar → agregar chips → guardar) sigue
      funcionando (SPEC-009), verificado por lectura + tests.
- [ ] C-NR (no regresión): calendario (anti-bucle), color por día, tipos incl.
      Cumpleaños, "Actividades por fecha", navegación al detalle y menú de la
      tarjeta, y la paleta/tema no cambian.
- [ ] C-Q (transversal): `flutter analyze` sin issues; `flutter test` en verde.

## 6. Riesgos y dependencias

- **R1 — LIMITACIÓN CONOCIDA: causa raíz exacta del bug B, mejor esfuerzo.** En
  este sandbox **no hay dispositivo ni `adb`** para capturar en vivo la excepción
  real que lanza `search()` en la cuenta del Lead. Por eso el fix #2 (corregir la
  causa raíz exacta — RF8) es **mejor esfuerzo, no garantizado**. La mitigación
  acordada con el Lead es el fix #1 (RF5, try/catch/finally que siempre apaga el
  spinner) + RF6 (mostrar el mensaje de error real en pantalla): si vuelve a
  fallar en el celular, el texto visible ES el diagnóstico exacto, sin necesitar
  `adb` la próxima vez. Esta limitación es esperada y aceptada, no un defecto de
  la entrega.
- **R2 — Legibilidad sobre fondos de color claros/oscuros.** Algunos colores de
  tipo/día pueden dar bajo contraste en un extremo. Se mitiga con el mismo
  criterio C8 (`estimateBrightnessForColor`) y una revisión visual del Lead. Sin
  dispositivo real, la apariencia final la valida el Lead (como en SPEC-004/005).
- **R3 — Ajuste del badge y del borde.** Al cambiar el fondo, el badge de fecha
  (antes `typeColor@0.18` sobre gris) y el borde `outlineVariant` pueden requerir
  ajuste fino para no "desaparecer" sobre el color. Cubierto por RF3; es trabajo
  de detalle visual, no de arquitectura.
- **R4 — Widget compartido.** `AppointmentCard` lo usan "Mis citas" y "Pendientes
  por programar" (vía `AppointmentsSection`); el cambio afecta a ambos por diseño
  (es lo pedido). `ContactPickerField` es el de SPEC-009: no se cambia su firma
  (RF9), solo su manejo interno de errores. `flutter analyze` atrapa referencias
  rotas.
- **R5 — Exposición del error crudo.** RF6 muestra texto técnico de la excepción
  en la UI de un campo de formulario; es intencional (diagnóstico acordado) y solo
  aparece cuando la búsqueda falla. No expone credenciales (el token va en
  headers, no en el cuerpo de error de `/contacts`). Si a futuro se quisiera un
  texto amable para usuario final, sería otra petición.

## 7. Alcance EXCLUIDO (explícito)

- Cambios de backend, BD o contrato de API: fuera (el endpoint `GET
  /contacts?search=` ya responde 200 con la lista; el bug es de cliente).
- Cambiar `colorForDay`, el círculo del calendario, "Actividades por fecha"
  (SPEC-010), la paleta o el tema: fuera.
- Cambiar la firma o el contrato multi-selección de `ContactPickerField`
  (SPEC-009): fuera — solo se corrige su manejo de estado/errores.
- Rediseñar el layout general de la tarjeta más allá del fondo, los colores de
  texto y el badge (p. ej. reordenar elementos): fuera.
- Un texto de error "amable" para usuario final en la búsqueda: fuera — en esta
  SPEC el objetivo del mensaje es el diagnóstico (acordado con el Lead).
- Alta rápida de contactos desde el picker: fuera (ya excluido en SPEC-009).
