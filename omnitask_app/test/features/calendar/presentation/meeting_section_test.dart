import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitask_app/features/calendar/presentation/widgets/meeting_section.dart';
import 'package:omnitask_app/models/activity.dart';

Activity _fakeActivity({String? meetingUrl, String? meetingProvider}) => Activity.fromJson({
      'id': 'a1',
      'user_id': 'u1',
      'contact_id': null,
      'type': 'meeting',
      'title': 'Reunión semanal',
      'description': null,
      'status': 'scheduled',
      'starts_at': '2026-07-21T15:00:00Z',
      'ends_at': null,
      'timezone': 'America/Bogota',
      'location': null,
      'created_at': '2026-07-01T10:00:00Z',
      'updated_at': '2026-07-01T10:00:00Z',
      'meeting_url': meetingUrl,
      'meeting_provider': meetingProvider,
    });

Widget _wrap(Widget child) => MaterialApp(home: Scaffold(body: child));

void main() {
  // El binding de test no responde por defecto al canal de plataforma del
  // clipboard: sin este mock, Clipboard.setData() nunca completa su Future y
  // el SnackBar de feedback (CA3) no llega a mostrarse en el widget test.
  TestWidgetsFlutterBinding.ensureInitialized();
  const clipboardChannel = SystemChannels.platform;

  setUp(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(clipboardChannel, (MethodCall call) async {
      if (call.method == 'Clipboard.setData') return null;
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(clipboardChannel, null);
  });

  // MeetingSection (SPEC-003 §3 RF3-RF7, CA6).
  group('MeetingSection', () {
    testWidgets('sin meeting_url no renderiza nada (oculto, CA6/RF7)', (tester) async {
      await tester.pumpWidget(_wrap(MeetingSection(activity: _fakeActivity())));
      await tester.pumpAndSettle();

      expect(find.byType(Card), findsNothing);
      expect(find.widgetWithText(OutlinedButton, 'Copiar'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, 'Abrir'), findsNothing);
      expect(find.widgetWithText(OutlinedButton, 'Compartir'), findsNothing);
    });

    testWidgets('con meeting_url muestra el link y el proveedor, y las 3 acciones', (tester) async {
      await tester.pumpWidget(_wrap(MeetingSection(
        activity: _fakeActivity(meetingUrl: 'https://meet.google.com/abc-defg-hij', meetingProvider: 'meet'),
      )));
      await tester.pumpAndSettle();

      expect(find.byType(Card), findsOneWidget);
      expect(find.text('Google Meet'), findsOneWidget);
      expect(find.text('https://meet.google.com/abc-defg-hij'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Copiar'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Abrir'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Compartir'), findsOneWidget);
    });

    testWidgets('proveedor teams usa la etiqueta correcta', (tester) async {
      await tester.pumpWidget(_wrap(MeetingSection(
        activity: _fakeActivity(meetingUrl: 'https://teams.microsoft.com/l/x', meetingProvider: 'teams'),
      )));
      await tester.pumpAndSettle();

      expect(find.text('Microsoft Teams'), findsOneWidget);
    });

    testWidgets('proveedor desconocido/null usa la etiqueta genérica "Reunión"', (tester) async {
      await tester.pumpWidget(_wrap(MeetingSection(
        activity: _fakeActivity(meetingUrl: 'https://example.com/sala'),
      )));
      await tester.pumpAndSettle();

      expect(find.text('Reunión'), findsOneWidget);
    });

    testWidgets('copiar muestra feedback de snackbar (CA3)', (tester) async {
      await tester.pumpWidget(_wrap(MeetingSection(
        activity: _fakeActivity(meetingUrl: 'https://meet.google.com/abc-defg-hij', meetingProvider: 'meet'),
      )));
      await tester.pumpAndSettle();

      await tester.tap(find.widgetWithText(OutlinedButton, 'Copiar'));
      await tester.pump(); // procesa el Future de Clipboard.setData
      await tester.pump(); // muestra el SnackBar
      await tester.pump(const Duration(milliseconds: 100)); // deja avanzar su animación de entrada

      expect(find.text('Link copiado al portapapeles'), findsOneWidget);
    });
  });
}
