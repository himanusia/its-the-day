import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;

import 'package:its_the_day/data/group_membership.dart';
import 'package:its_the_day/data/groups_api.dart';

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

void main() {
  test('uses the group list, mutation, and member route contracts', () async {
    final client = _QueueClient([
      (_) => _json({
        'groups': [
          {
            'id': 'group-1',
            'name': 'Study circle',
            'joinCode': 'JOIN1234',
            'role': 'owner',
            'memberCount': 2,
            'createdAt': '2026-10-01T10:00:00.000Z',
          },
        ],
        'state': 'online',
      }, 200),
      (_) => _json({
        'id': 'group-2',
        'name': 'New circle',
        'joinCode': 'CREATE12',
        'role': 'owner',
        'memberCount': 1,
        'state': 'online',
      }, 201),
      (_) => _json({
        'id': 'group-1',
        'name': 'Study circle',
        'role': 'member',
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
    final membership = GroupMembershipApi(
      GroupsApi(
        baseUrl: 'https://api.example',
        tokens: _MemoryTokenStore(),
        client: client,
        browser: false,
      ),
    );

    final groups = await membership.listGroups();
    final created = await membership.createGroup(
      'New circle',
      operationId: 'create-operation',
    );
    final joined = await membership.joinGroup(
      'JOIN1234',
      operationId: 'join-operation',
    );
    final members = await membership.listMembers('group-1');

    expect(groups.single.name, 'Study circle');
    expect(groups.single.memberCount, 2);
    expect(created.joinCode, 'CREATE12');
    expect(joined.role, GroupRole.member);
    expect(members.map((member) => member.role), [
      GroupRole.owner,
      GroupRole.member,
    ]);
    expect(members.every((member) => member.active), isTrue);

    expect(client.requests[0].url.path, '/api/groups');
    expect(client.requests[1].url.path, '/api/groups');
    expect(client.requests[2].url.path, '/api/groups/join');
    expect(client.requests[3].url.path, '/api/groups/group-1/members');
    expect(client.requests[1].headers['idempotency-key'], 'create-operation');
    expect(client.requests[2].headers['idempotency-key'], 'join-operation');
    expect(jsonDecode((client.requests[1] as http.Request).body), {
      'name': 'New circle',
    });
    expect(jsonDecode((client.requests[2] as http.Request).body), {
      'code': 'JOIN1234',
    });
  });

  test(
    'keeps one operation id for unchanged payloads and rotates on change',
    () {
      var next = 0;
      final operation = StableOperationId(
        generator: () => 'operation-${++next}',
      );

      final first = operation.forPayload({'name': 'Study circle'});
      final retry = operation.forPayload({'name': 'Study circle'});
      final changed = operation.forPayload({'name': 'New circle'});
      final changedRetry = operation.forPayload({'name': 'New circle'});

      expect(first, 'operation-1');
      expect(retry, first);
      expect(changed, 'operation-2');
      expect(changedRetry, changed);
    },
  );
}
