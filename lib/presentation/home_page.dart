import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/groups_api.dart';
import '../domain/countdown.dart';
import '../domain/goal.dart';
import '../domain/itstheday_event.dart';
import '../platform/platform_interfaces.dart';
import 'account_page.dart';
import 'brand_mark.dart';
import 'calendar_import_page.dart';
import 'day_illustrations.dart';
import 'event_editor_page.dart';
import 'goal_pages.dart';
import 'itstheday_controller.dart';
import 'itstheday_theme.dart';
import 'playful_widgets.dart';
import 'groups_page.dart';

class HomePage extends StatefulWidget {
  const HomePage({
    super.key,
    required this.controller,
    required this.accountApi,
  });

  final ItsTheDayController controller;
  final GroupsApi accountApi;

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  Timer? _ticker;
  bool _working = false;
  static const _widgetChannel = MethodChannel('itstheday/widget');

  ItsTheDayController get _controller => widget.controller;

  @override
  void initState() {
    super.initState();
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      _widgetChannel.setMethodCallHandler((call) async {
        if (call.method == 'openWidgetFocus') {
          await _openWidgetFocus(call.arguments);
        }
      });
      WidgetsBinding.instance.addPostFrameCallback((_) async {
        try {
          await _openWidgetFocus(
            await _widgetChannel.invokeMethod('getLaunchFocus'),
          );
        } on PlatformException {
          // The launcher has no widget focus.
        }
      });
    }
    // This timer exists only while the foreground page is mounted. Persistent
    // reminders use the notification scheduler rather than a background loop.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) _controller.refreshCountdown();
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      _widgetChannel.setMethodCallHandler(null);
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final selectedEvent = _controller.selectedEvent;
        final selectedGoal = _controller.selectedGoal;
        final goals = _controller.goals
            .where(
              (goal) => selectedEvent != null || goal.id != selectedGoal?.id,
            )
            .toList();
        final marks = _controller.events
            .where((event) => event.id != selectedEvent?.id)
            .toList();

