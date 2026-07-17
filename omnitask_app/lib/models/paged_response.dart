import 'package:freezed_annotation/freezed_annotation.dart';

part 'paged_response.freezed.dart';
part 'paged_response.g.dart';

/// Espejo genérico de PagedResponse&lt;T&gt; (API, §6, §17).
@Freezed(genericArgumentFactories: true)
class PagedResponse<T> with _$PagedResponse<T> {
  const factory PagedResponse({
    required List<T> items,
    required int page,
    required int limit,
    required int total,
  }) = _PagedResponse<T>;

  factory PagedResponse.fromJson(
    Map<String, dynamic> json,
    T Function(Object? json) fromJsonT,
  ) =>
      _$PagedResponseFromJson(json, fromJsonT);
}
