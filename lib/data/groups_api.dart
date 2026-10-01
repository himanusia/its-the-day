import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:http/http.dart' as http;

import 'session_http_client.dart';

abstract interface class SessionTokenStore {
  Future<String?> read();

  Future<void> write(String token);

  Future<void> clear();
}

class GroupsHealth {
  const GroupsHealth({required this.auth, required this.google});

  final String auth;
  final String google;

  bool get googleConfigured => google == 'configured';
}

/// Native sessions live outside ordinary app preferences and are never exposed
/// to widgets or logs.
class NativeSessionTokenStore implements SessionTokenStore {
  const NativeSessionTokenStore();

  static const _store = FlutterSecureStorage();
  static const _key = 'itstheday.session';

  @override
  Future<String?> read() => _store.read(key: _key);

  @override
  Future<void> write(String token) => _store.write(key: _key, value: token);

  @override
  Future<void> clear() => _store.delete(key: _key);
}

/// Same-origin browsers use Better Auth's HttpOnly cookie. Native clients use
/// Better Auth's bearer response header and secure storage.
class GroupsApi {
  GroupsApi({
    required this.baseUrl,
    required this.tokens,
    http.Client? client,
    bool? browser,
    Uri? pageOrigin,
  }) : _client = client ?? createSessionHttpClient(),
       _browser = browser ?? kIsWeb,
       _pageOrigin = pageOrigin ?? Uri.base;

  final String baseUrl;
  final SessionTokenStore tokens;
  final http.Client _client;
  final bool _browser;
  final Uri _pageOrigin;

  Uri? get _base {
    final configured = baseUrl.trim();
    final value = configured.isEmpty && _browser
        ? _pageOrigin.origin
        : configured;
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty ||
        uri.hasQuery ||
        uri.hasFragment ||
        (uri.path.isNotEmpty && uri.path != '/')) {
      return null;
    }

    final loopback = const [
      'localhost',
      '127.0.0.1',
      '::1',
      '10.0.2.2',
    ].contains(uri.host);
    final secureTransport = uri.scheme == 'https';
    final localDebugTransport = kDebugMode && uri.scheme == 'http' && loopback;
    if (!secureTransport && !localDebugTransport) return null;