        return Scaffold(
          body: SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final horizontal = constraints.maxWidth >= 700 ? 36.0 : 18.0;
                return Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 760),
                    child: CustomScrollView(
                      slivers: [
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(
                            horizontal,
                            14,
                            horizontal,
                            0,
                          ),
                          sliver: SliverToBoxAdapter(
                            child: _Header(
                              onImport: _openCalendarImport,
                              onAccount: _openAccount,
                              onAdd: () => _openEditor(),
                              onGroups: () => Navigator.push(
                                context,
                                MaterialPageRoute(
                                  builder: (_) =>
                                      GroupsPage(api: widget.accountApi),
                                ),
                              ),
                            ),
                          ),
                        ),
                        if (selectedEvent != null || selectedGoal != null)
                          SliverPadding(
                            padding: EdgeInsets.fromLTRB(
                              horizontal,
                              18,
                              horizontal,
                              0,
                            ),
                            sliver: SliverToBoxAdapter(
                              child: selectedEvent != null
                                  ? _FocusEventRow(
                                      event: selectedEvent,
                                      snapshot: _controller.countdownFor(
                                        selectedEvent,
                                      ),
                                      onTap: () => _selectEvent(selectedEvent),
                                      onEdit: () => _openEditor(selectedEvent),
                                      onDelete: () =>
                                          _deleteEvent(selectedEvent),
                                    )
                                  : _FocusGoalRow(
                                      goal: selectedGoal!,
                                      onTap: () => _openGoal(selectedGoal),
                                    ),
                            ),
                          ),
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(
                            horizontal,
                            26,
                            horizontal,
                            10,
                          ),
                          sliver: SliverToBoxAdapter(
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                Expanded(
                                  child: _SectionHeading(
                                    title: 'Goals',
                                    detail: _controller.goals.isEmpty
                                        ? null
                                        : '${_controller.goals.length} active',
                                  ),
                                ),
                                PlayfulButton.icon(
                                  icon: Icons.add_rounded,
                                  semanticLabel: 'Create a new goal',
                                  onPressed: () => Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (_) => GoalEditorPage(
                                        controller: _controller,
                                      ),
                                    ),
                                  ),
                                  label: const Text('New goal'),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (goals.isNotEmpty)
                          SliverPadding(
                            padding: EdgeInsets.symmetric(
                              horizontal: horizontal,
                            ),
                            sliver: SliverList.separated(
                              itemCount: goals.length,
                              itemBuilder: (context, index) {
                                final goal = goals[index];
                                return _GoalCard(
                                  goal: goal,
                                  onTap: () => _openGoal(goal),
                                );
                              },
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 12),
                            ),
                          )
                        else if (_controller.goals.isEmpty)
                          SliverPadding(
                            padding: EdgeInsets.symmetric(
                              horizontal: horizontal,
                            ),
                            sliver: SliverToBoxAdapter(
                              child: _EmptyGoals(
                                onAdd: () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        GoalEditorPage(controller: _controller),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(
                            horizontal,
                            30,
                            horizontal,
                            10,
                          ),
                          sliver: SliverToBoxAdapter(
                            child: _SectionHeading(
                              title: 'Marks',
                              detail: _controller.events.isEmpty
                                  ? null
                                  : _controller.events.length == 1
                                  ? '1 saved'
                                  : '${_controller.events.length} saved',
                            ),
                          ),
                        ),
                        if (marks.isNotEmpty)
                          SliverPadding(
                            padding: EdgeInsets.symmetric(
                              horizontal: horizontal,
                            ),
                            sliver: SliverList.separated(
                              itemCount: marks.length,
                              itemBuilder: (context, index) {
                                final event = marks[index];
                                return _EventListTile(
                                  event: event,
                                  snapshot: _controller.countdownFor(event),
                                  selected: false,
                                  onTap: () => _selectEvent(event),
                                  onEdit: () => _openEditor(event),
                                  onDelete: () => _deleteEvent(event),
                                );
                              },
                              separatorBuilder: (_, _) =>
                                  const SizedBox(height: 12),
                            ),
                          ),
                        SliverPadding(
                          padding: EdgeInsets.fromLTRB(
                            horizontal,
                            16,
                            horizontal,
                            28,
                          ),
                          sliver: SliverToBoxAdapter(
                            child: PlayfulButton.icon(
                              expand: true,
                              tone: PlayfulButtonTone.quiet,
                              icon: Icons.add_rounded,
                              semanticLabel: 'Add a new mark',
                              onPressed: _working ? null : () => _openEditor(),
                              label: const Text('Add a mark'),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
        );
      },
    );
  }

  Future<void> _openAccount() async {
    if (_working) return;
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => AccountPage(api: widget.accountApi)),
    );
  }

  Future<void> _openWidgetFocus(dynamic focus) async {
    if (!mounted || focus is! Map || focus['id'] is! String) return;
    final id = focus['id'] as String;
    if (focus['kind'] == 'goal') {
      for (final goal in _controller.goals) {
        if (goal.id == id) {
          await _openGoal(goal);
          return;
        }
      }
    } else {
      for (final event in _controller.events) {
        if (event.id == id) {
          await _selectEvent(event);
          return;
        }
      }
    }
  }

  Future<void> _openGoal(Goal goal) async {
    if (_working) return;
    setState(() => _working = true);
    try {
      await _controller.selectGoal(goal.id);
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) =>
              GoalDetailPage(controller: _controller, goalId: goal.id),
        ),
      );
    } catch (_) {
      if (mounted) _showMessage('Could not open goal. Try again.');
    } finally {
      if (mounted) setState(() => _working = false);
    }
  }

  Future<void> _selectEvent(ItsTheDayEvent event) async {
    if (_working) return;
    setState(() => _working = true);
    await _controller.selectEvent(event.id);
    if (mounted) setState(() => _working = false);
  }

  Future<void> _openEditor([ItsTheDayEvent? event]) async {
    if (_working) return;
    final result = await EventEditorPage.show(context, event: event);
    if (!mounted || result == null) return;

    setState(() => _working = true);
    if (result is EventSavedResult) {
      final saveResult = await _controller.saveEvent(result.event);
      if (mounted) _showSaveFeedback(result.event, saveResult);
    } else if (result is EventDeletedResult) {
      await _controller.deleteEvent(result.eventId);
    }
    if (mounted) setState(() => _working = false);
  }

  Future<void> _deleteEvent(ItsTheDayEvent event) async {
    if (_working) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete this mark?'),
        content: Text("“${event.title}” will be removed from It's the Day!."),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Keep it'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;
    setState(() => _working = true);
    try {
      await _controller.deleteEvent(event.id);
    } on Object {
      if (mounted) {
        _showMessage('Could not delete the mark. Try again.');
      }
    }
    if (mounted) setState(() => _working = false);
  }

  Future<void> _openCalendarImport() async {
    if (_working) return;
    final imported = await Navigator.of(context).push<ImportedCalendarEvent>(
      MaterialPageRoute(
        builder: (_) => CalendarImportPage(
          calendar: _controller.calendarGateway,
          googleCalendar: _controller.googleCalendarGateway,
        ),
      ),
    );
    if (!mounted || imported == null) return;
    setState(() => _working = true);
    final event = imported.toItsTheDayEvent();
    final result = await _controller.saveEvent(event);
    if (mounted) {
      _showSaveFeedback(event, result);
      setState(() => _working = false);
    }
  }

  void _showSaveFeedback(ItsTheDayEvent event, SaveEventResult result) {
    if (result.warning != null) {
      _showMessage('Saved, but ${result.warning}');
    } else if (event.reminders.isNotEmpty &&
        result.notificationPermission == NotificationPermissionStatus.denied) {
      _showMessage(
        "Saved. Notifications are off for It's the Day! in system settings.",
      );
    } else if (event.reminders.isNotEmpty && !result.notificationsSynced) {
      _showMessage('Saved. Reminders will be available on Android.');
    } else {
      _showMessage('${event.title} is now your focus.');
    }
  }

  void _showMessage(String message) {
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(content: Text(message)));
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.onImport,
    required this.onAccount,
    required this.onAdd,
    required this.onGroups,
  });

  final VoidCallback onImport;
  final VoidCallback onAccount;
  final VoidCallback onAdd;
  final VoidCallback onGroups;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            const ItsTheDayMark(size: 42),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                "IT'S THE DAY!",
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.titleLarge
                    ?.copyWith(letterSpacing: .7),
              ),
            ),
            Semantics(
              button: true,
              label: 'Add a new mark',
              child: IconButton.filled(
                onPressed: onAdd,
                icon: const Icon(Icons.add_rounded),
                tooltip: 'Add a new mark',
              ),
            ),
          ],
        ),
        const SizedBox(height: 6),
        Row(
          children: [
            _HeaderAction(
              icon: Icons.calendar_month_outlined,
              label: 'Import or connect a calendar',
              onPressed: onImport,
            ),
            _HeaderAction(
              icon: Icons.groups_outlined,
              label: 'Open online groups',
              onPressed: onGroups,
            ),
            _HeaderAction(
              icon: Icons.account_circle_outlined,
              label: 'Account',
              onPressed: onAccount,
            ),
          ],
        ),
      ],
    );
  }
}

