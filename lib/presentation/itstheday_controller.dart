import 'package:flutter/foundation.dart';

import '../data/event_repository.dart';
import '../domain/countdown.dart';
import '../domain/itstheday_event.dart';
import '../domain/goal.dart';
import '../platform/google_calendar_gateway.dart';
import '../platform/platform_interfaces.dart';

class SaveEventResult {
  const SaveEventResult({
    this.notificationPermission,
    this.notificationsSynced = false,
    this.warning,
  });

  final NotificationPermissionStatus? notificationPermission;
  final bool notificationsSynced;
  final String? warning;
}

/// Coordinates local data and platform ports without exposing Android APIs to
/// the widgets. All time-dependent work takes a clock so it remains testable.
class ItsTheDayController extends ChangeNotifier {
  ItsTheDayController({
    required EventRepository repository,
    required CalendarGateway calendar,
    required WidgetGateway widget,
    required ReminderGateway reminders,
    GoogleCalendarGateway googleCalendar =
        const UnsupportedGoogleCalendarGateway(),
    DateTime Function()? clock,
  }) : _repository = repository,
       _calendar = calendar,
       _widget = widget,
       _reminders = reminders,
       _googleCalendar = googleCalendar,
       _clock = clock ?? DateTime.now;

  final EventRepository _repository;
  final CalendarGateway _calendar;
  final WidgetGateway _widget;
  final ReminderGateway _reminders;
  final GoogleCalendarGateway _googleCalendar;
  final DateTime Function() _clock;

  List<ItsTheDayEvent> _events = const [];
  List<Goal> _goals = const [];
  String? _selectedId;
  String? _selectedGoalId;
  GoogleCalendarAccount? _googleCalendarAccount;
  bool _initialized = false;

  bool get isInitialized => _initialized;

  List<ItsTheDayEvent> get events => List.unmodifiable(_events);
  List<Goal> get goals => List.unmodifiable(_goals);

  Goal? get selectedGoal {
    for (final goal in _goals) {
      if (goal.id == _selectedGoalId) return goal;
    }
    return _goals.isEmpty ? null : _goals.first;
  }

  String? get selectedGoalId => selectedGoal?.id;

  ItsTheDayEvent? get selectedEvent {
    if (_selectedId == null && _selectedGoalId != null) return null;
    for (final event in _events) {
      if (event.id == _selectedId) return event;
    }
    return _events.isEmpty ? null : _events.first;
  }

  String? get selectedId => selectedEvent?.id;

  CalendarGateway get calendarGateway => _calendar;

  GoogleCalendarGateway get googleCalendarGateway => _googleCalendar;

  GoogleCalendarAccount? get googleCalendarAccount =>
      _googleCalendarAccount ?? _googleCalendar.currentAccount;

  bool get googleCalendarConfigured => _googleCalendar.isConfigured;

  Future<void> initialize() async {
    if (_initialized) return;
    final stored = await _repository.read();
    _goals = stored.goals;
    _selectedGoalId = _validGoalSelection(stored.selectedGoalId);
    if (_selectedGoalId == null && _goals.isNotEmpty) {
      _selectedGoalId = _goals.first.id;
    }
    final loaded = List<ItsTheDayEvent>.of(stored.events);
    if (!stored.hasStoredData) {
      final demo = ItsTheDayEvent.demo(_clock());
      loaded.add(demo);
      _selectedId = demo.id;
      _events = _sortEvents(loaded);
      await _repository.write(
        events: _events,
        selectedId: _selectedId,
        goals: _goals,
        selectedGoalId: _selectedGoalId,
      );
    } else {
      _events = _sortEvents(loaded);
      _selectedId = _validSelection(stored.selectedId);
      if (_selectedId == null &&
          _selectedGoalId == null &&
          _events.isNotEmpty) {
        _selectedId = _events.first.id;
        await _repository.write(
          events: _events,
          selectedId: _selectedId,
          goals: _goals,
          selectedGoalId: _selectedGoalId,
        );
      }
    }
    try {
      _googleCalendarAccount = await _googleCalendar.restore();
    } on Object {
      _googleCalendarAccount = null;
    }
    _initialized = true;
    notifyListeners();
    await _syncWidget();
  }

