# SPEC-009 — Frontend Flutter: selección múltiple de contactos

- ID: SPEC-009
- Estado: APROBADA (Lead humano, 2026-07-24: "APROBADO SPEC-008/009/010")
- Autor: DOCTOR STRANGE (la aprobación es del Lead humano, nunca del autor)
- Fecha: 2026-07-24
- Responsable de implementación: CAPTAIN AMERICA
- Colaboradores / revisores: DAREDEVIL (frontend), SPIDER-MAN (UX),
  WOLVERINE (calidad), HAWKEYE (pruebas)
- Fuente: `docs/contexto/tarea-multi-contacto-whatsapp.md` → PLAN-001 (APROBADO
  por el Lead, 2026-07-24), Fase 2.

---

## 1. Objetivo

Llevar la app Flutter a la **multi-selección de contactos** por actividad: el
formulario permite buscar, agregar y quitar varios contactos (chips); el modelo
`Activity`/`ActivityDraft` maneja una lista; la pantalla de detalle muestra todos
los contactos. Consume el contrato ya definido en SPEC-008 (`contacts` /
`contact_ids` en el JSON de la API).

## 2. Contexto

- `omnitask_app/lib/models/activity.dart`: `Activity` (freezed) tiene hoy
  `String? contactId` y **no** una lista de contactos ni un modelo de contacto
  embebido; deserializa `ActivityResponse` vía `Activity.fromJson`.
- `omnitask_app/lib/models/activity_draft.dart`: `ActivityDraft` tiene
  `String? contactId`; es el espejo de `ActivityCreateRequest`.
- `omnitask_app/lib/models/contact.dart`: modelo `Contact` (usado por
  `ContactPickerField`).
- `.../calendar/presentation/widgets/contact_picker_field.dart`:
  `ContactPickerField` es hoy de **selección única** (`Contact? selectedContact`
  + `ValueChanged<Contact?> onChanged`), con autocompletar con debounce contra
  `GET /contacts?search=` (`contactRepositoryProvider.search`).
- `.../calendar/presentation/activity_edit_screen.dart`: mantiene `Contact?
  _contact` (L32), usa `ContactPickerField` (L121) y solo envía `contactId:
  _contact?.id` **en creación** (L214). **Gap actual:** en edición no se hidrata
  `_contact` desde la actividad existente ni se envía el contacto en el PATCH
  (`_hydrateFrom` L49 no toca el contacto; `updateActivity` L199 no pasa contacto).
- `.../calendar/presentation/activity_detail_screen.dart`: `_DetailBody` **no
  muestra ningún contacto** hoy (solo fecha, ubicación, descripción, reunión,
  adjuntos, recordatorios).
- `.../calendar/data/activity_repository.dart`: `create` envía `'contact_id':
  draft.contactId` (L18); `update` (L81) **no** envía contacto.
- `.../calendar/application/activity_form_controller.dart`: `create` y
  `updateActivity` orquestan el repositorio.
- Colores: `activity_colors.dart` (paleta actual, no se toca en esta SPEC).

## 3. Requisitos funcionales

- **RF1 — `ContactPickerField` multi-selección con chips.** Reescribir el widget
  para gestionar una **lista** de contactos seleccionados:
  - Firma nueva: `List<Contact> selectedContacts` + `ValueChanged<List<Contact>>
    onChanged` (reemplaza `selectedContact`/`onChanged` únicos).
  - Mantener el autocompletar con debounce (350 ms, mínimo 2 caracteres) contra
    `contactRepositoryProvider.search` — sin traer la lista completa.
  - Al tocar un resultado, **agregar** ese contacto a la lista (si no está ya),
    limpiar el campo de búsqueda y ocultar resultados. Un contacto ya
    seleccionado no se ofrece/duplica.
  - Mostrar los seleccionados como `Chip`/`InputChip` con botón de quitar
    (`onDeleted`), en un `Wrap`.
  - Label en español: "Contactos (opcional)".

