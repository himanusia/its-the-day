import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/groups_api.dart';
import '../data/group_membership.dart';
import '../data/online_quantity_goals.dart';
import 'account_page.dart';
import 'playful_widgets.dart';

class OnlineQuantityGoalPage extends StatefulWidget {
  const OnlineQuantityGoalPage({
    super.key,
    required this.api,
    required this.goalId,
  });

  final GroupsApi api;
  final String goalId;

  @override
  State<OnlineQuantityGoalPage> createState() => _OnlineQuantityGoalPageState();
}

enum _OnlineGoalState {
  loading,
  online,
  signedOut,
  setup,
  offline,
  revoked,
  error,
}

class _OnlineQuantityGoalPageState extends State<OnlineQuantityGoalPage> {
  late final OnlineQuantityGoalsApi _goals;
  _OnlineGoalState _state = _OnlineGoalState.loading;
  OnlineQuantityGoalDetail? _detail;
  String? _error;
  bool _busy = false;
  bool _reloadedAfterAccountRecovery = false;
  bool _revokedDuringResult = false;

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
      _state = _OnlineGoalState.loading;
      _detail = null;
      _error = null;
    });
    try {
      final detail = await _goals.getGoal(widget.goalId);
      if (!mounted) return;
      setState(() {
        _detail = detail;
        _state = _OnlineGoalState.online;
      });
    } on GroupsSignedOut {
      if (mounted) setState(() => _state = _OnlineGoalState.signedOut);
    } on GroupsSetupNeeded {
      if (mounted) setState(() => _state = _OnlineGoalState.setup);
    } on GroupsOffline catch (error) {
      if (mounted) {
        setState(() {
          _state = _OnlineGoalState.offline;
          _error = error.message;
        });
      }
    } on GroupsPermissionDenied {
      if (mounted) {
        setState(() {
          _detail = null;
          _state = _OnlineGoalState.revoked;
          _error = null;
        });
      }
    } on GroupsRequestError catch (error) {
      if (mounted) {
        setState(() {
          _detail = null;
          _state = error.message == 'not_found'
              ? _OnlineGoalState.revoked
              : _OnlineGoalState.error;
          _error = error.message == 'not_found' ? null : error.message;
        });
      }
    } on Object catch (error) {
      if (mounted) {
        setState(() {
          _state = _OnlineGoalState.error;
          _error = _safeOnlineGoalError(error);
        });
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final title = _detail?.goal.title ?? 'Shared goal';
    return Scaffold(
      appBar: AppBar(
        title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: 'Refresh shared goal',
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
                  _OnlineGoalState.loading => const _OnlineGoalLoading(),
                  _OnlineGoalState.signedOut => _OnlineGoalStateCard(
                    icon: Icons.account_circle_outlined,
                    title: 'Sign in required',
                    message: 'Open your account to continue.',
                    actionLabel: 'Open account',
                    onAction: _openAccount,
                  ),
                  _OnlineGoalState.setup => _OnlineGoalStateCard(
                    icon: Icons.settings_suggest_outlined,
                    title: 'Server setup needed',
                    message: 'Connect this build to the configured server. Your local tracker is still available.',
                    actionLabel: 'Try again',
                    onAction: _load,
                  ),
                  _OnlineGoalState.offline => _OnlineGoalStateCard(
                    icon: Icons.cloud_off_outlined,
                    title: 'Offline',
                    message: _error ?? 'Could not reach the server. Your local tracker is still available.',
                    actionLabel: 'Try again',
                    onAction: _load,
                  ),
                  _OnlineGoalState.revoked => _OnlineGoalStateCard(
                    icon: Icons.lock_outline_rounded,
                    title: 'Group access revoked',
                    message: 'This shared goal is no longer available to this account.',
                    actionLabel: 'Try again',
                    onAction: _load,
                  ),
                  _OnlineGoalState.error => _OnlineGoalStateCard(
                    icon: Icons.error_outline_rounded,
                    title: 'Shared goal unavailable',
                    message:
                        _error ?? 'Could not load this shared goal. Try again.',
                    actionLabel: 'Try again',
                    onAction: _load,
                  ),
                  _OnlineGoalState.online => _OnlineGoalContent(
                    detail: _detail!,
                    busy: _busy,
                    onAdd: _addResult,
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

  void _markRevoked() {
    _revokedDuringResult = true;
    if (!mounted) return;
    setState(() {
      _detail = null;
      _state = _OnlineGoalState.revoked;
      _error = null;
    });
  }

  void _clearLoadedDetail() {
    _reloadedAfterAccountRecovery = false;
    if (!mounted) return;
    setState(() {
      _detail = null;
      _state = _OnlineGoalState.loading;
      _error = null;
    });
  }

  Future<void> _reloadAfterAccountRecovery() async {
    await _load();
    if (mounted) _reloadedAfterAccountRecovery = true;
  }

  Future<void> _addResult() async {
    if (_busy) return;
    _reloadedAfterAccountRecovery = false;
    _revokedDuringResult = false;
    final result = await showDialog<OnlineQuantityResult>(
      context: context,
      barrierDismissible: false,
      builder: (_) => _AddQuantityResultDialog(
        api: _goals,
        goalId: widget.goalId,
        onAccountRecoveryStart: _clearLoadedDetail,
        onAccountRecoveryComplete: _reloadAfterAccountRecovery,
        onAccessRevoked: _markRevoked,
      ),
    );
    if (!mounted) return;
    final reloadedAfterAccountRecovery = _reloadedAfterAccountRecovery;
    final revokedDuringResult = _revokedDuringResult;
    _reloadedAfterAccountRecovery = false;
    _revokedDuringResult = false;
    if (result == null &&
        (reloadedAfterAccountRecovery || revokedDuringResult)) {
      return;
    }
    await _load();
  }
}

class _OnlineGoalContent extends StatelessWidget {
  const _OnlineGoalContent({
    required this.detail,
    required this.busy,
    required this.onAdd,
  });

  final OnlineQuantityGoalDetail detail;
  final bool busy;
  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    final goal = detail.goal;
    final colors = Theme.of(context).colorScheme;
    final deadline = DateFormat.yMMMd().format(goal.deadline);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PlayfulPanel(
          padding: const EdgeInsets.fromLTRB(16, 15, 16, 16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                goal.title,
                style: Theme.of(context).textTheme.headlineSmall,
              ),
              const SizedBox(height: 14),
              Text(
                '${goal.completed} / ${goal.target} ${goal.unit}',
                style: Theme.of(context).textTheme.displaySmall
                    ?.copyWith(color: colors.primary),
              ),
              const SizedBox(height: 4),
              Text(
                '${goal.remaining} ${goal.unit} remaining',
                style: Theme.of(context).textTheme.titleMedium
                    ?.copyWith(color: colors.onSurface.withValues(alpha: .68)),
              ),
              const SizedBox(height: 14),
              PlayfulProgressBar(
                value: goal.progress,
                height: 12,
                semanticLabel:
                    '${goal.completed} of ${goal.target} ${goal.unit} complete',
              ),
              const SizedBox(height: 13),
              Wrap(
                spacing: 14,
                runSpacing: 5,
                children: [
                  Text(
                    'Target ${goal.target} ${goal.unit}',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: colors.onSurface.withValues(alpha: .66),
                    ),
                  ),
                  Text(
                    'Due $deadline',
                    style: Theme.of(context).textTheme.labelLarge?.copyWith(
                      color: colors.onSurface.withValues(alpha: .66),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const SizedBox(height: 18),
        PlayfulButton.icon(
          key: const ValueKey('online-add-result-action'),
          expand: true,
          icon: Icons.add_rounded,
          semanticLabel: 'Add a result',
          onPressed: busy ? null : onAdd,
          label: const Text('Add result'),
        ),
        const SizedBox(height: 20),
        Row(
          crossAxisAlignment: CrossAxisAlignment.baseline,
          textBaseline: TextBaseline.alphabetic,
          children: [
            Expanded(
              child: Text(
                'Results',
                style: Theme.of(context).textTheme.titleLarge,
              ),
            ),
            Text(
              '${goal.results.length}',
              style: Theme.of(context).textTheme.labelLarge
                  ?.copyWith(color: colors.onSurface.withValues(alpha: .52)),
            ),
          ],
        ),
        const SizedBox(height: 9),
        if (goal.results.isEmpty)
          PlayfulPanel(
            padding: const EdgeInsets.all(16),
            child: const Text('No results yet. Add the first contribution.'),
          )
        else
          for (final result in goal.results) ...[
            _ResultCard(goal: goal, result: result),
            const SizedBox(height: 10),
          ],
      ],
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.goal, required this.result});

  final OnlineQuantityGoal goal;
  final OnlineQuantityResult result;

  @override
  Widget build(BuildContext context) {
    final details = [
      DateFormat.yMMMd().add_jm().format(result.occurredAt.toLocal()),
      if (result.note != null) result.note!,
    ].join('\n');
    return PlayfulPanel(
      padding: const EdgeInsets.fromLTRB(13, 12, 13, 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            Icons.add_chart_rounded,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '+${result.amount} ${goal.unit}',
                  style: Theme.of(context).textTheme.titleMedium,
                ),
                const SizedBox(height: 4),
                Text(
                  details,
                  maxLines: 4,
                  overflow: TextOverflow.ellipsis,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.onSurface
                        .withValues(alpha: .64),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _OnlineGoalLoading extends StatelessWidget {
  const _OnlineGoalLoading();

  @override
  Widget build(BuildContext context) {
    return const Padding(
      padding: EdgeInsets.only(top: 80),
      child: Center(child: CircularProgressIndicator()),
    );
  }
}

class _OnlineGoalStateCard extends StatelessWidget {
  const _OnlineGoalStateCard({
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

class _AddQuantityResultDialog extends StatefulWidget {
  const _AddQuantityResultDialog({
    required this.api,
    required this.goalId,
    this.onAccountRecoveryStart,
    this.onAccountRecoveryComplete,
    this.onAccessRevoked,
  });

  final OnlineQuantityGoalsApi api;
  final String goalId;
  final VoidCallback? onAccountRecoveryStart;
  final Future<void> Function()? onAccountRecoveryComplete;
  final VoidCallback? onAccessRevoked;

  @override
  State<_AddQuantityResultDialog> createState() =>
      _AddQuantityResultDialogState();
}

class _AddQuantityResultDialogState extends State<_AddQuantityResultDialog> {
  final _formKey = GlobalKey<FormState>();
  final _amount = TextEditingController(text: '1');
  final _note = TextEditingController();
  final _operation = StableOperationId();
  String? _error;
  bool _authExpired = false;
  bool _submitting = false;

  @override
  void dispose() {
    _amount.dispose();
    _note.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Add result'),
      content: Form(
        key: _formKey,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextFormField(
                key: const ValueKey('online-result-amount-field'),
                controller: _amount,
                enabled: !_submitting,
                autofocus: true,
                keyboardType: TextInputType.number,
                textInputAction: TextInputAction.next,
                decoration: const InputDecoration(labelText: 'Amount'),
                validator: (value) =>
                    (int.tryParse((value ?? '').trim()) ?? 0) < 1
                    ? 'Enter a positive whole number'
                    : null,
              ),
              const SizedBox(height: 12),
              TextFormField(
                key: const ValueKey('online-result-note-field'),
                controller: _note,
                enabled: !_submitting,
                maxLines: 3,
                textInputAction: TextInputAction.newline,
                decoration: const InputDecoration(
                  labelText: 'Note (optional)',
                  alignLabelWithHint: true,
                ),
              ),
              const SizedBox(height: 14),
              InputDecorator(
                key: const ValueKey('online-result-date-field'),
                decoration: const InputDecoration(
                  labelText: 'Date',
                  helperText: 'Recorded by the server when you submit.',
                ),
                child: const Text('Assigned by server on submit'),
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
            key: const ValueKey('online-result-reauth'),
            onPressed: _submitting ? null : _openAccount,
            child: const Text('Open account'),
          ),
        TextButton(
          onPressed: _submitting ? null : () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        PlayfulButton(
          key: const ValueKey('online-result-submit'),
          onPressed: _submitting ? null : _submit,
          child: Text(_submitting ? 'Adding…' : 'Add result'),
        ),
      ],
    );
  }

  Future<void> _openAccount() async {
    widget.onAccountRecoveryStart?.call();
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AccountPage(api: widget.api.api)),
    );
    if (!mounted) return;
    final onComplete = widget.onAccountRecoveryComplete;
    if (onComplete != null) await onComplete();
  }

  Future<void> _submit() async {
    if (_submitting || !(_formKey.currentState?.validate() ?? false)) return;
    final amount = int.parse(_amount.text.trim());
    final note = _note.text.trim();
    final operationId = _operation.forPayload({'amount': amount, 'note': note});
    setState(() {
      _submitting = true;
      _error = null;
      _authExpired = false;
    });
    try {
      final result = await widget.api.addResult(
        widget.goalId,
        amount,
        note: note,
        operationId: operationId,
      );
      if (mounted) Navigator.pop(context, result);
    } on Object catch (error) {
      if (_isRevokedResultError(error)) widget.onAccessRevoked?.call();
      if (mounted) {
        setState(() {
          _error = _safeResultError(error);
          _authExpired = error is GroupsSignedOut;
        });
      }
    } finally {
      if (mounted) setState(() => _submitting = false);
    }
  }
}

bool _isRevokedResultError(Object error) =>
    error is GroupsPermissionDenied ||
    (error is GroupsRequestError && error.message == 'not_found');

String _safeOnlineGoalError(Object error) {
  if (error is GroupsOffline) return error.message;
  if (error is GroupsSetupNeeded) {
    return 'Server setup is needed before this shared goal can load.';
  }
  return 'Could not load this shared goal. Try again.';
}

String _safeResultError(Object error) {
  if (error is GroupsOffline) return error.message;
  if (error is GroupsSetupNeeded) {
    return 'Server setup is needed before results can be added.';
  }
  if (error is GroupsSignedOut) {
    return 'Your session has ended. Open Account to sign in again.';
  }
  if (error is GroupsPermissionDenied) {
    return 'This shared goal is no longer available to this account.';
  }
  if (error is GroupsRequestError && error.message == 'not_found') {
    return 'This shared goal is no longer available to this account.';
  }
  return 'Could not add the result. Try again.';
}
