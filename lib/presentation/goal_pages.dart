import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../domain/goal.dart';
import 'itstheday_controller.dart';
import 'day_illustrations.dart';
import 'brand_mark.dart';
import 'playful_widgets.dart';

String newGoalId() => 'g-${DateTime.now().microsecondsSinceEpoch}';

class GoalEditorPage extends StatefulWidget {
  const GoalEditorPage({super.key, required this.controller, this.goal});

  final ItsTheDayController controller;
  final Goal? goal;

  @override
  State<GoalEditorPage> createState() => _GoalEditorPageState();
}

class _GoalEditorPageState extends State<GoalEditorPage> {
  final form = GlobalKey<FormState>();
  late final TextEditingController title = TextEditingController(
    text: widget.goal?.title ?? '',
  );
  late final TextEditingController target = TextEditingController(
    text: '${widget.goal?.target ?? 10}',
  );
  late final TextEditingController unit = TextEditingController(
    text: widget.goal?.unit ?? 'times',
  );
  late GoalKind kind = widget.goal?.kind ?? GoalKind.quantity;
  late DateTime deadline =
      (widget.goal?.deadline ?? DateTime.now().add(const Duration(days: 7)))
          .toLocal();
  bool saving = false;

  @override
  void dispose() {
    title.dispose();
    target.dispose();
    unit.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.goal == null ? 'New goal' : 'Edit goal'),
      ),
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            return Align(
              alignment: Alignment.topCenter,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 620),
                child: Form(
                  key: form,
                  child: ListView(
                    padding: const EdgeInsets.fromLTRB(18, 8, 18, 28),
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    children: [
                      Text(
                        widget.goal == null
                            ? 'Give today a small, clear direction.'
                            : 'Keep the target useful and easy to return to.',
                        style: Theme.of(context).textTheme.bodyLarge?.copyWith(
                          color: Theme.of(context).colorScheme.onSurface
                              .withValues(alpha: .68),
                        ),
                      ),
                      const SizedBox(height: 18),
                      Text(
                        'Shape',
                        style: Theme.of(context).textTheme.labelLarge,
                      ),
                      const SizedBox(height: 9),
                      PlayfulChoice(
                        icon: Icons.trending_up_rounded,
                        label: 'Quantity',
                        description: 'Build a total, one entry at a time.',
                        selected: kind == GoalKind.quantity,
                        onTap: widget.goal == null
                            ? () => setState(() => kind = GoalKind.quantity)
                            : null,
                      ),
                      const SizedBox(height: 9),
                      PlayfulChoice(
                        icon: Icons.checklist_rounded,
                        label: 'Checklist',
                        description: 'Finish a short set of named steps.',
                        selected: kind == GoalKind.checklist,
                        onTap: widget.goal == null
                            ? () => setState(() => kind = GoalKind.checklist)
                            : null,
                      ),
                      const SizedBox(height: 18),
                      TextFormField(
                        controller: title,
                        textInputAction: TextInputAction.next,
                        decoration: const InputDecoration(
                          labelText: 'Goal name',
                          hintText: 'For example, learn Italian',
                        ),
                        validator: (value) =>
                            value == null || value.trim().isEmpty
                            ? 'Enter a name'
                            : null,
                      ),
                      if (kind == GoalKind.quantity) ...[
                        const SizedBox(height: 13),
                        TextFormField(
                          controller: target,
                          keyboardType: TextInputType.number,
                          textInputAction: TextInputAction.next,
                          decoration: const InputDecoration(
                            labelText: 'Target',
                            hintText: 'A positive whole number',
                          ),
                          validator: (value) =>
                              (int.tryParse(value?.trim() ?? '') ?? 0) < 1
                              ? 'Enter a positive whole number'
                              : null,
                        ),
                        const SizedBox(height: 13),
                        TextFormField(
                          controller: unit,
                          textInputAction: TextInputAction.done,
                          decoration: const InputDecoration(
                            labelText: 'Unit',
                            hintText: 'For example, pages or minutes',
                          ),
                          validator: (value) =>
                              value == null || value.trim().isEmpty
                              ? 'Enter a unit'
                              : null,
                        ),
                      ] else ...[
                        const SizedBox(height: 13),
                        Container(
                          padding: const EdgeInsets.all(15),
                          decoration: BoxDecoration(
                            color: Theme.of(context)
                                .colorScheme
                                .surfaceContainerHighest
                                .withValues(alpha: .6),
                            borderRadius: BorderRadius.circular(18),
                          ),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Icon(
                                Icons.lightbulb_outline_rounded,
                                color: Theme.of(context).colorScheme.secondary,
                              ),
                              const SizedBox(width: 10),
                              Expanded(
                                child: Text(
                                  'You can add the checklist steps after saving.',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                      const SizedBox(height: 17),
                      PlayfulButton.icon(
                        icon: Icons.event_rounded,
                        tone: PlayfulButtonTone.secondary,
                        expand: true,
                        semanticLabel: 'Choose goal deadline',
                        onPressed: saving ? null : _pickDeadline,
                        label: Text(
                          'Deadline · ${DateFormat.yMMMd().format(deadline)}',
                          textAlign: TextAlign.left,
                        ),
                      ),
                      const SizedBox(height: 22),
                      PlayfulButton(
                        expand: true,
                        semanticLabel: 'Save goal',
                        onPressed: saving ? null : _save,
                        child: Text(saving ? 'Saving…' : 'Save goal'),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Future<void> _pickDeadline() async {
    if (saving) return;
    final picked = await showDatePicker(
      context: context,
      initialDate: deadline,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
      helpText: 'Choose the finish day',
    );
    if (picked != null && mounted) {
      setState(() {
        deadline = DateTime(picked.year, picked.month, picked.day);
      });
    }
  }

  Goal? _latestGoal() {
    if (widget.goal == null) return null;
    for (final goal in widget.controller.goals) {
      if (goal.id == widget.goal!.id) return goal;
    }
    return widget.goal;
  }

  Future<void> _save() async {
    if (saving) return;
    FocusScope.of(context).unfocus();
    if (!form.currentState!.validate()) return;

    setState(() => saving = true);
    var popped = false;
    final previous = _latestGoal();
    final next = Goal(
      id: previous?.id ?? newGoalId(),
      title: title.text.trim(),
      kind: kind,
      deadline: deadline,
      target: kind == GoalKind.quantity ? int.parse(target.text.trim()) : 1,
      unit: kind == GoalKind.quantity ? unit.text.trim() : '',
      // Keep mutations made in the detail page while this editor was open.
      entries: previous?.entries ?? const [],
      items: previous?.items ?? const [],
    );

    try {
      await widget.controller.saveGoal(next);
      if (mounted) {
        popped = true;
        Navigator.of(context).pop();
      }
    } catch (error) {
      if (mounted) _showMessage('Could not save goal: $error');
    } finally {
      if (mounted && !popped) setState(() => saving = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class GoalDetailPage extends StatefulWidget {
  const GoalDetailPage({
    super.key,
    required this.controller,
    required this.goalId,
  });

  final ItsTheDayController controller;
  final String goalId;

  @override
  State<GoalDetailPage> createState() => _GoalDetailPageState();
}

class _GoalDetailPageState extends State<GoalDetailPage> {
  bool busy = false;
  bool _editorOpen = false;
  bool _celebrating = false;
  int _celebrationKey = 0;

  Goal? get goal {
    for (final item in widget.controller.goals) {
      if (item.id == widget.goalId) return item;
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.controller,
      builder: (context, _) {
        final current = goal;
        if (current == null) {
          return const Scaffold(body: Center(child: Text('Goal removed')));
        }
        final status = current.statusAt(DateTime.now());
        return Scaffold(
          appBar: AppBar(
            title: Text(
              current.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            actions: [
              IconButton(
                tooltip: 'Edit goal',
                onPressed: busy || _editorOpen
                    ? null
                    : () => Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => GoalEditorPage(
                            controller: widget.controller,
                            goal: current,
                          ),
                        ),
                      ),
                icon: const Icon(Icons.edit_outlined),
              ),
              IconButton(
                tooltip: 'Delete goal',
                onPressed: busy || _editorOpen
                    ? null
                    : () => _deleteGoal(current),
                icon: const Icon(Icons.delete_outline_rounded),
              ),
            ],
          ),
          body: SafeArea(
            child: Stack(
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 720),
                    child: ListView(
                      padding: const EdgeInsets.fromLTRB(18, 8, 18, 30),
                      keyboardDismissBehavior:
                          ScrollViewKeyboardDismissBehavior.onDrag,
                      children: [
                        _GoalSummaryCard(goal: current, status: status),
                        const SizedBox(height: 20),
                        if (current.kind == GoalKind.quantity)
                          _quantityContent(current)
                        else
                          _checklistContent(current),
                      ],
                    ),
                  ),
                ),
                if (_celebrating)
                  CelebrationBurst(
                    key: ValueKey(_celebrationKey),
                    onFinished: () {
                      if (mounted) setState(() => _celebrating = false);
                    },
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _quantityContent(Goal current) {
    final entries = current.entries.where((entry) => !entry.deleted).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PlayfulButton.icon(
          expand: true,
          icon: Icons.add_rounded,
          semanticLabel: 'Add a progress entry',
          onPressed: busy || _editorOpen ? null : () => _addEntry(current),
          label: const Text('Add result'),
        ),
        const SizedBox(height: 8),
        Align(
          alignment: Alignment.centerLeft,
          child: PlayfulButton.icon(
            icon: Icons.add_rounded,
            tone: PlayfulButtonTone.quiet,
            semanticLabel: 'Quickly add one ${current.unit}',
            onPressed: busy || _editorOpen
                ? null
                : () => _addEntry(current, quick: true),
            label: const Text('Quick +1'),
          ),
        ),
        const SizedBox(height: 20),
        if (entries.isEmpty) ...[
          _EntrySectionLabel(count: 0),
          const SizedBox(height: 9),
          _EmptyGoalHint(
            icon: Icons.edit_note_rounded,
            text: 'Your first result will show here.',
          ),
        ] else ...[
          _EntrySectionLabel(count: entries.length),
          const SizedBox(height: 9),
          for (final entry in entries)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _EntryCard(
                goal: current,
                entry: entry,
                busy: busy || _editorOpen,
                onEdit: () => _editEntry(current, entry),
                onDelete: () => _deleteEntry(current, entry),
              ),
            ),
        ],
      ],
    );
  }

  Widget _checklistContent(Goal current) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        PlayfulButton.icon(
          icon: Icons.add_rounded,
          semanticLabel: 'Add checklist item',
          onPressed: busy || _editorOpen ? null : () => _itemDialog(current),
          label: const Text('Add item'),
        ),
        const SizedBox(height: 14),
        if (current.items.isEmpty)
          _EmptyGoalHint(
            icon: Icons.checklist_rounded,
            text: 'Add a few steps, then check them off as you go.',
          )
        else
          for (final item in current.items)
            Padding(
              padding: const EdgeInsets.only(bottom: 10),
              child: _ChecklistCard(
                item: item,
                busy: busy || _editorOpen,
                onChanged: (checked) => _run(
                  () => widget.controller.setItemChecked(
                    current.id,
                    item.id,
                    checked,
                  ),
                ),
                onTap: () => _run(
                  () => widget.controller.setItemChecked(
                    current.id,
                    item.id,
                    !item.checked,
                  ),
                ),
                onEdit: () => _itemDialog(current, item: item),
              ),
            ),
      ],
    );
  }

  Future<bool> _run(Future<void> Function() operation) async {
    if (busy || !mounted) return false;
    final wasComplete = goal?.isComplete ?? false;
    setState(() => busy = true);
    try {
      await operation();
      if (mounted) {
        final nowComplete = goal?.isComplete ?? false;
        if (!wasComplete && nowComplete) {
          setState(() {
            _celebrationKey++;
            _celebrating = true;
          });
        } else if (wasComplete && !nowComplete) {
          _celebrating = false;
        }
      }
      return true;
    } catch (error) {
      if (mounted) _showMessage('Could not save: $error');
      return false;
    } finally {
      if (mounted) setState(() => busy = false);
    }
  }

  Future<bool> _confirm(String message) async {
    return await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Delete this?'),
            content: Text(message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Keep it'),
              ),
              PlayfulButton(
                tone: PlayfulButtonTone.danger,
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
  }

  Future<void> _deleteGoal(Goal current) async {
    if (busy ||
        _editorOpen ||
        !await _confirm('Delete ${current.title} and its progress?')) {
      return;
    }
    final deleted = await _run(() => widget.controller.deleteGoal(current.id));
    if (deleted && mounted && goal == null) Navigator.of(context).pop();
  }

  Future<void> _deleteEntry(Goal current, GoalEntry entry) async {
    if (busy || _editorOpen || !await _confirm('Delete this progress entry?')) {
      return;
    }
    await _run(() => widget.controller.deleteEntry(current.id, entry.id));
  }

  Future<void> _addEntry(Goal current, {bool quick = false}) async {
    if (busy || _editorOpen) return;
    if (quick) {
      await _run(
        () => widget.controller.addEntry(
          current.id,
          GoalEntry(id: newGoalId(), amount: 1, at: DateTime.now()),
        ),
      );
      return;
    }
    await _entryDialog(current);
  }

  Future<void> _editEntry(Goal current, GoalEntry entry) =>
      _entryDialog(current, entry: entry);

  Future<void> _entryDialog(Goal current, {GoalEntry? entry}) async {
    if (busy || _editorOpen || !mounted) return;
    setState(() => _editorOpen = true);
    try {
      await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _EntryEditorDialog(
          entry: entry,
          onSave: (next) => _run(
            () => entry == null
                ? widget.controller.addEntry(current.id, next)
                : widget.controller.editEntry(current.id, next),
          ),
        ),
      );
    } finally {
      if (mounted) setState(() => _editorOpen = false);
    }
  }

  Future<void> _itemDialog(Goal current, {ChecklistItem? item}) async {
    if (busy || _editorOpen || !mounted) return;
    setState(() => _editorOpen = true);
    try {
      await showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (_) => _ChecklistItemDialog(
          item: item,
          onSave: (next) {
            final latest = goal;
            if (latest == null) return Future.value(false);
            return _run(
              () => widget.controller.saveGoal(
                latest.copyWith(
                  items: [
                    for (final old in latest.items)
                      old.id == next.id ? next : old,
                    if (item == null) next,
                  ],
                ),
              ),
            );
          },
          onDelete: item == null
              ? null
              : () {
                  final latest = goal;
                  if (latest == null) return Future.value(false);
                  return _run(
                    () => widget.controller.saveGoal(
                      latest.copyWith(
                        items: latest.items
                            .where((old) => old.id != item.id)
                            .toList(),
                      ),
                    ),
                  );
                },
        ),
      );
    } finally {
      if (mounted) setState(() => _editorOpen = false);
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _GoalSummaryCard extends StatelessWidget {
  const _GoalSummaryCard({required this.goal, required this.status});

  final Goal goal;
  final GoalStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final unit = goal.kind == GoalKind.quantity ? goal.unit : 'items';
    final remaining = _remaining(goal);
    final now = DateTime.now();
    final accent = switch (status) {
      GoalStatus.upcoming => colors.primary,
      GoalStatus.today => colors.secondary,
      GoalStatus.overdue => colors.error,
      GoalStatus.completed => colors.tertiary,
    };
    return PlayfulPanel(
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 15),
      borderColor: accent.withValues(alpha: .52),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 7,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _StatusBadge(status: status),
                    Text(
                      goal.kind == GoalKind.quantity ? 'QUANTITY' : 'CHECKLIST',
                      style: Theme.of(context).textTheme.labelMedium?.copyWith(
                        color: colors.onSurface.withValues(alpha: .52),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              ClockSparkIllustration(
                size: 44,
                state: _goalClockState(status),
                semanticLabel: 'Goal status illustration',
              ),
            ],
          ),
          const SizedBox(height: 12),
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '${goal.completed} / ${goal.goalTarget} $unit',
                      style: Theme.of(context).textTheme.displaySmall
                          ?.copyWith(color: accent),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${_countLabel(remaining, unit)} remaining',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: colors.onSurface.withValues(alpha: .68),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Flexible(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(
                      _daysLeftLabel(goal.deadline, status, now),
                      textAlign: TextAlign.end,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium?.copyWith(
                        color: accent,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      status == GoalStatus.completed
                          ? 'Target reached'
                          : 'Due ${DateFormat.MMMd().format(goal.deadline.toLocal())}',
                      textAlign: TextAlign.end,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurface.withValues(alpha: .6),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          PlayfulProgressBar(
            value: goal.progress,
            height: 12,
            semanticLabel:
                '${goal.completed} of ${goal.goalTarget} $unit complete',
          ),
          const SizedBox(height: 10),
          Wrap(
            spacing: 14,
            runSpacing: 4,
            children: [
              Text(
                'Target ${goal.goalTarget} $unit',
                style: Theme.of(context).textTheme.labelLarge
                    ?.copyWith(color: colors.onSurface.withValues(alpha: .66)),
              ),
              Text(
                'Pace ${_paceLabel(goal, now)}',
                style: Theme.of(context).textTheme.labelLarge
                    ?.copyWith(color: colors.onSurface.withValues(alpha: .66)),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({required this.status});

  final GoalStatus status;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = switch (status) {
      GoalStatus.upcoming => colors.primary,
      GoalStatus.today => colors.secondary,
      GoalStatus.overdue => colors.error,
      GoalStatus.completed => colors.tertiary,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: .4)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            switch (status) {
              GoalStatus.upcoming => Icons.arrow_forward_rounded,
              GoalStatus.today => Icons.wb_sunny_outlined,
              GoalStatus.overdue => Icons.history_rounded,
              GoalStatus.completed => Icons.check_rounded,
            },
            size: 14,
            color: color,
          ),
          const SizedBox(width: 5),
          Flexible(
            child: Text(
              _statusLabel(status),
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: color),
            ),
          ),
        ],
      ),
    );
  }
}

class _EntrySectionLabel extends StatelessWidget {
  const _EntrySectionLabel({required this.count});

  final int count;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Text('Entries', style: Theme.of(context).textTheme.titleMedium),
        const SizedBox(width: 8),
        Text(
          '$count',
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
            color: Theme.of(context).colorScheme.onSurface
                .withValues(alpha: .52),
          ),
        ),
      ],
    );
  }
}

class _EntryCard extends StatelessWidget {
  const _EntryCard({
    required this.goal,
    required this.entry,
    required this.busy,
    required this.onEdit,
    required this.onDelete,
  });

  final Goal goal;
  final GoalEntry entry;
  final bool busy;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final title = entry.title?.isNotEmpty == true
        ? entry.title!
        : '+${entry.amount} ${goal.unit}';
    final details = [
      DateFormat.yMMMd().add_jm().format(entry.at.toLocal()),
      if (entry.note?.isNotEmpty == true) entry.note!,
      if (entry.url?.isNotEmpty == true) entry.url!,
    ].join('\n');
    return PlayfulPanel(
      padding: const EdgeInsets.fromLTRB(12, 11, 4, 11),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: colors.primaryContainer.withValues(alpha: .7),
              borderRadius: BorderRadius.circular(11),
              border: Border.all(color: colors.primary.withValues(alpha: .35)),
            ),
            child: Icon(Icons.add_chart_rounded, color: colors.primary),
          ),
          const SizedBox(width: 11),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(
                  details,
                  maxLines: 5,
                  overflow: TextOverflow.ellipsis,
                  softWrap: true,
                  style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: colors.onSurface.withValues(alpha: .64),
                  ),
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            tooltip: 'Entry actions',
            enabled: !busy,
            onSelected: (value) {
              if (value == 'edit') onEdit();
              if (value == 'delete') onDelete();
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'edit', child: Text('Edit entry')),
              PopupMenuItem(value: 'delete', child: Text('Delete entry')),
            ],
          ),
        ],
      ),
    );
  }
}

