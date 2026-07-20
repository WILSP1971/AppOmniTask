import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:omnitask_app/features/calendar/data/attachment_repository.dart';
import 'package:omnitask_app/features/calendar/presentation/widgets/attachments_section.dart';
import 'package:omnitask_app/models/attachment.dart';

class MockAttachmentRepository extends Mock implements AttachmentRepository {}

Attachment _fakeAttachment({
  String id = 'att1',
  String fileName = 'informe.pdf',
  String contentType = 'application/pdf',
  int sizeBytes = 2048,
}) =>
    Attachment(
      id: id,
      activityId: 'a1',
      fileName: fileName,
      contentType: contentType,
      sizeBytes: sizeBytes,
      uploadedAt: DateTime.utc(2026, 7, 20, 10),
    );

Widget _wrap(Widget child, {required AttachmentRepository repository}) => ProviderScope(
      overrides: [attachmentRepositoryProvider.overrideWithValue(repository)],
      child: MaterialApp(home: Scaffold(body: child)),
    );

void main() {
  // AttachmentsSection (SPEC-002 §3 RF6, CA1/CA2/CA4).
  group('AttachmentsSection', () {
    testWidgets('estado vacío muestra "Sin adjuntos todavía"', (tester) async {
      final repository = MockAttachmentRepository();
      when(() => repository.list('a1')).thenAnswer((_) async => <Attachment>[]);

      await tester.pumpWidget(_wrap(
        const AttachmentsSection(activityId: 'a1'),
        repository: repository,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Sin adjuntos todavía'), findsOneWidget);
      expect(find.byType(ListTile), findsNothing);
    });

    testWidgets('lista con adjuntos muestra nombre, tipo y tamaño legible', (tester) async {
      final repository = MockAttachmentRepository();
      when(() => repository.list('a1')).thenAnswer((_) async => [
            _fakeAttachment(id: 'att1', fileName: 'foto.jpg', contentType: 'image/jpeg', sizeBytes: 1536),
            _fakeAttachment(id: 'att2', fileName: 'informe.pdf', contentType: 'application/pdf', sizeBytes: 3 * 1024 * 1024),
          ]);

      await tester.pumpWidget(_wrap(
        const AttachmentsSection(activityId: 'a1'),
        repository: repository,
      ));
      await tester.pumpAndSettle();

      expect(find.text('Sin adjuntos todavía'), findsNothing);
      expect(find.text('foto.jpg'), findsOneWidget);
      expect(find.text('informe.pdf'), findsOneWidget);
      // 1536 B -> 1.5 KB; 3 MB -> 3.0 MB (formato legible KB/MB, RF6).
      expect(find.text('1.5 KB'), findsOneWidget);
      expect(find.text('3.0 MB'), findsOneWidget);
      // Cada fila trae acción abrir + eliminar.
      expect(find.byIcon(Icons.open_in_new), findsNWidgets(2));
      expect(find.byIcon(Icons.delete_outline), findsNWidgets(2));
    });

    testWidgets('eliminar pide confirmación antes de llamar al repositorio', (tester) async {
      final repository = MockAttachmentRepository();
      when(() => repository.list('a1')).thenAnswer((_) async => [_fakeAttachment()]);
      when(() => repository.delete('a1', 'att1')).thenAnswer((_) async {});

      await tester.pumpWidget(_wrap(
        const AttachmentsSection(activityId: 'a1'),
        repository: repository,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();

      // El diálogo de confirmación aparece y el repositorio NO se llamó todavía.
      expect(find.text('¿Eliminar este adjunto?'), findsOneWidget);
      verifyNever(() => repository.delete(any(), any()));

      // Cancelar ("Volver") no borra nada.
      await tester.tap(find.widgetWithText(TextButton, 'Volver'));
      await tester.pumpAndSettle();
      verifyNever(() => repository.delete(any(), any()));
    });

    testWidgets('confirmar el diálogo sí llama a delete en el repositorio', (tester) async {
      final repository = MockAttachmentRepository();
      when(() => repository.list('a1')).thenAnswer((_) async => [_fakeAttachment()]);
      when(() => repository.delete('a1', 'att1')).thenAnswer((_) async {});

      await tester.pumpWidget(_wrap(
        const AttachmentsSection(activityId: 'a1'),
        repository: repository,
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byIcon(Icons.delete_outline));
      await tester.pumpAndSettle();
      await tester.tap(find.widgetWithText(FilledButton, 'Eliminar'));
      await tester.pumpAndSettle();

      verify(() => repository.delete('a1', 'att1')).called(1);
    });

    testWidgets('error al listar muestra mensaje de error, no un 500 crudo', (tester) async {
      final repository = MockAttachmentRepository();
      when(() => repository.list('a1')).thenThrow(Exception('boom'));

      await tester.pumpWidget(_wrap(
        const AttachmentsSection(activityId: 'a1'),
        repository: repository,
      ));
      await tester.pumpAndSettle();

      expect(find.text('No se pudieron cargar los adjuntos'), findsOneWidget);
    });

    testWidgets('botones de selección de archivo están presentes (Cámara/Imagen/PDF)', (tester) async {
      final repository = MockAttachmentRepository();
      when(() => repository.list('a1')).thenAnswer((_) async => <Attachment>[]);

      await tester.pumpWidget(_wrap(
        const AttachmentsSection(activityId: 'a1'),
        repository: repository,
      ));
      await tester.pumpAndSettle();

      expect(find.widgetWithText(OutlinedButton, 'Cámara'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'Imagen'), findsOneWidget);
      expect(find.widgetWithText(OutlinedButton, 'PDF'), findsOneWidget);
    });
  });
}
