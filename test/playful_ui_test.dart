import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

import 'package:its_the_day/data/event_repository.dart';
import 'package:its_the_day/data/groups_api.dart';
import 'package:its_the_day/domain/goal.dart';
import 'package:its_the_day/domain/itstheday_event.dart';
import 'package:its_the_day/platform/platform_interfaces.dart';
import 'package:its_the_day/presentation/goal_pages.dart';
import 'package:its_the_day/presentation/home_page.dart';
import 'package:its_the_day/presentation/itstheday_controller.dart';
import 'package:its_the_day/presentation/itstheday_theme.dart';
import 'package:its_the_day/presentation/playful_widgets.dart';
import 'package:its_the_day/presentation/unavailable_groups_page.dart';

void main() {
  testWidgets('playful motion has a reduced-motion zero-duration path', (
    tester,
  ) async {
    Duration? regular;
    Duration? reduced;
    const duration = Duration(milliseconds: 420);

    Widget probe({
      required bool disableAnimations,
      required ValueChanged<BuildContext> onBuild,
    }) {
      return MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(disableAnimations: disableAnimations),
          child: Builder(
            builder: (context) {
              onBuild(context);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
    }

    await tester.pumpWidget(
      probe(
        disableAnimations: false,
        onBuild: (context) =>
            regular = playfulMotionDuration(context, duration),
      ),
    );
    await tester.pumpWidget(
      probe(
        disableAnimations: true,
        onBuild: (context) =>
            reduced = playfulMotionDuration(context, duration),
      ),
    );

    expect(regular, duration);
    expect(reduced, Duration.zero);
  });

  testWidgets('playful button exposes a semantic 48dp keyboard action', (
    tester,
  ) async {
    var taps = 0;
    await tester.pumpWidget(
      MaterialApp(
        theme: itsthedayLightTheme(),
        home: Center(
          child: PlayfulButton(
            semanticLabel: 'Add one page',
            onPressed: () => taps++,
            child: const Text('Add one'),
          ),
        ),
      ),
    );

    expect(
      tester.getSize(find.byType(PlayfulButton)).height,
      greaterThanOrEqualTo(48),
    );
    final semantics = tester.ensureSemantics();
    expect(find.bySemanticsLabel('Add one page'), findsOneWidget);
    await tester.tap(find.byType(PlayfulButton));
    expect(taps, 1);
    await tester.sendKeyEvent(LogicalKeyboardKey.tab);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    expect(taps, 2);
    semantics.dispose();
  });

  testWidgets('online groups stay explicitly unavailable in iteration 1', (
    tester,
  ) async {
    await tester.pumpWidget(_page(const GroupsUnavailablePage()));
    await tester.pump();

    expect(find.text('Online groups unavailable'), findsOneWidget);
    expect(find.textContaining('local-only'), findsOneWidget);
    expect(
      find.textContaining('Server setup is not included in this checkpoint.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'quantity detail shows days, actual total, remaining, and quick add',
    (tester) async {
      final goal = Goal(
        id: 'quantity',
        title: 'Read',
        kind: GoalKind.quantity,
        deadline: _futureDeadline(5),
        target: 3,
        unit: 'pages',
        entries: [
          GoalEntry(id: 'first', amount: 1, at: DateTime(2026, 9, 30, 9)),
        ],
      );
      final controller = await _initializedController(goals: [goal]);

      await tester.pumpWidget(
        _page(GoalDetailPage(controller: controller, goalId: goal.id)),
      );
      await tester.pump();

      expect(find.text('5 days left'), findsOneWidget);
      expect(find.text('1 / 3 pages'), findsOneWidget);
      expect(find.textContaining('remaining'), findsWidgets);
      expect(find.text('Quick +1'), findsOneWidget);

      await tester.tap(find.text('Quick +1'));
      await tester.pumpAndSettle();
      expect(find.text('2 / 3 pages'), findsOneWidget);
    },
  );

  testWidgets('checklist flow checks once and keeps the explanation visible', (
    tester,
  ) async {
    final goal = Goal(
      id: 'checklist',
      title: 'Leave the house',
      kind: GoalKind.checklist,
      deadline: _futureDeadline(5),
      items: [
        const ChecklistItem(
          id: 'shoes',
          title: 'Put on shoes',
          explanation: 'The comfy pair by the door.',
        ),
        const ChecklistItem(id: 'keys', title: 'Take keys'),
      ],
    );
    final controller = await _initializedController(goals: [goal]);

    await tester.pumpWidget(
      _page(GoalDetailPage(controller: controller, goalId: goal.id)),
    );
    await tester.pump();
    expect(find.text('0 / 2 items'), findsOneWidget);
    expect(find.text('The comfy pair by the door.'), findsOneWidget);

    await tester.tap(find.text('Put on shoes'));
    await tester.pumpAndSettle();
    expect(find.text('1 / 2 items'), findsOneWidget);
    await tester.tap(find.text('Take keys'));
    await tester.pump();
    expect(find.text('Goal complete!'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 900));
    expect(find.text('Goal complete!'), findsNothing);

    await tester.tap(find.byTooltip('Edit Put on shoes'));
    await tester.pump();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.last, 'Shoes first, then keys.');
    await tester.tap(find.text('Save').last);
    await tester.pumpAndSettle();
    expect(find.text('Shoes first, then keys.'), findsOneWidget);
  });

  testWidgets('goal and URL validation remain in the form', (tester) async {
    final controller = await _initializedController();
    await tester.pumpWidget(_page(GoalEditorPage(controller: controller)));
    await tester.pump();

    final saveGoal = find.text('Save goal');
    await tester.ensureVisible(saveGoal);
    await tester.pumpAndSettle();
    await tester.tap(saveGoal);
    await tester.pump();
    expect(find.text('Enter a name'), findsOneWidget);

    final goal = Goal(
      id: 'links',
      title: 'Log links',
      kind: GoalKind.quantity,
      deadline: _futureDeadline(5),
      target: 1,
      unit: 'link',
    );
    final detailController = await _initializedController(goals: [goal]);
    await tester.pumpWidget(
      _page(GoalDetailPage(controller: detailController, goalId: goal.id)),
    );
    await tester.pump();
    await tester.tap(find.text('Add result'));
    await tester.pump();
    final entryFields = find.byType(TextFormField);
    await tester.enterText(entryFields.at(3), 'https://user:pass@example.com');
    await tester.tap(find.text('Save').last);
    await tester.pump();
    expect(find.text('Use http or https'), findsOneWidget);
    expect(find.text('Add progress'), findsOneWidget);
  });

  testWidgets('failed entry write keeps all entered values and dialog open', (
    tester,
  ) async {
    final goal = Goal(
      id: 'failure',
      title: 'Keep draft',
      kind: GoalKind.quantity,
      deadline: _futureDeadline(5),
      target: 4,
      unit: 'pages',
    );
    final controller = await _initializedController(
      repository: _FailingRepository(goal),
      goals: [goal],
    );

    await tester.pumpWidget(
      _page(GoalDetailPage(controller: controller, goalId: goal.id)),
    );
    await tester.pump();
    await tester.tap(find.text('Add result'));
    await tester.pump();
    final fields = find.byType(TextFormField);
    await tester.enterText(fields.at(1), 'Draft title');
    await tester.enterText(fields.at(2), 'Draft note');
    await tester.tap(find.text('Save').last);
    await tester.pump();

    expect(find.text('Add progress'), findsOneWidget);
    expect(
      tester.widget<TextFormField>(fields.at(1)).controller!.text,
      'Draft title',
    );
    expect(
      tester.widget<TextFormField>(fields.at(2)).controller!.text,
      'Draft note',
    );
  });

  testWidgets(
    'a single focused goal never also renders the empty goal placeholder',
    (tester) async {
      final goal = Goal(
        id: 'only',
        title: 'Ship 50 videos',
        kind: GoalKind.quantity,
        deadline: _futureDeadline(30),
        target: 50,
        unit: 'videos',
      );
      final controller = await _initializedController(goals: [goal]);

      await tester.pumpWidget(
        _page(HomePage(controller: controller, accountApi: _offlineApi())),
      );
      await tester.pump();

      expect(find.text('No goals yet'), findsNothing);
      expect(find.text('Create your first goal'), findsNothing);
      expect(find.textContaining('Ship 50 videos'), findsWidgets);
      expect(find.text('1 active'), findsOneWidget);

      await tester.pumpWidget(const SizedBox.shrink());
    },
  );

  testWidgets('goal editor scrolls at 320dp and 200 percent text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final controller = await _initializedController();

    await tester.pumpWidget(_page(GoalEditorPage(controller: controller)));
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      MaterialApp(
        theme: itsthedayLightTheme(),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: GoalEditorPage(controller: controller),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(ListView), findsOneWidget);
  });

  testWidgets('quantity detail stays usable at 320dp and 200 percent text', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(320, 720));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    final goal = Goal(
      id: 'narrow-quantity',
      title: 'Practice',
      kind: GoalKind.quantity,
      deadline: _futureDeadline(5),
      target: 50,
      unit: 'minutes',
      entries: [
        GoalEntry(id: 'narrow-entry', amount: 1, at: DateTime(2026, 9, 30, 9)),
      ],
    );
    final controller = await _initializedController(goals: [goal]);

    await tester.pumpWidget(
      _page(GoalDetailPage(controller: controller, goalId: goal.id)),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);

    await tester.pumpWidget(
      MaterialApp(
        theme: itsthedayLightTheme(),
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: GoalDetailPage(controller: controller, goalId: goal.id),
        ),
      ),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byType(ListView), findsOneWidget);
    await tester.scrollUntilVisible(find.text('Add result'), 180);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    await tester.tap(find.text('Add result'));
    await tester.pumpAndSettle();
    expect(find.text('Add progress'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}

DateTime _futureDeadline(int days) {
  final now = DateTime.now();
  return DateTime(now.year, now.month, now.day).add(Duration(days: days));
}

MaterialApp _page(Widget home) {
  return MaterialApp(theme: itsthedayLightTheme(), home: home);
}

/// A host that is never reachable: widget tests must not depend on a running
/// local backend and must never touch the network.
GroupsApi _offlineApi() => GroupsApi(
  baseUrl: 'http://127.0.0.1:9',
  tokens: _NullTokenStore(),
  client: MockClient((_) async => http.Response('{"error":"offline"}', 503)),
  browser: false,
);

class _NullTokenStore implements SessionTokenStore {
  @override
  Future<String?> read() async => null;

  @override
  Future<void> write(String token) async {}

  @override
  Future<void> clear() async {}
}

Future<ItsTheDayController> _initializedController({
  EventRepository? repository,
  List<Goal> goals = const [],
}) async {
  final controller = ItsTheDayController(
    repository: repository ?? MemoryEventRepository(goals: goals),
    calendar: const UnsupportedCalendarGateway(),
    widget: const UnsupportedWidgetGateway(),
    reminders: const UnsupportedReminderGateway(),
    clock: () => DateTime(2026, 9, 30, 12),
  );
  await controller.initialize();
  return controller;
}

class _FailingRepository implements EventRepository {
  _FailingRepository(this.goal);

  final Goal goal;

  @override
  Future<EventStore> read() async => EventStore(
    events: const [],
    selectedId: null,
    hasStoredData: true,
    goals: [goal],
    selectedGoalId: goal.id,
  );

  @override
  Future<void> write({
    required List<ItsTheDayEvent> events,
    required String? selectedId,
    List<Goal> goals = const [],
    String? selectedGoalId,
  }) async {
    throw StateError('write failed');
  }
}
