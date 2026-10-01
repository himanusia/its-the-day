import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:its_the_day/data/group_membership.dart';
import 'package:its_the_day/data/groups_api.dart';
import 'package:its_the_day/presentation/group_goals_page.dart';
import 'package:its_the_day/presentation/group_members_page.dart';
import 'package:its_the_day/presentation/itstheday_theme.dart';
import 'package:its_the_day/presentation/playful_widgets.dart';

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

Future<http.Response> _offline(http.BaseRequest _) async =>
    throw http.ClientException('offline fixture');

GroupsApi _api(_QueueClient client) => GroupsApi(
  baseUrl: 'https://api.example',
  tokens: _MemoryTokenStore(),
  client: client,
  browser: false,
);

const _group = GroupSummary(
  id: 'group-1',
  name: 'Study circle',
  role: GroupRole.owner,
  memberCount: 2,
  joinCode: 'JOIN1234',
);

Map<String, Object?> _goal({
  String id = 'goal-1',
  String groupId = 'group-1',
  String visibility = 'shared',
  String kind = 'quantity',
  String targetMode = 'shared_total',
  String title = 'Read together',
  int target = 10,
  String unit = 'pages',
  String deadline = '2026-12-31',
}) => {
  'id': id,
  'ownerId': 'owner-account-id',
  'groupId': groupId,
  'visibility': visibility,
  'kind': kind,
  'targetMode': targetMode,
  'title': title,
  'unit': unit,
  'target': target,
  'deadline': deadline,
  'createdAt': '2026-10-01T10:00:00.000Z',
};

Map<String, Object?> _detail({int total = 4}) => {
  'goal': _goal(),
  'progress': [
    {
      'id': 'result-1',
      'goalId': 'goal-1',
      'actorId': 'member-account-id',
      'amount': total,
      'note': 'Morning reading',
      'occurredAt': '2026-10-02T09:30:00.000Z',
      'createdAt': '2026-10-02T09:30:00.000Z',
    },
  ],
  'total': total,
  'state': 'online',
  'serverTime': '2026-10-02T09:30:01.000Z',
};

Widget _groupGoalsPage(GroupsApi api, {Key? key}) => MaterialApp(
  theme: itsthedayLightTheme(),
  home: GroupGoalsPage(key: key, api: api, group: _group),
);

