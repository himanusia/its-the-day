import 'dart:convert';

import 'groups_api.dart';

enum GroupRole { owner, member, unknown }

extension GroupRoleLabels on GroupRole {
  String get label => switch (this) {
    GroupRole.owner => 'Owner',
    GroupRole.member => 'Member',
    GroupRole.unknown => 'Member',
  };
}

GroupRole groupRoleFromJson(Object? value) => switch (value?.toString()) {
  'owner' => GroupRole.owner,
  'member' => GroupRole.member,
  _ => GroupRole.unknown,
};

class GroupSummary {
  const GroupSummary({
    required this.id,
    required this.name,
    required this.role,
    required this.memberCount,
    this.joinCode,
    this.createdAt,
  });

  final String id;
  final String name;
  final String? joinCode;
  final GroupRole role;
  final int memberCount;
  final DateTime? createdAt;

  factory GroupSummary.fromJson(Map<String, dynamic> json) {
    return GroupSummary(
      id: _requiredString(json['id']),
      name: _requiredString(json['name']),
      joinCode: _optionalString(json['joinCode']),
      role: groupRoleFromJson(json['role']),
      memberCount: _integer(json['memberCount']),
      createdAt: _date(json['createdAt']),
    );
  }
}

class GroupMutationResult {
  const GroupMutationResult({
    required this.id,
    required this.name,
    required this.role,
    this.joinCode,
  });

  final String id;
  final String name;
  final GroupRole role;
  final String? joinCode;

  factory GroupMutationResult.fromJson(Map<String, dynamic> json) {
    return GroupMutationResult(
      id: _requiredString(json['id']),
      name: _requiredString(json['name']),
      role: groupRoleFromJson(json['role']),
      joinCode: _optionalString(json['joinCode']),
    );
  }
}

class GroupMember {
  const GroupMember({
    required this.role,
    required this.active,
    this.joinedAt,
    this.revokedAt,
  });

  final GroupRole role;
  final bool active;
  final DateTime? joinedAt;
  final DateTime? revokedAt;

  factory GroupMember.fromJson(Map<String, dynamic> json) {
    return GroupMember(
      role: groupRoleFromJson(json['role']),
      active: _boolean(json['active']),
      joinedAt: _date(json['joinedAt']),
      revokedAt: _date(json['revokedAt']),
    );
  }
}

/// Keeps the server-backed group routes separate from the local tracker while
/// reusing the existing authenticated transport and error states.
class GroupMembershipApi {
  const GroupMembershipApi(this.api);

  final GroupsApi api;

  Future<List<GroupSummary>> listGroups() async {
    final body = await api.request('GET', '/api/groups');
    final rows = body['groups'];
    if (rows is! List) throw _invalidResponse();
    return [for (final row in rows) GroupSummary.fromJson(_record(row))];
  }

  Future<GroupMutationResult> createGroup(
    String name, {
    String? operationId,
  }) async {
    final value = name.trim();
    if (value.isEmpty) {
      throw const GroupsRequestError('Enter a group name.');
    }
    final body = await api.mutate(
      'POST',
      '/api/groups',
      body: {'name': value},
      operationId: operationId,
    );
    return GroupMutationResult.fromJson(body);
  }

  Future<GroupMutationResult> joinGroup(
    String code, {
    String? operationId,
  }) async {
    final value = code.trim();
    if (value.isEmpty) {
      throw const GroupsRequestError('Enter an invite code.');
    }
    final body = await api.mutate(
      'POST',
      '/api/groups/join',
      body: {'code': value},
      operationId: operationId,
    );
    return GroupMutationResult.fromJson(body);
  }

  Future<List<GroupMember>> listMembers(String groupId) async {
    if (groupId.trim().isEmpty) throw _invalidResponse();
    final Map<String, dynamic> body;
    try {
      body = await api.request(
        'GET',
        '/api/groups/${Uri.encodeComponent(groupId)}/members',
      );
    } on GroupsRequestError catch (error) {
      // The server intentionally masks missing/non-member groups with 404.
      if (error.message == 'not_found') {
        throw const GroupsPermissionDenied('Group unavailable to this account.');
      }
      rethrow;
    }
    final rows = body['members'];
    if (rows is! List) throw _invalidResponse();
    return [for (final row in rows) GroupMember.fromJson(_record(row))];
  }
}

/// An operation key stays stable while the form payload is unchanged. This
/// lets a retry replay the server mutation rather than creating another group
/// or membership.
class StableOperationId {
  StableOperationId({String Function()? generator})
    : _generator = generator ?? GroupsApi.operationKey;

  final String Function() _generator;
  String? _fingerprint;
  String? _operationId;

  String forPayload(Map<String, Object?> payload) {
    final fingerprint = jsonEncode(payload);
    if (_fingerprint != fingerprint) {
      _fingerprint = fingerprint;
      _operationId = _generator();
    }
    return _operationId!;
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
  if (value is String && value.isNotEmpty) return value;
  return null;
}

int _integer(Object? value) {
  if (value is int) return value;
  if (value is num) return value.toInt();
  return 0;
}

bool _boolean(Object? value) => value == true || value == 1 || value == '1';

DateTime? _date(Object? value) {
  if (value is! String) return null;
  return DateTime.tryParse(value);
}

GroupsRequestError _invalidResponse() =>
    const GroupsRequestError('Server returned an invalid groups response.');