- **RF2 — `ActivityDraft` con lista.** Reemplazar `String? contactId` por
  `@Default(<String>[]) List<String> contactIds` (ids de contacto). Regenerar
  freezed.

- **RF3 — `Activity` con lista de contactos.** Agregar al modelo la lista de
  contactos que ahora devuelve la API (SPEC-008 RF9: `contacts` =
  `[{id, full_name, phone_e164}]`). Opciones: un modelo `ActivityContact`
  (freezed/JSON) o reutilizar `Contact`; se **recomienda** un
  `@Default(<Contact>[]) List<Contact> contacts` mapeado desde el JSON
  `contacts`. Mantener `String? contactId` por compatibilidad de lectura durante
  la ventana de transición (SPEC-008 RF12), sin usarlo como fuente de verdad en
  la UI nueva. Regenerar freezed/json.

- **RF4 — Repositorio envía `contact_ids`.**
  `.../data/activity_repository.dart`:
  - `create`: enviar `'contact_ids': draft.contactIds` (en vez de `contact_id`).
  - `update`: agregar soporte para `List<String>? contactIds` — cuando no es null,
    incluir `'contact_ids': contactIds` en el PATCH (null = no tocar los
    contactos; lista vacía = quitar todos), alineado con SPEC-008 RF9. Cierra el
    gap actual de que el update nunca enviaba contacto.

- **RF5 — `activity_edit_screen.dart` gestiona varios contactos.**
  - Estado: `List<Contact> _contacts` (reemplaza `Contact? _contact`).
  - `_hydrateFrom`: al editar, precargar `_contacts` desde `existing.contacts`
    (cierra el gap de que hoy no se hidrata el contacto en edición).
  - Render: `ContactPickerField(selectedContacts: _contacts, onChanged: ...)`.
  - `_submit`: en creación, `ActivityDraft(contactIds: _contacts.map((c)=>c.id))`;
    en edición, pasar `contactIds: _contacts.map((c)=>c.id).toList()` al
    `updateActivity` (reemplazo de conjunto completo).

- **RF6 — `activity_detail_screen.dart` muestra los contactos.** En `_DetailBody`,
  agregar una sección/`_InfoRow`(s) que liste los contactos de la actividad
  (nombre y, si aplica, teléfono), usando `Icons.person_outline` /
  `Icons.people_outline`. Si la actividad no tiene contactos, no se muestra la
  sección (mismo criterio condicional que `location`/`description`). Textos en
  español.

- **RF7 — `activity_form_controller.dart`.** Ajustar `create` y `updateActivity`
  para propagar la lista de contactos (draft con `contactIds` y parámetro
  `contactIds` en el update), sin cambiar la forma en que se distingue "no tocar"
  de "limpiar" en los otros campos (§23).

## 4. Requisitos no funcionales

- **RNF1 — Depende de SPEC-008.** Requiere que el backend ya exponga
  `contacts`/`contact_ids` y acepte `contact_ids` (contrato de SPEC-008). Se
  implementa después de SPEC-008 aprobada e implementada. Gracias a la ventana de
  compatibilidad (SPEC-008 RF12), un APK con esta SPEC funciona contra un backend
  que ya tiene SPEC-008.
- **RNF2 — No tocar el patrón anti-bucle del calendario.** Cero cambios en
  `calendar_screen.dart` / `month_calendar.dart` /
  `allowedViews`/`initialDisplayDate`/`skipLoadingOnReload`/`table_calendar`. Esta
  SPEC solo toca el formulario, el detalle, el picker, los modelos y el
  repositorio.
- **RNF3 — Diseño y paleta sin cambios.** No se cambia el tema, ni los colores
  (`activity_colors.dart`), ni el layout general — solo se **agrega** la UI de
  multi-selección (chips) y la sección de contactos en el detalle.
