# SPEC-004 — Push end-to-end y actividades sin fecha visibles/accesibles

- ID: SPEC-004
- Estado: APROBADA (Lead humano, 2026-07-20)
- Autor: DOCTOR STRANGE (la aprobación es del Lead humano, nunca del autor)
- Fecha: 2026-07-20
- Responsable de implementación: CAPTAIN AMERICA
- Colaboradores / revisores:
  - DAREDEVIL — frontend Flutter (permiso de notificaciones, empty-state de
    Dispositivos, acceso a Backlog desde Home)
  - WOLVERINE — calidad (revisión de código, no regresión del calendario)
  - HAWKEYE — pruebas (widget tests de las pantallas tocadas)
- Fuente: `docs/contexto/tarea-push-y-pendientes.md` (diagnóstico ya hecho por el
  Lead, no se re-investiga)

---

## 1. Objetivo

Dos fallos reales reportados en producción sobre `app-v1.0.11`:

- **(A) No llegan notificaciones push al celular** — la app nunca inicializaba
  Firebase, así que ningún dispositivo llegaba a registrarse.
- **(B) Las actividades sin fecha (`unscheduled`) no se ven ni son accesibles** —
  problema de navegación, no de datos: el Drawer con "Actividades sin programar"
  quedó inalcanzable tras el rediseño de Home (SPEC-001), porque `AgendaHeader` es
  un `PreferredSizeWidget` a medida sin botón de menú.

## 2. Contexto — estado ya resuelto en esta misma conversación (infraestructura)

Antes de esta SPEC, y ya verificado con `flutter analyze`/`flutter test`/un
`flutter build apk --release` real (commits `86c36e0`, `fb7f840`):

- Firebase configurado con `flutterfire configure` contra el proyecto
  **`omnitask-agenda`** — el mismo que ya usa el backend en producción vía
  `firebase-admin.json`, confirmado por el Lead.
- `lib/firebase_options.dart` generado y comiteado (no es secreto según la propia
  documentación de Firebase); `android/app/google-services.json` gitignored y
  reconstruido en `android-release.yml` desde el secret
  `GOOGLE_SERVICES_JSON_BASE64`, mismo patrón que el keystore.
- `main.dart` ya llama a `Firebase.initializeApp(options:
  DefaultFirebaseOptions.currentPlatform)`.
- Los cuatro guards `Firebase.apps.isEmpty` ya existentes (en
  `device_registration_notifier.dart`, `push_message_listener.dart`,
  `app_router.dart`, `devices_provider.dart`) ya dejan de saltarse — no hace falta
  tocarlos, esta SPEC no cambia esa lógica.

**Esta SPEC cubre lo que falta por encima de esa infraestructura**: la UX de pedir
permiso, el empty-state de Dispositivos, y hacer alcanzables las actividades sin
fecha desde el Home.

## 3. Requisitos funcionales

- **RF1 — Pedir permiso de notificaciones tras login/registro.** En
  `auth_notifier.dart` (login exitoso y registro exitoso), tras
  `registerCurrentDevice()`, llamar `FirebaseMessaging.instance.requestPermission()`
  si `Firebase.apps.isNotEmpty`. No bloquea el flujo de login si el usuario niega el
  permiso — solo condiciona si llegan pushes visibles.