class _ChecklistCard extends StatelessWidget {
  const _ChecklistCard({
    required this.item,
    required this.busy,
    required this.onChanged,
    required this.onTap,
    required this.onEdit,
  });

  final ChecklistItem item;
  final bool busy;
  final ValueChanged<bool> onChanged;
  final VoidCallback onTap;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final titleStyle = Theme.of(context).textTheme.titleMedium?.copyWith(
      decoration: item.checked ? TextDecoration.lineThrough : null,
      color: item.checked
          ? colors.onSurface.withValues(alpha: .56)
          : colors.onSurface,
    );
    return TactileSurface(
      onTap: busy ? () {} : onTap,
      semanticLabel:
          '${item.title}, ${item.checked ? 'completed' : 'not completed'}',
      child: PlayfulPanel(
        padding: const EdgeInsets.fromLTRB(7, 7, 4, 7),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            PlayfulCheck(
              value: item.checked,
              label:
                  '${item.title}, ${item.checked ? 'completed' : 'not completed'}',
              onChanged: busy ? null : onChanged,
            ),
            const SizedBox(width: 5),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(top: 10, bottom: 5),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(item.title, style: titleStyle),
                    if (item.explanation?.isNotEmpty == true) ...[
                      const SizedBox(height: 4),
                      Text(
                        item.explanation!,
                        softWrap: true,
                        style: Theme.of(context).textTheme.bodySmall?.copyWith(
                          color: colors.onSurface.withValues(alpha: .62),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            IconButton(
              tooltip: 'Edit ${item.title}',
              onPressed: busy ? null : onEdit,
              icon: const Icon(Icons.edit_outlined),
            ),
          ],
        ),
      ),
    );
  }
}

