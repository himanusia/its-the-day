import 'package:flutter/services.dart';

import '../domain/countdown.dart';
import '../domain/itstheday_event.dart';
import '../domain/goal.dart';
import 'platform_interfaces.dart';

class AndroidWidgetGateway implements WidgetGateway {
  AndroidWidgetGateway({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('itstheday/widget');

  final MethodChannel _channel;

  @override
  Future<void> update(ItsTheDayEvent event, CountdownSnapshot snapshot) {
    return _channel.invokeMethod<void>('updateWidget', {
      'title': event.title,
      'countdown': snapshot.displayText,
      'status': snapshot.status.name,
      'eventId': event.id,
      'focusKind': 'event',
      'eventTime': event.start.millisecondsSinceEpoch,
      'allDay': event.allDay,
    });
  }

  @override
  Future<void> clear() {
    return _channel.invokeMethod<void>('clearWidget');
  }

  @override
  Future<void> updateGoal(Goal goal, int daysRemaining) {
    final countdown = daysRemaining < 0
        ? 'D+${-daysRemaining}'
        : daysRemaining == 0
        ? 'D-DAY'
        : 'D-$daysRemaining';
    return _channel.invokeMethod<void>('updateWidget', {
      'title': goal.title,
      'countdown': countdown,
      'status': goal.isComplete
          ? 'completed'
          : '${goal.completed}/${goal.goalTarget} ${goal.kind == GoalKind.quantity ? goal.unit : 'items'}',
      'eventId': goal.id,
      'focusKind': 'goal',
      'goalDeadline': goal.toJson()['deadline'],
      'progress':
          '${goal.completed}/${goal.goalTarget} ${goal.kind == GoalKind.quantity ? goal.unit : 'items'}',
      'goalCompleted': goal.completed,
      'goalTarget': goal.goalTarget,
      'goalUnit': goal.kind == GoalKind.quantity ? goal.unit : 'items',
    });
  }
}
