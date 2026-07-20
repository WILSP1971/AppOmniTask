# Tarea: (A) Notificaciones push end-to-end + (B) actividades SIN fecha visibles/accesibles

## Contexto / diagnóstico ya hecho (no re-investigar, ir al fix)
Dos fallos reportados por el Lead en la app v1.0.11:

### A) No llegan notificaciones push al celular
Causa raíz: la **app Flutter NO tiene Firebase configurado**.
- No existe `omnitask_app/lib/firebase_options.dart` ni `android/app/google-services.json`.
- `main.dart` tiene `Firebase.initializeApp()` COMENTADO.
- Por eso `Firebase.apps` está vacío → `device_registration_notifier.dart` hace early-return
  (`if (Firebase.apps.isEmpty) return`) → nunca se obtiene el token FCM → nunca se llama a
  `POST /devices`. Verificado: `GET /api/v1/devices` devuelve `[]` (cero dispositivos).
- El backend de push YA está listo (FirebasePushSender + ReminderDispatchJob cada minuto +
  firebase-admin.json en el server). Falta SOLO el lado app + registrar el token.

### B) Las actividades SIN fecha (unscheduled) no se ven ni hay opción en el menú
Causa raíz: es un problema de **navegación en la UI**, no de datos.
- El backend guarda y devuelve bien: `GET /api/v1/activities/unscheduled` retorna las actividades
  sin fecha (status `unscheduled`).
- El backlog ("Pendientes por programar", ruta `/backlog`) y "Consultas" solo viven en el
  `AppDrawer`, PERO el header rediseñado `AgendaHeader`
  (`features/calendar/presentation/widgets/agenda_header.dart`) es un `PreferredSizeWidget`
  custom SIN botón de menú (☰) → el Drawer es INALCANZABLE. Por eso "ni en el menú está la opción".

## Qué implementar

### A) Push end-to-end (app Flutter)
1. Configurar Firebase en la app: generar `firebase_options.dart` y
   `android/app/google-services.json` (FlutterFire CLI o consola Firebase) del **MISMO proyecto
   Firebase** cuyo service-account (`firebase-admin.json`) ya usa el backend en el server.
2. Activar `Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform)` en `main.dart`.
3. Pedir permiso de notificaciones: `FirebaseMessaging.requestPermission()` (y en Android 13+ el
   permiso `POST_NOTIFICATIONS` en el AndroidManifest y en runtime).
4. Asegurar que tras login `registerCurrentDevice()` obtenga el token y haga `POST /devices`
   (ya existe el flujo; ahora sí correrá porque Firebase estará inicializado).
5. Verificar recepción en foreground y background (ya hay listeners en push_message_listener.dart
   y app_router.dart).
- ⚠️ DEPENDENCIA DEL LEAD: hace falta el proyecto Firebase y sus credenciales. El
  `google-services.json` de la app y el `firebase-admin.json` del server DEBEN ser del mismo
  proyecto. Si no hay proyecto Firebase, crearlo (doc §20) y avisar al Lead qué archivo colocar.
- Verificación de aceptación: tras login, `GET /devices` devuelve el dispositivo; al crear una
  actividad con fecha próxima, el recordatorio dispara push y llega al celular.

### B) Actividades sin fecha visibles y accesibles
1. Hacer alcanzable el Drawer: agregar botón de menú (☰) en `AgendaHeader` que abra el Drawer
   (`Scaffold.of(context).openDrawer()`), o exponer "Pendientes" en el bottom nav (`AppBottomNav`).
2. MEJOR (según la imagen de referencia, ver abajo): en el Home, debajo del calendario, agregar
   una sección tipo **"Próximas / Pendientes"** que liste las actividades **sin fecha**
   (`GET /activities/unscheduled`) y/o próximas, en **tarjetas de colores** con opción de abrir
   y **programar** (asignar fecha). Que crear una actividad sin fecha se vea de inmediato ahí.
