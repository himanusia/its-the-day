import 'package:flutter_test/flutter_test.dart';
import 'package:its_the_day/data/event_repository.dart';
import 'package:its_the_day/domain/goal.dart';
import 'package:its_the_day/domain/itstheday_event.dart';
import 'package:its_the_day/platform/platform_interfaces.dart';
import 'package:its_the_day/presentation/itstheday_controller.dart';

ItsTheDayController controller(EventRepository repo, {WidgetGateway? widget}) =>
    ItsTheDayController(
      repository: repo,
      calendar: const UnsupportedCalendarGateway(),
      widget: widget ?? const UnsupportedWidgetGateway(),
      reminders: const UnsupportedReminderGateway(),
    );
Goal goal(String id) => Goal(
  id: id,
  title: '50 Shorts',
  kind: GoalKind.quantity,
  deadline: DateTime(2027, 1, 1),
  target: 50,
  unit: 'videos',
);

class _DelayedRepository extends MemoryEventRepository {
  int activeWrites = 0;
  int maximumConcurrentWrites = 0;

  @override
  Future<void> write({
    required List<ItsTheDayEvent> events,
    required String? selectedId,
    List<Goal> goals = const [],
    String? selectedGoalId,
  }) async {
    activeWrites++;
    if (activeWrites > maximumConcurrentWrites)
      maximumConcurrentWrites = activeWrites;
    try {
      await Future<void>.delayed(const Duration(milliseconds: 15));
      await super.write(
        events: events,
        selectedId: selectedId,
        goals: goals,
        selectedGoalId: selectedGoalId,
      );
    } finally {
      activeWrites--;
    }
  }
}

void main() {
  test('event and goal writes share one snapshot queue', () async {
    for (final eventFirst in [true, false]) {
      final repo = _DelayedRepository();
      final c = controller(repo);
      await c.initialize();
      final e = ItsTheDayEvent(
        id: 'concurrent-event',
        title: 'Trip',
        start: DateTime(2027, 2, 1),
      );
      await Future.wait([
        if (eventFirst) c.saveEvent(e),
        c.saveGoal(goal('concurrent-goal')),
        if (!eventFirst) c.saveEvent(e),
      ]);
      final stored = await repo.read();
      expect(stored.events.any((item) => item.id == e.id), isTrue);
      expect(stored.goals.map((item) => item.id), contains('concurrent-goal'));
      expect(repo.maximumConcurrentWrites, 1);
    }
  });

  test(
    'event delete and selection cannot drop concurrent goal progress',
    () async {
      final repo = _DelayedRepository();
      final c = controller(repo);
      await c.initialize();
      final e = ItsTheDayEvent(
        id: 'e',
        title: 'Trip',
        start: DateTime(2027, 2, 1),
      );
      await c.saveEvent(e);
      await c.saveGoal(goal('g'));
      final entry = GoalEntry(
        id: 'result',
        amount: 2,
        at: DateTime(2026, 9, 30),
      );
      await Future.wait([c.selectEvent(e.id), c.addEntry('g', entry)]);
      await Future.wait([
        c.deleteEvent(e.id),
        c.addEntry('g', GoalEntry(id: 'next', amount: 1, at: entry.at)),
      ]);
      final stored = await repo.read();
      expect(stored.events.any((item) => item.id == e.id), isFalse);
      expect(stored.goals.single.completed, 3);
      expect(repo.maximumConcurrentWrites, 1);
    },
  );

  test(
    'concurrent quantity operations retain every entry exactly once',
    () async {
      final c = controller(MemoryEventRepository());
      await c.initialize();
      await c.saveGoal(goal('g'));
      final entry = GoalEntry(id: 'same', amount: 1, at: DateTime(2026, 9, 30));
      await Future.wait([
        c.addEntry('g', entry),
        c.addEntry('g', entry),
        c.addEntry('g', GoalEntry(id: 'second', amount: 2, at: entry.at)),
      ]);
      expect(c.goals.single.completed, 3);
      expect(c.goals.single.entries.length, 2);
    },
  );

  test(
    'goal focus overrides existing countdown and survives reload/deletion',
    () async {
      final e = ItsTheDayEvent(
        id: 'event',
        title: 'Trip',
        start: DateTime(2027, 2, 1),
      );
      final repo = MemoryEventRepository(events: [e], selectedId: e.id);
      final c = controller(repo);
      await c.initialize();
      expect(c.selectedEvent?.id, e.id);
      await c.saveGoal(goal('first'));
      await c.saveGoal(goal('second'));
      await c.selectGoal('first');
      expect(c.selectedEvent, isNull);
      final restart = controller(repo);
      await restart.initialize();
      expect(restart.selectedGoal?.id, 'first');
      expect(restart.selectedEvent, isNull);
      await restart.deleteEvent(e.id);
      final again = controller(repo);
      await again.initialize();
      expect(again.selectedGoal?.id, 'first');
    },
  );

  test('empty checklist never reports completed', () {
    final g = Goal(
      id: 'list',
      title: 'Tasks',
      kind: GoalKind.checklist,
      deadline: DateTime(2027, 1, 1),
    );
    expect(g.isComplete, false);
    expect(g.progress, 0);
  });
}
