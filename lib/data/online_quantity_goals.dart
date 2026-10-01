import 'groups_api.dart';

/// The server-owned result of a shared quantity goal contribution.
class OnlineQuantityResult {
  const OnlineQuantityResult({
    required this.id,
    required this.goalId,
    required this.actorId,
    required this.amount,
    required this.occurredAt,
    this.title,
    this.note,
    this.url,
    this.createdAt,
  });

  final String id;
  final String goalId;
  final String actorId;
  final int amount;
  final DateTime occurredAt;
  final String? title;
  final String? note;
  final String? url;
  final DateTime? createdAt;

  factory OnlineQuantityResult.fromJson(Map<String, dynamic> json) {
    return OnlineQuantityResult(
      id: _requiredString(json['id']),
      goalId: _requiredString(json['goalId']),
      actorId: _requiredString(json['actorId']),
      amount: _positiveInteger(json['amount']),
      occurredAt: _requiredDate(json['occurredAt']),
      title: _optionalString(json['title']),
      note: _optionalString(json['note']),
      url: _optionalString(json['url']),
      createdAt: _optionalDate(json['createdAt']),
    );
  }
}

/// A server-backed shared-total quantity goal.
///
/// List responses do not include progress. In that case [completed] is zero
/// until the authoritative detail route is read.
class OnlineQuantityGoal {
  const OnlineQuantityGoal({
    required this.id,
    required this.ownerId,
    required this.groupId,
    required this.visibility,
    required this.kind,
    required this.targetMode,
    required this.title,
    required this.unit,
    required this.target,
    required this.deadline,
    this.completed = 0,
    this.results = const [],
    this.createdAt,
  });

  final String id;
  final String ownerId;
  final String? groupId;
  final String visibility;
  final String kind;
  final String targetMode;
  final String title;
  final String unit;
  final int target;
  final DateTime deadline;
  final int completed;
  final List<OnlineQuantityResult> results;
  final DateTime? createdAt;

  int get remaining => (target - completed).clamp(0, target).toInt();

  double get progress {
    if (target <= 0) return 0;
    return (completed / target).clamp(0.0, 1.0).toDouble();
  }

  factory OnlineQuantityGoal.fromJson(
    Map<String, dynamic> json, {
    int completed = 0,
    List<OnlineQuantityResult> results = const [],
  }) {
    return OnlineQuantityGoal(
      id: _requiredString(json['id']),
      ownerId: _requiredString(json['ownerId']),
      groupId: _optionalString(json['groupId']),
      visibility: _requiredString(json['visibility']),
      kind: _requiredString(json['kind']),
      targetMode: _requiredString(json['targetMode']),
      title: _requiredString(json['title']),
      unit: _requiredString(json['unit']),
      target: _positiveInteger(json['target']),
      deadline: _requiredCalendarDate(json['deadline']),
      completed: completed,
      results: List.unmodifiable(results),
      createdAt: _optionalDate(json['createdAt']),
    );
  }

  OnlineQuantityGoal copyWith({
    int? completed,
    List<OnlineQuantityResult>? results,
  }) {
    return OnlineQuantityGoal(
      id: id,
      ownerId: ownerId,
      groupId: groupId,
      visibility: visibility,
      kind: kind,
      targetMode: targetMode,
      title: title,
      unit: unit,
      target: target,
      deadline: deadline,
      completed: completed ?? this.completed,
      results: results ?? this.results,
      createdAt: createdAt,
    );
  }
}

class OnlineQuantityGoalDetail {
  const OnlineQuantityGoalDetail({
    required this.goal,
    required this.state,
    this.serverTime,
  });

  final OnlineQuantityGoal goal;
  final String state;
  final DateTime? serverTime;

  List<OnlineQuantityResult> get results => goal.results;

  factory OnlineQuantityGoalDetail.fromJson(Map<String, dynamic> json) {
    final goalJson = _record(json['goal']);
    final progressJson = json['progress'];
    if (progressJson is! List) throw _invalidResponse();

    final results = [
      for (final value in progressJson)
        OnlineQuantityResult.fromJson(_record(value)),
    ];
    final totalValue = json['total'] ?? json['completed'];
    final completed = _nonNegativeInteger(totalValue);
    final goal = OnlineQuantityGoal.fromJson(
      goalJson,
      completed: completed,
      results: results,
    );
    return OnlineQuantityGoalDetail(
      goal: goal,
      state: json['state']?.toString() ?? 'online',
      serverTime: _optionalDate(json['serverTime']),
    );
  }
}

/// Client for the server-authoritative shared-total quantity slice.
///
/// This class deliberately has no local repository or offline queue. A list
/// is filtered after the server's accessible-goal response so private,
/// individual, checklist, and other-group rows cannot appear in this page.
class OnlineQuantityGoalsApi {
  const OnlineQuantityGoalsApi(this.api);

  final GroupsApi api;

  Future<List<OnlineQuantityGoal>> listGroupGoals(String groupId) async {
    final selectedGroup = groupId.trim();
    if (selectedGroup.isEmpty) throw _invalidResponse();
    final body = await api.request('GET', '/api/goals');
    final rows = body['goals'];
    if (rows is! List) throw _invalidResponse();

    return [
      for (final value in rows)
        if (_isSharedQuantityForGroup(value, selectedGroup))
          OnlineQuantityGoal.fromJson(_record(value)),
    ];
  }

