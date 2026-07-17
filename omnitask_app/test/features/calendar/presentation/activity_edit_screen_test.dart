import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:omnitask_app/features/calendar/data/activity_repository.dart';
import 'package:omnitask_app/features/calendar/presentation/activity_edit_screen.dart';
import 'package:omnitask_app/models/activity.dart';
import 'package:omnitask_app/models/activity_draft.dart';

class MockActivityRepository extends Mock implements ActivityRepository {}

/// _submit() llama a context.pop() al guardar (§14) — go_router exige un
/// GoRouter real en el árbol, y además algo debajo en la pila para poder
/// volver (en la app real, ActivityEditScreen siempre se abre encima del
/// calendario o del backlog). Se anida "/edit" bajo "/" para que exista esa
/// ruta anterior.
Widget _wrapWithRouter(Widget child) {
  final router = GoRouter(
    initialLocation: '/edit',
    routes: [
      GoRoute(
        path: '/',
        builder: (context, state) => const SizedBox(),
        routes: [
          GoRoute(path: 'edit', builder: (context, state) => child),
        ],
      ),
    ],
  );
  return MaterialApp.router(routerConfig: router);
}

void main() {
  setUpAll(() {
    registerFallbackValue(const ActivityDraft(type: 'task', title: 'fallback'));
  });

  // Regresión del bug real corregido en la §24: "con fecha" activado pero sin
  // seleccionar ninguna fecha enviaba un POST silencioso; ahora debe avisar
  // y no llamar al repositorio en absoluto.
  testWidgets('crear con "con fecha" activado pero sin fecha elegida no envía nada', (tester) async {
    final repository = MockActivityRepository();

    await tester.pumpWidget(
      ProviderScope(
        overrides: [activityRepositoryProvider.overrideWithValue(repository)],
        child: _wrapWithRouter(const ActivityEditScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Título'), 'Reunión de equipo');
    await tester.tap(find.widgetWithText(FilledButton, 'Crear'));
    await tester.pump();

    expect(find.textContaining('Selecciona una fecha de inicio'), findsOneWidget);
    verifyNever(() => repository.create(any()));
  });

  testWidgets('"Sin fecha por ahora" activado sí permite crear sin fecha', (tester) async {
    final repository = MockActivityRepository();
    when(() => repository.create(any())).thenAnswer((invocation) async {
      final draft = invocation.positionalArguments.single as ActivityDraft;
      return _fakeActivity(title: draft.title);
    });

    await tester.pumpWidget(
      ProviderScope(
        overrides: [activityRepositoryProvider.overrideWithValue(repository)],
        child: _wrapWithRouter(const ActivityEditScreen()),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.widgetWithText(TextFormField, 'Título'), 'Llamar al proveedor');
    await tester.tap(find.widgetWithText(SwitchListTile, 'Sin fecha por ahora'));
    await tester.pump();
    await tester.tap(find.widgetWithText(FilledButton, 'Crear'));
    await tester.pump();

    final captured = verify(() => repository.create(captureAny())).captured.single as ActivityDraft;
    expect(captured.startsAt, isNull);
    expect(captured.title, 'Llamar al proveedor');
  });
}

Activity _fakeActivity({required String title}) => Activity.fromJson({
      'id': 'a1',
      'user_id': 'u1',
      'contact_id': null,
      'type': 'task',
      'title': title,
      'description': null,
      'status': 'unscheduled',
      'starts_at': null,
      'ends_at': null,
      'timezone': 'America/Bogota',
      'location': null,
      'created_at': '2026-07-01T10:00:00Z',
      'updated_at': '2026-07-01T10:00:00Z',
    });
