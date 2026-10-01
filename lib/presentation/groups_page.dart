import 'package:flutter/material.dart';

import '../data/group_membership.dart';
import '../data/groups_api.dart';
import 'account_page.dart';
import 'group_members_page.dart';
import 'playful_widgets.dart';

class GroupsPage extends StatefulWidget {
  const GroupsPage({super.key, required this.api});

  final GroupsApi api;

  @override
  State<GroupsPage> createState() => _GroupsPageState();
}

enum _GroupsState {
  loading,
  online,
  signedOut,
  setup,
  offline,
  forbidden,
  error,
}

class _GroupsPageState extends State<GroupsPage> {
  late final GroupMembershipApi _membership;
  _GroupsState _state = _GroupsState.loading;
  List<GroupSummary> _groups = const [];
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
      _state = _GroupsState.loading;
      _error = null;
    });
    try {
      final groups = await _membership.listGroups();
      if (!mounted) return;
      setState(() {
        _groups = groups;
        _state = _GroupsState.online;
      });
    } on GroupsSignedOut {
      if (mounted) setState(() => _state = _GroupsState.signedOut);
    } on GroupsSetupNeeded {
      if (mounted) setState(() => _state = _GroupsState.setup);
    } on GroupsOffline catch (error) {
      if (mounted) {
        setState(() {
          _state = _GroupsState.offline;
          _error = error.message;
        });
      }
    } on GroupsPermissionDenied {
      if (mounted) setState(() => _state = _GroupsState.forbidden);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _state = _GroupsState.error;
          _error = _safeGroupError(error);
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
        title: const Text('Groups'),
        actions: [
          if (_state == _GroupsState.online)
            IconButton(
              tooltip: 'Refresh groups',
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
                  _GroupsState.loading => const _GroupsLoading(),
                  _GroupsState.signedOut => _GroupsStateCard(
                    icon: Icons.account_circle_outlined,
                    title: 'Sign in to use groups',
                    message:
                        'Open your account to sign in, then come back here.',
                    actionLabel: 'Open account',
                    onAction: _openAccount,
                  ),
                  _GroupsState.setup => _GroupsStateCard(
                    icon: Icons.settings_suggest_outlined,
                    title: 'Server setup needed',
                    message: 'Connect this build to the configured server. Your local tracker is still available.',
                    actionLabel: 'Try again',
                    onAction: _load,
                  ),
                  _GroupsState.offline => _GroupsStateCard(
                    icon: Icons.cloud_off_outlined,
                    title: 'Offline',
                    message: _error ?? 'Could not reach the server. Your local tracker is still available.',
                    actionLabel: 'Try again',
                    onAction: _load,
                  ),
                  _GroupsState.forbidden => _GroupsStateCard(
                    icon: Icons.lock_outline_rounded,
                    title: 'Access denied',
                    message: 'This account cannot view these groups.',
                    actionLabel: 'Try again',
                    onAction: _load,
                  ),
                  _GroupsState.error => _GroupsStateCard(
                    icon: Icons.error_outline_rounded,
                    title: 'Groups unavailable',
                    message: _error ?? 'Could not load groups. Try again.',
                    actionLabel: 'Try again',
                    onAction: _load,
                  ),
                  _GroupsState.online => _OnlineGroups(
                    groups: _groups,
                    busy: _busy,
                    onCreate: _createGroup,
                    onJoin: _joinGroup,
                    onOpen: _openGroup,
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

  Future<void> _openGroup(GroupSummary group) async {
    if (_busy) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => GroupMembersPage(api: widget.api, group: group),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _createGroup() async {
    if (_busy) return;
    final result = await showDialog<GroupMutationResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _GroupMutationDialog(api: _membership, joining: false),
    );
    if (!mounted || result == null) return;
    await _load();
    if (!mounted || result.joinCode == null) return;
    _showMessage('Group created. Invite code: ${result.joinCode}');
  }

  Future<void> _joinGroup() async {
    if (_busy) return;
    final result = await showDialog<GroupMutationResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _GroupMutationDialog(api: _membership, joining: true),
    );
    if (!mounted || result == null) return;
    await _load();
    if (mounted) _showMessage('Joined ${result.name}.');
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _OnlineGroups extends StatelessWidget {
  const _OnlineGroups({
    required this.groups,
    required this.busy,
    required this.onCreate,
    required this.onJoin,
    required this.onOpen,
  });

  final List<GroupSummary> groups;
  final bool busy;
  final VoidCallback onCreate;
  final VoidCallback onJoin;
  final ValueChanged<GroupSummary> onOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('Your groups', style: Theme.of(context).textTheme.headlineSmall),
        const SizedBox(height: 8),
        Text(
          'Create a circle or join one with an invite code.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurface
                .withValues(alpha: .68),
          ),
        ),
        const SizedBox(height: 16),
        if (groups.isEmpty)
          const _EmptyGroups()
        else
          for (final group in groups) ...[
            _GroupCard(group: group, onTap: () => onOpen(group)),
            const SizedBox(height: 12),
          ],
        const SizedBox(height: 8),
        Wrap(
          spacing: 12,
          runSpacing: 12,
          children: [
            PlayfulButton.icon(
              key: const ValueKey('create-group-action'),
              icon: Icons.group_add_rounded,
              semanticLabel: 'Create a group',
              onPressed: busy ? null : onCreate,
              label: const Text('Create group'),
            ),
            PlayfulButton.icon(
              key: const ValueKey('join-group-action'),
              icon: Icons.login_rounded,
              semanticLabel: 'Join a group',
              tone: PlayfulButtonTone.secondary,
              onPressed: busy ? null : onJoin,
              label: const Text('Join group'),
            ),
          ],
        ),
      ],
    );
  }
}