  Future<OnlineQuantityGoal> createSharedQuantityGoal(
    String groupId, {
    required String title,
    required int target,
    required String unit,
    required DateTime deadline,
    String? operationId,
  }) async {
    final selectedGroup = groupId.trim();
    final cleanTitle = title.trim();
    final cleanUnit = unit.trim();
    if (selectedGroup.isEmpty) {
      throw const GroupsRequestError('A group is required.');
    }
    if (cleanTitle.isEmpty) {
      throw const GroupsRequestError('Enter a goal title.');
    }
    if (target < 1) {
      throw const GroupsRequestError('Enter a positive whole-number target.');
    }
    if (cleanUnit.isEmpty) {
      throw const GroupsRequestError('Enter a unit.');
    }
    final body = <String, dynamic>{
      'title': cleanTitle,
      'kind': 'quantity',
      'visibility': 'shared',
      'groupId': selectedGroup,
      'targetMode': 'shared_total',
      'target': target,
      'unit': cleanUnit,
      'deadline': _formatCalendarDate(deadline),
    };
    final response = await api.mutate(
      'POST',
      '/api/goals',
      body: body,
      operationId: operationId,
    );
    final goal = OnlineQuantityGoal.fromJson(response);
    _ensureSharedQuantity(goal);
    return goal;
  }

  Future<OnlineQuantityGoalDetail> getGoal(String goalId) async {
    final id = goalId.trim();
    if (id.isEmpty) throw _invalidResponse();
    final response = await api.request('GET', _goalPath(id));
    final detail = OnlineQuantityGoalDetail.fromJson(response);
    _ensureSharedQuantity(detail.goal);
    return detail;
  }

  Future<OnlineQuantityResult> addResult(
    String goalId,
    int amount, {
    String? note,
    String? operationId,
  }) async {
    final id = goalId.trim();
    if (id.isEmpty) throw _invalidResponse();
    if (amount < 1) {
      throw const GroupsRequestError('Enter a positive whole-number amount.');
    }
    final cleanNote = note?.trim() ?? '';
    final body = <String, dynamic>{
      'amount': amount,
      if (cleanNote.isNotEmpty) 'note': cleanNote,
    };
    final response = await api.mutate(
      'POST',
      '${_goalPath(id)}/progress',
      body: body,
      operationId: operationId,
    );
    return OnlineQuantityResult.fromJson(response);
  }

  static String _goalPath(String goalId) =>
      '/api/goals/${Uri.encodeComponent(goalId)}';

  static bool _isSharedQuantityForGroup(Object? value, String groupId) {
    if (value is! Map) return false;
    final row = Map<String, dynamic>.from(value);
    return row['groupId'] == groupId &&
        row['visibility'] == 'shared' &&
        row['kind'] == 'quantity' &&
        row['targetMode'] == 'shared_total';
  }

  static void _ensureSharedQuantity(OnlineQuantityGoal goal) {
    if (goal.visibility != 'shared' ||
        goal.kind != 'quantity' ||
        goal.targetMode != 'shared_total' ||
        goal.groupId == null ||
        goal.groupId!.isEmpty) {
      throw _invalidResponse();
    }
  }
}

Map<String, dynamic> _record(Object? value) {
  if (value is! Map) throw _invalidResponse();
  return Map<String, dynamic>.from(value);
}

String _requiredString(Object? value) {
  if (value is String && value.trim().isNotEmpty) return value;
  throw _invalidResponse();
}

String? _optionalString(Object? value) {
  if (value is String && value.trim().isNotEmpty) return value;
  return null;
}

int _positiveInteger(Object? value) {
  if (value is int && value > 0) return value;
  if (value is num && value == value.roundToDouble() && value > 0) {
    return value.toInt();
  }
  throw _invalidResponse();
}

int _nonNegativeInteger(Object? value) {
  if (value is int && value >= 0) return value;
  if (value is num && value == value.roundToDouble() && value >= 0) {
    return value.toInt();
  }
  throw _invalidResponse();
}

DateTime _requiredCalendarDate(Object? value) {
  if (value is! String || !RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(value)) {
    throw _invalidResponse();
  }
  final parts = value.split('-').map(int.parse).toList();
  final checked = DateTime.utc(parts[0], parts[1], parts[2]);
  if (checked.year != parts[0] ||
      checked.month != parts[1] ||
      checked.day != parts[2]) {
    throw _invalidResponse();
  }
  return DateTime(parts[0], parts[1], parts[2]);
}

String _formatCalendarDate(DateTime value) {
  return '${value.year.toString().padLeft(4, '0')}-'
      '${value.month.toString().padLeft(2, '0')}-'
      '${value.day.toString().padLeft(2, '0')}';
}

DateTime _requiredDate(Object? value) {
  final date = _optionalDate(value);
  if (date == null) throw _invalidResponse();
  return date;
}

DateTime? _optionalDate(Object? value) {
  if (value is! String || value.trim().isEmpty) return null;
  return DateTime.tryParse(value);
}

GroupsRequestError _invalidResponse() => const GroupsRequestError(
  'Server returned an invalid online goal response.',
);
