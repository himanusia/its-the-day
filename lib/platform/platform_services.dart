import 'package:flutter/foundation.dart';

import 'android_calendar_gateway.dart';
import 'android_reminder_gateway.dart';
import 'android_widget_gateway.dart';
import 'google_calendar_gateway.dart';
import 'platform_interfaces.dart';

class PlatformServices {
  const PlatformServices({
    required this.calendar,
    required this.widget,
    required this.reminders,
    required this.googleCalendar,
  });

  final CalendarGateway calendar;
  final WidgetGateway widget;
  final ReminderGateway reminders;
  final GoogleCalendarGateway googleCalendar;

  factory PlatformServices.current() {
    if (!kIsWeb && defaultTargetPlatform == TargetPlatform.android) {
      return PlatformServices(
        calendar: AndroidCalendarGateway(),
        widget: AndroidWidgetGateway(),
        reminders: AndroidReminderGateway(),
        googleCalendar: AndroidGoogleCalendarGateway(),
      );
    }
    return PlatformServices(
      calendar: const UnsupportedCalendarGateway(),
      widget: const UnsupportedWidgetGateway(),
      reminders: const UnsupportedReminderGateway(),
      googleCalendar: const UnsupportedGoogleCalendarGateway(),
    );
  }
}