  CountdownSnapshot countdownFor(ItsTheDayEvent event) {
    return CountdownCalculator.calculate(event, _clock());
  }

  Future<SaveEventResult> saveEvent(ItsTheDayEvent event) =>
      _serialize(() => _saveEvent(event));

  Future<SaveEventResult> _saveEvent(ItsTheDayEvent event) async {
    final existing = _find(event.id);
    String? warning;
    NotificationPermissionStatus? permission;
    var notificationsSynced = false;

    // Cancel first so changing a title, time, or offset never leaves an old
    // notification scheduled under the same event id.
    try {
      await _reminders.cancelEvent(event.id);
      if (event.reminders.isNotEmpty) {
        permission = await _reminders.requestPermission();
        if (permission == NotificationPermissionStatus.granted) {
          await _reminders.sync(event, now: _clock());
          notificationsSynced = true;
        }
      }
    } on Object catch (error) {
      warning = 'Reminder sync failed: $error';
    }

    final next = List<ItsTheDayEvent>.of(_events);
    if (existing == null) {
      next.add(event);
    } else {
      final index = next.indexWhere((item) => item.id == event.id);
      next[index] = event;
    }
    final sorted = _sortEvents(next);
    await _repository.write(
      events: sorted,
      selectedId: event.id,
      goals: _goals,
      selectedGoalId: _selectedGoalId,
    );
    _events = sorted;
    _selectedId = event.id;
    notifyListeners();
    await _syncWidget();

    return SaveEventResult(
      notificationPermission: permission,
      notificationsSynced: notificationsSynced,
      warning: warning,
    );
  }

  Future<void> deleteEvent(String eventId) =>
      _serialize(() => _deleteEvent(eventId));

  Future<void> _deleteEvent(String eventId) async {
    await _reminders.cancelEvent(eventId);
    final next = _events.where((event) => event.id != eventId).toList();
    final selection = _selectedId == eventId
        ? (next.isEmpty ? null : next.first.id)
        : _selectedId;
    await _repository.write(
      events: next,
      selectedId: selection,
      goals: _goals,
      selectedGoalId: _selectedGoalId,
    );
    _events = next;
    _selectedId = selection;
    notifyListeners();
    await _syncWidget();
  }

  Future<void> selectEvent(String eventId) =>
      _serialize(() => _selectEvent(eventId));

  Future<void> _selectEvent(String eventId) async {
    if (_find(eventId) == null || eventId == _selectedId) return;
    await _repository.write(
      events: _events,
      selectedId: eventId,
      goals: _goals,
      selectedGoalId: _selectedGoalId,
    );
    _selectedId = eventId;
    notifyListeners();
    await _syncWidget();
  }

  Future<CalendarResult> getUpcomingCalendarEvents() {
    return _calendar.getUpcomingEvents();
  }

  Future<CalendarResult> getUpcomingGoogleCalendarEvents() {
    return _googleCalendar.getUpcomingEvents();
  }

  Future<GoogleCalendarAccount> connectGoogleCalendar() async {
    final account = await _googleCalendar.signIn();
    _googleCalendarAccount = account;
    notifyListeners();
    return account;
  }

  Future<void> disconnectGoogleCalendar() async {
    await _googleCalendar.signOut();
    _googleCalendarAccount = null;
    notifyListeners();
  }

  /// Allows the home screen to repaint after its foreground timer ticks.
  void refreshCountdown() => notifyListeners();

  Future<void> _mutationTail = Future<void>.value();

  Future<T> _serialize<T>(Future<T> Function() operation) {
    final result = _mutationTail.then((_) => operation());
    _mutationTail = result.then<void>(
      (_) {},
      onError: (Object _, StackTrace __) {},
    );
    return result;
  }

  Future<void> saveGoal(Goal goal) => _serialize(() => _saveGoal(goal));

  Future<void> _saveGoal(Goal goal) async {
    final next = List<Goal>.of(_goals);
    final index = next.indexWhere((g) => g.id == goal.id);
    if (index < 0) {
      next.add(goal);
    } else {
      next[index] = goal;
    }
    await _writeGoals(next, focusGoalId: goal.id);
  }

  Future<void> deleteGoal(String id) =>
      _serialize(() => _writeGoals(_goals.where((g) => g.id != id).toList()));

