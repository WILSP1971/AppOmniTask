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