class _EmptyGoalHint extends StatelessWidget {
  const _EmptyGoalHint({required this.icon, required this.text});

  final IconData icon;
  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return PlayfulPanel(
      bottomEdge: false,
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Icon(icon, color: colors.secondary),
          const SizedBox(width: 11),
          Expanded(
            child: Text(text, style: Theme.of(context).textTheme.bodyLarge),
          ),
        ],
      ),
    );
  }
}

class _EntryEditorDialog extends StatefulWidget {
  const _EntryEditorDialog({required this.entry, required this.onSave});

  final GoalEntry? entry;
  final Future<bool> Function(GoalEntry entry) onSave;

  @override
  State<_EntryEditorDialog> createState() => _EntryEditorDialogState();
}

class _EntryEditorDialogState extends State<_EntryEditorDialog> {
  final form = GlobalKey<FormState>();
  late final TextEditingController amount = TextEditingController(
    text: '${widget.entry?.amount ?? 1}',
  );
  late final TextEditingController title = TextEditingController(
    text: widget.entry?.title ?? '',
  );
  late final TextEditingController note = TextEditingController(
    text: widget.entry?.note ?? '',
  );
  late final TextEditingController url = TextEditingController(
    text: widget.entry?.url ?? '',
  );
  late DateTime at = (widget.entry?.at ?? DateTime.now()).toLocal();
  bool saving = false;

