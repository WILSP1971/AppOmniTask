import 'package:freezed_annotation/freezed_annotation.dart';

part 'activity_draft.freezed.dart';

/// Lo que arma la pantalla de edición (§14) para crear una actividad —
/// espejo de ActivityCreateRequest (API, §6). Actualizar usa parámetros
/// nombrados directos en ActivityRepository.update(), no este tipo, porque
/// el update necesita distinguir "no tocar" de "limpiar" (§23) campo por
/// campo — algo que un Draft con nulls no puede expresar por sí solo.
@freezed
class ActivityDraft with _$ActivityDraft {
  const factory ActivityDraft({
    required String type,
    required String title,
    String? description,
    String? contactId,
    DateTime? startsAt,
    DateTime? endsAt,
    String? location,
    // SPEC-003 (§6, §3 RF1/RF2): reunión manual, opcional al crear.
    String? meetingUrl,
    String? meetingProvider,
  }) = _ActivityDraft;
}
