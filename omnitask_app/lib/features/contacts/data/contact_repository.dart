import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/network/dio_client.dart';
import '../../../models/contact.dart';

class ContactRepository {
  ContactRepository(this._dio);
  final Dio _dio;

  Future<Contact> create({required String fullName, required String phoneE164, String? notes}) async {
    final response = await _dio.post('/contacts', data: {
      'full_name': fullName,
      'phone_e164': phoneE164,
      'notes': notes,
    });
    return Contact.fromJson(response.data as Map<String, dynamic>);
  }

  Future<List<Contact>> search(String? query) async {
    final response = await _dio.get('/contacts', queryParameters: {
      if (query != null && query.isNotEmpty) 'search': query,
    });
    final data = response.data;
    // RF8 (SPEC-011): endurecer el parseo — si `response.data` no es una
    // `List` (p. ej. viene envuelto en un objeto, o es null), no lanzar un
    // `_TypeError` opaco; se trata como "sin resultados" ante una forma de
    // respuesta inesperada.
    if (data is! List) return [];
    final contacts = <Contact>[];
    for (final item in data) {
      if (item is Map<String, dynamic>) {
        contacts.add(Contact.fromJson(item));
      }
      // Elementos que no son un mapa se descartan en vez de lanzar — mejor
      // esfuerzo (RF8): una entrada malformada no debe tumbar toda la lista.
    }
    return contacts;
  }

  Future<Contact> fetchById(String id) async {
    final response = await _dio.get('/contacts/$id');
    return Contact.fromJson(response.data as Map<String, dynamic>);
  }
}

final contactRepositoryProvider = Provider<ContactRepository>(
  (ref) => ContactRepository(ref.watch(dioClientProvider)),
);
