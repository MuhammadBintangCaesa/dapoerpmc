import 'dart:convert';

import 'package:http/http.dart' as http;

class BackendApi {
  BackendApi._();
  static final BackendApi instance = BackendApi._();

  String baseUrl = const String.fromEnvironment(
    'API_BASE_URL',
    defaultValue: 'http://192.168.1.9:8765',
  );
  String? token;
  Map<String, dynamic>? account;
  final http.Client _client = http.Client();

  Uri _uri(String path, [Map<String, String>? query]) => Uri.parse(
    '${baseUrl.replaceFirst(RegExp(r'/$'), '')}$path',
  ).replace(queryParameters: query);

  Future<dynamic> _request(
    String method,
    String path, {
    Map<String, String>? query,
    Map<String, dynamic>? body,
    bool auth = true,
  }) async {
    final headers = <String, String>{'Content-Type': 'application/json'};
    if (auth && token != null) headers['Authorization'] = 'Bearer $token';
    try {
      final uri = _uri(path, query);
      late http.Response response;
      switch (method) {
        case 'GET':
          response = await _client.get(uri, headers: headers).timeout(const Duration(seconds: 10));
          break;
        case 'POST':
          response = await _client.post(
            uri,
            headers: headers,
            body: jsonEncode(body ?? {}),
          ).timeout(const Duration(seconds: 10));
          break;
        case 'PUT':
          response = await _client.put(
            uri,
            headers: headers,
            body: jsonEncode(body ?? {}),
          ).timeout(const Duration(seconds: 10));
          break;
        case 'PATCH':
          response = await _client.patch(
            uri,
            headers: headers,
            body: jsonEncode(body ?? {}),
          ).timeout(const Duration(seconds: 10));
          break;
        case 'DELETE':
          response = await _client.delete(uri, headers: headers).timeout(const Duration(seconds: 10));
          break;
        default:
          throw BackendException('Metode HTTP tidak didukung');
      }
      final decoded = response.body.isEmpty ? null : jsonDecode(response.body);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final message = decoded is Map ? decoded['error']?.toString() : null;
        throw BackendException(
          message ?? 'Backend mengembalikan ${response.statusCode}',
        );
      }
      return decoded;
    } on BackendException {
      rethrow;
    } catch (error) {
      throw BackendException('Tidak dapat terhubung ke backend: $error');
    }
  }

  Future<Map<String, dynamic>> login(String email, String password) async {
    final result = await _request(
      'POST',
      '/api/auth/login',
      auth: false,
      body: {'email': email, 'password': password},
    );
    token = result['token'] as String;
    account = Map<String, dynamic>.from(result['account'] as Map);
    return account!;
  }

  Future<void> logout() async {
    if (token != null) await _request('POST', '/api/auth/logout');
    token = null;
    account = null;
  }

  Future<Map<String, dynamic>> currentAccount() async {
    final result = await _request('GET', '/api/auth/me');
    account = Map<String, dynamic>.from(result as Map);
    return account!;
  }

  Future<List<Map<String, dynamic>>> accounts({bool onlineOnly = false}) async {
    final result = await _request(
      'GET',
      '/api/accounts',
      query: {'online_only': '$onlineOnly'},
    );
    return (result as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  Future<void> createAccount(Map<String, dynamic> data) async =>
      _request('POST', '/api/accounts', body: data);
  Future<void> updateAccount(String id, Map<String, dynamic> data) async =>
      _request('PATCH', '/api/accounts/$id', body: data);
  Future<void> resetAccountPassword(String id, String password) async =>
      _request(
        'POST',
        '/api/accounts/$id/reset-password',
        body: {'password': password},
      );
  Future<void> forceLogout(String id) async =>
      _request('POST', '/api/accounts/$id/logout');

  Future<List<Map<String, dynamic>>> transactions() async {
    final result = await _request('GET', '/api/transactions');
    return (result as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  Future<String> createTransaction(Map<String, dynamic> data) async =>
      (await _request('POST', '/api/transactions', body: data))['id'] as String;
  Future<void> updateTransaction(String id, Map<String, dynamic> data) async =>
      _request('PATCH', '/api/transactions/$id', body: data);
  Future<void> verifyTransaction(
    String id, {
    String status = 'verified',
  }) async => _request(
    'PATCH',
    '/api/transactions/$id/verify',
    body: {'status': status},
  );
  Future<void> deleteTransaction(String id) async =>
      _request('DELETE', '/api/transactions/$id');

  Future<List<Map<String, dynamic>>> calendarEvents(
    DateTime from,
    DateTime to,
  ) async {
    final result = await _request(
      'GET',
      '/api/calendar/events',
      query: {'from': _date(from), 'to': _date(to)},
    );
    return (result as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  Future<String> createCalendarEvent(Map<String, dynamic> data) async =>
      (await _request('POST', '/api/calendar/events', body: data))['id']
          as String;
  Future<void> updateCalendarEvent(
    String id,
    Map<String, dynamic> data,
  ) async => _request('PATCH', '/api/calendar/events/$id', body: data);
  Future<void> deleteCalendarEvent(String id) async =>
      _request('DELETE', '/api/calendar/events/$id');

  Future<List<Map<String, dynamic>>> activityLog() async {
    final result = await _request('GET', '/api/activity');
    return (result as List)
        .map((item) => Map<String, dynamic>.from(item as Map))
        .toList();
  }

  Future<Map<String, dynamic>> whatsappSettings() async =>
      Map<String, dynamic>.from(
        await _request('GET', '/api/integrations/whatsapp') as Map,
      );
  Future<void> saveWhatsappSettings({
    required String phoneNumberId,
    required String ownerPhone,
    required String verifyToken,
  }) async => _request(
    'PUT',
    '/api/integrations/whatsapp',
    body: {
      'phoneNumberId': phoneNumberId,
      'ownerPhone': ownerPhone,
      'verifyToken': verifyToken,
    },
  );

  String _date(DateTime value) =>
      '${value.year.toString().padLeft(4, '0')}-${value.month.toString().padLeft(2, '0')}-${value.day.toString().padLeft(2, '0')}';
}

class BackendException implements Exception {
  const BackendException(this.message);
  final String message;
  @override
  String toString() => message;
}
