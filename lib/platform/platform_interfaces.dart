import '../domain/countdown.dart';
import '../domain/itstheday_event.dart';
import '../domain/goal.dart';

class GoogleCalendarAccount {
  const GoogleCalendarAccount({
    required this.email,
    this.displayName,
    this.photoUrl,
  });

  final String email;
  final String? displayName;
  final String? photoUrl;
}

/// Platform-independent result for a calendar import attempt.
enum CalendarResultStatus { granted, denied, unavailable, empty, error }

class ImportedCalendarEvent {
  const ImportedCalendarEvent({
    required this.sourceId,
    required this.title,
    required this.start,
    required this.end,
    required this.allDay,
    this.location,
    this.calendarName,
    this.provider = CalendarProvider.device,
  });

  final String sourceId;
  final String title;
  final DateTime start;
  final DateTime end;
  final bool allDay;
  final String? location;
  final String? calendarName;
  final CalendarProvider provider;

  ItsTheDayEvent toItsTheDayEvent() {
    final localStart = start.toLocal();
    return ItsTheDayEvent(
      id: 'calendar-$sourceId-${localStart.millisecondsSinceEpoch}',
      title: title.trim(),
      start: allDay
          ? DateTime(localStart.year, localStart.month, localStart.day)
          : localStart,
      allDay: allDay,
      source: provider == CalendarProvider.google
          ? EventSource.google
          : EventSource.calendar,
    );
  }
}

enum CalendarProvider { device, google }

class CalendarResult {
  const CalendarResult._({
    required this.status,
    this.events = const [],
    this.message,
  });

  CalendarResult.granted(List<ImportedCalendarEvent> events)
    : this._(
        status: events.isEmpty
            ? CalendarResultStatus.empty
            : CalendarResultStatus.granted,
        events: events,
      );

  const CalendarResult.denied([String? message])
    : this._(status: CalendarResultStatus.denied, message: message);

  const CalendarResult.unavailable([String? message])
    : this._(status: CalendarResultStatus.unavailable, message: message);

  const CalendarResult.error(String message)
    : this._(status: CalendarResultStatus.error, message: message);

  final CalendarResultStatus status;
  final List<ImportedCalendarEvent> events;
  final String? message;

  bool get hasEvents => events.isNotEmpty;
}

abstract interface class CalendarGateway {
  /// Requests access and, only after access is granted, reads upcoming events.
  Future<CalendarResult> getUpcomingEvents();
}

abstract interface class GoogleCalendarGateway {
  bool get isConfigured;

  GoogleCalendarAccount? get currentAccount;

  Future<void> initialize();

  Future<GoogleCalendarAccount?> restore();

  Future<GoogleCalendarAccount> signIn();

  Future<void> signOut();

  Future<CalendarResult> getUpcomingEvents();
}

abstract interface class WidgetGateway {
  Future<void> update(ItsTheDayEvent event, CountdownSnapshot snapshot);

  Future<void> updateGoal(Goal goal, int daysRemaining);

  Future<void> clear();
}

abstract interface class ReminderGateway {
  Future<NotificationPermissionStatus> requestPermission();

  Future<void> sync(ItsTheDayEvent event, {required DateTime now});

  Future<void> cancelEvent(String eventId);
}

enum NotificationPermissionStatus { granted, denied, unavailable }

class UnsupportedCalendarGateway implements CalendarGateway {
  const UnsupportedCalendarGateway();

  @override
  Future<CalendarResult> getUpcomingEvents() async =>
      const CalendarResult.unavailable(
        'Calendar import is available on Android.',
      );
}

class UnsupportedWidgetGateway implements WidgetGateway {
  const UnsupportedWidgetGateway();

  @override
  Future<void> clear() async {}

  @override
  Future<void> update(ItsTheDayEvent event, CountdownSnapshot snapshot) async {}

  @override
  Future<void> updateGoal(Goal goal, int daysRemaining) async {}
}

class UnsupportedReminderGateway implements ReminderGateway {
  const UnsupportedReminderGateway();

  @override
  Future<void> cancelEvent(String eventId) async {}

  @override
  Future<NotificationPermissionStatus> requestPermission() async =>
      NotificationPermissionStatus.unavailable;

  @override
  Future<void> sync(ItsTheDayEvent event, {required DateTime now}) async {}
}
