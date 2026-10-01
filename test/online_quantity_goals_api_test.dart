import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:its_the_day/data/group_membership.dart';
import 'package:its_the_day/data/groups_api.dart';
import 'package:its_the_day/data/online_quantity_goals.dart';

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

OnlineQuantityGoalsApi _api(_QueueClient client) => OnlineQuantityGoalsApi(
  GroupsApi(
    baseUrl: 'https://api.example',
    tokens: _MemoryTokenStore(),
    client: client,
    browser: false,
  ),
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

void main() {
  test(
    'filters group goals and parses authoritative detail and result routes',
    () async {
      final client = _QueueClient([
        (_) => _json({
          'goals': [
            _goal(),
            _goal(
              id: 'private-goal',
              visibility: 'private',
              groupId: '',
              title: 'Private',
            ),
            _goal(id: 'other-group', groupId: 'group-2', title: 'Other group'),
            _goal(
              id: 'individual-goal',
              targetMode: 'individual',
              title: 'Individual',
            ),
            _goal(
              id: 'checklist-goal',
              kind: 'checklist',
              unit: '',
              title: 'Checklist',
            ),
          ],
          'state': 'online',
        }, 200),
        (_) => _json(_detail(), 200),
        (_) => _json({
          'id': 'result-2',
          'goalId': 'goal-1',
          'actorId': 'member-account-id',
          'amount': 2,
          'note': 'Evening reading',
          'occurredAt': '2026-10-02T18:00:00.000Z',
          'createdAt': '2026-10-02T18:00:00.000Z',
          'state': 'online',
        }, 201),
      ]);
      final api = _api(client);

      final goals = await api.listGroupGoals('group-1');
      final detail = await api.getGoal('goal/1');
      final result = await api.addResult(
        'goal/1',
        2,
        note: 'Evening reading',
        operationId: 'result-operation',
      );

      expect(goals, hasLength(1));
      expect(goals.single.title, 'Read together');
      expect(goals.single.groupId, 'group-1');
      expect(detail.goal.completed, 4);
      expect(detail.goal.remaining, 6);
      expect(detail.goal.deadline, DateTime(2026, 12, 31));
      expect(detail.results.single.note, 'Morning reading');
      expect(
        detail.results.single.occurredAt,
        DateTime.utc(2026, 10, 2, 9, 30),
      );
      expect(result.amount, 2);

      expect(client.requests[0].url.path, '/api/goals');
      expect(
        client.requests[1].url.toString(),
        contains('/api/goals/goal%2F1'),
      );
      expect(
        client.requests[2].url.toString(),
        contains('/api/goals/goal%2F1/progress'),
      );
      expect(client.requests[2].headers['idempotency-key'], 'result-operation');
      expect(jsonDecode((client.requests[2] as http.Request).body), {
        'amount': 2,
        'note': 'Evening reading',
      });
    },
  );

  test(
    'creates fixed shared-total quantity goal with a calendar deadline',
    () async {
      final client = _QueueClient([
        (_) => _json({
          ..._goal(id: 'created-goal', title: 'Read'),
          'state': 'online',
        }, 201),
      ]);

      final created = await _api(client).createSharedQuantityGoal(
        'group/1',
        title: 'Read',
        target: 12,
        unit: 'pages',
        deadline: DateTime(2026, 2, 3, 23, 59),
        operationId: 'create-operation',
      );

      expect(created.title, 'Read');
      expect(created.targetMode, 'shared_total');
      expect(created.deadline, DateTime(2026, 12, 31));
      expect(client.requests.single.url.path, '/api/goals');
      expect(
        client.requests.single.headers['idempotency-key'],
        'create-operation',
      );
      expect(jsonDecode((client.requests.single as http.Request).body), {
        'title': 'Read',
        'kind': 'quantity',
        'visibility': 'shared',
        'groupId': 'group/1',
        'targetMode': 'shared_total',
        'target': 12,
        'unit': 'pages',
        'deadline': '2026-02-03',
      });
    },
  );

  test('StableOperationId keeps retries bound to the same unchanged draft', () {
    var next = 0;
    final operation = StableOperationId(generator: () => 'operation-${++next}');

    final first = operation.forPayload({
      'groupId': 'group-1',
      'title': 'Read',
      'target': 10,
      'unit': 'pages',
      'deadline': '2026-12-31',
    });
    final retry = operation.forPayload({
      'groupId': 'group-1',
      'title': 'Read',
      'target': 10,
      'unit': 'pages',
      'deadline': '2026-12-31',
    });
    final changed = operation.forPayload({
      'groupId': 'group-1',
      'title': 'Read more',
      'target': 10,
      'unit': 'pages',
      'deadline': '2026-12-31',
    });

    expect(retry, first);
    expect(changed, isNot(first));
  });
}
