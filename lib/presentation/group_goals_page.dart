import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/group_membership.dart';
import '../data/groups_api.dart';
import '../data/online_quantity_goals.dart';
import 'account_page.dart';
import 'online_quantity_goal_page.dart';
import 'playful_widgets.dart';

class GroupGoalsPage extends StatefulWidget {
  const GroupGoalsPage({super.key, required this.api, required this.group});

  final GroupsApi api;
  final GroupSummary group;

  @override
  State<GroupGoalsPage> createState() => _GroupGoalsPageState();
}

enum _GroupGoalsState {
  loading,
  online,
  signedOut,
  setup,
  offline,
  revoked,
  error,
}

class _GroupGoalsPageState extends State<GroupGoalsPage> {
  late final OnlineQuantityGoalsApi _goals;
  _GroupGoalsState _state = _GroupGoalsState.loading;
  List<OnlineQuantityGoal> _items = const [];
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _goals = OnlineQuantityGoalsApi(widget.api);
    _load();
  }

  Future<void> _load() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _state = _GroupGoalsState.loading;
      _error = null;
    });
    try {
      final goals = await _goals.listGroupGoals(widget.group.id);
      if (!mounted) return;
      setState(() {
        _items = goals;
        _state = _GroupGoalsState.online;
      });
    } on GroupsSignedOut {
      if (mounted) setState(() => _state = _GroupGoalsState.signedOut);
    } on GroupsSetupNeeded {
      if (mounted) setState(() => _state = _GroupGoalsState.setup);
    } on GroupsOffline catch (error) {
      if (mounted) {
        setState(() {
          _state = _GroupGoalsState.offline;
          _error = error.message;
        });
      }
    } on GroupsPermissionDenied {
      if (mounted) setState(() => _state = _GroupGoalsState.revoked);
    } on GroupsRequestError catch (error) {
      if (mounted) {
        setState(() {
          _state = error.message == 'not_found'
              ? _GroupGoalsState.revoked
              : _GroupGoalsState.error;
          _error = error.message == 'not_found' ? null : error.message;
        });
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _state = _GroupGoalsState.error;
          _error = _safeGoalListError(error);
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
        title: Text('${widget.group.name} · Shared goals'),
        actions: [
          IconButton(
            tooltip: 'Refresh shared goals',
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
                  _GroupGoalsState.loading => const _GroupGoalsLoading(),
                  _GroupGoalsState.signedOut => _GroupGoalsStateCard(
                    icon: Icons.account_circle_outlined,
                    title: 'Sign in required',
                    message: 'Open your account to continue.',
                    actionLabel: 'Open account',
                    onAction: _openAccount,
                  ),
                  _GroupGoalsState.setup => _GroupGoalsStateCard(
                    icon: Icons.settings_suggest_outlined,
                    title: 'Server setup needed',
                    message: 'Connect this build to the configured server. Your local tracker is still available.',
                    actionLabel: 'Try again',
                    onAction: _load,
                  ),
                  _GroupGoalsState.offline => _GroupGoalsStateCard(
                    icon: Icons.cloud_off_outlined,
                    title: 'Offline',
                    message: _error ?? 'Could not reach the server. Your local tracker is still available.',
                    actionLabel: 'Try again',
                    onAction: _load,
                  ),
                  _GroupGoalsState.revoked => _GroupGoalsStateCard(
                    icon: Icons.lock_outline_rounded,
                    title: 'Group access revoked',
                    message: 'This account can no longer view this group’s shared goals.',
                    actionLabel: 'Try again',
                    onAction: _load,
                  ),
                  _GroupGoalsState.error => _GroupGoalsStateCard(
                    icon: Icons.error_outline_rounded,
                    title: 'Shared goals unavailable',
                    message:
                        _error ?? 'Could not load shared goals. Try again.',
                    actionLabel: 'Try again',
                    onAction: _load,
                  ),
                  _GroupGoalsState.online => _OnlineGroupGoals(
                    goals: _items,
                    busy: _busy,
                    onCreate: _createGoal,
                    onOpen: _openGoal,
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

  Future<void> _openGoal(OnlineQuantityGoal goal) async {
    if (_busy) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) =>
            OnlineQuantityGoalPage(api: widget.api, goalId: goal.id),
      ),
    );
    if (mounted) await _load();
  }

  Future<void> _createGoal() async {
    if (_busy) return;
    final created = await showDialog<OnlineQuantityGoal>(
      context: context,
      barrierDismissible: false,
      builder: (_) =>
          _SharedQuantityGoalDialog(api: _goals, group: widget.group),
    );
    if (!mounted || created == null) return;
    await _load();
  }
}

class _OnlineGroupGoals extends StatelessWidget {
  const _OnlineGroupGoals({
    required this.goals,
    required this.busy,
    required this.onCreate,
    required this.onOpen,
  });

  final List<OnlineQuantityGoal> goals;
  final bool busy;
  final VoidCallback onCreate;
  final ValueChanged<OnlineQuantityGoal> onOpen;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Shared quantity goals',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        Text(
          'Everyone contributes to the same server-backed total.',
          style: Theme.of(context).textTheme.bodyMedium?.copyWith(
            color: Theme.of(context).colorScheme.onSurface
                .withValues(alpha: .68),
          ),
        ),
        const SizedBox(height: 16),
        if (goals.isEmpty)
          const _EmptySharedGoals()
        else
          for (final goal in goals) ...[
            _SharedGoalCard(goal: goal, onTap: () => onOpen(goal)),
            const SizedBox(height: 12),
          ],
        const SizedBox(height: 8),
        PlayfulButton.icon(
          key: const ValueKey('create-shared-goal-action'),
          icon: Icons.add_rounded,
          semanticLabel: 'Create a shared quantity goal',
          onPressed: busy ? null : onCreate,
          label: const Text('New shared goal'),
        ),
      ],
    );
  }
}

