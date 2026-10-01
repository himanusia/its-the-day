import 'package:flutter_test/flutter_test.dart';

import 'package:its_the_day/data/group_membership.dart';
import 'package:its_the_day/data/groups_api.dart';

class _EphemeralTokens implements SessionTokenStore {
  String? _token;
  @override
  Future<String?> read() async => _token;
  @override
  Future<void> write(String token) async => _token = token;
  @override
  Future<void> clear() async => _token = null;
}

void main() {
  const enabled = bool.fromEnvironment('ITD_LOCAL_E2E');
  test(
    'real local Worker supports two-account group client and revocation',
    () async {
      final owner = GroupsApi(
        baseUrl: 'http://127.0.0.1:8787',
        tokens: _EphemeralTokens(),
      );
      final member = GroupsApi(
        baseUrl: 'http://127.0.0.1:8787',
        tokens: _EphemeralTokens(),
      );
      final outsider = GroupsApi(
        baseUrl: 'http://127.0.0.1:8787',
        tokens: _EphemeralTokens(),
      );
      final runId = GroupsApi.operationKey();
      try {
        final health = await owner.health();
        expect(health.auth, 'better_auth');
        await owner.signUp(
          'QA Owner',
          'owner-$runId@example.test',
          GroupsApi.operationKey(),
        );
        final memberUser = await member.signUp(
          'QA Member',
          'member-$runId@example.test',
          GroupsApi.operationKey(),
        );
        await outsider.signUp(
          'QA Outsider',
          'outsider-$runId@example.test',
          GroupsApi.operationKey(),
        );
        final ownerGroups = GroupMembershipApi(owner);
        final memberGroups = GroupMembershipApi(member);
        final group = await ownerGroups.createGroup(
          'QA Circle',
          operationId: 'create-$runId',
        );
        final replay = await ownerGroups.createGroup(
          'QA Circle',
          operationId: 'create-$runId',
        );
        expect(replay.id, group.id);
        expect((await ownerGroups.listGroups()).length, 1);
        final joined = await memberGroups.joinGroup(
          group.joinCode!,
          operationId: 'join-$runId',
        );
        expect(joined.id, group.id);
        expect((await memberGroups.listGroups()).single.id, group.id);
        expect(
          (await ownerGroups.listMembers(group.id))
              .where((m) => m.active)
              .length,
          2,
        );
        expect(
          (await memberGroups.listMembers(group.id))
              .where((m) => m.active)
              .length,
          2,
        );
        await expectLater(
          GroupMembershipApi(outsider).listMembers(group.id),
          throwsA(isA<GroupsPermissionDenied>()),
        );
        final memberId = (memberUser['user'] as Map)['id'] as String;
        await owner.mutate(
          'POST',
          '/api/groups/${group.id}/revoke/$memberId',
          operationId: 'revoke-$runId',
        );
        await expectLater(
          memberGroups.listMembers(group.id),
          throwsA(isA<GroupsPermissionDenied>()),
        );
        expect(await memberGroups.listGroups(), isEmpty);
        await member.signOut();
        await expectLater(
          memberGroups.listGroups(),
          throwsA(isA<GroupsSignedOut>()),
        );
      } finally {
        for (final api in [owner, member, outsider]) {
          try {
            await api.signOut();
          } catch (_) {
            /* Local QA cleanup is best effort. */
          }
          api.close();
        }
      }
    },
    skip: !enabled
        ? 'Opt-in local-only QA; requires configured Worker at loopback:8787.'
        : false,
  );
}