  @override
  void dispose() {
    amount.dispose();
    title.dispose();
    note.dispose();
    url.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * .62;
    return AlertDialog(
      title: Text(widget.entry == null ? 'Add progress' : 'Edit progress'),
      content: SizedBox(
        height: maxHeight.clamp(260.0, 560.0).toDouble(),
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Form(
            key: form,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                TextFormField(
                  controller: amount,
                  keyboardType: TextInputType.number,
                  decoration: const InputDecoration(labelText: 'Amount'),
                  validator: (value) =>
                      (int.tryParse(value?.trim() ?? '') ?? 0) < 1
                      ? 'Positive whole number required'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: title,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(
                    labelText: 'Title (optional)',
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: note,
                  maxLines: 3,
                  textInputAction: TextInputAction.newline,
                  decoration: const InputDecoration(
                    labelText: 'Note (optional)',
                    alignLabelWithHint: true,
                  ),
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: url,
                  keyboardType: TextInputType.url,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: 'Link (http(s), optional)',
                    hintText: 'https://…',
                  ),
                  validator: _urlValidator,
                ),
                const SizedBox(height: 16),
                Text(
                  'When did it happen?',
                  style: Theme.of(context).textTheme.labelLarge,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    PlayfulButton.icon(
                      icon: Icons.calendar_today_rounded,
                      tone: PlayfulButtonTone.secondary,
                      onPressed: saving ? null : _pickDate,
                      label: Text(DateFormat.yMMMd().format(at)),
                    ),
                    PlayfulButton.icon(
                      icon: Icons.schedule_rounded,
                      tone: PlayfulButtonTone.secondary,
                      onPressed: saving ? null : _pickTime,
                      label: Text(DateFormat.jm().format(at)),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        PlayfulButton(
          onPressed: saving ? null : _save,
          child: Text(saving ? 'Saving…' : 'Save'),
        ),
      ],
    );
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: at,
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null && mounted) {
      setState(() {
        at = DateTime(
          picked.year,
          picked.month,
          picked.day,
          at.hour,
          at.minute,
        );
      });
    }
  }

  Future<void> _pickTime() async {
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(at),
    );
    if (picked != null && mounted) {
      setState(() {
        at = DateTime(at.year, at.month, at.day, picked.hour, picked.minute);
      });
    }
  }

  Future<void> _save() async {
    if (saving || !form.currentState!.validate()) return;
    setState(() => saving = true);
    final next = GoalEntry(
      id: widget.entry?.id ?? newGoalId(),
      amount: int.parse(amount.text.trim()),
      at: at,
      title: _optional(title.text),
      note: _optional(note.text),
      url: _optional(url.text),
    );
    final saved = await widget.onSave(next);
    if (!mounted) return;
    if (saved) {
      Navigator.pop(context, true);
    } else {
      // Keep every controller and the selected timestamp intact for retry.
      setState(() => saving = false);
    }
  }
}

class _ChecklistItemDialog extends StatefulWidget {
  const _ChecklistItemDialog({
    required this.item,
    required this.onSave,
    this.onDelete,
  });

