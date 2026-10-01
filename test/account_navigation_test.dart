import 'package:flutter_test/flutter_test.dart';

import 'package:its_the_day/data/event_repository.dart';
import 'package:its_the_day/data/groups_api.dart';
import 'package:its_the_day/platform/platform_interfaces.dart';
import 'package:its_the_day/presentation/itstheday_app.dart';

void main() {
  testWidgets('home account action opens the focused account page', (
    tester,
  ) async {
    await tester.pumpWidget(
      ItsTheDayApp(
        repository: MemoryEventRepository(),
        calendar: const UnsupportedCalendarGateway(),
        widget: const UnsupportedWidgetGateway(),
        reminders: const UnsupportedReminderGateway(),
        accountApi: GroupsApi(
          baseUrl: '',
          tokens: const NativeSessionTokenStore(),
          browser: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Account'));
    await tester.pumpAndSettle();

    expect(find.text('Account'), findsOneWidget);
    expect(find.text('Server setup needed'), findsOneWidget);
  });

  testWidgets('home groups action opens the server-backed groups page', (
    tester,
  ) async {
    await tester.pumpWidget(
      ItsTheDayApp(
        repository: MemoryEventRepository(),
        calendar: const UnsupportedCalendarGateway(),
        widget: const UnsupportedWidgetGateway(),
        reminders: const UnsupportedReminderGateway(),
        accountApi: GroupsApi(
          baseUrl: '',
          tokens: const NativeSessionTokenStore(),
          browser: false,
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Open online groups'));
    await tester.pumpAndSettle();

    expect(find.text('Groups'), findsOneWidget);
    expect(find.text('Server setup needed'), findsOneWidget);
    expect(find.text('Online groups unavailable'), findsNothing);
  });
}
