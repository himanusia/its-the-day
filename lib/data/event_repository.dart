import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../domain/itstheday_event.dart';
import '../domain/goal.dart';

class EventStore {
  const EventStore({
    required this.events,
    required this.selectedId,
    required this.hasStoredData,
    this.goals = const [],
    this.selectedGoalId,
  });

  final List<ItsTheDayEvent> events;
  final String? selectedId;
  final bool hasStoredData;
  final List<Goal> goals;
  final String? selectedGoalId;
}

abstract interface class EventRepository {
  Future<EventStore> read();

  Future<void> write({
    required List<ItsTheDayEvent> events,
    required String? selectedId,
    List<Goal> goals = const [],
    String? selectedGoalId,
  });
}

class SharedPreferencesEventRepository implements EventRepository {
  SharedPreferencesEventRepository({
    Future<SharedPreferences> Function()? preferencesLoader,
  }) : _preferencesLoader = preferencesLoader ?? SharedPreferences.getInstance;

  static const storageKey = 'itstheday.event_store.v1';

  final Future<SharedPreferences> Function() _preferencesLoader;

  @override
  Future<EventStore> read() async {
    final preferences = await _preferencesLoader();
    final encoded = preferences.getString(storageKey);
    if (encoded == null) {
      return const EventStore(
        events: <ItsTheDayEvent>[],
        selectedId: null,
        hasStoredData: false,
      );
    }

    try {
      final decoded = jsonDecode(encoded);
      if (decoded is! Map) throw const FormatException('Invalid event store');
      final version = decoded['version'] as int? ?? 1;
      if (version > 2) throw UnsupportedError('Newer event store version');
      final rawEvents = decoded['events'];
      final events = <ItsTheDayEvent>[];
      if (rawEvents is List) {
        for (final rawEvent in rawEvents) {
          if (rawEvent is! Map) {
            throw const FormatException('Invalid saved event');
          }
          events.add(
            ItsTheDayEvent.fromJson(Map<String, dynamic>.from(rawEvent)),
          );
        }
      }
      return EventStore(
        events: List.unmodifiable(events),
        selectedId: decoded['selectedId'] as String?,
        hasStoredData: true,
        goals: List.unmodifiable(
          (decoded['goals'] as List? ?? []).map(
            (raw) => Goal.fromJson(Map<String, dynamic>.from(raw as Map)),
          ),
        ),
        selectedGoalId: decoded['selectedGoalId'] as String?,
      );
    } on Object catch (error) {
      throw FormatException('Could not read saved marks: $error');
    }
  }

  @override
  Future<void> write({
    required List<ItsTheDayEvent> events,
    required String? selectedId,
    List<Goal> goals = const [],
    String? selectedGoalId,
  }) async {
    final preferences = await _preferencesLoader();
    final saved = await preferences.setString(
      storageKey,
      jsonEncode({
        'version': 2,
        'events': events.map((event) => event.toJson()).toList(),
        'goals': goals.map((goal) => goal.toJson()).toList(),
        'selectedGoalId': selectedGoalId,
        'selectedId': selectedId,
      }),
    );
    if (!saved) throw StateError('Local storage rejected the write');
  }
}

/// A deterministic repository for app/widget tests and non-Android previews.
class MemoryEventRepository implements EventRepository {
  MemoryEventRepository({
    List<ItsTheDayEvent> events = const [],
    String? selectedId,
    bool hasStoredData = true,
    List<Goal> goals = const [],
    String? selectedGoalId,
  }) : _events = List.of(events),
       _selectedId = selectedId,
       _hasStoredData = hasStoredData,
       _goals = List.of(goals),
       _selectedGoalId = selectedGoalId;

  List<ItsTheDayEvent> _events;
  String? _selectedId;
  bool _hasStoredData;
  List<Goal> _goals;
  String? _selectedGoalId;

  @override
  Future<EventStore> read() async => EventStore(
    events: List.unmodifiable(_events),
    selectedId: _selectedId,
    hasStoredData: _hasStoredData,
    goals: List.unmodifiable(_goals),
    selectedGoalId: _selectedGoalId,
  );

  @override
  Future<void> write({
    required List<ItsTheDayEvent> events,
    required String? selectedId,
    List<Goal> goals = const [],
    String? selectedGoalId,
  }) async {
    _events = List.of(events);
    _selectedId = selectedId;
    _goals = List.of(goals);
    _selectedGoalId = selectedGoalId;
    _hasStoredData = true;
  }
}