  final ChecklistItem? item;
  final Future<bool> Function(ChecklistItem item) onSave;
  final Future<bool> Function()? onDelete;

  @override
  State<_ChecklistItemDialog> createState() => _ChecklistItemDialogState();
}

class _ChecklistItemDialogState extends State<_ChecklistItemDialog> {
  final form = GlobalKey<FormState>();
  late final TextEditingController title = TextEditingController(
    text: widget.item?.title ?? '',
  );
  late final TextEditingController explanation = TextEditingController(
    text: widget.item?.explanation ?? '',
  );
  bool saving = false;

  @override
  void dispose() {
    title.dispose();
    explanation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final maxHeight = MediaQuery.sizeOf(context).height * .52;
    return AlertDialog(
      title: Text(
        widget.item == null ? 'Add checklist item' : 'Edit checklist item',
      ),
      content: SizedBox(
        height: maxHeight.clamp(190.0, 420.0).toDouble(),
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Form(
            key: form,
            child: Column(
              children: [
                TextFormField(
                  controller: title,
                  textInputAction: TextInputAction.next,
                  decoration: const InputDecoration(labelText: 'Item name'),
                  validator: (value) => value == null || value.trim().isEmpty
                      ? 'Enter a name'
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: explanation,
                  maxLines: 4,
                  textInputAction: TextInputAction.newline,
                  decoration: const InputDecoration(
                    labelText: 'Explanation (optional)',
                    alignLabelWithHint: true,
                    hintText: 'A helpful little reminder',
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
      actions: [
        if (widget.item != null && widget.onDelete != null)
          TextButton(
            onPressed: saving ? null : _delete,
            child: const Text('Delete'),
          ),
        TextButton(
          onPressed: saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        PlayfulButton(
          onPressed: saving ? null : _save,
          child: Text(saving ? 'Saving…' : 'Save'),
        ),
      ],
    );
  }

  Future<void> _save() async {
    if (saving || !form.currentState!.validate()) return;
    setState(() => saving = true);
    final next = ChecklistItem(
      id: widget.item?.id ?? newGoalId(),
      title: title.text.trim(),
      checked: widget.item?.checked ?? false,
      explanation: _optional(explanation.text),
    );
    final saved = await widget.onSave(next);
    if (!mounted) return;
    if (saved) {
      Navigator.pop(context, true);
    } else {
      setState(() => saving = false);
    }
  }

  Future<void> _delete() async {
    if (saving || widget.onDelete == null) return;
    final confirmed =
        await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Delete checklist item?'),
            content: Text('“${title.text.trim()}” will be removed.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Keep it'),
              ),
              PlayfulButton(
                tone: PlayfulButtonTone.danger,
                onPressed: () => Navigator.pop(dialogContext, true),
                child: const Text('Delete'),
              ),
            ],
          ),
        ) ??
        false;
    if (!confirmed || !mounted) return;
    setState(() => saving = true);
    final deleted = await widget.onDelete!();
    if (!mounted) return;
    if (deleted) {
      Navigator.pop(context, true);
    } else {
      setState(() => saving = false);
    }
  }
}

String? _urlValidator(String? value) {
  final trimmed = value?.trim() ?? '';
  if (trimmed.isEmpty) return null;
  final uri = Uri.tryParse(trimmed);
  if (uri == null ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    return 'Use http or https';
  }
  return null;
}

String? _optional(String value) {
  final trimmed = value.trim();
  return trimmed.isEmpty ? null : trimmed;
}

int _remaining(Goal goal) =>
    (goal.goalTarget - goal.completed).clamp(0, goal.goalTarget).toInt();

String _countLabel(int count, String unit) => '$count $unit';

String _paceLabel(Goal goal, DateTime now) {
  final pace = goal.paceAt(now);
  if (pace == null) return goal.isComplete ? 'complete' : '—';
  final unit = goal.kind == GoalKind.quantity ? goal.unit : 'items';
  return '$pace $unit/day';
}

ClockSparkState _goalClockState(GoalStatus status) => switch (status) {
  GoalStatus.upcoming => ClockSparkState.ready,
  GoalStatus.today => ClockSparkState.inProgress,
  GoalStatus.overdue => ClockSparkState.overdue,
  GoalStatus.completed => ClockSparkState.complete,
};

String _daysLeftLabel(DateTime deadline, GoalStatus status, DateTime now) {
  if (status == GoalStatus.completed) return 'Complete';
  final today = DateTime(now.year, now.month, now.day);
  final due = DateTime(deadline.year, deadline.month, deadline.day);
  final difference = due.difference(today).inDays;
  if (status == GoalStatus.today) return 'Today';
  if (status == GoalStatus.overdue) {
    final days = difference.abs();
    return '${days == 1 ? 1 : days} day${days == 1 ? '' : 's'} overdue';
  }
  return '${difference == 1 ? 1 : difference} day${difference == 1 ? '' : 's'} left';
}

String _statusLabel(GoalStatus status) => switch (status) {
  GoalStatus.upcoming => 'ON THE WAY',
  GoalStatus.today => 'DUE TODAY',
  GoalStatus.overdue => 'PAST DUE',
  GoalStatus.completed => 'COMPLETE',
};
