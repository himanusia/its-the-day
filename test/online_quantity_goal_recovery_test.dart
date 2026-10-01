import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:its_the_day/data/groups_api.dart';
import 'package:its_the_day/presentation/itstheday_theme.dart';
import 'package:its_the_day/presentation/online_quantity_goal_page.dart';

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

Future<http.Response> _json(Map<String, Object?> body, int status) async =>
    http.Response(jsonEncode(body), status);

GroupsApi _api(_QueueClient client) => GroupsApi(
  baseUrl: 'https://api.example',
  tokens: _MemoryTokenStore(),
  client: client,
  browser: false,
);

Map<String, Object?> _goal({String title = 'Read together'}) => {
  'id': 'goal-1',
  'ownerId': 'owner-account-id',
  'groupId': 'group-1',
  'visibility': 'shared',
  'kind': 'quantity',
  'targetMode': 'shared_total',
  'title': title,
  'unit': 'pages',
  'target': 10,
  'deadline': '2026-12-31',
  'createdAt': '2026-10-01T10:00:00.000Z',
};

Map<String, Object?> _detail({
  int total = 4,
  String note = 'Morning reading',
  String title = 'Read together',
}) => {
  'goal': _goal(title: title),
  'progress': [
    {
      'id': 'result-1',
      'goalId': 'goal-1',
      'actorId': 'member-account-id',
      'amount': total,
      'note': note,
      'occurredAt': '2026-10-02T09:30:00.000Z',
      'createdAt': '2026-10-02T09:30:00.000Z',
    },
  ],
  'total': total,
  'state': 'online',
  'serverTime': '2026-10-02T09:30:01.000Z',
};

Widget _page(GroupsApi api, {Key? key}) => MaterialApp(
  theme: itsthedayLightTheme(),
  home: OnlineQuantityGoalPage(key: key, api: api, goalId: 'goal-1'),
);

void main() {
  testWidgets(
    'revoked add canceled invalidates old detail and shows a human revoked state',
    (tester) async {
      final client = _QueueClient([
        (_) => _json(_detail(), 200),
        (_) => _json({'error': 'not_found'}, 404),
        (_) => _json({'error': 'not_found'}, 404),
      ]);

      await tester.pumpWidget(_page(_api(client)));
      await tester.pumpAndSettle();
      expect(find.text('4 / 10 pages'), findsOneWidget);
      expect(find.textContaining('Morning reading'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('online-add-result-action')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('online-result-submit')));
      await tester.pumpAndSettle();

      expect(
        find.text('This shared goal is no longer available to this account.'),
        findsAtLeastNWidgets(1),
      );
      expect(find.text('not_found'), findsNothing);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('Group access revoked'), findsOneWidget);
      expect(find.text('4 / 10 pages'), findsNothing);
      expect(find.textContaining('Morning reading'), findsNothing);
    },
  );

  testWidgets(
    'account recovery from add refreshes the parent even when the dialog is canceled',
    (tester) async {
      final client = _QueueClient([
        (_) => _json(_detail(note: 'Old account result'), 200),
        (_) => _json({'error': 'unauthorized'}, 401),
        (_) => _json({'auth': 'better_auth', 'google': 'setup_needed'}, 200),
        (_) => _json({'state': 'online', 'email': 'new@example.test'}, 200),
        (_) => _json(_detail(total: 8, note: 'New account result'), 200),
      ]);

      await tester.pumpWidget(_page(_api(client)));
      await tester.pumpAndSettle();
      expect(find.textContaining('Old account result'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('online-add-result-action')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('online-result-submit')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('online-result-reauth')));
      await tester.pumpAndSettle();
      expect(find.text('Signed in'), findsOneWidget);

      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.text('8 / 10 pages'), findsOneWidget);
      expect(find.textContaining('New account result'), findsOneWidget);
      expect(find.textContaining('Old account result'), findsNothing);
    },
  );

  testWidgets(
    'account recovery preserves the add draft and stable operation key',
    (tester) async {
      final client = _QueueClient([
        (_) => _json(_detail(), 200),
        (_) => _json({'error': 'unauthorized'}, 401),
        (_) => _json({'auth': 'better_auth', 'google': 'setup_needed'}, 200),
        (_) => _json({'state': 'online', 'email': 'new@example.test'}, 200),
        (_) => _json(_detail(total: 4, note: 'After recovery refresh'), 200),
        (_) => _json({
          'id': 'result-2',
          'goalId': 'goal-1',
          'actorId': 'member-account-id',
          'amount': 2,
          'note': 'Keep this draft',
          'occurredAt': '2026-10-02T18:00:00.000Z',
          'createdAt': '2026-10-02T18:00:00.000Z',
          'state': 'online',
        }, 201),
        (_) => _json(_detail(total: 6, note: 'Keep this draft'), 200),
      ]);

      await tester.pumpWidget(_page(_api(client)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('online-add-result-action')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('online-result-amount-field')),
        '2',
      );
      await tester.enterText(
        find.byKey(const ValueKey('online-result-note-field')),
        'Keep this draft',
      );
      await tester.tap(find.byKey(const ValueKey('online-result-submit')));
      await tester.pumpAndSettle();

      final firstPost = client.requests.singleWhere(
        (request) => request.url.path == '/api/goals/goal-1/progress',
      ) as http.Request;
      final operationKey = firstPost.headers['idempotency-key'];
      expect(operationKey, isNotEmpty);

      await tester.tap(find.byKey(const ValueKey('online-result-reauth')));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('online-result-amount-field')),
            )
            .controller!
            .text,
        '2',
      );
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('online-result-note-field')),
            )
            .controller!
            .text,
        'Keep this draft',
      );

      await tester.tap(find.byKey(const ValueKey('online-result-submit')));
      await tester.pumpAndSettle();

      final progressPosts = client.requests
          .where((request) => request.url.path == '/api/goals/goal-1/progress')
          .cast<http.Request>()
          .toList();
      expect(progressPosts, hasLength(2));
      expect(progressPosts[1].headers['idempotency-key'], operationKey);
      expect(jsonDecode(progressPosts[1].body), {
        'amount': 2,
        'note': 'Keep this draft',
      });
      expect(find.text('6 / 10 pages'), findsOneWidget);
    },
  );

  testWidgets('add dialog does not claim a local date before submit', (
    tester,
  ) async {
    final client = _QueueClient([(_) => _json(_detail(), 200)]);

    await tester.pumpWidget(_page(_api(client)));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey('online-add-result-action')));
    await tester.pumpAndSettle();

    expect(find.text('Assigned by server on submit'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('online-result-date-field')),
        matching: find.text('Assigned by server on submit'),
      ),
      findsOneWidget,
    );
  });
}
