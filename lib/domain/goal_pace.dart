import 'goal.dart';

enum GoalPaceState { active, completed, overdue, empty }

/// A deterministic suggestion for completing the remaining work on time.
///
/// Calendar math is intentionally based on local date components converted to
/// UTC midnight so daylight-saving transitions never change the day count.
class GoalPaceSuggestion {
  const GoalPaceSuggestion._({
    required this.state,
    required this.remaining,
    required this.days,
    this.dailyTarget,
    this.intervalDays,
  });

  final GoalPaceState state;
  final int remaining;

  /// Inclusive local calendar days through the deadline, or zero when overdue
  /// or there is no work to schedule.
  final int days;

  /// The number of units to aim for each day when the remaining work is at
  /// least one unit per inclusive day.
  final int? dailyTarget;

  /// The number of calendar days between single-unit sessions when the
  /// remaining work is less than one unit per inclusive day.
  final int? intervalDays;

  bool get isToday => state == GoalPaceState.active && days == 1;

  factory GoalPaceSuggestion.forGoal(Goal goal, DateTime now) {
    return GoalPaceSuggestion.forValues(
      target: goal.goalTarget,
      completed: goal.completed,
      deadline: goal.deadline,
      now: now,
    );
  }

  factory GoalPaceSuggestion.forValues({
    required int target,
    required int completed,
    required DateTime deadline,
    required DateTime now,
  }) {
    final safeTarget = target < 0 ? 0 : target;
    final remaining = safeTarget == 0
        ? 0
        : (safeTarget - completed).clamp(0, safeTarget).toInt();
    final today = _localDateUtc(now);
    final due = _localDateUtc(deadline);
    final calendarDays = due.isBefore(today)
        ? 0
        : due.difference(today).inDays + 1;

    if (safeTarget == 0) {
      return const GoalPaceSuggestion._(
        state: GoalPaceState.empty,
        remaining: 0,
        days: 0,
      );
    }
    if (remaining == 0) {
      return GoalPaceSuggestion._(
        state: GoalPaceState.completed,
        remaining: 0,
        days: calendarDays,
      );
    }
    if (calendarDays <= 0) {
      return GoalPaceSuggestion._(
        state: GoalPaceState.overdue,
        remaining: remaining,
        days: 0,
      );
    }

    if (remaining >= calendarDays) {
      return GoalPaceSuggestion._(
        state: GoalPaceState.active,
        remaining: remaining,
        days: calendarDays,
        dailyTarget: (remaining + calendarDays - 1) ~/ calendarDays,
      );
    }

    return GoalPaceSuggestion._(
      state: GoalPaceState.active,
      remaining: remaining,
      days: calendarDays,
      intervalDays: calendarDays ~/ remaining,
    );
  }

  /// A short label suitable for app and shared-goal summaries.
  String label(String unit) {
    final cleanUnit = unit.trim().isEmpty ? 'unit' : unit.trim();
    return switch (state) {
      GoalPaceState.empty => 'no work yet',
      GoalPaceState.completed => 'complete',
      GoalPaceState.overdue => 'overdue',
      GoalPaceState.active when isToday => '$remaining $cleanUnit today',
      GoalPaceState.active when dailyTarget != null =>
        '$dailyTarget $cleanUnit/day',
      GoalPaceState.active => '1 $cleanUnit every $intervalDays days',
    };
  }
}

DateTime _localDateUtc(DateTime value) {
  final local = value.toLocal();
  return DateTime.utc(local.year, local.month, local.day);
}