    if (_browser && uri.origin != _pageOrigin.origin) return null;
    return uri;
  }

  String _sameOriginCallbackUrl() {
    final origin = _pageOrigin.origin;
    if (origin.isEmpty || origin == 'null') return _pageOrigin.toString();
    return '$origin/';
  }

  bool get configured => _base != null;

  static String operationKey() {
    final random = Random.secure();
    return List.generate(
      16,
      (_) => random.nextInt(256).toRadixString(16).padLeft(2, '0'),
    ).join();
  }

  void close() => _client.close();

  Future<Map<String, dynamic>> signIn(String email, String password) =>
      _authenticate('/api/auth/sign-in/email', {
        'email': email,
        'password': password,
      });

  /// Exchanges a native Google ID token at Better Auth's direct social-login
  /// endpoint. The Google token is never written to the session store; only
  /// Better Auth's bearer session is persisted by [_authenticate].
  Future<Map<String, dynamic>> signInWithGoogleIdToken(String idToken) {
    final token = idToken.trim();
    if (token.isEmpty) {
      throw const GroupsRequestError('Google did not return an ID token.');
    }
    return _authenticate('/api/auth/sign-in/social', {
      'provider': 'google',
      'idToken': {'token': token},
    });
  }

  /// Starts Better Auth's browser OAuth redirect flow.
  ///
  /// The web client deliberately does not use google_sign_in. Better Auth
  /// creates the provider URL and owns the callback/cookie session lifecycle.
  Future<String> beginGoogleWebSignIn() async {
    if (!_browser) {
      throw const GroupsRequestError(
        'Google web sign-in is only available in a browser.',
      );
    }
    final response = await _send(
      'POST',
      '/api/auth/sign-in/social',
      body: {
        'provider': 'google',
        'callbackURL': _sameOriginCallbackUrl(),
        'disableRedirect': true,
      },
      authenticated: false,
    );
    final body = _decode(response);
    final value = body['url'];
    if (value is! String) {
      throw const GroupsRequestError(
        'Server returned an invalid Google authorization URL.',
      );
    }
    final uri = Uri.tryParse(value);
    if (uri == null ||
        uri.host.isEmpty ||
        (uri.scheme != 'https' && uri.scheme != 'http')) {
      throw const GroupsRequestError(
        'Server returned an invalid Google authorization URL.',
      );
    }
    return value;
  }

  Future<Map<String, dynamic>> signUp(
    String name,
    String email,
    String password,
  ) => _authenticate('/api/auth/sign-up/email', {
    'name': name,
    'email': email,
    'password': password,
  });

  Future<Map<String, dynamic>> _authenticate(
    String path,
    Map<String, dynamic> body,
  ) async {
    final response = await _send(
      'POST',
      path,
      body: body,
      authenticated: false,
    );
    final result = _decode(response, authenticationRequest: true);
    if (!_browser) {
      final token = response.headers['set-auth-token'];
      if (token == null || token.isEmpty) {
        throw const GroupsRequestError(
          'Sign-in did not return a native session.',
        );
      }
      await tokens.write(token);
    }
    return result;
  }

  Future<void> signOut() async {
    try {
      await request('POST', '/api/auth/sign-out', body: {});
    } finally {
      // A local token must not remain usable by the app after the user asks to
      // sign out, even when a later network read reports an error.
      if (!_browser) await tokens.clear();
    }
  }

  Future<GroupsHealth> health() async {
    final body = _decode(
      await _send('GET', '/health', authenticated: false),
    );
    return GroupsHealth(
      auth: body['auth']?.toString() ?? 'unknown',
      google: body['google']?.toString() ?? 'setup_needed',
    );
  }

  Future<Map<String, dynamic>> request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? idempotencyKey,
  }) async => _decode(
    await _send(method, path, body: body, idempotencyKey: idempotencyKey),
  );

  Future<Map<String, dynamic>> mutate(
    String method,
    String path, {
    Map<String, dynamic> body = const {},
    String? operationId,
  }) => request(
    method,
    path,
    body: body,
    idempotencyKey: operationId ?? operationKey(),
  );

  Future<http.Response> _send(
    String method,
    String path, {
    Map<String, dynamic>? body,
    String? idempotencyKey,
    bool authenticated = true,
  }) async {
    final base = _base;
    if (base == null) throw const GroupsSetupNeeded();
    final validPublicPath = path == '/health';
    if ((!path.startsWith('/api/') && !validPublicPath) ||
        path.startsWith('//')) {
      throw ArgumentError('Invalid API path');
    }

    final headers = <String, String>{'Content-Type': 'application/json'};
    if (authenticated && !_browser) {
      final token = await tokens.read();
      if (token == null || token.isEmpty) throw const GroupsSignedOut();
      headers['Authorization'] = 'Bearer $token';
    }
    if (idempotencyKey != null) headers['Idempotency-Key'] = idempotencyKey;

    try {
      final request = http.Request(method, base.resolve(path))
        ..headers.addAll(headers)
        ..body = body == null ? '' : jsonEncode(body);
      final response = await http.Response.fromStream(
        await _client.send(request),
      ).timeout(const Duration(seconds: 20));
      return response;
    } on TimeoutException {
      throw const GroupsOffline(
        'Request timed out. Your local tracker is still available.',
      );
    } on http.ClientException {
      throw const GroupsOffline(
        'Could not reach the server. Your local tracker is still available.',
      );
    }
  }

  Map<String, dynamic> _decode(
    http.Response response, {
    bool authenticationRequest = false,
  }) {
    Map<String, dynamic> body;
    try {
      final raw = response.body.trim();
      if (raw.isEmpty) {
        body = <String, dynamic>{};
      } else {
        final decoded = jsonDecode(raw);
        if (decoded is! Map) throw const FormatException();
        body = Map<String, dynamic>.from(decoded);
      }
    } on FormatException {
      throw const GroupsRequestError('Server returned an invalid response.');
    } on Object {
      throw const GroupsRequestError('Server returned an invalid response.');
    }

    if (response.statusCode == 401) {
      if (authenticationRequest) {
        throw GroupsRequestError(
          body['message']?.toString() ??
              body['error']?.toString() ??
              'Invalid email or password.',
        );
      }
      throw const GroupsSignedOut();
    }
    if (body['state'] == 'setup_needed') throw const GroupsSetupNeeded();
    if (response.statusCode == 403) {
      throw GroupsPermissionDenied(
        body['error']?.toString() ?? 'Access denied',
      );
    }
    if (response.statusCode >= 400) {
      throw GroupsRequestError(
        body['message']?.toString() ??
            body['error']?.toString() ??
            'Server error. Try again.',
      );
    }
    return body;
  }
}

class GroupsSetupNeeded implements Exception {
  const GroupsSetupNeeded();
}

class GroupsSignedOut implements Exception {
  const GroupsSignedOut();
}

class GroupsPermissionDenied implements Exception {
  const GroupsPermissionDenied(this.message);

  final String message;

  @override
  String toString() => message;
}

class GroupsRequestError implements Exception {
  const GroupsRequestError(this.message);

  final String message;

  @override
  String toString() => message;
}

class GroupsOffline implements Exception {
  const GroupsOffline(this.message);

  final String message;

  @override
  String toString() => message;
}
