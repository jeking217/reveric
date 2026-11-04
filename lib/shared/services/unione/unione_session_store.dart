// 职责: 持久化 Unione 登录会话与门户地址，使登录一次后无需重复登录。
// 关联文件:
//   lib/shared/models/unione_session.dart
//   lib/shared/providers/unione_auth_providers.dart
//   lib/shared/widgets/auth/unione_login_card.dart
// 遵循的 Rules:
//   .agents/rules/service-naming.md
//

import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../../app_config.dart';
import '../../logger/app_logger.dart';
import '../../models/unione_session.dart';

final _log = AppLogger.forModule('UnioneSession');

/// 账号会话与门户地址的本地存档。
///
/// 会话存在 SharedPreferences 中：它只是"这台机器上已经登录过"的凭据，
/// 应用本身不使用平台令牌发起其它请求，因此不引入额外的加密存储依赖；
/// 令牌也不会写入日志。
class UnioneSessionStore {
  static const _sessionKey = 'unione.session.v1';
  static const _portalUrlKey = 'unione.portal_url.v1';

  /// 读出已保存的会话；没有或已损坏时返回 null。
  Future<UnioneSession?> load() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_sessionKey);
    if (raw == null || raw.isEmpty) {
      return null;
    }
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) {
        return null;
      }
      final session = UnioneSession.fromJson(decoded);
      if (session == null) {
        _log.warning('Stored Unione session is incomplete; sign-in required.');
      }
      return session;
    } on FormatException catch (error) {
      _log.warning('Stored Unione session is unreadable: ${error.message}');
      return null;
    }
  }

  /// 保存会话；失败时向上抛，由调用方提示"登录状态未能保存"。
  Future<void> save(UnioneSession session) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_sessionKey, jsonEncode(session.toJson()));
  }

  /// 清除会话（退出登录）。
  Future<void> clear() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_sessionKey);
  }

  /// 当前使用的门户地址：本地设置优先，其次编译期默认值。
  Future<String> portalUrl() async {
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_portalUrlKey)?.trim();
    if (saved != null && saved.isNotEmpty) {
      return saved;
    }
    return unioneDefaultPortalUrl;
  }

  /// 保存门户地址；空值表示恢复默认。
  Future<void> savePortalUrl(String url) async {
    final prefs = await SharedPreferences.getInstance();
    final trimmed = url.trim();
    if (trimmed.isEmpty) {
      await prefs.remove(_portalUrlKey);
      return;
    }
    await prefs.setString(_portalUrlKey, trimmed);
  }
}