class _HeaderAction extends StatelessWidget {
  const _HeaderAction({
    required this.icon,
    required this.label,
    required this.onPressed,
  });

  final IconData icon;
  final String label;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: label,
      child: IconButton(
        onPressed: onPressed,
        icon: Icon(icon),
        tooltip: label,
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

class _FocusEventRow extends StatelessWidget {
  const _FocusEventRow({
    required this.event,
    required this.snapshot,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  final ItsTheDayEvent event;
  final CountdownSnapshot snapshot;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final accent = _accent(context, snapshot.status);
    return Semantics(
      container: true,
      label: snapshot.accessibleLabel,
      child: TactileSurface(
        onTap: onTap,
        semanticLabel: snapshot.accessibleLabel,
        child: PlayfulPanel(
          padding: const EdgeInsets.all(14),
          borderColor: accent.withValues(alpha: .56),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClockSparkIllustration(
                size: 44,
                state: _clockState(snapshot.status),
                semanticLabel: 'Focused mark illustration',
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: _StatusBadge(
                            status: snapshot.status,
                            color: accent,
                            compact: true,
                          ),
                        ),
                        IconButton(
                          onPressed: onEdit,
                          icon: const Icon(Icons.edit_outlined),
                          tooltip: 'Edit ${event.title}',
                          visualDensity: VisualDensity.compact,
                        ),
                        PopupMenuButton<String>(
                          tooltip: 'Actions for ${event.title}',
                          onSelected: (action) {
                            if (action == 'delete') onDelete();
                          },
                          itemBuilder: (context) => const [
                            PopupMenuItem(
                              value: 'delete',
                              child: Text('Delete mark'),
                            ),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      event.title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 6),
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.baseline,
                      textBaseline: TextBaseline.alphabetic,
                      children: [
                        Flexible(
                          child: FittedBox(
                            fit: BoxFit.scaleDown,
                            alignment: Alignment.centerLeft,
                            child: Text(
                              snapshot.displayText,
                              style: Theme.of(context).textTheme.headlineSmall
                                  ?.copyWith(
                                    color: accent,
                                    fontFeatures: const [
                                      FontFeature.tabularFigures(),
                                    ],
                                  ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            _eventDateLine(event),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.bodySmall
                                ?.copyWith(
                                  color: Theme.of(context).colorScheme.onSurface
                                      .withValues(alpha: .62),
                                ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _FocusGoalRow extends StatelessWidget {
  const _FocusGoalRow({required this.goal, required this.onTap});

  final Goal goal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = goal.statusAt(DateTime.now());
    final accent = _goalAccent(context, status);
    final unit = goal.kind == GoalKind.quantity ? goal.unit : 'items';
    return Semantics(
      container: true,
      label: '${goal.title}, ${goal.completed} of ${goal.goalTarget} $unit',
      child: TactileSurface(
        onTap: onTap,
        semanticLabel: 'Open ${goal.title}',
        child: PlayfulPanel(
          padding: const EdgeInsets.all(14),
          borderColor: accent.withValues(alpha: .56),
          child: Row(
            children: [
              ClockSparkIllustration(
                size: 42,
                state: _clockStateForGoal(status),
                semanticLabel: 'Focused goal illustration',
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'FOCUSED GOAL',
                      style: Theme.of(context).textTheme.labelMedium
                          ?.copyWith(color: accent),
                    ),
                    const SizedBox(height: 3),
                    Text(
                      goal.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      '${goal.completed} / ${goal.goalTarget} $unit · ${_statusLabel(status)}',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface
                            .withValues(alpha: .64),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Icon(Icons.arrow_forward_rounded, color: accent),
            ],
          ),
        ),
      ),
    );
  }
}

class _GoalCard extends StatelessWidget {
  const _GoalCard({required this.goal, required this.onTap});

  final Goal goal;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final status = goal.statusAt(DateTime.now());
    final accent = _goalAccent(context, status);
    final colors = Theme.of(context).colorScheme;
    final unit = goal.kind == GoalKind.quantity ? goal.unit : 'items';
    return Semantics(
      button: true,
      label:
          '${goal.title}, ${goal.completed} of ${goal.goalTarget}, ${status.name}',
      child: TactileSurface(
        onTap: onTap,
        semanticLabel:
            '${goal.title}, ${goal.completed} of ${goal.goalTarget}, ${status.name}',
        child: PlayfulPanel(
          padding: const EdgeInsets.fromLTRB(14, 13, 14, 14),
          borderColor: colors.outlineVariant,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.center,
                children: [
                  Expanded(
                    child: Row(
                      children: [
                        _GoalStatusPill(status: status, color: accent),
                        const SizedBox(width: 9),
                        Flexible(
                          child: Text(
                            goal.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Icon(Icons.arrow_forward_rounded, color: accent),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Expanded(
                    child: Text(
                      '${goal.completed} / ${goal.goalTarget} $unit',
                      style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: accent,
                        fontFeatures: const [FontFeature.tabularFigures()],
                      ),
                    ),
                  ),
                  Flexible(
                    child: Text(
                      _goalDeadlineLabel(goal),
                      textAlign: TextAlign.end,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurface.withValues(alpha: .62),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 9),
              PlayfulProgressBar(
                value: goal.progress,
                height: 10,
                semanticLabel:
                    '${goal.completed} of ${goal.goalTarget} $unit complete',
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EventListTile extends StatelessWidget {
  const _EventListTile({
    required this.event,
    required this.snapshot,
    required this.selected,
    required this.onTap,
    required this.onEdit,
    required this.onDelete,
  });

  final ItsTheDayEvent event;
  final CountdownSnapshot snapshot;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final accent = _accent(context, snapshot.status);
    return Semantics(
      button: true,
      selected: selected,
      label: '${event.title}, ${snapshot.accessibleLabel}',
      child: TactileSurface(
        onTap: onTap,
        semanticLabel: '${event.title}, ${snapshot.accessibleLabel}',
        child: PlayfulPanel(
          color: selected
              ? colors.primaryContainer.withValues(alpha: .35)
              : colors.surface,
          borderColor: selected
              ? accent.withValues(alpha: .7)
              : colors.outlineVariant,
          padding: const EdgeInsets.fromLTRB(13, 11, 5, 11),
          child: Row(
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: accent,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      event.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      _eventDateLine(event),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: colors.onSurface.withValues(alpha: .58),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    snapshot.displayText,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      color: accent,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    snapshot.statusLabel,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colors.onSurface.withValues(alpha: .5),
                    ),
                  ),
                ],
              ),
              PopupMenuButton<String>(
                tooltip: 'Actions for ${event.title}',
                onSelected: (action) {
                  if (action == 'edit') onEdit();
                  if (action == 'delete') onDelete();
                },
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Edit mark')),
                  PopupMenuItem(value: 'delete', child: Text('Delete mark')),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _GoalStatusPill extends StatelessWidget {
  const _GoalStatusPill({required this.status, required this.color});

  final GoalStatus status;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: .1),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: color.withValues(alpha: .42)),
      ),
      child: Text(
        _statusLabel(status),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
      ),
    );
  }
}

class _StatusBadge extends StatelessWidget {
  const _StatusBadge({
    required this.status,
    required this.color,
    this.compact = false,
  });

  final CountdownStatus status;
  final Color color;
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final label = switch (status) {
      CountdownStatus.upcoming => 'UPCOMING',
      CountdownStatus.today => 'TODAY',
      CountdownStatus.overdue => 'OVERDUE',
    };
    return Align(
      alignment: Alignment.centerLeft,
      child: Container(
        padding: EdgeInsets.symmetric(
          horizontal: compact ? 8 : 10,
          vertical: compact ? 4 : 6,
        ),
        decoration: BoxDecoration(
          color: color.withValues(alpha: .1),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: color.withValues(alpha: .38)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 6,
              height: 6,
              decoration: BoxDecoration(color: color, shape: BoxShape.circle),
            ),
            const SizedBox(width: 6),
            Text(
              label,
              style: Theme.of(context).textTheme.labelSmall
                  ?.copyWith(color: color),
            ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeading extends StatelessWidget {
  const _SectionHeading({required this.title, this.detail});

  final String title;
  final String? detail;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.baseline,
      textBaseline: TextBaseline.alphabetic,
      children: [
        Text(title, style: Theme.of(context).textTheme.headlineSmall),
        if (detail != null) ...[
          const SizedBox(width: 9),
          Flexible(
            child: Text(
              detail!,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: Theme.of(context).colorScheme.onSurface
                    .withValues(alpha: .52),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _EmptyGoals extends StatelessWidget {
  const _EmptyGoals({required this.onAdd});

  final VoidCallback onAdd;

  @override
  Widget build(BuildContext context) {
    return PlayfulPanel(
      padding: const EdgeInsets.all(15),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              const ClockSparkIllustration(
                size: 50,
                state: ClockSparkState.ready,
                semanticLabel: 'Ready goal illustration',
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'No goals yet',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      'Start with one clear target.',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurface
                            .withValues(alpha: .65),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 13),
          PlayfulButton.icon(
            expand: true,
            icon: Icons.add_rounded,
            semanticLabel: 'Create your first goal',
            onPressed: onAdd,
            label: const Text('Add a goal'),
          ),
        ],
      ),
    );
  }
}

Color _accent(BuildContext context, CountdownStatus status) {
  switch (status) {
    case CountdownStatus.upcoming:
      return Theme.of(context).brightness == Brightness.dark
          ? ItsTheDayPalette.mint
          : ItsTheDayPalette.mintStrong;
    case CountdownStatus.today:
      return Theme.of(context).brightness == Brightness.dark
          ? ItsTheDayPalette.amber
          : ItsTheDayPalette.amberStrong;
    case CountdownStatus.overdue:
      return Theme.of(context).brightness == Brightness.dark
          ? ItsTheDayPalette.coral
          : ItsTheDayPalette.coralStrong;
  }
}

Color _goalAccent(BuildContext context, GoalStatus status) {
  final colors = Theme.of(context).colorScheme;
  return switch (status) {
    GoalStatus.upcoming => colors.primary,
    GoalStatus.today => colors.secondary,
    GoalStatus.overdue => colors.error,
    GoalStatus.completed => colors.tertiary,
  };
}

ClockSparkState _clockState(CountdownStatus status) => switch (status) {
  CountdownStatus.upcoming => ClockSparkState.ready,
  CountdownStatus.today => ClockSparkState.inProgress,
  CountdownStatus.overdue => ClockSparkState.overdue,
};

ClockSparkState _clockStateForGoal(GoalStatus status) => switch (status) {
  GoalStatus.upcoming => ClockSparkState.ready,
  GoalStatus.today => ClockSparkState.inProgress,
  GoalStatus.overdue => ClockSparkState.overdue,
  GoalStatus.completed => ClockSparkState.complete,
};

String _statusLabel(GoalStatus status) => switch (status) {
  GoalStatus.upcoming => 'ON THE WAY',
  GoalStatus.today => 'DUE TODAY',
  GoalStatus.overdue => 'PAST DUE',
  GoalStatus.completed => 'COMPLETE',
};

String _goalDeadlineLabel(Goal goal) {
  final status = goal.statusAt(DateTime.now());
  if (status == GoalStatus.completed) return 'Complete';
  return '${_daysLeftLabel(goal.deadline, status, DateTime.now())} · ${DateFormat.MMMd().format(goal.deadline.toLocal())}';
}

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

String _eventDateLine(ItsTheDayEvent event) {
  final local = event.localStart;
  final date = DateFormat('EEE, d MMM yyyy').format(local);
  return event.allDay
      ? '$date · All day'
      : '$date · ${DateFormat('HH:mm').format(local)}';
}