void main() {
  testWidgets('group members links to filtered shared quantity goals', (
    tester,
  ) async {
    final client = _QueueClient([
      (_) => _json({
        'members': [
          {
            'accountId': 'owner-account-id',
            'role': 'owner',
            'active': 1,
            'joinedAt': '2026-10-01T10:00:00.000Z',
          },
        ],
        'state': 'online',
      }, 200),
      (_) => _json({
        'goals': [
          _goal(),
          _goal(
            id: 'private-goal',
            visibility: 'private',
            groupId: '',
            title: 'Private goal',
          ),
          _goal(id: 'other-goal', groupId: 'group-2', title: 'Other group'),
          _goal(
            id: 'checklist-goal',
            kind: 'checklist',
            unit: '',
            title: 'Checklist goal',
          ),
        ],
        'state': 'online',
      }, 200),
    ]);

    await tester.pumpWidget(
      MaterialApp(
        theme: itsthedayLightTheme(),
        home: GroupMembersPage(api: _api(client), group: _group),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byKey(const ValueKey('group-goals-action')), findsOneWidget);
    expect(find.text('owner-account-id'), findsNothing);
    await tester.tap(find.byKey(const ValueKey('group-goals-action')));
    await tester.pumpAndSettle();

    expect(find.byType(GroupGoalsPage), findsOneWidget);
    expect(find.text('Read together'), findsOneWidget);
    expect(find.text('Private goal'), findsNothing);
    expect(find.text('Other group'), findsNothing);
    expect(find.text('Checklist goal'), findsNothing);
  });

  testWidgets(
    'opens authoritative detail and refreshes after one guarded result add',
    (tester) async {
      final pendingAdd = Completer<http.Response>();
      final client = _QueueClient([
        (_) => _json({
          'goals': [_goal()],
          'state': 'online',
        }, 200),
        (_) => _json(_detail(total: 4), 200),
        (_) => pendingAdd.future,
        (_) => _json(_detail(total: 6), 200),
      ]);

      await tester.pumpWidget(_groupGoalsPage(_api(client)));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Read together'));
      await tester.pumpAndSettle();

      expect(find.text('4 / 10 pages'), findsOneWidget);
      expect(find.text('6 pages remaining'), findsOneWidget);
      expect(find.text('Due Dec 31, 2026'), findsOneWidget);
      expect(find.textContaining('Morning reading'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('online-add-result-action')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('online-result-amount-field')),
        '2',
      );
      await tester.enterText(
        find.byKey(const ValueKey('online-result-note-field')),
        'Evening reading',
      );
      await tester.tap(find.byKey(const ValueKey('online-result-submit')));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('online-result-submit')));
      await tester.pump();

      expect(find.text('Adding…'), findsOneWidget);
      expect(
        client.requests.where(
          (request) => request.url.path == '/api/goals/goal-1/progress',
        ),
        hasLength(1),
      );

      pendingAdd.complete(
        await _json({
          'id': 'result-2',
          'goalId': 'goal-1',
          'actorId': 'member-account-id',
          'amount': 2,
          'note': 'Evening reading',
          'occurredAt': '2026-10-02T18:00:00.000Z',
          'createdAt': '2026-10-02T18:00:00.000Z',
          'state': 'online',
        }, 201),
      );
      await tester.pumpAndSettle();

      expect(find.text('6 / 10 pages'), findsOneWidget);
      expect(find.text('4 pages remaining'), findsOneWidget);
      expect(
        jsonDecode(
          (client.requests.singleWhere(
            (request) => request.url.path == '/api/goals/goal-1/progress',
          ) as http.Request).body,
        ),
        {'amount': 2, 'note': 'Evening reading'},
      );
    },
  );

  testWidgets(
    'account recovery from create refreshes the parent even when the dialog is canceled',
    (tester) async {
      final client = _QueueClient([
        (_) => _json({
          'goals': [_goal(title: 'Old account goal')],
          'state': 'online',
        }, 200),
        (_) => _json({'error': 'unauthorized'}, 401),
        (_) => _json({'auth': 'better_auth', 'google': 'setup_needed'}, 200),
        (_) => _json({'state': 'online', 'email': 'new@example.test'}, 200),
        (_) => _json({
          'goals': [_goal(title: 'New account goal')],
          'state': 'online',
        }, 200),
      ]);

      await tester.pumpWidget(_groupGoalsPage(_api(client)));
      await tester.pumpAndSettle();
      expect(find.text('Old account goal'), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('create-shared-goal-action')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('shared-goal-title-field')),
        'Draft goal',
      );
      await tester.tap(find.byKey(const ValueKey('shared-goal-submit')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('shared-goal-reauth')), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey('shared-goal-reauth')));
      await tester.pumpAndSettle();
      expect(find.text('Signed in'), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(find.text('New account goal'), findsOneWidget);
      expect(find.text('Old account goal'), findsNothing);
      expect(
        client.requests.where(
          (request) =>
              request.method == 'GET' && request.url.path == '/api/goals',
        ),
        hasLength(2),
      );
    },
  );

  testWidgets(
    'keeps create recovery actions disabled until the parent refresh completes',
    (tester) async {
      final recoveryGet = Completer<http.Response>();
      final client = _QueueClient([
        (_) => _json({
          'goals': [_goal(title: 'Old account goal')],
          'state': 'online',
        }, 200),
        (_) => _json({'error': 'unauthorized'}, 401),
        (_) => _json({'auth': 'better_auth', 'google': 'setup_needed'}, 200),
        (_) => _json({'state': 'online', 'email': 'new@example.test'}, 200),
        (_) => recoveryGet.future,
        (_) =>
            _json(_goal(id: 'goal-2', title: 'Draft goal', unit: 'times'), 201),
        (_) => _json({
          'goals': [_goal(title: 'Final account goal')],
          'state': 'online',
        }, 200),
      ]);
      List<http.Request> createPosts() => client.requests
          .where(
            (request) =>
                request.method == 'POST' && request.url.path == '/api/goals',
          )
          .cast<http.Request>()
          .toList();

      await tester.pumpWidget(_groupGoalsPage(_api(client)));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('create-shared-goal-action')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey('shared-goal-title-field')),
        'Draft goal',
      );
      await tester.tap(find.byKey(const ValueKey('shared-goal-submit')));
      await tester.pumpAndSettle();

      final firstPost = createPosts().single;
      final operationKey = firstPost.headers['idempotency-key'];
      expect(operationKey, isNotEmpty);

      await tester.tap(find.byKey(const ValueKey('shared-goal-reauth')));
      await tester.pumpAndSettle();
      expect(find.text('Signed in'), findsOneWidget);
      await tester.tap(find.byTooltip('Back'));
      await tester.pump(const Duration(milliseconds: 500));

      expect(recoveryGet.isCompleted, isFalse);
      expect(
        client.requests.where(
          (request) =>
              request.method == 'GET' && request.url.path == '/api/goals',
        ),
        hasLength(2),
      );
      expect(
        tester
            .widget<PlayfulButton>(
              find.byKey(const ValueKey('shared-goal-submit')),
            )
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Cancel'))
            .onPressed,
        isNull,
      );
      expect(
        tester
            .widget<TextButton>(
              find.byKey(const ValueKey('shared-goal-reauth')),
            )
            .onPressed,
        isNull,
      );

      await tester.tap(find.byKey(const ValueKey('shared-goal-submit')));
      await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
      await tester.tap(find.byKey(const ValueKey('shared-goal-reauth')));
      await tester.pump();
      expect(createPosts(), hasLength(1));
      expect(find.byKey(const ValueKey('shared-goal-reauth')), findsOneWidget);

      recoveryGet.complete(
        await _json({
          'goals': [_goal(title: 'Recovered account goal')],
          'state': 'online',
        }, 200),
      );
      await tester.pumpAndSettle();

      expect(
        tester
            .widget<PlayfulButton>(
              find.byKey(const ValueKey('shared-goal-submit')),
            )
            .onPressed,
        isNotNull,
      );
      expect(
        tester
            .widget<TextButton>(find.widgetWithText(TextButton, 'Cancel'))
            .onPressed,
        isNotNull,
      );
      expect(
        tester
            .widget<TextButton>(
              find.byKey(const ValueKey('shared-goal-reauth')),
            )
            .onPressed,
        isNotNull,
      );
      expect(
        tester
            .widget<TextFormField>(
              find.byKey(const ValueKey('shared-goal-title-field')),
            )
            .controller!
            .text,
        'Draft goal',
      );

      await tester.tap(find.byKey(const ValueKey('shared-goal-submit')));
      await tester.pumpAndSettle();

      final posts = createPosts();
      expect(posts, hasLength(2));
      expect(posts[1].headers['idempotency-key'], operationKey);
      final body = jsonDecode(posts[1].body) as Map<String, dynamic>;
      expect(body['groupId'], 'group-1');
      expect(body['title'], 'Draft goal');
      expect(body['target'], 10);
      expect(body['unit'], 'times');
      expect(find.text('Final account goal'), findsOneWidget);
      expect(find.text('Recovered account goal'), findsNothing);
    },
  );

  testWidgets(
    'renders setup and offline states instead of local or fake goals',
    (tester) async {
      await tester.pumpWidget(
        _groupGoalsPage(
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
      expect(
        find.textContaining('Your local tracker is still available.'),
        findsOneWidget,
      );

      await tester.pumpWidget(
        _groupGoalsPage(
          _api(_QueueClient([_offline])),
          key: const ValueKey('offline'),
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
}