class _SharedGoalCard extends StatelessWidget {
  const _SharedGoalCard({required this.goal, required this.onTap});

  final OnlineQuantityGoal goal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final deadline = DateFormat.yMMMd().format(goal.deadline);
    return Card(
      child: Semantics(
        button: true,
        label: '${goal.title}, ${goal.target} ${goal.unit}, due $deadline',
        child: ListTile(
          minVerticalPadding: 12,
          onTap: onTap,
          leading: const Icon(Icons.trending_up_rounded),
          title: Text(goal.title),
          subtitle: Text(
            'Shared total · ${goal.target} ${goal.unit} · Due $deadline',
          ),
          trailing: const Icon(Icons.chevron_right_rounded),
        ),
      ),
    );
  }
}

class _EmptySharedGoals extends StatelessWidget {
  const _EmptySharedGoals();

  @override
  Widget build(BuildContext context) {
    return PlayfulPanel(
      padding: const EdgeInsets.all(18),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.flag_outlined,
            size: 44,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'No shared quantity goals yet. Create one for this group.',
            ),
          ),
        ],
      ),
    );
  }
}

class _GroupGoalsLoading extends StatelessWidget {
  const _GroupGoalsLoading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 80),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _GroupGoalsStateCard extends StatelessWidget {
  const _GroupGoalsStateCard({
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

class _SharedQuantityGoalDialog extends StatefulWidget {
  const _SharedQuantityGoalDialog({required this.api, required this.group});

  final OnlineQuantityGoalsApi api;
  final GroupSummary group;

  @override
  State<_SharedQuantityGoalDialog> createState() =>
      _SharedQuantityGoalDialogState();
}

class _SharedQuantityGoalDialogState extends State<_SharedQuantityGoalDialog> {
  final _formKey = GlobalKey<FormState>();
  final _title = TextEditingController();
  final _target = TextEditingController(text: '10');
  final _unit = TextEditingController(text: 'times');
  final _operation = StableOperationId();
  DateTime _deadline = _dateOnly(DateTime.now().add(const Duration(days: 7)));
  String? _error;
  bool _authExpired = false;
  bool _submitting = false;

  @override
  void dispose() {
    _title.dispose();
    _target.dispose();
    _unit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('New shared goal'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('Create a shared total for ${widget.group.name}.'),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey('shared-goal-title-field'),
                controller: _title,
                enabled: !_submitting,
                autofocus: true,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Goal title'),
                validator: (value) =>
                    (value ?? '').trim().isEmpty ? 'Enter a goal title' : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('shared-goal-target-field'),
                controller: _target,
                enabled: !_submitting,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Target'),
                validator: (value) =>
                    (int.tryParse((value ?? '').trim()) ?? 0) < 1
                    ? 'Enter a positive whole number'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('shared-goal-unit-field'),
                controller: _unit,
                enabled: !_submitting,
                textInputAction: TextInputAction.done,
                decoration: const InputDecoration(labelText: 'Unit'),
                validator: (value) =>
                    (value ?? '').trim().isEmpty ? 'Enter a unit' : null,
              ),
              const SizedBox(height: 14),
              PlayfulButton.icon(
                key: const ValueKey('shared-goal-deadline'),
                icon: Icons.event_rounded,
                tone: PlayfulButtonTone.secondary,
                onPressed: _submitting ? null : _pickDeadline,
                label: Text(
                  'Deadline · ${DateFormat.yMMMd().format(_deadline)}',
                ),
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
            key: const ValueKey('shared-goal-reauth'),
            onPressed: _submitting ? null : _openAccount,
            child: const Text('Open account'),
          ),
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        PlayfulButton(
          key: const ValueKey('shared-goal-submit'),
          onPressed: _submitting ? null : _submit,
          child: Text(_submitting ? 'Creating…' : 'Create goal'),
        ),
      ],
    );
  }

  Future<void> _pickDeadline() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _deadline,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'Choose the finish day',
    );
    if (picked != null && mounted) {
      setState(() => _deadline = _dateOnly(picked));
    }
  }

  Future<void> _openAccount() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AccountPage(api: widget.api.api)),
    );
  }

  Future<void> _submit() async {
    if (_submitting || !(_formKey.currentState?.validate() ?? false)) return;
    final title = _title.text.trim();
    final target = int.parse(_target.text.trim());
    final unit = _unit.text.trim();
    final payload = <String, Object?>{
      'groupId': widget.group.id,
      'title': title,
      'target': target,
      'unit': unit,
      'deadline': _calendarDate(_deadline),
    };
    final operationId = _operation.forPayload(payload);
    setState(() {
      _submitting = true;
      _error = null;
      _authExpired = false;
    });
    try {
      final goal = await widget.api.createSharedQuantityGoal(
        widget.group.id,
        title: title,
        target: target,
        unit: unit,
        deadline: _deadline,
        operationId: operationId,
      );
      if (mounted) Navigator.pop(context, goal);
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _error = _safeCreateError(error);
          _authExpired = error is GroupsSignedOut;
        });
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}

DateTime _dateOnly(DateTime value) =>
    DateTime(value.year, value.month, value.day);

String _calendarDate(DateTime value) =>
    '${value.year.toString().padLeft(4, '0')}-'
    '${value.month.toString().padLeft(2, '0')}-'
    '${value.day.toString().padLeft(2, '0')}';

String _safeGoalListError(Object error) {
  if (error is GroupsSignedOut) return 'Your session has ended. Sign in again.';
  if (error is GroupsOffline) return error.message;
  if (error is GroupsSetupNeeded) {
    return 'Server setup is needed before shared goals can load.';
  }
  return 'Could not load shared goals. Try again.';
}

String _safeCreateError(Object error) {
  if (error is GroupsOffline) return error.message;
  if (error is GroupsSetupNeeded) {
    return 'Server setup is needed before shared goals can be changed.';
  }
  if (error is GroupsSignedOut) {
    return 'Your session has ended. Open Account to sign in again.';
  }
  if (error is GroupsPermissionDenied) {
    return 'This account can no longer change this group.';
  }
  if (error is GroupsRequestError) return error.message;
  return 'Could not create the shared goal. Try again.';
}
