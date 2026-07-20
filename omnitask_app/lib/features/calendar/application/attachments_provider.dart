import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../core/network/dio_client.dart';
import '../../../models/attachment.dart';
import '../data/attachment_repository.dart';

part 'attachments_provider.g.dart';

/// Lista de adjuntos de una actividad (SPEC-002 §3 RF2) — se invalida tras
/// subir o eliminar (ver AttachmentActionsController) para que la UI del
/// detalle siempre refleje el estado real del servidor.
@riverpod
Future<List<Attachment>> activityAttachments(
  ActivityAttachmentsRef ref,
  String activityId,
) {
  return ref.watch(attachmentRepositoryProvider).list(activityId);
}

/// Resultado de una acción sobre adjuntos: [value] tiene el dato en éxito;
/// [errorMessage] ya viene mapeado a español (nunca un 500/objeto crudo) para
/// que la UI lo muestre directo en un SnackBar.
class AttachmentActionResult<T> {
  const AttachmentActionResult.success(this.value) : errorMessage = null;
  const AttachmentActionResult.failure(this.errorMessage) : value = null;

  final T? value;
  final String? errorMessage;

  bool get isSuccess => errorMessage == null;
}

/// Subir/eliminar/descargar adjuntos (SPEC-002 §3 RF1/RF3/RF4). Estado de
/// carga expuesto para que la UI deshabilite acciones mientras hay una
/// operación en curso; el resultado de cada acción viaja en su propio
/// retorno (no en `state.error`, que es de solo lectura fuera del notifier).
@riverpod
class AttachmentActionsController extends _$AttachmentActionsController {
  @override
  FutureOr<void> build(String activityId) {}

  Future<AttachmentActionResult<Attachment>> upload({
    required String fileName,
    required String contentType,
    required List<int> bytes,
  }) async {
    state = const AsyncLoading();
    final result = await AsyncValue.guard(() => ref.read(attachmentRepositoryProvider).upload(
          activityId: activityId,
          fileName: fileName,
          contentType: contentType,
          bytes: bytes,
        ));
    state = result.hasError ? AsyncError(result.error!, result.stackTrace!) : const AsyncData(null);
    if (result.hasError) {
      return AttachmentActionResult.failure(mapApiError(result.error!));
    }
    ref.invalidate(activityAttachmentsProvider(activityId));
    return AttachmentActionResult.success(result.value);
  }

  Future<AttachmentActionResult<void>> delete(String attachmentId) async {
    state = const AsyncLoading();
    final result = await AsyncValue.guard(
        () => ref.read(attachmentRepositoryProvider).delete(activityId, attachmentId));
    state = result;
    if (result.hasError) {
      return AttachmentActionResult.failure(mapApiError(result.error!));
    }
    ref.invalidate(activityAttachmentsProvider(activityId));
    return const AttachmentActionResult.success(null);
  }

  Future<AttachmentActionResult<List<int>>> download(String attachmentId) async {
    state = const AsyncLoading();
    final result = await AsyncValue.guard(
        () => ref.read(attachmentRepositoryProvider).download(activityId, attachmentId));
    state = result.hasError ? AsyncError(result.error!, result.stackTrace!) : const AsyncData(null);
    if (result.hasError) {
      return AttachmentActionResult.failure(mapApiError(result.error!));
    }
    return AttachmentActionResult.success(result.value);
  }
}
