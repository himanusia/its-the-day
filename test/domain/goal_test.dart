import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:its_the_day/data/event_repository.dart';
import 'package:its_the_day/domain/goal.dart';
import 'package:its_the_day/platform/platform_interfaces.dart';
import 'package:its_the_day/presentation/itstheday_controller.dart';

void main() {
  Goal sample() => Goal(
    id: 'one',
    title: 'Read',
    kind: GoalKind.quantity,
    deadline: DateTime(2026, 10, 1),
    target: 3,
    unit: 'books',
  );
  test('inclusive deadline, safe pace and overachievement', () {
    final g = sample();
    expect(g.statusAt(DateTime(2026, 10, 1, 23, 59)), GoalStatus.today);
    expect(g.statusAt(DateTime(2026, 10, 2)), GoalStatus.overdue);
    expect(g.paceAt(DateTime(2026, 10, 1, 12)), 3);
    expect(g.paceAt(DateTime(2026, 10, 2)), isNull);
    final over = g.copyWith(
      entries: [GoalEntry(id: 'a', amount: 4, at: DateTime(2026, 9, 30))],
    );
    expect(over.completed, 4);
    expect(over.progress, 1);
    expect(over.statusAt(DateTime(2026, 10, 2)), GoalStatus.completed);
  });
  test('checklist checks count once and reverse', () {
    final g = Goal(
      id: 'check',
      title: 'Pack',
      kind: GoalKind.checklist,
      deadline: DateTime(2026, 10, 1),
      items: [const ChecklistItem(id: 'a', title: 'Bag', checked: true)],
    );
    expect(g.completed, 1);
    expect(
      g.copyWith(items: [g.items.first.copyWith(checked: false)]).completed,
      0,
    );
  });
  test('controller ignores a repeated entry id', () async {
    final repository = MemoryEventRepository(events: const []);
    final controller = ItsTheDayController(
      repository: repository,
      calendar: const UnsupportedCalendarGateway(),
      widget: const UnsupportedWidgetGateway(),
      reminders: const UnsupportedReminderGateway(),
      clock: () => DateTime(2026, 9, 30),
    );
    await controller.initialize();
    final goal = sample();
    await controller.saveGoal(goal);
    final entry = GoalEntry(
      id: 'same-operation',
      amount: 2,
      at: DateTime(2026, 9, 30),
    );
    await controller.addEntry(goal.id, entry);
    await controller.addEntry(goal.id, entry);
    expect(controller.goals.single.completed, 2);
    expect(controller.goals.single.entries, hasLength(1));
  });

  test('legacy event JSON migrates and goals survive restart', () async {
    SharedPreferences.setMockInitialValues({
      SharedPreferencesEventRepository.storageKey: jsonEncode({
        'events': [
          {
            'id': 'old',
            'title': 'Old',
            'start': '2026-10-01T00:00:00.000',
            'allDay': true,
            'reminders': [],
          },
        ],
        'selectedId': 'old',
      }),
    });
    final repo = SharedPreferencesEventRepository();
    final legacy = await repo.read();
    expect(legacy.events.single.id, 'old');
    expect(legacy.goals, isEmpty);
    await repo.write(
      events: legacy.events,
      selectedId: legacy.selectedId,
      goals: [sample()],
    );
    final restarted = await SharedPreferencesEventRepository().read();
    expect(restarted.events.single.id, 'old');
    expect(restarted.goals.single.title, 'Read');
  });
  test('malformed store surfaces error', () async {
    SharedPreferences.setMockInitialValues({
      SharedPreferencesEventRepository.storageKey: 'broken',
    });
    expect(SharedPreferencesEventRepository().read(), throwsFormatException);
  });
}
