import 'package:flutter/material.dart';

import '../data/group_membership.dart';
import '../data/groups_api.dart';
import 'account_page.dart';
import 'group_goals_page.dart';
import 'playful_widgets.dart';

class GroupMembersPage extends StatefulWidget {
  const GroupMembersPage({super.key, required this.api, required this.group});

  final GroupsApi api;
  final GroupSummary group;

  @override
  State<GroupMembersPage> createState() => _GroupMembersPageState();
}

enum _MembersState {
  loading,
  online,
  signedOut,
  setup,
  offline,
  forbidden,
  error,
}

class _GroupMembersPageState extends State<GroupMembersPage> {
  late final GroupMembershipApi _membership;
  _MembersState _state = _MembersState.loading;
  List<GroupMember> _members = const [];
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _membership = GroupMembershipApi(widget.api);
    _load();
  }

  Future<void> _load() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _state = _MembersState.loading;
      _error = null;
    });
    try {
      final members = await _membership.listMembers(widget.group.id);
      if (!mounted) return;
      setState(() {
        _members = members;
        _state = _MembersState.online;
      });
    } on GroupsSignedOut {
      if (mounted) setState(() => _state = _MembersState.signedOut);
    } on GroupsSetupNeeded {
      if (mounted) setState(() => _state = _MembersState.setup);
    } on GroupsOffline catch (error) {
      if (mounted) {
        setState(() {
          _state = _MembersState.offline;
          _error = error.message;
        });
      }
    } on GroupsPermissionDenied {
      if (mounted) setState(() => _state = _MembersState.forbidden);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _state = _MembersState.error;
          _error = _safeMemberError(error);
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.group.name),
        actions: [
          IconButton(
            tooltip: 'Refresh members',
            onPressed: _busy ? null : _load,
            icon: const Icon(Icons.refresh_rounded),
          ),
        ],
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 680),
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 28),
              children: [
                switch (_state) {
                  _MembersState.loading => const _MembersLoading(),
                  _MembersState.signedOut => _MembersStateCard(
                    icon: Icons.account_circle_outlined,
                    title: 'Sign in required',
                    message: 'Open your account to continue.',
                    actionLabel: 'Open account',
                    onAction: _openAccount,
                  ),
                  _MembersState.setup => _MembersStateCard(
                    icon: Icons.settings_suggest_outlined,
                    title: 'Server setup needed',
                    message: 'Connect this build to the configured server. Your local tracker is still available.',
                    actionLabel: 'Try again',
                    onAction: _load,
                  ),
                  _MembersState.offline => _MembersStateCard(
                    icon: Icons.cloud_off_outlined,
                    title: 'Offline',
                    message: _error ?? 'Could not reach the server. Your local tracker is still available.',
                    actionLabel: 'Try again',
                    onAction: _load,
                  ),
                  _MembersState.forbidden => _MembersStateCard(
                    icon: Icons.lock_outline_rounded,
                    title: 'Access denied',
                    message: 'You are not allowed to view this group.',
                    actionLabel: 'Try again',
                    onAction: _load,
                  ),
                  _MembersState.error => _MembersStateCard(
                    icon: Icons.error_outline_rounded,
                    title: 'Members unavailable',
                    message: _error ?? 'Could not load members. Try again.',
                    actionLabel: 'Try again',
                    onAction: _load,
                  ),
                  _MembersState.online => _OnlineMembers(
                    group: widget.group,
                    members: _members,
                    onOpenGoals: _openGoals,
                  ),
                },
              ],
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _openAccount() async {
    if (_busy) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AccountPage(api: widget.api)),
    );
    if (mounted) await _load();
  }

  Future<void> _openGoals() async {
    if (_busy) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GroupGoalsPage(api: widget.api, group: widget.group),
      ),
    );
  }
}

class _OnlineMembers extends StatelessWidget {
  const _OnlineMembers({
    required this.group,
    required this.members,
    required this.onOpenGoals,
  });

  final GroupSummary group;
  final List<GroupMember> members;
  final VoidCallback onOpenGoals;

  @override
  Widget build(BuildContext context) {
    final activeCount = members.where((member) => member.active).length;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PlayfulButton.icon(
          key: const ValueKey('group-goals-action'),
          icon: Icons.flag_outlined,
          semanticLabel: 'Open shared goals',
          onPressed: onOpenGoals,
          label: const Text('Shared goals'),
        ),
        const SizedBox(height: 20),
        if (group.role == GroupRole.owner && group.joinCode != null) ...[
          PlayfulPanel(
            padding: const EdgeInsets.all(18),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Invite code',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 4),
                SelectableText(
                  group.joinCode!,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    color: Theme.of(context).colorScheme.primary,
                    letterSpacing: 1.4,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const SizedBox(height: 4),
                const Text('Share this code with someone you want to invite.'),
              ],
            ),
          ),
          const SizedBox(height: 24),
        ],
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text(
                'Members',
                style: Theme.of(context).textTheme.headlineSmall,
              ),
            ),
            Text(
              '$activeCount active',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurface
                    .withValues(alpha: .62),
              ),
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (members.isEmpty)
          const _NoMembers()
        else
          for (final member in members) ...[
            _MemberCard(member: member),
            const SizedBox(height: 10),
          ],
      ],
    );
  }
}

class _MemberCard extends StatelessWidget {
  const _MemberCard({required this.member});

  final GroupMember member;

  @override
  Widget build(BuildContext context) {
    final active = member.active;
    return Card(
      child: ListTile(
        minVerticalPadding: 12,
        leading: Icon(
          member.role == GroupRole.owner
              ? Icons.workspace_premium_outlined
              : Icons.person_outline_rounded,
          color: Theme.of(context).colorScheme.primary,
        ),
        title: Text(member.role.label),
        subtitle: Text(active ? 'Active member' : 'Access revoked'),
      ),
    );
  }
}

class _NoMembers extends StatelessWidget {
  const _NoMembers();

  @override
  Widget build(BuildContext context) {
    return PlayfulPanel(
      padding: const EdgeInsets.all(18),
      child: const Text('No members found.'),
    );
  }
}

class _MembersLoading extends StatelessWidget {
  const _MembersLoading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 80),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _MembersStateCard extends StatelessWidget {
  const _MembersStateCard({
    required this.icon,
    required this.title,
    required this.message,
    required this.actionLabel,
    required this.onAction,
  });

  final IconData icon;
  final String title;
  final String message;
  final String actionLabel;
  final VoidCallback onAction;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, size: 48, color: Theme.of(context).colorScheme.primary),
            const SizedBox(height: 16),
            Text(title, style: Theme.of(context).textTheme.headlineSmall),
            const SizedBox(height: 10),
            Text(message),
            const SizedBox(height: 20),
            FilledButton(onPressed: onAction, child: Text(actionLabel)),
          ],
        ),
      ),
    );
  }
}

String _safeMemberError(Object error) {
  if (error is GroupsRequestError) {
    return 'Could not load members. Try again.';
  }
  if (error is GroupsPermissionDenied) {
    return 'You are not allowed to view this group.';
  }
  if (error is GroupsSignedOut) return 'Your session has ended. Sign in again.';
  return 'Could not load members. Try again.';
}
