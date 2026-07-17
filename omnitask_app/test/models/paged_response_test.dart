import 'package:flutter_test/flutter_test.dart';
import 'package:omnitask_app/models/paged_response.dart';

void main() {
  test('PagedResponse<T>.fromJson delega en el fromJsonT del tipo genérico', () {
    final response = PagedResponse<int>.fromJson(
      {
        'items': [1, 2, 3],
        'page': 2,
        'limit': 3,
        'total': 9,
      },
      (json) => json as int,
    );

    expect(response.items, [1, 2, 3]);
    expect(response.page, 2);
    expect(response.limit, 3);
    expect(response.total, 9);
  });
}
