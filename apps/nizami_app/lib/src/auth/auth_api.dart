class AuthSession {
  const AuthSession({
    required this.token,
    required this.userId,
    required this.username,
    required this.displayName,
    required this.roleCode,
    required this.tenantId,
    required this.tenantName,
    required this.tenantSlug,
    required this.branchIds,
    required this.mustChangePassword,
    this.permissions = const [],
    this.expiresAt,
  });

  final String token;
  final String userId;
  final String username;
  final String displayName;
  final String roleCode;
  final String tenantId;
  final String tenantName;
  final String tenantSlug;
  final List<String> branchIds;
  final bool mustChangePassword;
  final List<String> permissions;
  final DateTime? expiresAt;

  bool get isExpired =>
      expiresAt != null && !expiresAt!.isAfter(DateTime.now().toUtc());

  Map<String, Object?> toJson() => {
    'token': token,
    'user_id': userId,
    'username': username,
    'display_name': displayName,
    'role_code': roleCode,
    'tenant_id': tenantId,
    'tenant_name': tenantName,
    'tenant_slug': tenantSlug,
    'branch_ids': branchIds,
    'must_change_password': mustChangePassword,
    'permissions': permissions,
    'expires_at': expiresAt?.toUtc().toIso8601String(),
  };

  factory AuthSession.fromJson(Map<String, dynamic> json) => AuthSession(
    token: json['token']?.toString() ?? '',
    userId: json['user_id']?.toString() ?? '',
    username: json['username']?.toString() ?? '',
    displayName: json['display_name']?.toString() ?? '',
    roleCode: json['role_code']?.toString() ?? '',
    tenantId: json['tenant_id']?.toString() ?? '',
    tenantName: json['tenant_name']?.toString() ?? '',
    tenantSlug: json['tenant_slug']?.toString() ?? '',
    branchIds: (json['branch_ids'] as List? ?? const [])
        .map((value) => value.toString())
        .toList(growable: false),
    mustChangePassword: json['must_change_password'] == true,
    permissions: (json['permissions'] as List? ?? const [])
        .map((value) => value.toString())
        .toList(growable: false),
    expiresAt: DateTime.tryParse(json['expires_at']?.toString() ?? ''),
  );

  AuthSession passwordChanged() => AuthSession(
    token: token,
    userId: userId,
    username: username,
    displayName: displayName,
    roleCode: roleCode,
    tenantId: tenantId,
    tenantName: tenantName,
    tenantSlug: tenantSlug,
    branchIds: branchIds,
    mustChangePassword: false,
    permissions: permissions,
    expiresAt: expiresAt,
  );
}

abstract interface class AuthApi {
  Future<AuthSession> login({
    required String tenant,
    required String username,
    required String password,
  });

  Future<void> logout(String token);

  Future<void> changePassword({
    required String token,
    required String currentPassword,
    required String password,
    required String passwordConfirmation,
  });
}

/// Optional capability used only when restoring a locally cached session.
///
/// Keeping this separate from [AuthApi] avoids forcing lightweight/test auth
/// implementations to perform a network request. Production HTTP auth
/// implements it with the existing `auth/me` endpoint.
abstract interface class AuthSessionValidator {
  /// Confirms [cachedSession] with the server and returns its current tenant,
  /// user, branch and permission context while preserving its bearer token.
  Future<AuthSession> validateSession(AuthSession cachedSession);
}

class AuthApiException implements Exception {
  const AuthApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}
