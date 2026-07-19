import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:omnitask_app/features/calendar/data/activity_repository.dart';
import 'package:omnitask_app/features/calendar/presentation/calendar_screen.dart';
import 'package:omnitask_app/features/notifications/data/notification_repository.dart';
import 'package:omnitask_app/models/paged_response.dart';

class MockActivityRepository extends Mock implements ActivityRepository {}

class MockNotificationRepository extends Mock implements NotificationRepository {}

/// Regresión de ADR-001/C2 y C4 (SPEC-001):
/// - C2: con SfCalendar, onViewChanged podía dispararse en cada layout y no
///   solo al cambiar de mes/vista realmente, arrastrando un refetch en
///   bucle si no había guard. Con table_calendar, onPageChanged solo debe
///   dispararse al cambiar de página — este test cuenta las llamadas reales
///   a fetchActivities para dejar eso demostrado (sin bucle: un número
///   estable de llamadas por cada cambio real, no creciente).
/// - C4: la carga inicial del Home debe traer el MES completo (para que
///   MonthCalendar pinte los puntitos de todo el mes), no solo la semana por
///   defecto de visibleRangeProvider — este test verifica el rango
///   (`from`/`to`) real de la última llamada de la carga inicial.
void main() {
  Widget wrap(ActivityRepository activityRepository,
      NotificationRepository notificationRepository) {
    final router = GoRouter(
      initialLocation: '/',
      routes: [
        GoRoute(path: '/', builder: (context, state) => const CalendarScreen()),
        GoRoute(
          path: '/notifications',
          builder: (context, state) => const SizedBox(),
        ),
        GoRoute(
          path: '/settings',
          builder: (context, state) => const SizedBox(),
        ),
        GoRoute(
          path: '/activities/new',
          builder: (context, state) => const SizedBox(),
        ),
      ],
    );
    return ProviderScope(
      overrides: [
        activityRepositoryProvider.overrideWithValue(activityRepository),
        notificationRepositoryProvider.overrideWithValue(notificationRepository),
      ],
      child: MaterialApp.router(routerConfig: router),
    );
  }

  testWidgets(
      'cambiar de mes en el calendario dispara un único refetch por cambio real',
      (tester) async {
    await initializeDateFormatting('es_CO');
    final activityRepository = MockActivityRepository();
    final notificationRepository = MockNotificationRepository();

    when(() => activityRepository.fetchActivities(
          from: any(named: 'from'),
          to: any(named: 'to'),
        )).thenAnswer((_) async =>
        const PagedResponse(items: [], page: 1, limit: 0, total: 0));
    when(() => notificationRepository.fetchUnreadCount())
        .thenAnswer((_) async => 0);

    await tester.pumpWidget(wrap(activityRepository, notificationRepository));
    await tester.pumpAndSettle();

    // Carga inicial: visibleRangeProvider arranca en la SEMANA por defecto
    // (pensada para el SfCalendar anterior), así que hay una primera consulta
    // transitoria con ese rango que CalendarScreen corrige a nivel de
    // microtask apenas se monta (Riverpod no permite mutar un provider
    // síncronamente durante ningún lifecycle, así que no hay forma de
    // evitar esta llamada extra sin tocar visible_range_provider.dart,
    // fuera de alcance de esta SPEC). Lo que sí debe quedar demostrado es
    // que son exactamente 2 llamadas — no más — y que la ÚLTIMA (la que de
    // verdad se pinta) cubre el mes completo, no la semana.
    final initialCalls =
        verify(() => activityRepository.fetchActivities(
              from: captureAny(named: 'from'),
              to: captureAny(named: 'to'),
            ));
    expect(initialCalls.callCount, 2);

    // Blindaje de C4 (rango inicial): la última llamada de la carga inicial
    // — la que activitiesForRangeProvider deja como estado final y
    // MonthCalendar / AppointmentsSection terminan pintando — debe cubrir el
    // MES completo, no la semana. Si el fix de sincronización se rompe (p.
    // ej. deja de corregirse, o vuelve a quedarse en la semana), este assert
    // falla aunque el conteo de llamadas por accidente siga dando el mismo
    // número.
    final now = DateTime.now();
    final expectedFrom = DateTime(now.year, now.month, 1);
    final expectedTo = DateTime(now.year, now.month + 1, 1);
    final lastFrom = initialCalls.captured[initialCalls.captured.length - 2]
        as DateTime;
    final lastTo = initialCalls.captured.last as DateTime;
    expect(lastFrom, expectedFrom);
    expect(lastTo, expectedTo);
    // La semana por defecto de visibleRangeProvider nunca cubre el mes
    // completo (ningún mes tiene 7 días o menos) — este assert es la forma
    // directa de detectar una regresión a "se quedó en la semana".
    expect(lastTo.difference(lastFrom).inDays >= 28, isTrue);

    // Reconstruir el árbol sin cambiar de mes (p.ej. rebuild por otro
    // provider) no debe volver a pedir ningún rango — ni el de semana ni el
    // de mes ya corregido.
    await tester.pump();
    await tester.pump();
    verifyNever(() => activityRepository.fetchActivities(
          from: any(named: 'from'),
          to: any(named: 'to'),
        ));

    // Avanzar de mes con el botón '›' del header sí debe refetchar — y
    // exactamente una vez para ese nuevo rango.
    await tester.tap(find.widgetWithIcon(IconButton, Icons.chevron_right));
    await tester.pumpAndSettle();

    final callsAfterMonthChange =
        verify(() => activityRepository.fetchActivities(
              from: any(named: 'from'),
              to: any(named: 'to'),
            )).callCount;
    expect(callsAfterMonthChange, 1);
  });
}
