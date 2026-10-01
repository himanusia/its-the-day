import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:its_the_day/data/groups_api.dart';

class _MemoryTokenStore implements SessionTokenStore {
  String? token;
  int writes = 0;
  int clears = 0;

  @override
  Future<String?> read() async => token;

  @override
  Future<void> write(String value) async {
    writes++;
    token = value;
  }

  @override
  Future<void> clear() async {
    clears++;
    token = null;
  }
}

class _QueueClient extends http.BaseClient {
  _QueueClient(this._responses);

  final List<Future<http.Response> Function(http.BaseRequest)> _responses;
  final requests = <http.BaseRequest>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request);
    final response = await _responses.removeAt(0)(request);
    return http.StreamedResponse(
      Stream.value(response.bodyBytes),
      response.statusCode,
      headers: response.headers,
      reasonPhrase: response.reasonPhrase,
      request: request,
    );
  }
}

Future<http.Response> _json(
  Map<String, Object?> body,
  int status, {
  Map<String, String> headers = const {},
}) async => http.Response(jsonEncode(body), status, headers: headers);

void main() {
  test('health preserves the server-owned Google provider state', () async {
    final client = _QueueClient([
      (_) => _json(
        {'ok': true, 'auth': 'better_auth', 'google': 'setup_needed'},
        200,
      ),
    ]);
    final api = GroupsApi(
      baseUrl: 'https://api.example',
      tokens: _MemoryTokenStore(),
      client: client,
      browser: false,
    );

    final health = await api.health();

    expect(health.auth, 'better_auth');
    expect(health.google, 'setup_needed');
    expect(client.requests.single.url.path, '/health');
    expect(client.requests.single.headers.containsKey('authorization'), isFalse);
  });

  test('native Google ID token uses Better Auth social sign-in and stores bearer',
      () async {
    final tokens = _MemoryTokenStore();
    final client = _QueueClient([
      (_) => _json(
        {
          'redirect': false,
          'token': 'better-auth-session',
          'user': {'id': 'account-google'},
        },
        200,
        headers: {'set-auth-token': 'better-auth-session'},
      ),
    ]);
    final api = GroupsApi(
      baseUrl: 'https://api.example',
      tokens: tokens,
      client: client,
      browser: false,
    );

    final result = await api.signInWithGoogleIdToken('google-id-token');

    expect(result['user'], {'id': 'account-google'});
    expect(tokens.token, 'better-auth-session');
    final request = client.requests.single as http.Request;
    expect(jsonDecode(request.body), {
      'provider': 'google',
      'idToken': {'token': 'google-id-token'},
    });
  });

  test('web Google sign-in asks Better Auth for same-origin redirect', () async {
    final client = _QueueClient([
      (_) => _json(
        {
          'url': 'https://accounts.google.com/o/oauth2/v2/auth?state=opaque',
          'redirect': false,
        },
        200,
      ),
    ]);
    final api = GroupsApi(
      baseUrl: '',
      tokens: _MemoryTokenStore(),
      client: client,
      browser: true,
      pageOrigin: Uri.parse('https://app.example/'),
    );

    final url = await api.beginGoogleWebSignIn();

    expect(url, startsWith('https://accounts.google.com/'));
    final request = client.requests.single as http.Request;
    expect(jsonDecode(request.body), {
      'provider': 'google',
      'callbackURL': 'https://app.example/',
      'disableRedirect': true,
    });
    expect(request.headers.containsKey('authorization'), isFalse);
  });

  test(
    'native auth persists bearer token and clears it after logout',
    () async {
      final tokens = _MemoryTokenStore();
      final client = _QueueClient([
        (_) => _json(
          {
            'user': {'id': 'account-1', 'email': 'synthetic@example.test'},
          },
          200,
          headers: {'set-auth-token': 'synthetic-native-token'},
        ),
        (_) => _json(
          {
            'state': 'online',
            'accountId': 'account-1',
            'email': 'synthetic@example.test',
          },
          200,
        ),
        (_) => _json({'state': 'signed_out'}, 200),
      ]);
      final api = GroupsApi(
        baseUrl: 'https://api.example',
        tokens: tokens,
        client: client,
        browser: false,
      );

      await api.signUp(
        'Synthetic User',
        'synthetic@example.test',
        'not-a-real-password',
      );
      expect(tokens.token, 'synthetic-native-token');
      expect(tokens.writes, 1);
      expect(client.requests[0].headers.containsKey('authorization'), isFalse);

      await api.request('GET', '/api/session');
      expect(
        client.requests[1].headers['authorization'],
        'Bearer synthetic-native-token',
      );

      await api.signOut();
      expect(
        client.requests[2].headers['authorization'],
        'Bearer synthetic-native-token',
      );
      expect(tokens.token, isNull);
      expect(tokens.clears, 1);
    },
  );

  test('web auth sends no bearer and uses the exact page origin', () async {
    final tokens = _MemoryTokenStore()..token = 'must-not-leak-to-web';
    final client = _QueueClient([
      (_) => _json(
        {
          'state': 'online',
          'accountId': 'cookie-account',
          'email': 'cookie@example.test',
        },
        200,
      ),
    ]);
    final api = GroupsApi(
      baseUrl: '',
      tokens: tokens,
      client: client,
      browser: true,
      pageOrigin: Uri.parse('https://app.example/'),
    );

    await api.request('GET', '/api/session');

    expect(client.requests.single.url.origin, 'https://app.example');
    expect(
      client.requests.single.headers.containsKey('authorization'),
      isFalse,
    );
    expect(tokens.token, 'must-not-leak-to-web');
  });

  test(
    'web rejects a cross-origin API instead of sending credentials',
    () async {
      final client = _QueueClient([]);
      final api = GroupsApi(
        baseUrl: 'https://api.example',
        tokens: _MemoryTokenStore(),
        client: client,
        browser: true,
        pageOrigin: Uri.parse('https://app.example/'),
      );

      expect(
        () => api.request('GET', '/api/session'),
        throwsA(isA<GroupsSetupNeeded>()),
      );
      expect(client.requests, isEmpty);
    },
  );

  test(
    'auth failure does not clear the token store until logout succeeds',
    () async {
      final tokens = _MemoryTokenStore()..token = 'still-valid-locally';
      final client = _QueueClient([
        (_) => _json({'error': 'Invalid email or password'}, 401),
      ]);
      final api = GroupsApi(
        baseUrl: 'https://api.example',
        tokens: tokens,
        client: client,
        browser: false,
      );

      await expectLater(
        api.signIn('synthetic@example.test', 'not-a-real-password'),
        throwsA(isA<GroupsRequestError>()),
      );
      expect(tokens.token, 'still-valid-locally');
    },
  );
}
