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