- **RF2 — Empty-state real en Dispositivos.** `devices_screen.dart`: si
  `myDevicesProvider` devuelve lista vacía, mostrar un mensaje claro ("Aún no hay
  dispositivos. Activa las notificaciones para recibir recordatorios") y un botón
  **"Activar notificaciones en este dispositivo"** que pida el permiso, obtenga el
  token FCM y llame a `registerCurrentDevice()` — control explícito además del
  registro automático de RF1.
- **RF3 — Menú alcanzable desde Home.** Agregar un botón ☰ en `AgendaHeader` que
  abra el Drawer (`Scaffold.of(context).openDrawer()`) — desbloquea de inmediato el
  Drawer y "Actividades sin programar" ya existentes, sin tocar su lógica.
- **RF4 — Sección "Pendientes por programar" en el Home.** Debajo de "Mis citas" en
  `calendar_screen.dart`, agregar una sección que liste
  `unscheduledActivitiesProvider` reutilizando `AppointmentsSection`/
  `AppointmentCard` tal cual existen (ya manejan `startsAt == null` mostrando "--"
  en el badge de fecha) — cero componentes ni colores nuevos. Tocar "Editar" en esa
  tarjeta ya lleva a `/activities/{id}/edit`, donde se le puede asignar fecha
  (mueve la actividad al calendario vía `fn_update_activity`, ya soportado).

## 4. Requisitos no funcionales

- **RNF1 — No regresión.** CERO cambios en `allowedViews`, `initialDisplayDate`,
  `skipLoadingOnReload`, el guard anti-bucle de `_handleMonthChanged`/
  `onViewChanged`, `appointmentBuilder`/`table_calendar`, ni en los guards
  `Firebase.apps.isEmpty` ya existentes (dejan de ser no-ops, pero su código no
  cambia).
- **RNF2 — Cero cambios de backend/BD.** El backend de push ya funciona
  (`FirebasePushSender` + `ReminderDispatchJob`); `GET /activities/unscheduled` ya
  devuelve lo correcto. Esta SPEC es 100% frontend.
- **RNF3 — Localización.** Textos en español (es_CO), coherentes con el resto de
  la app.
- **RNF4 — Fallar en silencio, no en pantalla.** Si el usuario niega el permiso de
  notificaciones, ninguna pantalla debe romperse ni mostrar un error — el
  empty-state de RF2 sigue disponible para reintentar cuando quiera.

## 5. Criterios de aceptación verificables

- [ ] CA1: Tras login/registro con Firebase inicializado, `GET /devices` devuelve
      el dispositivo actual (verificable con la guía `docs/pruebas-api.html`).
- [ ] CA2: Pantalla Dispositivos vacía muestra el empty-state + botón; tocarlo
      registra el dispositivo y la lista deja de estar vacía.
- [ ] CA3: Desde el Home, el botón ☰ abre el Drawer y "Actividades sin programar"
      es alcanzable.
- [ ] CA4: El Home muestra una sección "Pendientes por programar" con las
      actividades sin fecha, coloreadas por tipo igual que "Mis citas".
- [ ] CA5: Tocar "Editar" en una tarjeta pendiente permite asignarle fecha y la
      actividad pasa a aparecer en el calendario (deja de estar en "Pendientes").
- [ ] CA6 (transversal): `flutter analyze` y `flutter test` en verde;
      `flutter build apk --release` compila y firma con el keystore existente.
- [ ] C-NR (no regresión): `git diff` demuestra CERO cambios en
      `allowedViews`/`initialDisplayDate`/`skipLoadingOnReload`/
      `appointmentBuilder`/`table_calendar`/los guards `Firebase.apps.isEmpty`
      existentes.

## 6. Riesgos y dependencias

- **R1 — No verificable de punta a punta en este entorno.** No hay dispositivo ni
  emulador Android real aquí — se puede confirmar que el código compila, que
  `GET /devices` devuelve el token tras un flujo simulado, y que la UI se ve
  correcta por inspección de widget tests, pero la entrega real de una notificación
  push a un celular queda como verificación manual del Lead tras instalar
  `app-v1.0.12`.
- **R2 — Permiso denegado por el usuario.** Si el usuario niega el permiso en el
  diálogo del sistema, `requestPermission()` no lanza; simplemente no habrá
  notificaciones visibles. Documentado como comportamiento esperado, no un bug.

## 7. Alcance EXCLUIDO (explícito)

- **Rediseño visual adicional** (más allá de reutilizar componentes ya existentes
  de SPEC-001): fuera de esta SPEC.
- **Notificaciones por WhatsApp**: ya funcionan del lado del backend
  (`ReminderDispatchJob`), no es parte de este alcance.
- **Reordenar o filtrar** "Pendientes por programar" más allá de la lista simple
  que ya devuelve `GET /activities/unscheduled`: fuera.
