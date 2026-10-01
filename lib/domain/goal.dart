enum GoalKind { quantity, checklist }

enum GoalStatus { upcoming, today, overdue, completed }

/// A date-only deadline is inclusive in the device's local calendar.
class Goal {
  Goal({
    required this.id,
    required this.title,
    required this.kind,
    required this.deadline,
    this.target = 1,
    this.unit = '',
    List<GoalEntry> entries = const [],
    List<ChecklistItem> items = const [],
  }) : entries = List.unmodifiable(entries),
       items = List.unmodifiable(items) {
    if (id.trim().isEmpty ||
        entries.map((e) => e.id).toSet().length != entries.length ||
        items.map((e) => e.id).toSet().length != items.length ||
        title.trim().isEmpty ||
        target < 1 ||
        (kind == GoalKind.quantity && unit.trim().isEmpty)) {
      throw ArgumentError(
        'A goal needs a title, positive target, and quantity unit',
      );
    }
  }

  final String id, title, unit;
  final GoalKind kind;
  final DateTime deadline;
  final int target;
  final List<GoalEntry> entries;
  final List<ChecklistItem> items;

  int get completed => kind == GoalKind.quantity
      ? entries.where((e) => !e.deleted).fold(0, (sum, e) => sum + e.amount)
      : items.where((e) => e.checked).length;
  int get goalTarget => kind == GoalKind.quantity ? target : items.length;
  double get progress =>
      goalTarget == 0 ? 0 : (completed / goalTarget).clamp(0, 1);
  bool get isComplete => goalTarget > 0 && completed >= goalTarget;

  GoalStatus statusAt(DateTime now) {
    now = now.toLocal();
    if (isComplete) return GoalStatus.completed;
    final today = DateTime(now.year, now.month, now.day);
    final due = DateTime(deadline.year, deadline.month, deadline.day);
    if (due.isBefore(today)) return GoalStatus.overdue;
    if (due == today) return GoalStatus.today;
    return GoalStatus.upcoming;
  }

  /// Remaining units per inclusive local calendar day, or null when expired/complete.
  int? paceAt(DateTime now) {
    now = now.toLocal();
    if (isComplete || statusAt(now) == GoalStatus.overdue) return null;
    final today = DateTime.utc(now.year, now.month, now.day);
    final due = DateTime.utc(deadline.year, deadline.month, deadline.day);
    final days = due.difference(today).inDays + 1;
    if (days <= 0) return null;
    return ((goalTarget - completed).clamp(0, goalTarget) / days).ceil();
  }

  Goal copyWith({
    String? title,
    DateTime? deadline,
    int? target,
    String? unit,
    List<GoalEntry>? entries,
    List<ChecklistItem>? items,
  }) => Goal(
    id: id,
    title: title ?? this.title,
    kind: kind,
    deadline: deadline ?? this.deadline,
    target: target ?? this.target,
    unit: unit ?? this.unit,
    entries: entries ?? this.entries,
    items: items ?? this.items,
  );

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'kind': kind.name,
    'deadline':
        '${deadline.year.toString().padLeft(4, '0')}-${deadline.month.toString().padLeft(2, '0')}-${deadline.day.toString().padLeft(2, '0')}',
    'target': target,
    'unit': unit,
    'entries': entries.map((e) => e.toJson()).toList(),
    'items': items.map((e) => e.toJson()).toList(),
  };
  factory Goal.fromJson(Map<String, dynamic> json) => Goal(
    id: json['id'] as String,
    title: json['title'] as String,
    kind: GoalKind.values.byName(json['kind'] as String),
    deadline: DateTime.parse(json['deadline'] as String),
    target: json['target'] as int? ?? 1,
    unit: json['unit'] as String? ?? '',
    entries: (json['entries'] as List? ?? [])
        .map((e) => GoalEntry.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
    items: (json['items'] as List? ?? [])
        .map((e) => ChecklistItem.fromJson(Map<String, dynamic>.from(e as Map)))
        .toList(),
  );
}

class GoalEntry {
  GoalEntry({
    required this.id,
    required this.amount,
    required this.at,
    this.title,
    this.note,
    this.url,
    this.deleted = false,
  }) {
    final parsed = url == null ? null : Uri.tryParse(url!);
    if (id.trim().isEmpty ||
        amount < 1 ||
        (url != null &&
            (parsed == null ||
                !['http', 'https'].contains(parsed.scheme) ||
                parsed.host.isEmpty ||
                parsed.userInfo.isNotEmpty))) {
      throw ArgumentError(
        'Entry needs positive amount and optional http(s) URL',
      );
    }
  }
  final String id;
  final int amount;
  final DateTime at;
  final String? title, note, url;
  final bool deleted;
  GoalEntry copyWith({
    int? amount,
    String? title,
    String? note,
    String? url,
    bool? deleted,
    bool clearTitle = false,
    bool clearNote = false,
    bool clearUrl = false,
  }) => GoalEntry(
    id: id,
    amount: amount ?? this.amount,
    at: at,
    title: clearTitle ? null : title ?? this.title,
    note: clearNote ? null : note ?? this.note,
    url: clearUrl ? null : url ?? this.url,
    deleted: deleted ?? this.deleted,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'amount': amount,
    'at': at.toIso8601String(),
    'title': title,
    'note': note,
    'url': url,
    'deleted': deleted,
  };
  factory GoalEntry.fromJson(Map<String, dynamic> json) => GoalEntry(
    id: json['id'] as String,
    amount: json['amount'] as int,
    at: DateTime.parse(json['at'] as String),
    title: json['title'] as String?,
    note: json['note'] as String?,
    url: json['url'] as String?,
    deleted: json['deleted'] as bool? ?? false,
  );
}

class ChecklistItem {
  const ChecklistItem({
    required this.id,
    required this.title,
    this.checked = false,
    this.explanation,
  });
  final String id, title;
  final bool checked;
  final String? explanation;
  ChecklistItem copyWith({
    String? title,
    bool? checked,
    String? explanation,
    bool clearExplanation = false,
  }) => ChecklistItem(
    id: id,
    title: title ?? this.title,
    checked: checked ?? this.checked,
    explanation: clearExplanation ? null : explanation ?? this.explanation,
  );
  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'checked': checked,
    'explanation': explanation,
  };
  factory ChecklistItem.fromJson(Map<String, dynamic> json) => ChecklistItem(
    id: json['id'] as String,
    title: json['title'] as String,
    checked: json['checked'] as bool? ?? false,
    explanation: json['explanation'] as String?,
  );
}
