import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../models/activity.dart';
import '../../../models/activity_draft.dart';
import '../../../models/paged_response.dart';

class ActivityRepository {
  ActivityRepository(this._dio);
  final Dio _dio;

  Future<Activity> create(ActivityDraft draft) async {
    final response = await _dio.post('/activities', data: {
      'type': draft.type,
      'title': draft.title,
      'description': draft.description,
      'contact_id': draft.contactId,
      'starts_at': draft.startsAt?.toUtc().toIso8601String(),
      'ends_at': draft.endsAt?.toUtc().toIso8601String(),
      'location': draft.location,
    });
    return Activity.fromJson(response.data as Map<String, dynamic>);
  }

  Future<PagedResponse<Activity>> fetchActivities({
    required DateTime from,
    required DateTime to,
    String? type,
    String? status,
  }) async {
    final response = await _dio.get('/activities', queryParameters: {
      'from': from.toUtc().toIso8601String(),
      'to': to.toUtc().toIso8601String(),
      if (type != null) 'type': type,
      if (status != null) 'status': status,
    });
    return PagedResponse.fromJson(
      response.data as Map<String, dynamic>,
      (json) => Activity.fromJson(json as Map<String, dynamic>),
    );
  }

  Future<List<Activity>> fetchUnscheduled() async {
    final response = await _dio.get('/activities/unscheduled');
    return (response.data as List).map((j) => Activity.fromJson(j as Map<String, dynamic>)).toList();
  }

  Future<Activity> fetchById(String id) async {
    final response = await _dio.get('/activities/$id');
    return Activity.fromJson(response.data as Map<String, dynamic>);
  }

  /// clearStartsAt/clearEndsAt distinguen "no tocar" de "limpiar" (§23) — un
  /// simple null no alcanza para expresar "quitar la fecha" sin ambigüedad.
  Future<Activity> update(
    String id, {
    String? title,
    String? description,
    DateTime? startsAt,
    bool clearStartsAt = false,
    DateTime? endsAt,
    bool clearEndsAt = false,
    String? status,
    String? location,
  }) async {
    final response = await _dio.patch('/activities/$id', data: {
      if (title != null) 'title': title,
      if (description != null) 'description': description,
      if (startsAt != null) 'starts_at': startsAt.toUtc().toIso8601String(),
      'clear_starts_at': clearStartsAt,
      if (endsAt != null) 'ends_at': endsAt.toUtc().toIso8601String(),
      'clear_ends_at': clearEndsAt,
      if (status != null) 'status': status,
      if (location != null) 'location': location,
    });
    return Activity.fromJson(response.data as Map<String, dynamic>);
  }

  /// Soft delete (§6): equivalente a status = cancelled.
  Future<void> cancel(String id) => _dio.delete('/activities/$id');
}

final activityRepositoryProvider = Provider<ActivityRepository>(
  (ref) => ActivityRepository(ref.watch(dioClientProvider)),
);
