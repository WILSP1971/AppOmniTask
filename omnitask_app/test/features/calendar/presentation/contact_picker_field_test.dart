import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:omnitask_app/features/calendar/presentation/widgets/contact_picker_field.dart';
import 'package:omnitask_app/features/contacts/data/contact_repository.dart';
import 'package:omnitask_app/models/contact.dart';

class MockContactRepository extends Mock implements ContactRepository {}

Contact _fakeContact({String id = 'c1', String fullName = 'Ana Pérez'}) => Contact(
      id: id,
      fullName: fullName,
      phoneE164: '+573001234567',
    );

Widget _wrap(Widget child, {required ContactRepository repository}) => ProviderScope(
      overrides: [contactRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp(home: Scaffold(body: child)),
    );

void main() {
  // ContactPickerField — SPEC-011 RF5/RF6/RF7 (fix del spinner atascado y
  // mensaje de error real) y RF9 (no regresión del multi-contacto SPEC-009).
  group('ContactPickerField — búsqueda', () {
    testWidgets(
        'una excepción en search() apaga el spinner y muestra el mensaje real (RF5/RF6/CA4/CA5, RNF6)',
        (tester) async {
      final repository = MockContactRepository();
      when(() => repository.search(any())).thenThrow(Exception('fallo de red simulado'));

      await tester.pumpWidget(_wrap(
        ContactPickerField(selectedContacts: const [], onChanged: (_) {}),
        repository: repository,
      ));

      await tester.enterText(find.byType(TextField), 'an');
      // El debounce es de 350ms; se espera lo suficiente para que dispare y
      // la excepción sea capturada por el try/catch/finally.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      // CA4: sin spinner infinito.
      expect(find.byType(CircularProgressIndicator), findsNothing);
      // CA5: mensaje real de la excepción, no un genérico "Algo falló".
      expect(find.textContaining('fallo de red simulado'), findsOneWidget);
      expect(find.text('Algo falló. Intenta de nuevo.'), findsNothing);
    });

    testWidgets('sin resultados muestra "Sin coincidencias" (CA6, distinto de error)',
        (tester) async {
      final repository = MockContactRepository();
      when(() => repository.search(any())).thenAnswer((_) async => <Contact>[]);

      await tester.pumpWidget(_wrap(
        ContactPickerField(selectedContacts: const [], onChanged: (_) {}),
        repository: repository,
      ));

      await tester.enterText(find.byType(TextField), 'zz');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      expect(find.text('Sin coincidencias'), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsNothing);
    });

    testWidgets('al reintentar tras un error, el mensaje anterior se limpia (RF7/CA7)',
        (tester) async {
      final repository = MockContactRepository();
      when(() => repository.search('an')).thenThrow(Exception('fallo de red simulado'));
      when(() => repository.search('ana')).thenAnswer((_) async => [_fakeContact()]);

      await tester.pumpWidget(_wrap(
        ContactPickerField(selectedContacts: const [], onChanged: (_) {}),
        repository: repository,
      ));

      await tester.enterText(find.byType(TextField), 'an');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(find.textContaining('fallo de red simulado'), findsOneWidget);

      await tester.enterText(find.byType(TextField), 'ana');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      expect(find.textContaining('fallo de red simulado'), findsNothing);
      expect(find.text('Ana Pérez'), findsOneWidget);
    });

    testWidgets('buscar y agregar un contacto como chip sigue funcionando (RF9, SPEC-009)',
        (tester) async {
      final repository = MockContactRepository();
      when(() => repository.search(any())).thenAnswer((_) async => [_fakeContact()]);
      List<Contact>? selected;

      await tester.pumpWidget(_wrap(
        ContactPickerField(
          selectedContacts: const [],
          onChanged: (contacts) => selected = contacts,
        ),
        repository: repository,
      ));

      await tester.enterText(find.byType(TextField), 'an');
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      expect(find.text('Ana Pérez'), findsOneWidget);
      await tester.tap(find.text('Ana Pérez'));
      await tester.pump();

      expect(selected, isNotNull);
      expect(selected!.single.id, 'c1');
    });
  });
}
