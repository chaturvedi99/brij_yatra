import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../config/app_flags.dart';
import '../config/env.dart';
import '../providers/session_provider.dart';

class ApiException implements Exception {
  ApiException(this.statusCode, this.body);
  final int statusCode;
  final String body;

  @override
  String toString() => 'ApiException($statusCode): $body';
}

typedef TokenProvider = Future<String?> Function();

class ApiClient {
  ApiClient({required this.getToken});

  final TokenProvider getToken;

  Uri _uri(String path, [Map<String, String>? query]) {
    final base = Env.apiBaseUrl.replaceAll(RegExp(r'/$'), '');
    final p = path.startsWith('/') ? path : '/$path';
    return Uri.parse('$base$p').replace(queryParameters: query);
  }

  Future<Map<String, String>> _headers({bool jsonBody = false}) async {
    final h = <String, String>{
      if (jsonBody) 'Content-Type': 'application/json',
    };
    final t = await getToken();
    if (t != null && t.isNotEmpty) {
      h['Authorization'] = 'Bearer $t';
    }
    return h;
  }

  Future<dynamic> getJson(String path) async {
    final res = await http.get(_uri(path), headers: await _headers());
    return _decode(res);
  }

  Future<dynamic> postJson(String path, Object? body) async {
    final res = await http.post(
      _uri(path),
      headers: await _headers(jsonBody: true),
      body: body == null ? null : jsonEncode(body),
    );
    return _decode(res);
  }

  Future<dynamic> patchJson(String path, Object? body) async {
    final res = await http.patch(
      _uri(path),
      headers: await _headers(jsonBody: true),
      body: body == null ? null : jsonEncode(body),
    );
    return _decode(res);
  }

  dynamic _decode(http.Response res) {
    if (res.statusCode >= 200 && res.statusCode < 300) {
      if (res.body.isEmpty) return null;
      return jsonDecode(res.body);
    }
    throw ApiException(res.statusCode, res.body);
  }
}

final apiClientProvider = Provider<ApiClient>((ref) {
  return ApiClient(
    getToken: () async {
      if (AppFlags.useFirebaseAuth) {
        final u = FirebaseAuth.instance.currentUser;
        if (u == null) return null;
        return u.getIdToken();
      }
      return ref.read(sessionProvider).token;
    },
  );
});
