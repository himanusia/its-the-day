import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:its_the_day/data/groups_api.dart';
import 'package:its_the_day/presentation/group_members_page.dart';
import 'package:its_the_day/presentation/groups_page.dart';
import 'package:its_the_day/presentation/itstheday_theme.dart';

class _MemoryTokenStore implements SessionTokenStore {
  String? token = 'session-token';

  @override
  Future<String?> read() async => token;

  @override
  Future<void> write(String value) async => token = value;

  @override
  Future<void> clear() async => token = null;
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

Future<http.Response> _offline(http.BaseRequest _) async =>
    throw http.ClientException('offline fixture');

GroupsApi _api(_QueueClient client) => GroupsApi(
  baseUrl: 'https://api.example',
  tokens: _MemoryTokenStore(),
  client: client,
  browser: false,
);

Widget _page(GroupsApi api, {Key? key}) => MaterialApp(
  theme: itsthedayLightTheme(),
  home: GroupsPage(key: key, api: api),
);

Map<String, Object?> _group({
  String id = 'group-1',
  String name = 'Study circle',
  String role = 'owner',
  int memberCount = 2,
  String joinCode = 'JOIN1234',
}) => {
  'id': id,
  'name': name,
  'joinCode': joinCode,
  'role': role,
  'memberCount': memberCount,
  'createdAt': '2026-10-01T10:00:00.000Z',
};

void main() {
  testWidgets('lists groups, refreshes, and opens members without raw ids', (
    tester,
  ) async {
    final client = _QueueClient([
      (_) => _json({
        'groups': [_group()],
        'state': 'online',
      }, 200),
      (_) => _json({
        'members': [
          {
            'accountId': 'owner-account-id',
            'role': 'owner',
            'active': 1,
            'joinedAt': '2026-10-01T10:00:00.000Z',
          },
          {
            'accountId': 'member-account-id',
            'role': 'member',
            'active': 1,
            'joinedAt': '2026-10-01T11:00:00.000Z',
          },
        ],
        'state': 'online',
      }, 200),
      (_) => _json({
        'members': [
          {
            'accountId': 'owner-account-id',
            'role': 'owner',
            'active': 1,
            'joinedAt': '2026-10-01T10:00:00.000Z',
          },
          {
            'accountId': 'member-account-id',
            'role': 'member',
            'active': 1,
            'joinedAt': '2026-10-01T11:00:00.000Z',
          },
        ],
        'state': 'online',
      }, 200),
    ]);

    await tester.pumpWidget(_page(_api(client)));
    await tester.pumpAndSettle();

    expect(find.text('Study circle'), findsOneWidget);
    expect(find.textContaining('2 members'), findsOneWidget);
    expect(find.text('owner-account-id'), findsNothing);
    expect(find.textContaining('owner-account-id'), findsNothing);

    await tester.tap(find.text('Study circle'));
    await tester.pumpAndSettle();

    expect(find.byType(GroupMembersPage), findsOneWidget);
    expect(find.text('Members'), findsOneWidget);
    expect(find.text('Owner'), findsOneWidget);
    expect(find.text('Member'), findsOneWidget);
    expect(find.text('owner-account-id'), findsNothing);
    expect(find.text('member-account-id'), findsNothing);

    await tester.tap(find.byTooltip('Refresh members'));
    await tester.pumpAndSettle();
    expect(find.text('Members'), findsOneWidget);
    expect(client.requests[2].url.path, '/api/groups/group-1/members');
  });

  testWidgets('creates a group and disables duplicate submit taps', (
    tester,
  ) async {
    final pending = Completer<http.Response>();
    final client = _QueueClient([
      (_) => _json({'groups': <Object?>[], 'state': 'online'}, 200),
      (_) => pending.future,
      (_) => _json({
        'groups': [
          _group(
            id: 'group-2',
            name: 'New circle',
            memberCount: 1,
            joinCode: 'CREATE12',
          ),
        ],
        'state': 'online',
      }, 200),
    ]);

    await tester.pumpWidget(_page(_api(client)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('create-group-action')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('group-name-field')),
      'New circle',
    );
    await tester.tap(find.byKey(const ValueKey('create-group-submit')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('create-group-submit')));
    await tester.pump();

    expect(find.text('Creating…'), findsOneWidget);
    expect(
      client.requests.where((request) => request.url.path == '/api/groups'),
      hasLength(2),
    );
    final createRequest = client.requests[1] as http.Request;
    expect(createRequest.headers['idempotency-key'], isNotEmpty);

    pending.complete(
      await _json({
        'id': 'group-2',
        'name': 'New circle',
        'joinCode': 'CREATE12',
        'role': 'owner',
        'memberCount': 1,
        'state': 'online',
      }, 201),
    );
    await tester.pumpAndSettle();

    expect(find.text('New circle'), findsOneWidget);
    expect(find.text('CREATE12'), findsOneWidget);
  });

  testWidgets('joins a group with an invite code and reloads membership', (
    tester,
  ) async {
    final client = _QueueClient([
      (_) => _json({'groups': <Object?>[], 'state': 'online'}, 200),
      (_) => _json({
        'id': 'group-1',
        'name': 'Study circle',
        'role': 'member',
        'state': 'online',
      }, 200),
      (_) => _json({
        'groups': [_group(role: 'member')],
        'state': 'online',
      }, 200),
    ]);

    await tester.pumpWidget(_page(_api(client)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('join-group-action')));
    await tester.pumpAndSettle();

    await tester.enterText(
      find.byKey(const ValueKey('group-code-field')),
      'JOIN1234',
    );
    await tester.tap(find.byKey(const ValueKey('join-group-submit')));
    await tester.pumpAndSettle();

    final joinRequest = client.requests[1] as http.Request;
    expect(joinRequest.url.path, '/api/groups/join');
    expect(joinRequest.headers['idempotency-key'], isNotEmpty);
    expect(jsonDecode(joinRequest.body), {'code': 'JOIN1234'});
    expect(find.text('Study circle'), findsOneWidget);
    expect(find.textContaining('Member'), findsOneWidget);
  });

  testWidgets('shows signed-out, setup, offline, and forbidden retry states', (
    tester,
  ) async {
    await tester.pumpWidget(
      _page(
        _api(
          _QueueClient([
            (_) => _json({'error': 'unauthorized'}, 401),
          ]),
        ),
        key: const ValueKey('signed-out'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Sign in to use groups'), findsOneWidget);
    expect(find.text('Open account'), findsOneWidget);

    await tester.pumpWidget(
      _page(
        _api(
          _QueueClient([
            (_) => _json({'state': 'setup_needed'}, 503),
          ]),
        ),
        key: const ValueKey('setup'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Server setup needed'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);

    await tester.pumpWidget(
      _page(_api(_QueueClient([_offline])), key: const ValueKey('offline')),
    );
    await tester.pumpAndSettle();
    expect(find.text('Offline'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);

    await tester.pumpWidget(
      _page(
        _api(
          _QueueClient([
            (_) => _json({'error': 'forbidden'}, 403),
          ]),
        ),
        key: const ValueKey('forbidden'),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Access denied'), findsOneWidget);
    expect(find.text('Try again'), findsOneWidget);
  });
}