  Future<void> addEntry(String goalId, GoalEntry entry) => _serialize(() async {
    final goal = _goal(goalId);
    if (goal.kind != GoalKind.quantity) throw StateError('Not a quantity goal');
    if (goal.entries.any((e) => e.id == entry.id)) return;
    await _saveGoal(goal.copyWith(entries: [...goal.entries, entry]));
  });

  Future<void> editEntry(String goalId, GoalEntry entry) => _serialize(
    () async {
      final goal = _goal(goalId);
      if (!goal.entries.any((e) => e.id == entry.id)) {
        throw StateError('Entry missing');
      }
      await _saveGoal(
        goal.copyWith(
          entries: [for (final e in goal.entries) e.id == entry.id ? entry : e],
        ),
      );
    },
  );

  Future<void> deleteEntry(String goalId, String entryId) =>
      _serialize(() async {
        final goal = _goal(goalId);
        await _saveGoal(
          goal.copyWith(
            entries: [
              for (final e in goal.entries)
                e.id == entryId ? e.copyWith(deleted: true) : e,
            ],
          ),
        );
      });

  Future<void> setItemChecked(
    String goalId,
    String itemId,
    bool checked, {
    String? explanation,
  }) => _serialize(() async {
    final goal = _goal(goalId);
    if (goal.kind != GoalKind.checklist) {
      throw StateError('Not a checklist goal');
    }
    await _saveGoal(
      goal.copyWith(
        items: [
          for (final item in goal.items)
            item.id == itemId
                ? item.copyWith(checked: checked, explanation: explanation)
                : item,
        ],
      ),
    );
  });

  Goal _goal(String id) => _goals.firstWhere((g) => g.id == id);

  Future<void> _writeGoals(List<Goal> next, {String? focusGoalId}) async {
    final selection =
        focusGoalId ??
        (next.any((goal) => goal.id == _selectedGoalId)
            ? _selectedGoalId
            : next.isEmpty
            ? null
            : next.first.id);
    final eventSelection = focusGoalId != null ? null : _selectedId;
    await _repository.write(
      events: _events,
      selectedId: eventSelection,
      goals: next,
      selectedGoalId: selection,
    );
    _selectedId = eventSelection;
    _goals = List.unmodifiable(next);
    _selectedGoalId = selection;
    notifyListeners();
    await _syncWidget();
  }

  Future<void> selectGoal(String goalId) => _serialize(() async {
    if (!_goals.any((goal) => goal.id == goalId) ||
        (goalId == _selectedGoalId && _selectedId == null)) {
      return;
    }
    await _repository.write(
      events: _events,
      selectedId: null,
      goals: _goals,
      selectedGoalId: goalId,
    );
    _selectedId = null;
    _selectedGoalId = goalId;
    notifyListeners();
    await _syncWidget();
  });

  ItsTheDayEvent? _find(String id) {
    for (final event in _events) {
      if (event.id == id) return event;
    }
    return null;
  }

  String? _validSelection(String? candidate) {
    if (candidate == null) return null;
    return _find(candidate) == null ? null : candidate;
  }

  String? _validGoalSelection(String? candidate) {
    if (candidate == null) return null;
    return _goals.any((goal) => goal.id == candidate) ? candidate : null;
  }

  List<ItsTheDayEvent> _sortEvents(Iterable<ItsTheDayEvent> events) {
    final result = List<ItsTheDayEvent>.of(events);
    result.sort((a, b) => a.localStart.compareTo(b.localStart));
    return result;
  }

  Future<void> _syncWidget() async {
    final event = selectedEvent;
    try {
      if (event != null) {
        await _widget.update(event, countdownFor(event));
        return;
      }
      if (selectedGoal != null) {
        final goal = selectedGoal!;
        final now = _clock().toLocal();
        final today = DateTime.utc(now.year, now.month, now.day);
        final due = DateTime.utc(
          goal.deadline.year,
          goal.deadline.month,
          goal.deadline.day,
        );
        await _widget.updateGoal(goal, due.difference(today).inDays);
        return;
      }
      await _widget.clear();
    } on Object {
      // A missing widget host must not make local editing fail.
    }
  }
}
