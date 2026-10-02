import 'package:flutter_test/flutter_test.dart';
import 'package:its_the_day/domain/goal.dart';
import 'package:its_the_day/domain/goal_pace.dart';

void main() {
  test(
    'uses inclusive local days and switches to an every-few-days cadence',
    () {
      final goal = Goal(
        id: 'reading',
        title: 'Read',
        kind: GoalKind.quantity,
        deadline: DateTime(2026, 10, 10),
        target: 5,
        unit: 'sessions',
        entries: [
          GoalEntry(id: 'done-1', amount: 2, at: DateTime(2026, 10, 1)),
        ],
      );

      final pace = GoalPaceSuggestion.forGoal(
        goal,
        DateTime(2026, 10, 1, 23, 59),
      );

      expect(pace.state, GoalPaceState.active);
      expect(pace.remaining, 3);
      expect(pace.days, 10);
      expect(pace.dailyTarget, isNull);
      expect(pace.intervalDays, 3);
      expect(pace.label(goal.unit), '1 sessions every 3 days');
    },
  );

  test('keeps daily, today, completed, overdue, and empty states honest', () {
    final dailyGoal = Goal(
      id: 'daily',
      title: 'Practice',
      kind: GoalKind.quantity,
      deadline: DateTime(2026, 10, 3),
      target: 4,
      unit: 'minutes',
      entries: [GoalEntry(id: 'done-1', amount: 1, at: DateTime(2026, 10, 1))],
    );

    final daily = GoalPaceSuggestion.forGoal(dailyGoal, DateTime(2026, 10, 1));
    expect(daily.days, 3);
    expect(daily.remaining, 3);
    expect(daily.dailyTarget, 1);
    expect(daily.intervalDays, isNull);
    expect(daily.label(dailyGoal.unit), '1 minutes/day');

    final today = GoalPaceSuggestion.forGoal(
      dailyGoal,
      DateTime(2026, 10, 3, 18),
    );
    expect(today.days, 1);
    expect(today.dailyTarget, 3);
    expect(today.label(dailyGoal.unit), '3 minutes today');

    final completed = GoalPaceSuggestion.forValues(
      target: 4,
      completed: 4,
      deadline: dailyGoal.deadline,
      now: DateTime(2026, 10, 4),
    );
    expect(completed.state, GoalPaceState.completed);
    expect(completed.label('minutes'), 'complete');

    final overdue = GoalPaceSuggestion.forGoal(
      dailyGoal,
      DateTime(2026, 10, 4),
    );
    expect(overdue.state, GoalPaceState.overdue);
    expect(overdue.days, 0);
    expect(overdue.label(dailyGoal.unit), 'overdue');

    final empty = GoalPaceSuggestion.forValues(
      target: 0,
      completed: 0,
      deadline: dailyGoal.deadline,
      now: DateTime(2026, 10, 1),
    );
    expect(empty.state, GoalPaceState.empty);
    expect(empty.remaining, 0);
    expect(empty.label('items'), 'no work yet');
  });

  test('a one-day interval is presented as a daily target', () {
    final pace = GoalPaceSuggestion.forValues(
      target: 48,
      completed: 0,
      deadline: DateTime(2027, 1, 1),
      now: DateTime(2026, 10, 2),
    );
    expect(pace.intervalDays, 1);
    expect(pace.label('tasks'), '1 tasks/day');
  });

  test('online-style totals use the authoritative completed value', () {
    final pace = GoalPaceSuggestion.forValues(
      target: 10,
      completed: 9,
      deadline: DateTime(2026, 10, 10),
      now: DateTime(2026, 10, 1),
    );

    expect(pace.remaining, 1);
    expect(pace.days, 10);
    expect(pace.intervalDays, 10);
    expect(pace.label('pages'), '1 pages every 10 days');
  });
}