3. La actividad sin fecha debe poder abrirse, editarse y programarse (asignar fecha la mueve al
   calendario). El backend ya soporta esto (fn_update_activity).

## Diseño / COLORES (importante: como la imagen de referencia)
Referencia visual: mockup tipo "calendario + Upcoming" — calendario mensual con **círculos de
color** en los días con actividad y, debajo, una lista de tarjetas de colores con **ícono de
campana** (recordatorio). Mantener la paleta colorida ya usada (ver docs/contexto/agenda2.jpg y
agenda3.jpg): teal (#26C6A6), naranja (#F5A623), rosa/magenta (#EC4899), azul (#4A6CF7); color por
tipo de actividad. Fondo oscuro. No volver a un diseño monocromo.

## Restricciones DURAS
- No romper lo existente: login, calendario rediseñado, adjuntos, link de reunión, y el patrón
  anti-bucle del calendario.
- snake_case en el JSON; no cambiar contratos de la API ni la BD (para estos fixes NO hace falta
  tocar backend/BD — ya funcionan; el push server-side ya está).
- Mantener localización en español.

## Proceso y entrega
- Presenta PRIMERO un PLAN y espera aprobación del Lead (incluye qué credenciales Firebase se
  necesitan). Luego SPEC, y a implementar.
- flutter analyze + flutter test verdes.
- Cortar release por tag app-v1.0.12.

### A.bis) Pantalla "Dispositivos" vacía (mismo origen que A)
Reportado por el Lead: la pantalla de Dispositivos (`features/settings/presentation/devices_screen.dart`)
aparece **vacía y sin botón para agregar**. Causa: es la misma de A — como no hay Firebase, nunca se
registró un token → `GET /devices` = `[]` → la lista se pinta vacía. El diseño registra el dispositivo
AUTOMÁTICAMENTE (no manual), por eso no hay "agregar".
Fix (parte de A):
1. Una vez configurado Firebase (A), el dispositivo actual debe **auto-registrarse** tras login y
   aparecer en esta pantalla (marcado como "Este dispositivo").
2. Agregar un **empty-state claro**: mensaje tipo "Aún no hay dispositivos. Activa las notificaciones
   para recibir recordatorios" + un botón **"Activar notificaciones en este dispositivo"** que pida el
   permiso, obtenga el token FCM y llame a `registerCurrentDevice()` (POST /devices). Así el usuario
   tiene un control explícito además del registro automático.
3. `currentTokenProvider`/`getToken()` deben funcionar (dependen de Firebase inicializado).

## Credenciales Firebase (COLOCADAS por el Lead — 2026-07-20)
- Proyecto Firebase: **omnitask-agenda** (paquete com.clinicacampbell.omnitask_app).
- `google-services.json` YA está en `omnitask_app/android/app/google-services.json` (colocado).
  Está **gitignoreado**.
- ⚠️ CRÍTICO PARA EL CI: el workflow `android-release.yml` compila el APK sin el google-services.json
  (gitignoreado) → el plugin `com.google.gms.google-services` FALLARÁ el build o el APK quedará sin
  Firebase. HAY QUE hacerlo disponible en el build: (a) commitearlo (es config de cliente, ya viaja
  dentro del APK), o (b) inyectarlo como secret base64 de GitHub Actions y escribirlo en el workflow
  (mismo patrón que el keystore). Recomendado: (b) por consistencia, o (a) por simplicidad.
- NO usar `flutterfire configure` (falta el permiso serviceusage.services.enable y NO es necesario):
  en Android, con google-services.json + el plugin Gradle de Google Services, basta
  `Firebase.initializeApp()` SIN options.
- El `firebase-admin.json` (service account, SECRETO) va SOLO en el server de producción
  (`E:\App\APIOmniTask\secrets\firebase-admin.json`), del MISMO proyecto omnitask-agenda. NUNCA al repo.
