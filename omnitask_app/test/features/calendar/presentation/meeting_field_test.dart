import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:omnitask_app/features/calendar/presentation/widgets/meeting_field.dart';

Widget _wrap({
  required GlobalKey<FormState> formKey,
  String? provider,
  required TextEditingController controller,
  ValueChanged<String?>? onProviderChanged,
}) =>
    MaterialApp(
      home: Scaffold(
        body: Form(
          key: formKey,
          child: MeetingField(
            provider: provider,
            urlController: controller,
            onProviderChanged: onProviderChanged ?? (_) {},
          ),
        ),
      ),
    );

void main() {
  // MeetingField (SPEC-003 §3 RF1/RF2, CA1).
  group('MeetingField', () {
    testWidgets('campo vacío es válido (URL de reunión opcional)', (tester) async {
      final formKey = GlobalKey<FormState>();
      final controller = TextEditingController();

      await tester.pumpWidget(_wrap(formKey: formKey, controller: controller));
      await tester.pumpAndSettle();

      expect(formKey.currentState!.validate(), isTrue);
      expect(find.textContaining('Ingresa un link válido'), findsNothing);
    });

    testWidgets('URL http:// es válida', (tester) async {
      final formKey = GlobalKey<FormState>();
      final controller = TextEditingController(text: 'http://meet.example.com/sala');

      await tester.pumpWidget(_wrap(formKey: formKey, controller: controller));
      await tester.pumpAndSettle();

      expect(formKey.currentState!.validate(), isTrue);
    });

    testWidgets('URL https:// es válida', (tester) async {
      final formKey = GlobalKey<FormState>();
      final controller = TextEditingController(text: 'https://meet.google.com/abc-defg-hij');

      await tester.pumpWidget(_wrap(formKey: formKey, controller: controller));
      await tester.pumpAndSettle();

      expect(formKey.currentState!.validate(), isTrue);
    });

    testWidgets('texto que no es una URL http/https se rechaza con mensaje claro', (tester) async {
      final formKey = GlobalKey<FormState>();
      final controller = TextEditingController(text: 'esto no es un link');

      await tester.pumpWidget(_wrap(formKey: formKey, controller: controller));
      await tester.pumpAndSettle();

      expect(formKey.currentState!.validate(), isFalse);
      await tester.pump();
      expect(find.textContaining('Ingresa un link válido'), findsOneWidget);
    });

    testWidgets('esquema no http (ftp://) se rechaza', (tester) async {
      final formKey = GlobalKey<FormState>();
      final controller = TextEditingController(text: 'ftp://example.com/reunion');

      await tester.pumpWidget(_wrap(formKey: formKey, controller: controller));
      await tester.pumpAndSettle();

      expect(formKey.currentState!.validate(), isFalse);
    });

    testWidgets('el selector de proveedor muestra Meet/Teams/Otro/Ninguno', (tester) async {
      final formKey = GlobalKey<FormState>();
      final controller = TextEditingController();

      await tester.pumpWidget(_wrap(formKey: formKey, controller: controller));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();

      expect(find.text('Ninguno'), findsWidgets);
      expect(find.text('Google Meet'), findsOneWidget);
      expect(find.text('Microsoft Teams'), findsOneWidget);
      expect(find.text('Otro'), findsOneWidget);
    });

    testWidgets('seleccionar un proveedor invoca onProviderChanged', (tester) async {
      final formKey = GlobalKey<FormState>();
      final controller = TextEditingController();
      String? selected;

      await tester.pumpWidget(_wrap(
        formKey: formKey,
        controller: controller,
        onProviderChanged: (value) => selected = value,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(DropdownButtonFormField<String>));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Google Meet').last);
      await tester.pumpAndSettle();

      expect(selected, 'meet');
    });
  });
}
