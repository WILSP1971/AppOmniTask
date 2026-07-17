import 'package:flutter/material.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'visible_range_provider.g.dart';

/// Rango visible del calendario — cambiar de vista o deslizar de semana
/// actualiza esto, y activitiesForRangeProvider (que lo observa) recalcula
/// solo, sin invalidación manual (§12).
@riverpod
class VisibleRange extends _$VisibleRange {
  @override
  DateTimeRange build() => _weekRangeContaining(DateTime.now());

  void setRange(DateTimeRange range) => state = range;
}

DateTimeRange _weekRangeContaining(DateTime day) {
  final startOfWeek = day.subtract(Duration(days: day.weekday - 1));
  final start = DateTime(startOfWeek.year, startOfWeek.month, startOfWeek.day);
  return DateTimeRange(start: start, end: start.add(const Duration(days: 7)));
}
