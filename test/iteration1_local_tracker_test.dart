import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:its_the_day/data/event_repository.dart';
import 'package:its_the_day/domain/goal.dart';
import 'package:its_the_day/platform/platform_interfaces.dart';
import 'package:its_the_day/presentation/itstheday_controller.dart';

ItsTheDayController _controller(EventRepository repository) =>
    ItsTheDayController(
      repository: repository,
      calendar: const UnsupportedCalendarGateway(),
      widget: const UnsupportedWidgetGateway(),
      reminders: const UnsupportedReminderGateway(),
      clock: () => DateTime(2026, 9, 30, 12),
    );

void main() {
  test(
    'iteration 1 quantity flow persists target, entries, notes, and progress',
    () async {
      SharedPreferences.setMockInitialValues({});
      final repository = SharedPreferencesEventRepository();
      final controller = _controller(repository);
      await controller.initialize();

      final goal = Goal(
        id: 'videos-50',
        title: 'Publish short videos',
        kind: GoalKind.quantity,
        deadline: DateTime(2027, 1, 1),
        target: 50,
        unit: 'videos',
      );
      await controller.saveGoal(goal);

      final first = GoalEntry(
        id: 'first-batch',
        amount: 10,
        at: DateTime(2026, 9, 30, 9),
        title: 'First batch',
        note: 'Ten clips ready for review.',
      );
      final removed = GoalEntry(
        id: 'remove-me',
        amount: 5,
        at: DateTime(2026, 9, 30, 10),
        note: 'Draft was counted by mistake.',
      );
      await controller.addEntry(goal.id, first);
      await controller.addEntry(goal.id, removed);
      expect(controller.goals.single.completed, 15);

      await controller.editEntry(
        goal.id,
        first.copyWith(amount: 20, note: 'Twenty clips ready for review.'),
      );
      await controller.deleteEntry(goal.id, removed.id);

      final current = controller.goals.single;
      expect(current.target, 50);
      expect(current.unit, 'videos');
      expect(current.deadline, DateTime(2027, 1, 1));
      expect(current.completed, 20);
      expect(current.progress, closeTo(.4, .0001));
      expect(current.entries.where((entry) => !entry.deleted), hasLength(1));
      expect(
        current.entries.singleWhere((entry) => !entry.deleted).note,
        'Twenty clips ready for review.',
      );

      final reloaded = _controller(SharedPreferencesEventRepository());
      await reloaded.initialize();
      final restored = reloaded.goals.single;
      expect(restored.title, 'Publish short videos');
      expect(restored.target, 50);
      expect(restored.unit, 'videos');
      expect(restored.deadline, DateTime(2027, 1, 1));
      expect(restored.completed, 20);
      expect(restored.progress, closeTo(.4, .0001));
      expect(restored.entries.where((entry) => !entry.deleted), hasLength(1));
      expect(
        restored.entries.singleWhere((entry) => !entry.deleted).note,
        'Twenty clips ready for review.',
      );
      expect(
        restored.entries.singleWhere((entry) => entry.deleted).id,
        'remove-me',
      );
    },
  );

  test('checklist completion remains separate from quantity totals', () async {
    final controller = _controller(MemoryEventRepository());
    await controller.initialize();

    final quantity = Goal(
      id: 'quantity',
      title: 'Videos',
      kind: GoalKind.quantity,
      deadline: DateTime(2027, 1, 1),
      target: 50,
      unit: 'videos',
    );
    final checklist = Goal(
      id: 'checklist',
      title: 'Release checklist',
      kind: GoalKind.checklist,
      deadline: DateTime(2027, 1, 1),
      items: const [ChecklistItem(id: 'review', title: 'Review clips')],
    );
    await controller.saveGoal(quantity);
    await controller.saveGoal(checklist);
    await controller.addEntry(
      quantity.id,
      GoalEntry(id: 'one', amount: 3, at: DateTime(2026, 9, 30)),
    );
    await controller.setItemChecked(checklist.id, 'review', true);

    expect(
      controller.goals.singleWhere((goal) => goal.id == quantity.id).completed,
      3,
    );
    expect(
      controller.goals.singleWhere((goal) => goal.id == checklist.id).completed,
      1,
    );
    expect(
      controller.goals.singleWhere((goal) => goal.id == checklist.id).target,
      1,
    );
  });
}