class _GroupCard extends StatelessWidget {
  const _GroupCard({required this.group, required this.onTap});

  final GroupSummary group;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final countLabel =
        '${group.memberCount} ${group.memberCount == 1 ? 'member' : 'members'}';
    return Card(
      child: Semantics(
        button: true,
        label: '${group.name}, $countLabel, ${group.role.label}',
        child: ListTile(
          minVerticalPadding: 12,
          onTap: onTap,
          leading: const Icon(Icons.groups_rounded),
          title: Text(group.name),
          subtitle: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('$countLabel · ${group.role.label}'),
              if (group.role == GroupRole.owner && group.joinCode != null)
                Text(group.joinCode!),
            ],
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
        ),
      ),
    );
  }
}

class _EmptyGroups extends StatelessWidget {
  const _EmptyGroups();

  @override
  Widget build(BuildContext context) {
    return PlayfulPanel(
      padding: const EdgeInsets.all(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.groups_outlined,
            size: 44,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'No groups yet. Create one or join with an invite code.',
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupsLoading extends StatelessWidget {
  const _GroupsLoading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 80),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _GroupsStateCard extends StatelessWidget {
  const _GroupsStateCard({
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

class _GroupMutationDialog extends StatefulWidget {
  const _GroupMutationDialog({required this.api, required this.joining});

  final GroupMembershipApi api;
  final bool joining;

  @override
  State<_GroupMutationDialog> createState() => _GroupMutationDialogState();
}

class _GroupMutationDialogState extends State<_GroupMutationDialog> {
  final _formKey = GlobalKey<FormState>();
  final _value = TextEditingController();
  final _operation = StableOperationId();
  String? _error;
  bool _authExpired = false;
  bool _submitting = false;

  @override
  void dispose() {
    _value.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final joining = widget.joining;
    return AlertDialog(
      title: Text(joining ? 'Join group' : 'Create group'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                joining ? 'Enter the invite code shared by the group owner.' : 'Give your group a short name. You can share its invite code after creation.',
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: ValueKey(
                  joining ? 'group-code-field' : 'group-name-field',
                ),
                controller: _value,
                enabled: !_submitting,
                autofocus: true,
                autocorrect: false,
                textCapitalization: joining
                    ? TextCapitalization.none
                    : TextCapitalization.sentences,
                decoration: InputDecoration(
                  labelText: joining ? 'Invite code' : 'Group name',
                ),
                validator: (value) {
                  final text = (value ?? '').trim();
                  if (text.isEmpty) {
                    return joining
                        ? 'Enter an invite code'
                        : 'Enter a group name';
                  }
                  if (joining &&
                      !RegExp(r'^[A-Za-z0-9_-]{4,32}$').hasMatch(text)) {
                    return 'Use the invite code as shown';
                  }
                  return null;
                },
                onFieldSubmitted: _submitting ? null : (_) => _submit(),
              ),
              if (_error != null) ...[
                const SizedBox(height: 12),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        if (_authExpired)
          TextButton(
            key: const ValueKey('group-reauth'),
            onPressed: _submitting ? null : _openAccount,
            child: const Text('Open account'),
          ),
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        PlayfulButton(
          key: ValueKey(joining ? 'join-group-submit' : 'create-group-submit'),
          onPressed: _submitting ? null : _submit,
          child: Text(
            _submitting
                ? joining
                      ? 'Joining…'
                      : 'Creating…'
                : joining
                ? 'Join group'
                : 'Create group',
          ),
        ),
      ],
    );
  }

  Future<void> _openAccount() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AccountPage(api: widget.api.api)),
    );
    // Keep the same dialog/controller/operation key beneath the account route.
    // The next submit checks authentication; returning alone is not login proof.
  }

  Future<void> _submit() async {
    if (_submitting || !(_formKey.currentState?.validate() ?? false)) return;
    final value = _value.text.trim();
    final payload = <String, Object?>{widget.joining ? 'code' : 'name': value};
    final operationId = _operation.forPayload(payload);
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final result = widget.joining
          ? await widget.api.joinGroup(value, operationId: operationId)
          : await widget.api.createGroup(value, operationId: operationId);
      if (mounted) Navigator.pop(context, result);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _error = _safeMutationError(error);
          _authExpired = error is GroupsSignedOut;
        });
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}

String _safeGroupError(Object error) {
  if (error is GroupsRequestError) {
    return 'Could not load groups. Try again.';
  }
  if (error is GroupsPermissionDenied) {
    return 'This account cannot view these groups.';
  }
  if (error is GroupsSignedOut) return 'Your session has ended. Sign in again.';
  return 'Could not load groups. Try again.';
}

String _safeMutationError(Object error) {
  if (error is GroupsOffline) return error.message;
  if (error is GroupsSetupNeeded) {
    return 'Server setup is needed before groups can be changed.';
  }
  if (error is GroupsSignedOut) {
    return 'Your session has ended. Open Account to sign in again.';
  }
  if (error is GroupsPermissionDenied) {
    return 'This account cannot change this group.';
  }
  return 'Could not complete the group request. Try again.';
}
