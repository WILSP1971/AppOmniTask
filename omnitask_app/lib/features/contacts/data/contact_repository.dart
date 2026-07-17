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
    return (response.data as List).map((j) => Contact.fromJson(j as Map<String, dynamic>)).toList();
  }

  Future<Contact> fetchById(String id) async {
    final response = await _dio.get('/contacts/$id');
    return Contact.fromJson(response.data as Map<String, dynamic>);
  }
}

final contactRepositoryProvider = Provider<ContactRepository>(
  (ref) => ContactRepository(ref.watch(dioClientProvider)),
);
