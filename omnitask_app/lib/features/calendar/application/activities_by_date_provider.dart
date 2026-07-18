import 'package:riverpod_annotation/riverpod_annotation.dart';

import '../../../models/activity.dart';
import '../data/activity_repository.dart';

part 'activities_by_date_provider.g.dart';

/// Consulta de "Actividades calendario según fecha" (§28, menú lateral) — un
/// solo día, a diferencia de activitiesForRangeProvider que sigue el rango
/// visible del calendario (§12).
@riverpod
Future<List<Activity>> activitiesByDate(ActivitiesByDateRef ref, DateTime day) async {
  final start = DateTime(day.year, day.month, day.day);
  final end = start.add(const Duration(days: 1));

  final paged = await ref.watch(activityRepositoryProvider).fetchActivities(from: start, to: end);
  final items = [...paged.items];
  items.sort((a, b) {
    final aStart = a.startsAt;
    final bStart = b.startsAt;
    if (aStart == null || bStart == null) return 0;
    return aStart.compareTo(bStart);
  });
  return items;
}
