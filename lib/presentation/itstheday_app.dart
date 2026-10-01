import 'package:flutter/material.dart';

import '../data/event_repository.dart';
import '../data/groups_api.dart';
import '../platform/google_calendar_gateway.dart';
import '../platform/platform_interfaces.dart';
import 'itstheday_controller.dart';
import 'itstheday_theme.dart';
import 'home_page.dart';
import 'brand_mark.dart';

class ItsTheDayApp extends StatelessWidget {
  const ItsTheDayApp({
    super.key,
    required this.repository,
    required this.calendar,
    required this.widget,
    required this.reminders,
    this.googleCalendar = const UnsupportedGoogleCalendarGateway(),
    this.accountApi,
    this.clock,
  });

  final EventRepository repository;
  final CalendarGateway calendar;
  final WidgetGateway widget;
  final ReminderGateway reminders;
  final GoogleCalendarGateway googleCalendar;
  final GroupsApi? accountApi;
  final DateTime Function()? clock;

  @override
  Widget build(BuildContext context) {
    final onlineApi =
        accountApi ??
        GroupsApi(
          baseUrl: const String.fromEnvironment('GROUPS_API_URL'),
          tokens: const NativeSessionTokenStore(),
        );
    final controller = ItsTheDayController(
      repository: repository,
      calendar: calendar,
      widget: widget,
      reminders: reminders,
      googleCalendar: googleCalendar,
      clock: clock,
    );
    return MaterialApp(
      title: "It's the Day!",
      debugShowCheckedModeBanner: false,
      theme: itsthedayLightTheme(),
      darkTheme: itsthedayDarkTheme(),
      themeMode: ThemeMode.system,
      home: _ItsTheDayBootstrap(controller: controller, accountApi: onlineApi),
    );
  }
}

class _ItsTheDayBootstrap extends StatefulWidget {
  const _ItsTheDayBootstrap({
    required this.controller,
    required this.accountApi,
  });

  final ItsTheDayController controller;
  final GroupsApi accountApi;

  @override
  State<_ItsTheDayBootstrap> createState() => _ItsTheDayBootstrapState();
}

class _ItsTheDayBootstrapState extends State<_ItsTheDayBootstrap> {
  late Future<void> _ready;

  @override
  void initState() {
    super.initState();
    _ready = widget.controller.initialize();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<void>(
      future: _ready,
      builder: (context, snapshot) {
        if (snapshot.connectionState != ConnectionState.done) {
          return const _ItsTheDayLoading();
        }
        if (snapshot.hasError) {
          return _ItsTheDayLoadError(onRetry: _retry);
        }
        return HomePage(
          controller: widget.controller,
          accountApi: widget.accountApi,
        );
      },
    );
  }

  void _retry() {
    setState(() {
      _ready = widget.controller.initialize();
    });
  }
}

class _ItsTheDayLoading extends StatelessWidget {
  const _ItsTheDayLoading();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const ItsTheDayMark(size: 64),
            const SizedBox(height: 18),
            Text(
              "IT'S THE DAY!",
              style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: Theme.of(context).colorScheme.primary,
                letterSpacing: 2.4,
              ),
            ),
            SizedBox(
              width: 34,
              height: 34,
              child: CircularProgressIndicator(
                strokeWidth: 2.5,
                color: Theme.of(context).colorScheme.primary,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _ItsTheDayLoadError extends StatelessWidget {
  const _ItsTheDayLoadError({required this.onRetry});

  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(28),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.cloud_off_outlined,
                size: 48,
                color: Theme.of(context).colorScheme.error,
              ),
              const SizedBox(height: 16),
              Text(
                "It's the Day! could not open your marks.",
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 18),
              FilledButton(onPressed: onRetry, child: const Text('Try again')),
            ],
          ),
        ),
      ),
    );
  }
}
