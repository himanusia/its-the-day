import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:its_the_day/data/groups_api.dart';
import 'package:its_the_day/platform/google_auth_gateway.dart';
import 'package:its_the_day/presentation/account_page.dart';
import 'package:its_the_day/presentation/itstheday_theme.dart';

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

Future<http.Response> _offline(http.BaseRequest _) async =>
    throw http.ClientException('offline fixture');

Future<http.Response> _health(http.BaseRequest _) async =>
    _json({'ok': true, 'auth': 'better_auth', 'google': 'configured'}, 200);

class _FakeGoogleAuth implements GoogleAccountAuthGateway {
  _FakeGoogleAuth();

  final bool configured = true;

  @override
  bool get isConfigured => configured;

  @override
  bool get isSupported => true;

  @override
  Future<GoogleAccountIdentity> signIn() async => const GoogleAccountIdentity(
    email: 'google@example.test',
    displayName: 'Google User',
    idToken: 'google-id-token',
  );
}

GroupsApi _api(_QueueClient client, {String? token}) => GroupsApi(
  baseUrl: 'https://api.example',
  tokens: _MemoryTokenStore()..token = token,
  client: client,
  browser: false,
);

class _MemoryTokenStore implements SessionTokenStore {
  String? token;

  @override
  Future<String?> read() async => token;

  @override
  Future<void> write(String value) async => token = value;

  @override
  Future<void> clear() async => token = null;
}

Widget _page(AccountPage page) =>
    MaterialApp(theme: itsthedayLightTheme(), home: page);

void main() {
  testWidgets('account page renders loading then signed-in state', (
    tester,
  ) async {
    final client = _QueueClient([
      _health,
      (_) => _json(
        {
          'state': 'online',
          'accountId': 'account-123',
          'email': 'signed-in@example.test',
        },
        200,
      ),
    ]);

    await tester.pumpWidget(
      _page(AccountPage(api: _api(client, token: 'existing-token'))),
    );
    expect(find.text('Loading account…'), findsOneWidget);

    await tester.pumpAndSettle();

    expect(find.text('Signed in'), findsOneWidget);
    expect(find.text('signed-in@example.test'), findsOneWidget);
    // The internal account id is never rendered or copyable.
    expect(find.text('account-123'), findsNothing);
    expect(find.textContaining('account-123'), findsNothing);
    expect(
      find.textContaining('Groups stay unavailable until Iteration 3.'),
      findsOneWidget,
    );
  });

  testWidgets('failed sign-in preserves fields and ignores repeated submits', (
    tester,
  ) async {
    final pending = Completer<http.Response>();
    final client = _QueueClient([_health, (_) => pending.future]);

    await tester.pumpWidget(_page(AccountPage(api: _api(client))));
    await tester.pumpAndSettle();
    expect(find.text('Sign in to sync'), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey('account-email')),
      'user@example.test',
    );
    await tester.enterText(
      find.byKey(const ValueKey('account-password')),
      'not-a-real-password',
    );
    await tester.tap(find.byType(FilledButton).first);
    await tester.pump();
    await tester.tap(find.byType(FilledButton).first);
    await tester.pump();

    expect(
      client.requests.where(
        (request) => request.url.path.endsWith('/sign-in/email'),
      ),
      hasLength(1),
    );
    expect(find.text('Connecting…'), findsOneWidget);

    pending.complete(await _json({'error': 'Invalid email or password'}, 401));
    await tester.pumpAndSettle();

    expect(find.text('Invalid email or password'), findsOneWidget);
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('account-email')))
          .controller!
          .text,
      'user@example.test',
    );
    expect(
      tester
          .widget<TextFormField>(find.byKey(const ValueKey('account-password')))
          .controller!
          .text,
      'not-a-real-password',
    );
  });

  testWidgets('signed-out account can sign out after a successful session', (
    tester,
  ) async {
    final client = _QueueClient([
      _health,
      (_) => _json(
        {
          'user': {'id': 'account-123'},
        },
        200,
        headers: {'set-auth-token': 'synthetic-native-token'},
      ),
      (_) => _json({'state': 'signed_out'}, 200),
    ]);
    final api = _api(client);

    await tester.pumpWidget(_page(AccountPage(api: api)));
    await tester.pumpAndSettle();
    await tester.enterText(
      find.byKey(const ValueKey('account-email')),
      'user@example.test',
    );
    await tester.enterText(
      find.byKey(const ValueKey('account-password')),
      'not-a-real-password',
    );
    await tester.tap(find.byType(FilledButton).first);
    await tester.pumpAndSettle();

    expect(find.text('Signed in'), findsOneWidget);
    await tester.tap(find.byType(FilledButton).first);
    await tester.pumpAndSettle();

    expect(find.text('Sign in to sync'), findsOneWidget);
    expect(
      client.requests.where(
        (request) => request.url.path.endsWith('/sign-out'),
      ),
      hasLength(1),
    );
  });

  testWidgets(
    'account page exposes setup and offline states without blocking local app',
    (tester) async {
      await tester.pumpWidget(
        _page(
          AccountPage(
            api: GroupsApi(
              baseUrl: '',
              tokens: _MemoryTokenStore(),
              client: _QueueClient([]),
              browser: false,
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Server setup needed'), findsOneWidget);

      final offlineClient = _QueueClient([_offline]);
      await tester.pumpWidget(
        _page(
          AccountPage(
            key: const ValueKey('offline-account'),
            api: _api(offlineClient, token: 'existing-token'),
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.text('Offline'), findsOneWidget);
      expect(
        find.textContaining('Your local tracker is still available.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('configured Google action exchanges an ID token for a session', (
    tester,
  ) async {
    final client = _QueueClient([
      _health,
      (_) => _json(
        {
          'user': {'id': 'account-google'},
        },
        200,
        headers: {'set-auth-token': 'better-auth-session'},
      ),
    ]);
    final api = _api(client);

    await tester.pumpWidget(
      _page(AccountPage(api: api, googleAuth: _FakeGoogleAuth())),
    );
    await tester.pumpAndSettle();

    await tester.ensureVisible(
      find.byKey(const ValueKey('continue-with-google')),
    );
    await tester.tap(find.byKey(const ValueKey('continue-with-google')));
    await tester.pumpAndSettle();

    expect(find.text('Signed in'), findsOneWidget);
    expect(
      client.requests.where(
        (request) => request.url.path.endsWith('/sign-in/social'),
      ),
      hasLength(1),
    );
  });

  testWidgets('server Google setup_needed state is shown and disables action', (
    tester,
  ) async {
    final client = _QueueClient([
      (_) => _json({
        'ok': true,
        'auth': 'better_auth',
        'google': 'setup_needed',
      }, 200),
    ]);
    final api = _api(client);

    await tester.pumpWidget(
      _page(AccountPage(api: api, googleAuth: _FakeGoogleAuth())),
    );
    await tester.pumpAndSettle();

    expect(find.textContaining('Google sign-in setup needed'), findsOneWidget);
    expect(
      tester
          .widget<OutlinedButton>(
            find.byKey(const ValueKey('continue-with-google')),
          )
          .onPressed,
      isNull,
    );
  });
}