- **RNF4 — Localización.** Todos los textos nuevos en español (es_CO).
- **RNF5 — Calidad.** `flutter analyze` sin issues y `flutter test` en verde;
  regenerar código freezed/json (`build_runner`) para los modelos tocados.
- **RNF6 — Release.** Una vez en `main` con CI en verde, cortar release por tag
  `app-vX.Y.Z` (dispara `android-release.yml`), como en SPECs previas.

## 5. Manejo de errores

- Buscar contactos con la red caída: mismo comportamiento que hoy en
  `ContactPickerField` (la búsqueda no rompe el formulario; si falla, no se
  agregan resultados). No se introduce un manejo de error nuevo.
- Guardar con la lista de contactos vacía: válido (actividad sin contactos), tal
  como acepta SPEC-008.
- Un error de guardado (p. ej. contrato) se muestra con el mismo `SnackBar` que ya
  usa el listener de `activityFormControllerProvider` en `activity_edit_screen.dart`.

## 6. Criterios de aceptación verificables

- [ ] CA1: En "Nueva actividad" se pueden buscar y agregar 2+ contactos (aparecen
      como chips) y quitar cualquiera con su botón; al crear, todos quedan
      asociados (verificable en `GET /activities/{id}` → `contacts`).
- [ ] CA2: Al editar una actividad que ya tenía contactos, el formulario los
      precarga como chips (cierra el gap de hidratación actual).
- [ ] CA3: En edición se pueden agregar/quitar contactos y guardar; el conjunto
      resultante reemplaza al anterior (SPEC-008 RF5); dejar la lista vacía quita
      todos los contactos.
- [ ] CA4: La pantalla de detalle muestra todos los contactos de la actividad
      (nombre); una actividad sin contactos no muestra la sección.
- [ ] CA5: Un mismo contacto no se puede agregar dos veces (sin duplicados en los
      chips ni en `contact_ids`).
- [ ] CA6 (transversal): `flutter analyze` sin issues; `flutter test` en verde;
      `build_runner` regenera los `.freezed.dart`/`.g.dart` sin errores.
- [ ] C-NR (no regresión): calendario (Mes/Agenda, anti-bucle), color por día
      (SPEC-005), tipos de actividad (incl. Cumpleaños, SPEC-006), reunión y
      adjuntos siguen funcionando igual; la paleta/tema no cambia.

## 7. Riesgos y dependencias

- **R1 — Dependencia dura de SPEC-008.** Sin el contrato de backend
  (`contacts`/`contact_ids`), esta SPEC no tiene a qué apuntar. Orden:
  SPEC-008 → SPEC-009 (RNF1).
- **R2 — Cambio de firma de `ContactPickerField`.** Es un widget compartido;
  verificar que su único consumidor actual (`activity_edit_screen.dart`) se
  actualice; si aparece otro consumidor, migrarlo también. `flutter analyze`
  atrapa referencias rotas.
- **R3 — Regeneración de código.** Cambiar los modelos freezed obliga a correr
  `build_runner`; olvidarlo deja el build roto. Cubierto por CI (RNF5).
- **R4 — Validación visual final.** Sin dispositivo real en el sandbox, la
  apariencia de los chips y de la sección de contactos se valida por lectura +
  `flutter test`; la revisión visual final queda al Lead (como en SPEC-004/005).

## 8. Alcance EXCLUIDO (explícito)

- Cambios de backend/BD/contrato: fuera — es SPEC-008.
- Crear/editar contactos desde el picker (alta rápida): fuera — el picker solo
  busca y selecciona contactos ya existentes, como hoy.
- Cambiar la paleta, el tema o el layout general: fuera (RNF3).
- Orden manual de contactos, roles por contacto, o vista dedicada de "contactos de
  la actividad": fuera.
- Mostrar por contacto el estado de entrega del WhatsApp en el detalle: fuera —
  el detalle lista los contactos, no el resultado de cada envío (eso vive en la
  bandeja de notificaciones).
