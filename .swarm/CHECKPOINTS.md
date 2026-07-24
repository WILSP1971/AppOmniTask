# CHECKPOINTS — Avengers Swarm / OmniTask

Registro de checkpoints de verificacion por SPEC.

## SPEC-001 — Rediseno visual real de Home v1.0.9 (implementada por CAPTAIN AMERICA, revisada por DAREDEVIL/WOLVERINE/HAWKEYE)
- [x] C1: `flutter analyze` sin errores nuevos (0 issues) y `flutter build apk --debug` compila.
- [x] C2: sin refetch infinito al cambiar de mes/dia — demostrado con test
      `test/features/calendar/presentation/calendar_screen_test.dart` (cuenta
      llamadas a fetchActivities: 2 llamadas en carga inicial (1 transitoria
      con rango semanal heredado + 1 definitiva de mes), 0 en rebuilds sin
      cambio de mes, 1 por cambio real de mes — no es un bucle (no crece),
      pero si una llamada de red descartada en cada apertura de Home;
      corregirlo de raiz requeriria tocar `application/**` (fuera de alcance
      de esta SPEC).
- [x] C3: las 6 pantallas del alcance comparten fondo/radio/tipografia via tema
      (se corrigieron colores hardcodeados en activity_detail_screen.dart y
      notifications_inbox_screen.dart; se agregaron Card wrappers en
      settings_screen.dart y activity_edit_screen.dart).
- [x] C4: badges/puntos de fecha coloreados por tipo aparecen en la lista
      (AppointmentCard) y puntitos en MonthCalendar.
- [x] C5: bottom nav (AppBottomNav) navega a rutas existentes del router sin
      crear rutas nuevas ni duplicar la navegacion del Drawer.
- [x] C6: localizacion en espanol intacta (es_CO en DateFormat, textos sin cambios).
- [x] C7: CERO cambios en APIOmniTask/**, db/**, */data/**, */application/**
      (verificado con `git diff --stat` sobre esos paths — vacio).
- [x] C8: contraste texto/fondo del dia seleccionado (WCAG AA) verificado
      cuantitativamente para los 3 acentos de tipo en `month_calendar.dart`:
      `task` #F5A623 y `appointment` #26C6A6 con texto negro dan ~8-10:1
      (holgado). `meeting` #4A6CF7 con texto blanco da 4.39:1 (bajo el umbral
      normal de 4.5:1); se resolvio subiendo el numero del dia seleccionado a
      19px bold, que califica como "texto grande" WCAG (>=18.66px bold,
      umbral 3:1), donde 4.39:1 si cumple.

## SPEC-002 — Adjuntos en actividades (documentos e imagenes) — Punto 7 (implementada por CAPTAIN AMERICA, revisada por BLACK PANTHER/DAREDEVIL/BLACK WIDOW/WOLVERINE, verificada por HAWKEYE 2026-07-20)

Entorno de verificacion: sin Postgres real ni Docker disponibles (`psql`,
`pg_isready`, `docker` no existen en este sandbox). Los tests de integracion
usan `[SkippableFact]` (mismo patron que `ActivityServiceTests` preexistente)
y se SALTAN, no fallan, sin `TEST_DATABASE_URL` alcanzable. El CI real
(`backend-ci.yml`) si tiene un service container de Postgres 16 y corre estos
mismos tests de punta a punta — ahi es donde CA2-CA8 quedan ejecutados de
verdad, no solo compilados. Aqui se ejecutaron y pasaron todos los tests que
no requieren BD (unitarios puros de validacion + verificacion estatica del
limite de Kestrel).

- [x] CA1 (adjuntar imagen y PDF, aparecen con nombre/tipo/tamano): cubierto
      por widget test `attachments_section_test.dart` ("lista con adjuntos
      muestra nombre, tipo y tamaño legible" — verifica `foto.jpg`/`1.5 KB` e
      `informe.pdf`/`3.0 MB`) + integracion
      `AttachmentServiceTests.UploadAsync_y_ListAsync_devuelven_los_adjuntos_subidos`
      (subida real de imagen y PDF, ambos aparecen en `ListAsync`). Integracion
      SKIP en este entorno (sin Postgres); widget test PASS.
- [x] CA2 (persisten al reabrir, GET los devuelve):
      `AttachmentServiceTests.UploadAsync_y_ListAsync_devuelven_los_adjuntos_subidos`
      (integracion, SKIP sin Postgres) + `attachment_repository_test.dart`
      ("list — GET a /activities/{id}/attachments y mapea la lista", PASS,
      confirma el contrato HTTP GET -> lista de `Attachment`).
- [x] CA3 (bytes integros en descarga, probado en API):
      `AttachmentServiceTests.DownloadAsync_devuelve_los_mismos_bytes_que_se_subieron`
      — sube 5000 bytes aleatorios, descarga y compara arreglo completo
      (`Assert.Equal(originalBytes, downloadedBytes)`). Integracion, SKIP sin
      Postgres real; el codigo esta listo para que CI lo ejecute de verdad.
- [x] CA4 (eliminar quita de lista + borra archivo fisico; cascada al borrar
      actividad): `AttachmentServiceTests.DeleteAsync_quita_el_adjunto_de_la_lista_y_borra_el_archivo_fisico`
      (verifica `File.Exists` antes/despues) +
      `CancelAsync_no_impide_verificar_cascada_de_adjuntos_al_borrar_la_actividad`
      (DELETE fisico de la fila `activities`, confirma
      `COUNT(*) FROM activity_attachments` = 0 por el FK `ON DELETE CASCADE`
      de `db/04_activity_attachments.sql`). Ambos SKIP sin Postgres.
      Confirmacion de UI: widget test "confirmar el diálogo sí llama a delete
      en el repositorio" (PASS).
- [x] CA5 (archivo >10MB -> 4xx, no 500): dos capas verificadas.
      (1) Chequeo interno real:
      `AttachmentServiceTests.UploadAsync_con_stream_mayor_a_10MB_lanza_413_sin_excepcion_sin_capturar`
      sube 11 MB y confirma `ApiException` con `StatusCode == 413` (nunca una
      excepcion sin capturar), y que no queda registro ni archivo huerfano.
      SKIP sin Postgres. (2) Limite de Kestrel/RNF2 (caso limite senalado por
      WOLVERINE): `ActivityAttachmentsControllerLimitsTests` verifica por
      reflexion que `Upload` declara `[RequestSizeLimit(11*1024*1024)]` y
      `[RequestFormLimits(MultipartBodyLengthLimit=11*1024*1024)]` — PASS (no
      requiere BD). **Limitacion explicita**: no se ejercito un servidor
      Kestrel real end-to-end con un POST multipart >11MB por HTTP (el
      proyecto no tiene `WebApplicationFactory`/`TestServer` configurado; no
      es un patron ya usado aqui). La verificacion estatica confirma que el
      atributo esta bien declarado; falta un test HTTP real en CI o staging
      para confirmar que Kestrel efectivamente corta la conexion antes del
      controlador.
- [x] CA6 (tipo no permitido -> 4xx, no 500): `AttachmentServiceTests.UploadAsync_con_content_type_no_permitido_lanza_415`
      (`.exe` con `application/x-msdownload` -> `ApiException(415)`) +
      `UploadAsync_con_extension_incoherente_con_el_content_type_lanza_415`
      (`.docx` con `Content-Type: application/pdf` -> 415, defensa R3 de
      BLACK WIDOW). Integracion, SKIP sin Postgres. Cubierto tambien en
      unitario puro (PASS, sin BD): `AttachmentValidationTests` — 8 casos con
      `[Theory]` sobre `IsContentTypeAllowed`/`IsExtensionCoherent`.
- [x] CA7 (usuario no puede acceder a adjuntos de otro usuario -> 404, probado
      en API): `AttachmentServiceTests.Operaciones_sobre_adjunto_de_otro_usuario_devuelven_404`
      — ejercita `ListAsync`/`DownloadAsync`/`DeleteAsync` con `otherUserId` y
      confirma `StatusCode == 404` en los tres, y que el adjunto del dueño
      real sigue intacto. Integracion, SKIP sin Postgres.
- [x] CA8 (nombre fisico es GUID, no el original):
      `AttachmentServiceTests.UploadAsync_genera_nombre_fisico_GUID_distinto_del_nombre_del_cliente`
      — sube con nombre "nombre original con espacios y ñ.png", confirma que
      el DTO conserva ese nombre para el usuario pero el archivo fisico en
      `RootPath` es `Guid.TryParse`-parseable y distinto del nombre original.
      Integracion, SKIP sin Postgres.
- [x] CA9 (transversal, `flutter analyze`/`flutter test` y pruebas de API en
      verde): `flutter analyze` -> 0 issues. `flutter test` -> 51 tests reales
      pasando, 0 fallos (confirmado via reporter JSON, el conteo compacto de
      consola no imprime todas las lineas por buffering pero el JSON del
      framework de test lo confirma linea por linea). `dotnet test` (backend)
      -> 81 total, 49 passed, 32 skipped (0 failed) — de esos 32 skipped, 15
      son nuevos de esta verificacion (9 `AttachmentServiceTests` + 6
      `ActivityServiceMeetingTests`, SPEC-003) que se saltan solo por falta de
      Postgres real en este sandbox, no por fallar.
- [x] C-NR (no regresion): `git diff --stat f31e1b0..HEAD -- omnitask_app/lib`
      muestra unicamente archivos nuevos/aditivos de adjuntos y reunion (12
      archivos, +612 lineas, 0 borradas); `grep` sobre ese mismo diff para
      `allowedViews|initialDisplayDate|skipLoadingOnReload|appointmentBuilder|table_calendar|Drawer\(`
      no encuentra ninguna coincidencia — cero cambios en la logica del
      calendario.

**Verificado en CI real (2026-07-20, post-implementación):** el primer run de
`Backend CI` contra Postgres real (commit `7a3a951`, run 29709877372) corrió
los 15 tests de integración nuevos de verdad y encontró un bug real: `fn_list_activities`
(`db/03_stored_procedures_and_functions.sql`) nunca se actualizó para devolver
`meeting_url`/`meeting_provider`, y `ActivityService.ListAsync` reventaba con
`IndexOutOfRangeException: Field not found in row: meeting_url` al listar
actividades — habría roto el endpoint de listado en producción. Corregido en
`db/06_stored_procedures_attachments_and_meeting.sql` (commit `4af7a67`):
redefinición de `fn_list_activities` agregando ambas columnas al `RETURNS TABLE`
y al `SELECT`. Re-run de `Backend CI` (run 29710116351, commit `4af7a67`):
**success**, paso "Ejecutar pruebas" en verde — el mismo test que había fallado
(`Actividad_sin_campos_de_reunion_sigue_funcionando_en_list_get_y_patch`) ahora
pasa contra Postgres real. `Flutter CI` en verde desde el commit `7a3a951`.
Ruta de almacenamiento en el servidor de producción (IIS/Windows) confirmada
ejecutada por el Lead — ver `docs/despliegue-adjuntos-produccion.md`.

## SPEC-003 — Link de reunion (Meet/Teams) en actividades — Punto 8 (implementada por CAPTAIN AMERICA, revisada por SPIDER-MAN/BLACK PANTHER/DAREDEVIL/WOLVERINE, verificada por HAWKEYE 2026-07-20)

Mismo entorno y limitacion que SPEC-002: sin Postgres/Docker en este sandbox,
los tests de integracion usan `[SkippableFact]` y se saltan (no fallan).

- [x] CA1 (pegar meeting_url y elegir provider; URL invalida se rechaza con
      mensaje): widget test `meeting_field_test.dart` — 8 casos PASS
      (campo vacio valido, `http://`/`https://` validas, texto no-URL
      rechazado con "Ingresa un link válido", esquema `ftp://` rechazado,
      selector muestra Meet/Teams/Otro/Ninguno, seleccionar invoca el
      callback). Integracion real de servidor:
      `ActivityServiceMeetingTests.CreateAsync_con_meeting_url_invalida_lanza_400`
      y `CreateAsync_con_meeting_provider_no_permitido_lanza_400` confirman
      `ApiException(400)` — SKIP sin Postgres. Unitario puro (PASS, sin BD):
      `MeetingValidationTests` — 10 casos sobre `IsValidMeetingUrl`/
      `IsValidProvider` (http/https validos, ftp/texto/vacio/null invalidos,
      meet/teams/other validos insensible a mayusculas, resto invalido).
- [x] CA2 (link y provider persisten y se muestran tras reabrir, GET):
      `ActivityServiceMeetingTests.CreateAsync_con_meeting_url_y_provider_persiste_y_se_puede_releer`
      (crea con meeting_url/provider, relee con `GetByIdAsync`, confirma
      ambos campos). Integracion, SKIP sin Postgres. Widget test
      `meeting_section_test.dart` ("con meeting_url muestra el link y el
      proveedor...") confirma que el detalle los renderiza (PASS).
- [x] CA3 (boton copiar copia al portapapeles con feedback visible): widget
      test `meeting_section_test.dart` — "copiar muestra feedback de
      snackbar" (PASS; requirio mockear el canal de plataforma del
      clipboard con `TestDefaultBinaryMessengerBinding`, documentado en el
      propio test).
- [x] CA4 (boton abrir abre el link externo): cubierto por lectura de codigo
      — `MeetingSection._open` usa `launchUrl(uri, mode: LaunchMode.externalApplication)`
      de `url_launcher`; no hay test automatizado de que el navegador real se
      abra (requeriria un dispositivo/emulador, fuera de alcance de un
      widget test). El boton "Abrir" se confirma presente/visible en
      `meeting_section_test.dart`.
- [x] CA5 (boton compartir abre share sheet con texto que incluye el link):
      cubierto por lectura de codigo — `MeetingSection._share` arma
      `'Te comparto el link de la reunión "$title": $url'` y llama
      `SharePlus.instance.share`; igual que CA4, el share sheet real del SO
      no es verificable en un widget test headless. El boton "Compartir" se
      confirma presente en `meeting_section_test.dart`.
- [x] CA6 (sin meeting_url, acciones ocultas): widget test
      `meeting_section_test.dart` — "sin meeting_url no renderiza nada" (PASS,
      confirma `Card`/`Copiar`/`Abrir`/`Compartir` ausentes, no solo
      deshabilitados — cumple RF7 al pie de la letra).
- [x] CA7 (migracion aditiva, actividades existentes siguen funcionando en
      list/get/patch): `ActivityServiceMeetingTests.Actividad_sin_campos_de_reunion_sigue_funcionando_en_list_get_y_patch`
      — crea sin meeting_url, confirma `ListAsync`/`GetByIdAsync` con
      `MeetingUrl == null`, y que un PATCH normal (cambiar titulo) sigue
      funcionando sin tocar los campos de reunion. Integracion, SKIP sin
      Postgres. Revision estatica de `db/05_activity_meeting.sql`: ambas
      columnas son `ALTER TABLE ... ADD COLUMN` sin `NOT NULL` ni default
      obligatorio — aditivo por diseño.
- [x] CA8 (transversal, igual que CA9 de SPEC-002): mismo resultado —
      `flutter analyze` 0 issues, `flutter test` 51/51 reales en verde,
      `dotnet test` backend 81 total/49 passed/32 skipped/0 failed (de los 32
      skipped, 6 son `ActivityServiceMeetingTests` de esta SPEC).
- [x] C-NR (no regresion): mismo `git diff --stat f31e1b0..HEAD` de arriba —
      SPEC-002 y SPEC-003 se implementaron en los mismos commits
      (664729d/614ff77/f8e237c), el diff conjunto ya confirma cero cambios en
      la logica del calendario.

**Verificado en CI real (2026-07-20, post-implementación):** mismo run que
SPEC-002 — los 6 tests de `ActivityServiceMeetingTests` corrieron contra
Postgres real. Uno falló por el mismo bug de `fn_list_activities` (ver nota de
SPEC-002 arriba, el test de CA7 usa `ListAsync`); corregido en el commit
`4af7a67`, re-run en verde (run 29710116351). `Flutter CI` en verde. Queda como
limitación documentada, no bloqueante para IMPLEMENTADA: CA4/CA5 (abrir
navegador externo / share sheet del SO) siguen sin verificación automatizada
end-to-end en dispositivo real — solo por lectura de código y presencia de los
botones en widget test. Recomendado hacer una prueba manual puntual en un
dispositivo Android real antes de anunciar la función a usuarios finales.

## SPEC-004 — Push end-to-end y actividades sin fecha visibles/accesibles (implementada por CAPTAIN AMERICA 2026-07-20)

Infraestructura de Firebase (previa a esta SPEC, commits `86c36e0`/`fb7f840`):
`flutterfire configure` contra el proyecto `omnitask-agenda` (confirmado por el
Lead como el mismo que usa el backend vía `firebase-admin.json`, tras descubrir
que la primera cuenta usada para el login no tenía acceso a ese proyecto sino a
uno distinto — `zealous-valor-gsjh2` — y corregir con la cuenta correcta,
`ingenierodesarrollador@clinicacampbell.com.co`). `firebase_options.dart`
generado y comiteado (no es secreto según la documentación de Firebase);
`google-services.json` gitignored, reconstruido en `android-release.yml` desde
el secret `GOOGLE_SERVICES_JSON_BASE64`. `main.dart` llama a
`Firebase.initializeApp(...)` de verdad.

- [x] CA1: `registerCurrentDevice()` (llamado tras login/registro/restauración
      de sesión) ahora pide permiso (`FirebaseMessaging.instance.requestPermission()`,
      idempotente) antes de `getToken()` — con Firebase inicializado, el flujo
      completo hasta `POST /devices` deja de cortarse en el guard
      `Firebase.apps.isEmpty`. Verificable en producción con
      `docs/pruebas-api.html` (`GET /devices`).
- [x] CA2: `devices_screen.dart` — lista vacía muestra `_EmptyDevicesState`
      (mensaje + botón "Activar notificaciones en este dispositivo") en vez de
      una pantalla en blanco; el botón llama a
      `deviceRegistrationProvider.notifier.registerCurrentDevice()` y refresca
      `myDevicesProvider`.
- [x] CA3: botón ☰ agregado en `AgendaHeader` (`Scaffold.of(context).openDrawer()`)
      — el Drawer y "Actividades sin programar" dejan de ser inalcanzables
      desde el Home.
- [x] CA4: nueva sección "Pendientes por programar" en `calendar_screen.dart`,
      debajo de "Mis citas", reutilizando `AppointmentsSection`/`AppointmentCard`
      tal cual (parámetro `title` agregado a `AppointmentsSection` para poder
      reutilizarlo con otro encabezado) contra `unscheduledActivitiesProvider`
      — cero componentes ni colores nuevos.
- [x] CA5: "Editar" en una tarjeta de "Pendientes" ya llevaba a
      `/activities/{id}/edit`, que ya soporta asignar fecha (sin cambios de
      lógica necesarios — ya existía desde antes de esta SPEC).
- [x] CA6 (transversal): `flutter analyze` 0 issues; `flutter test` 49/49 en
      verde; `flutter build apk --release` compila y firma con el keystore
      existente (mismo certificado SHA-256 `960d1db5...`, se instala como
      actualización).
- [x] C-NR (no regresión): `git diff` de `calendar_screen.dart` confirma que
      solo se agregó un import, un `ref.watch` nuevo y una sección al final del
      `Column` — `initState`, `_handleMonthChanged`, `skipLoadingOnReload`,
      `MonthCalendar`/`onPageChanged` y los guards `Firebase.apps.isEmpty`
      preexistentes no se tocaron.

**Limitación documentada, no bloqueante:** R1 de la SPEC — no hay dispositivo ni
emulador Android real en este entorno de trabajo, así que la entrega real de
una notificación push a un celular queda pendiente de verificación manual del
Lead tras instalar el release. Todo lo demás (compilación, firma, flujo hasta
`POST /devices`, UI de las 3 pantallas tocadas) sí se verificó de verdad.

## SPEC-005 — Color por día, íconos de tipo, azul steel y rediseño del Login (implementada por CAPTAIN AMERICA 2026-07-24)

- [x] CA1: `colorForDay()` (nueva, `activity_colors.dart`) es la única fuente
      del color de un día — la usan tanto `MonthCalendar._dayAccent()` (círculo
      del día) como `CalendarScreen.build()` (color pasado a
      `AppointmentsSection.dayColor` → `AppointmentCard.color`), indexando la
      MISMA lista (`byDay[selectedKey]`). Un día con 2+ tipos distintos ahora
      muestra el mismo color en el círculo y en todas sus tarjetas de "Mis
      citas" — antes cada tarjeta llamaba a `colorForActivityType(activity.type)`
      por su cuenta y solo coincidía por casualidad en días de un único tipo.
      "Pendientes por programar" no recibe `dayColor` (no tiene día), sigue
      coloreando por tipo sin cambios.
- [x] CA2: `AppointmentCard` agrega `iconForActivityType()` (nueva) en la
      esquina inferior derecha de la tarjeta — reunión=`Icons.groups`,
      tarea=`Icons.task_alt`, cita=`Icons.event`, cumpleaños=`Icons.cake` —
      separado del menú de 3 puntos (arriba) para no superponerse.
- [x] CA3: `#4A6CF7` → Steel Blue `#4682B4` en `app_theme.dart::_darkPrimary` y
      `activity_colors.dart::colorForActivityType('meeting')` — mismo valor en
      los dos lugares, un solo azul en toda la app.
- [x] CA4: `login_screen.dart` rediseñado — `LoginBackgroundPainter` (nuevo,
      `CustomPainter` con `MaskFilter.blur`, pintado una sola vez) + tarjeta
      centrada (avatar circular, campos con `OutlineInputBorder` de píldora,
      botón `StadiumBorder`, enlace "¿No tienes cuenta? Crear cuenta"); mismos
      `_formKey`/controllers/validadores/`authNotifierProvider` y flujo de
      error de antes — solo cambió la UI. `register_screen.dart` no se tocó.
- [x] CA5 (transversal): `flutter analyze` → "No issues found!"; `flutter test`
      → 49/49; `flutter build apk --release` compila y firma con el keystore
      existente (59.1MB).
- [x] C-NR (no regresión): `git diff` confirma cero cambios en `APIOmniTask/**`
      ni `db/**` por esta SPEC, y `initState`/`_handleMonthChanged`/
      `skipLoadingOnReload`/`onPageChanged` de `calendar_screen.dart` y
      `month_calendar.dart` sin tocar (solo se refactorizó `_dayAccent()` para
      llamar a `colorForDay()` en vez de duplicar la lógica).

**Limitación documentada, no bloqueante:** R1 de la SPEC — sin dispositivo ni
emulador real en este entorno, la validación visual final (contraste, verse
bien en pantalla) queda en manos del Lead tras instalar el release.

## SPEC-006 — Tipo de actividad "Cumpleaños" (implementada por CAPTAIN AMERICA 2026-07-24)

- [x] CA1/CA2: `db/07_activity_type_birthday.sql` (`ALTER TYPE activity_type
      ADD VALUE IF NOT EXISTS 'birthday'`, script propio — Postgres no permite
      usar un valor de enum recién agregado en la misma transacción en que se
      agrega); `ActivityType.Birthday` agregado a `OmniTask.Domain/Enums.cs`
      (sin tocar `Program.cs`: `MapEnum<ActivityType>` ya mapea el enum
      completo); `activity_edit_screen.dart` agrega
      `DropdownMenuItem(value: 'birthday', child: Text('Cumpleaños'))`. Con
      esto se puede crear/listar/editar/reprogramar/cancelar una actividad de
      tipo cumpleaños igual que cualquier otra (mismos endpoints, sin cambios
      de contrato).
- [x] CA3: color propio vía `colorForActivityType('birthday')` (reutiliza
      `kAccentPink`, distinto de los 3 tipos existentes) e ícono propio
      (`Icons.cake`) en `iconForActivityType()` — compartidos con SPEC-005.
- [x] CA4 (transversal): `dotnet build` 0 errores/warnings; `dotnet test` 49
      passed (32 de integración se saltan sin Postgres real en este entorno,
      igual que en corridas previas); `.github/workflows/backend-ci.yml`
      actualizado para aplicar `db/07_*.sql` contra el Postgres real del job
      de CI (antes solo llegaba hasta `db/06_*.sql`), así que la migración
      queda validada contra Postgres real en cada corrida.
- [x] C-NR: actividades con los 4 valores previos del enum siguen
      funcionando igual — el cambio es aditivo (`ADD VALUE`, no reescribe
      filas existentes).

## SPEC-007 — Limpiar historial de notificaciones (implementada por CAPTAIN AMERICA 2026-07-24)

- [x] CA1: `db/08_clear_notifications.sql` agrega
      `sp_clear_notifications(p_user_id)` (`DELETE FROM notification_log WHERE
      user_id = ...`); `INotificationService.ClearAllAsync` +
      `NotificationService.ClearAllAsync` (mismo patrón que
      `AcknowledgeAllAsync`) + `DELETE /api/v1/notifications` en
      `NotificationsController` → `204 No Content`. `notification_repository.dart`
      agrega `clearAll()`; `notifications_inbox_screen.dart` agrega un botón
      "Limpiar historial" que, al confirmar, invalida
      `notificationsInboxProvider`/`unreadNotificationsCountProvider`.
- [x] CA2: el botón pide confirmación explícita (`AlertDialog` "¿Borrar todo
      el historial de notificaciones? ... Esta acción no se puede deshacer")
      antes de llamar al repositorio — cancelar el diálogo no invoca
      `clearAll()`.
- [x] CA3: el borrado usa `User.GetUserId()` igual que el resto de
      `/notifications` — solo afecta filas del `user_id` autenticado.
- [x] CA4: `reminder_id` en `notification_log` tiene `ON DELETE SET NULL`
      hacia `notification_log`, no al revés — borrar aquí no dispara ninguna
      cascada hacia `reminders` ni `activities`.
- [x] CA5 (transversal): mismas corridas que SPEC-006 (`dotnet build`/
      `dotnet test`/`flutter analyze`/`flutter test`), todas en verde; CI
      actualizado para aplicar también `db/08_*.sql`.
- [x] C-NR: `PATCH /{id}/ack` y `POST /ack-all` sin cambios de código ni de
      comportamiento — solo se agregó un método nuevo al lado.

## SPEC-008 — Varios contactos por actividad y WhatsApp a todos (implementada por CAPTAIN AMERICA 2026-07-24)

- [x] CA1/CA2: `db/09_activity_contacts.sql` agrega la tabla puente
      `activity_contacts` y recrea `fn_create_activity`/`fn_update_activity`
      con `p_contact_ids UUID[]` (+ `p_sync_contacts BOOLEAN` en update, para
      distinguir "no tocar" de "reemplazar el conjunto"). Revisión del
      orquestador encontró y corrigió un bug real antes de entregar el script:
      faltaba `DROP FUNCTION IF EXISTS fn_get_activity_by_id(UUID, UUID)` —
      Postgres rechaza `CREATE OR REPLACE FUNCTION` cuando cambia el tipo de
      retorno (de `SETOF activities` a `RETURNS TABLE(...)`) sin ese DROP
      explícito; sin el fix, el script se habría caído a mitad de camino en
      cualquier entorno real.
- [x] CA3: migración de datos (`INSERT ... SELECT ... ON CONFLICT DO
      NOTHING`) idempotente; `activities.contact_id` se conserva (no se
      borra) pero queda documentada como deprecada vía `COMMENT ON COLUMN`.
- [x] CA4: `fn_get_activity_by_id`/`fn_list_activities`/
      `fn_list_unscheduled_activities` devuelven la columna `contacts JSONB`
      agregada; `ActivityService.MapActivity`/`ParseContacts` la leen sin
      romper cuando la columna no existe (create/update, que siguen siendo
      `SETOF activities` puro — se completa con `LoadContactsAsync`,
      una segunda consulta a `fn_get_activity_by_id`).
- [x] CA5: `fn_get_reminder_dispatch_info` pasa a `LEFT JOIN
      activity_contacts`/`contacts` — una fila por contacto de la actividad,
      una fila con `contact_*` en NULL si no hay ninguno.
- [x] CA6: `ReminderDispatchJob.SendReminderAsync` recorre todas las filas:
      un `notification_log` por contacto (con try/catch individual, un
      destinatario inválido no cancela el envío a los demás), un solo push al
      dueño fuera del bucle. De paso corrige un bug real de precedencia en la
      condición original (`channel is Whatsapp or Both && contactId is not
      null` se evaluaba como `Whatsapp or (Both && contactId is not null)`
      por precedencia de operadores) con paréntesis explícitos.
- [x] CA7 (compatibilidad, RF12): `ActivityCreateRequest`/`ActivityResponse`
      conservan `ContactId` (legado) junto a `ContactIds`/`Contacts` (nuevo);
      `MergeContactIds` une y de-duplica ambos en creación.
- [x] CA8 (autorización, RNF2): la sincronización de `activity_contacts` en
      SQL filtra `JOIN contacts c ON c.id = ids.contact_id AND c.user_id =
      p_user_id` — un `contact_id` de otro usuario se ignora en silencio.
- [x] CA9 (transversal): `dotnet build` 0 errores/0 warnings; `dotnet test`
      49 passed/32 skipped (integración sin Postgres real en este entorno,
      igual que en SPECs previas); `backend-ci.yml` aplica `db/09` contra
      Postgres real del job de CI.
- [x] C-NR: generación de reminders, resto de endpoints de `/activities`,
      push al dueño y bandeja/limpieza de notificaciones (SPEC-007) sin
      cambios de comportamiento más allá de los campos aditivos nuevos.

**Limitación documentada, no bloqueante:** R5 de la SPEC — el envío real de
WhatsApp a múltiples contactos requiere la config de Meta ya conocida en
producción; no verificable en este sandbox. El bucle y el registro por
contacto se validan por lectura de código + `dotnet build`/`dotnet test`.
**Pendiente de acción del Lead:** aplicar `db/09_activity_contacts.sql` en el
servidor de producción y republicar el backend actualizado (ver
`docs/despliegue-spec-006-007-produccion.md` como referencia de formato;
mismo procedimiento: psql + `dotnet publish` + reciclar el Application Pool)
antes de que SPEC-009 (frontend) tenga un backend real contra el cual probar
de punta a punta.

## SPEC-010 — Color del día en "Actividades por fecha" (implementada por CAPTAIN AMERICA 2026-07-24)

- [x] CA1/CA2: `activities_by_date_screen.dart` calcula `dayColor =
      colorForDay(activities, Theme.of(context).colorScheme.primary)` una
      sola vez por día consultado (misma función y mismo fallback que "Mis
      citas", SPEC-005) y lo pasa a `_ActivityTile(dayColor: ...)`, que lo usa
      en la barra lateral en vez de `colorForActivityType(activity.type)`.
- [x] CA3 (transversal): `flutter analyze` → "No issues found!"; `flutter
      test` → 49/49.
- [x] C-NR: no se tocó `calendar_screen.dart`/`month_calendar.dart`/
      `appointments_section.dart`/`appointment_card.dart` ni el ícono por
      tipo; la navegación al detalle de la tarjeta no cambió.

## SPEC-009 — Frontend Flutter: selección múltiple de contactos (implementada por CAPTAIN AMERICA 2026-07-24)

- [x] CA1: `ContactPickerField` reescrito a multi-selección
      (`List<Contact> selectedContacts` + `ValueChanged<List<Contact>>`),
      chips (`InputChip`/`Wrap`) con `onDeleted`; buscar y agregar 2+
      contactos los asocia todos al crear (`activity_repository.dart` envía
      `contact_ids`).
- [x] CA2: `_hydrateFrom` en `activity_edit_screen.dart` ahora precarga
      `existing.contacts` — cierra el gap real de que la edición nunca
      hidrataba el contacto.
- [x] CA3: `updateActivity` siempre envía `contactIds` como el conjunto
      completo actual (reemplazo, alineado con SPEC-008 RF5); una lista
      vacía intencional quita todos los contactos.
- [x] CA4: `activity_detail_screen.dart` agrega una sección condicional
      (`_InfoRow` con ícono `person_outline`/`people_outline`) listando
      nombre y teléfono de cada contacto; oculta si `activity.contacts` está
      vacío.
- [x] CA5: `ContactPickerField` filtra de los resultados de búsqueda los
      contactos ya seleccionados — sin duplicados posibles en chips ni en
      `contact_ids`.
- [x] CA6 (transversal): `dart run build_runner build` sin errores;
      `flutter analyze` → "No issues found!"; `flutter test` → 52/52 (49
      previos + 3 nuevos que cubren las tres ramas de `contactIds` en
      `update`: null/vacío/con valores). `flutter build apk --release`
      compila y firma con el keystore existente.
- [x] C-NR: `calendar_screen.dart`, `month_calendar.dart`,
      `activities_by_date_screen.dart` (SPEC-010), paleta/tema y el patrón
      anti-bucle del calendario sin cambios; `ContactPickerField` solo tenía
      un consumidor (`activity_edit_screen.dart`), verificado con grep antes
      de cambiar su firma.

**Decisión de diseño:** se reutilizó el modelo `Contact` existente para
`Activity.contacts` (en vez de crear un `ActivityContact` nuevo), ya que el
JSON `contacts` de SPEC-008 (`{id, full_name, phone_e164}`) es
estructuralmente idéntico a `ContactResponse`.

**Limitación documentada, no bloqueante:** R4 de la SPEC — sin dispositivo
real en este entorno, la apariencia final de los chips y la sección de
contactos en el detalle se valida por lectura + `flutter test`; la revisión
visual queda en manos del Lead tras instalar el release.
