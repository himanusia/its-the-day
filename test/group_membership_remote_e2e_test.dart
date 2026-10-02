// Explicit opt-in: creates isolated synthetic QA accounts and records on the authorized deployment.
import 'package:flutter_test/flutter_test.dart';

import 'package:its_the_day/data/group_membership.dart';
import 'package:its_the_day/data/groups_api.dart';
import 'package:its_the_day/data/online_quantity_goals.dart';

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
  const enabled = bool.fromEnvironment('ITD_REMOTE_E2E');
  test(
    'real HTTPS Cloudflare Worker quantity client shares authoritative contributions',
    () async {
      final owner = GroupsApi(
        baseUrl: 'https://its-the-day.himanusia.com',
        tokens: _EphemeralTokens(),
      );
      final member = GroupsApi(
        baseUrl: 'https://its-the-day.himanusia.com',
        tokens: _EphemeralTokens(),
      );
      final id = GroupsApi.operationKey();
      try {
        await owner.signUp(
          'QA Goal Owner',
          'goal-owner-$id@example.test',
          GroupsApi.operationKey(),
        );
        final memberUser = await member.signUp(
          'QA Contributor',
          'goal-member-$id@example.test',
          GroupsApi.operationKey(),
        );
        final group = await GroupMembershipApi(owner)
            .createGroup('QA Shared Goal', operationId: 'group-$id');
        await GroupMembershipApi(member)
            .joinGroup(group.joinCode!, operationId: 'join-$id');
        final a = OnlineQuantityGoalsApi(owner);
        final b = OnlineQuantityGoalsApi(member);
        final goal = await a.createSharedQuantityGoal(
          group.id,
          title: 'Read together',
          target: 10,
          unit: 'pages',
          deadline: DateTime(2027, 1, 1),
          operationId: 'goal-$id',
        );
        expect((await b.listGroupGoals(group.id)).single.id, goal.id);
        final first = await a.addResult(
          goal.id,
          2,
          note: 'Owner note',
          operationId: 'a-$id',
        );
        final replay = await a.addResult(
          goal.id,
          2,
          note: 'Owner note',
          operationId: 'a-$id',
        );
        expect(replay.id, first.id);
        await b.addResult(
          goal.id,
          3,
          note: 'Member note',
          operationId: 'b-$id',
        );
        for (final client in [a, b]) {
          final detail = await client.getGoal(goal.id);
          expect(detail.goal.completed, 5);
          expect(detail.goal.remaining, 5);
          expect(detail.results.length, 2);
          expect(
            detail.results.map((r) => r.note),
            containsAll(['Owner note', 'Member note']),
          );
        }
        final other = await GroupMembershipApi(owner)
            .createGroup('Unrelated group', operationId: 'other-$id');
        expect(await a.listGroupGoals(other.id), isEmpty);
        final memberId = (memberUser['user'] as Map)['id'] as String;
        await owner.mutate(
          'POST',
          '/api/groups/${group.id}/revoke/$memberId',
          operationId: 'revoke-$id',
        );
        await expectLater(
          b.getGoal(goal.id),
          throwsA(isA<GroupsRequestError>()),
        );
      } finally {
        for (final api in [owner, member]) {
          try {
            await api.signOut();
          } catch (_) {}
          api.close();
        }
      }
    },
    skip: !enabled
        ? 'Opt-in authorized HTTPS Cloudflare/D1 integration.'
        : false,
  );
  test(
    'real HTTPS Cloudflare Worker supports two-account group client and revocation',
    () async {
      final owner = GroupsApi(
        baseUrl: 'https://its-the-day.himanusia.com',
        tokens: _EphemeralTokens(),
      );
      final member = GroupsApi(
        baseUrl: 'https://its-the-day.himanusia.com',
        tokens: _EphemeralTokens(),
      );
      final outsider = GroupsApi(
        baseUrl: 'https://its-the-day.himanusia.com',
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
        ? 'Opt-in remote QA; requires reviewed HTTPS Worker deployment.'
        : false,
  );
}
