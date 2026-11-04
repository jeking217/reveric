// 职责: Unione 平台登录后保存在本地的账号会话（平台身份 + 平台令牌 + 登录时间）。
// 关联文件:
//   lib/shared/services/unione/unione_auth_client.dart
//   lib/shared/services/unione/unione_session_store.dart
//   lib/shared/providers/unione_auth_providers.dart
//

/// 平台身份在本地的快照。
///
/// 身份以 `{tenantId}:{userId}` 为准：Unione 的用户 id 只在租户内唯一，
/// 只用 id 会让 A 租户的 42 号和 B 租户的 42 号撞成同一个人。
class UnioneSession {
  const UnioneSession({
    required this.userId,
    required this.tenantId,
    required this.username,
    required this.token,
    required this.signedInAt,
    this.orgName,
    this.realName,
    this.email,
  });

  final int userId;
  final int tenantId;
  final String username;

  /// 平台签发的令牌。只在本地留档：应用其余请求不依赖它，也不写入日志。
  final String token;
  final DateTime signedInAt;

  final String? orgName;
  final String? realName;
  final String? email;

  /// 跨租户唯一的身份标识。
  String get subject => '$tenantId:$userId';

  /// 界面上展示的名字：真实姓名优先，其次账号。
  String get displayName {
    final name = realName?.trim();
    if (name != null && name.isNotEmpty) {
      return name;
    }
    return username;
  }

  Map<String, dynamic> toJson() => {
    'user_id': userId,
    'tenant_id': tenantId,
    'username': username,
    'token': token,
    'signed_in_at': signedInAt.toIso8601String(),
    if (orgName != null) 'org_name': orgName,
    if (realName != null) 'real_name': realName,
    if (email != null) 'email': email,
  };

  /// 从本地存档还原；字段缺失或类型不对时返回 null，让调用方重新登录，
  /// 而不是拿着半个会话进入应用。
  static UnioneSession? fromJson(Map<String, dynamic> json) {
    final userId = json['user_id'];
    final tenantId = json['tenant_id'];
    final username = json['username'];
    final token = json['token'];
    final signedInAt = DateTime.tryParse('${json['signed_in_at'] ?? ''}');
    if (userId is! int ||
        tenantId is! int ||
        username is! String ||
        username.isEmpty ||
        token is! String ||
        token.isEmpty ||
        signedInAt == null) {
      return null;
    }
    String? text(Object? value) {
      if (value is! String) return null;
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }

    return UnioneSession(
      userId: userId,
      tenantId: tenantId,
      username: username,
      token: token,
      signedInAt: signedInAt,
      orgName: text(json['org_name']),
      realName: text(json['real_name']),
      email: text(json['email']),
    );
  }
}
