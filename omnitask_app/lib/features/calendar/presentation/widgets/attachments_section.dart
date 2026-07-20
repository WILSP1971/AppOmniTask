import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:open_filex/open_filex.dart' show OpenFilex, ResultType;
import 'package:path_provider/path_provider.dart';

import '../../../../models/attachment.dart';
import '../../application/attachments_provider.dart';

/// Adjuntos de la actividad (SPEC-002 §3 RF6): subir imagen (cámara/galería)
/// o PDF, listar con nombre/tipo/tamaño, abrir con el visor del sistema y
/// eliminar con confirmación. Sin previsualización enriquecida (fuera de
/// alcance, §9 de la SPEC).
class AttachmentsSection extends ConsumerWidget {
  const AttachmentsSection({super.key, required this.activityId});
  final String activityId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final attachmentsAsync = ref.watch(activityAttachmentsProvider(activityId));
    final actionState = ref.watch(attachmentActionsControllerProvider(activityId));
    final controller = ref.read(attachmentActionsControllerProvider(activityId).notifier);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Adjuntos', style: Theme.of(context).textTheme.titleMedium),
                ),
                if (actionState.isLoading)
                  const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  ),
              ],
            ),
            const SizedBox(height: 8),
            attachmentsAsync.when(
              data: (attachments) => attachments.isEmpty
                  ? Text('Sin adjuntos todavía',
                      style: TextStyle(color: Theme.of(context).colorScheme.outline))
                  : Column(
                      children: attachments
                          .map((a) => _AttachmentTile(
                                activityId: activityId,
                                attachment: a,
                                busy: actionState.isLoading,
                              ))
                          .toList(),
                    ),
              loading: () => const Padding(
                padding: EdgeInsets.symmetric(vertical: 8),
                child: Center(child: CircularProgressIndicator()),
              ),
              error: (e, _) => Text('No se pudieron cargar los adjuntos',
                  style: TextStyle(color: Theme.of(context).colorScheme.error)),
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              children: [
                OutlinedButton.icon(
                  onPressed: actionState.isLoading
                      ? null
                      : () => _pickImage(context, controller, ImageSource.camera),
                  icon: const Icon(Icons.photo_camera_outlined, size: 18),
                  label: const Text('Cámara'),
                ),
                OutlinedButton.icon(
                  onPressed: actionState.isLoading
                      ? null
                      : () => _pickImage(context, controller, ImageSource.gallery),
                  icon: const Icon(Icons.image_outlined, size: 18),
                  label: const Text('Imagen'),
                ),
                OutlinedButton.icon(
                  onPressed: actionState.isLoading ? null : () => _pickPdf(context, controller),
                  icon: const Icon(Icons.picture_as_pdf_outlined, size: 18),
                  label: const Text('PDF'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickImage(
    BuildContext context,
    AttachmentActionsController controller,
    ImageSource source,
  ) async {
    final picked = await ImagePicker().pickImage(source: source, imageQuality: 90);
    if (picked == null) return;
    final bytes = await picked.readAsBytes();
    if (!context.mounted) return;
    await _upload(
      context,
      controller,
      fileName: picked.name,
      contentType: picked.mimeType ?? _inferImageContentType(picked.name),
      bytes: bytes,
    );
  }

  /// Respaldo cuando el picker nativo no informa mimeType (ocurre en algunos
  /// dispositivos/Android): el backend valida por Content-Type (SPEC-002 §3
  /// RF7), así que hace falta un valor coherente con la extensión real.
  String _inferImageContentType(String fileName) {
    final lower = fileName.toLowerCase();
    if (lower.endsWith('.png')) return 'image/png';
    if (lower.endsWith('.heic')) return 'image/heic';
    return 'image/jpeg';
  }

  Future<void> _pickPdf(BuildContext context, AttachmentActionsController controller) async {
    final result = await FilePicker.pickFiles(type: FileType.custom, allowedExtensions: ['pdf'], withData: true);
    final file = result?.files.single;
    if (file == null || file.bytes == null) return;
    if (!context.mounted) return;
    await _upload(context, controller,
        fileName: file.name, contentType: 'application/pdf', bytes: file.bytes!);
  }

  Future<void> _upload(
    BuildContext context,
    AttachmentActionsController controller, {
    required String fileName,
    String? contentType,
    required List<int> bytes,
  }) async {
    final result = await controller.upload(
      fileName: fileName,
      contentType: contentType ?? 'application/octet-stream',
      bytes: bytes,
    );
    if (!context.mounted) return;
    final message = result.isSuccess ? 'Archivo adjuntado' : result.errorMessage!;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
  }
}

class _AttachmentTile extends ConsumerWidget {
  const _AttachmentTile({required this.activityId, required this.attachment, required this.busy});
  final String activityId;
  final Attachment attachment;
  final bool busy;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final controller = ref.read(attachmentActionsControllerProvider(activityId).notifier);

    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(_iconFor(attachment.contentType)),
      title: Text(attachment.fileName, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitle: Text(_readableSize(attachment.sizeBytes)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'Abrir',
            icon: const Icon(Icons.open_in_new),
            onPressed: busy ? null : () => _open(context, controller),
          ),
          IconButton(
            tooltip: 'Eliminar',
            icon: const Icon(Icons.delete_outline),
            onPressed: busy ? null : () => _confirmDelete(context, controller),
          ),
        ],
      ),
    );
  }

  IconData _iconFor(String contentType) {
    if (contentType == 'application/pdf') return Icons.picture_as_pdf_outlined;
    if (contentType.startsWith('image/')) return Icons.image_outlined;
    return Icons.insert_drive_file_outlined;
  }

  String _readableSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Future<void> _open(BuildContext context, AttachmentActionsController controller) async {
    final downloadResult = await controller.download(attachment.id);
    if (!context.mounted) return;
    if (!downloadResult.isSuccess) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(downloadResult.errorMessage!)));
      return;
    }
    final dir = await getTemporaryDirectory();
    final file = File('${dir.path}/${attachment.id}_${_sanitizedFileName(attachment.fileName)}');
    await file.writeAsBytes(downloadResult.value!, flush: true);
    final openResult = await OpenFilex.open(file.path);
    if (!context.mounted) return;
    if (openResult.type != ResultType.done) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('No se pudo abrir el archivo con una app del dispositivo')),
      );
    }
  }

  /// Defensa en profundidad del lado cliente (el servidor ya garantiza que el
  /// nombre físico es un GUID): toma solo el basename de [fileName] y
  /// descarta separadores de ruta y `..`, para que nunca pueda escribirse un
  /// archivo temporal fuera del directorio esperado.
  String _sanitizedFileName(String fileName) {
    final basename = fileName.split(RegExp(r'[\\/]')).last;
    final sanitized = basename.replaceAll('..', '').replaceAll(RegExp(r'[\\/]'), '_');
    return sanitized.isEmpty ? 'archivo' : sanitized;
  }

  Future<void> _confirmDelete(BuildContext context, AttachmentActionsController controller) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('¿Eliminar este adjunto?'),
        content: Text('Se eliminará "${attachment.fileName}" de forma permanente.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Volver')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Eliminar')),
        ],
      ),
    );
    if (confirmed != true) return;
    final result = await controller.delete(attachment.id);
    if (!context.mounted || result.isSuccess) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(result.errorMessage!)));
  }
}
