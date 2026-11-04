// 职责: 调用 Unione 平台的图形验证码与账号密码登录接口，把平台身份落成本地会话。
// 关联文件:
//   lib/shared/services/unione/unione_sm2.dart
//   lib/shared/services/unione/unione_session_store.dart
//   lib/shared/models/unione_session.dart
//   lib/shared/providers/unione_auth_providers.dart
// 遵循的 Rules:
//   .agents/rules/error-handling.md
//   .agents/rules/service-naming.md
//
// 平台登录只认它自己的协议，所以这里直连门户（桌面端不受浏览器同源策略限制）：
//
// * 密码由调用方先用平台公钥做 SM2 加密，到达这里已是密文，本进程读不到明文。
// * 验证码答案与图形之间靠 `CAPTCHAID` 头关联：平台同时下发 cookie，但那个
//   cookie 属于另一个"浏览器"，只有响应头这一份能带回平台。
// * 平台拒绝登录时返回 HTTP 200 + `success=false`，其中 message 是给登录人看的
//   那句话（密码错、验证码过期、账号锁定），这里原样透出，不自造更含糊的文案。

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../../logger/app_logger.dart';
import '../../models/unione_session.dart';

final _log = AppLogger.forModule('UnioneAuth');

/// 平台明确拒绝了这次登录（账号密码错误、验证码不符、账号被锁等）。
class UnioneAuthException implements Exception {
  UnioneAuthException(this.message);

  /// 平台给出的、给登录人看的那句话。
  final String message;

  @override
  String toString() => 'UnioneAuthException: $message';
}

/// 平台不可达或答复无法解析，属于环境问题而非凭据问题。
class UnionePortalException implements Exception {
  UnionePortalException(this.message);

  final String message;

  @override
  String toString() => 'UnionePortalException: $message';
}

/// 一张图形验证码：图片本体，以及平台登记答案时用的 id。
class UnioneCaptcha {
  const UnioneCaptcha({
    required this.captchaId,
    required this.image,
    required this.contentType,
  });

  final String captchaId;
  final Uint8List image;
  final String contentType;

  /// 可直接给 `Image.memory` 用的 data URL。
  String get dataUrl => 'data:$contentType;base64,${base64Encode(image)}';
}

/// 平台的身份与平台签发的令牌。
class UnioneIdentity {
  const UnioneIdentity({
    required this.userId,
    required this.tenantId,
    required this.username,
    required this.token,
    this.realName,
    this.orgName,
    this.email,
  });

  final int userId;
  final int tenantId;
  final String username;
  final String token;
  final String? realName;
  final String? orgName;
  final String? email;

  UnioneSession toSession({required DateTime signedInAt}) => UnioneSession(
    userId: userId,
    tenantId: tenantId,
    username: username,
    token: token,
    signedInAt: signedInAt,
    realName: realName,
    orgName: orgName,
    email: email,
  );
}

class UnioneAuthClient {
  UnioneAuthClient({
    required String portalUrl,
    http.Client? httpClient,
    this.timeout = const Duration(seconds: 15),
  }) : portalUrl = _normalize(portalUrl),
       _http = httpClient ?? http.Client();

  /// 门户地址，含 context path，末尾斜杠已去掉。
  final String portalUrl;
  final Duration timeout;
  final http.Client _http;

  static String _normalize(String url) {
    var value = url.trim();
    while (value.endsWith('/')) {
      value = value.substring(0, value.length - 1);
    }
    return value;
  }

  /// 门户地址是否填写完整到足以发起请求。
  bool get isConfigured {
    final uri = Uri.tryParse(portalUrl);
    return uri != null && uri.hasScheme && uri.host.isNotEmpty;
  }

  /// 取一张新验证码。
  Future<UnioneCaptcha> fetchCaptcha() async {
    final response = await _send(
      () => _http.get(Uri.parse('$portalUrl/api/security/captcha/image')),
      action: 'captcha',
    );
    if (response.statusCode != 200 || response.bodyBytes.isEmpty) {
      _log.warning('Unione captcha returned ${response.statusCode}');
      throw UnionePortalException('平台没有返回验证码，请稍后重试');
    }
    final captchaId = _header(response, 'CAPTCHAID')?.trim() ?? '';
    if (captchaId.isEmpty) {
      _log.warning('Unione captcha without CAPTCHAID header');
      throw UnionePortalException('平台没有返回验证码标识，请稍后重试');
    }
    final contentType = (_header(response, 'Content-Type') ?? 'image/jpeg')
        .split(';')
        .first;
    return UnioneCaptcha(
      captchaId: captchaId,
      image: Uint8List.fromList(response.bodyBytes),
      contentType: contentType,
    );
  }

  /// 账号密码登录。[passwordCiphertext] 必须是 SM2 密文，明文不会经由这里发出。
  Future<UnioneIdentity> signIn({
    required String username,
    required String passwordCiphertext,
    String? captcha,
    String? captchaId,
  }) async {
    final body = <String, dynamic>{
      'username': username,
      'password': passwordCiphertext,
      if (captcha != null && captcha.isNotEmpty) 'captcha': captcha,
    };
    final response = await _send(
      () => _http.post(
        Uri.parse('$portalUrl/api/security/login/uname'),
        headers: {
          'Content-Type': 'application/json',
          if (captchaId != null && captchaId.isNotEmpty) 'CAPTCHAID': captchaId,
        },
        body: jsonEncode(body),
      ),
      action: 'login',
    );
    return _identityFrom(_envelope(response, action: 'login'));
  }

  void close() => _http.close();

  Future<http.Response> _send(
    Future<http.Response> Function() request, {
    required String action,
  }) async {
    try {
      return await request().timeout(timeout);
    } on TimeoutException {
      _log.warning('Unione $action timed out');
      throw UnionePortalException('连接登录服务器超时，请检查网络后重试');
    } on SocketException catch (error) {
      _log.warning('Unione $action unreachable: ${error.osError?.message}');
      throw UnionePortalException('无法连接登录服务器，请检查门户地址与网络');
    } on http.ClientException catch (error) {
      _log.warning('Unione $action failed: ${error.message}');
      throw UnionePortalException('无法连接登录服务器，请检查门户地址与网络');
    }
  }

  /// 解析 `Results`/`LoginResult` 信封；`success=false` 转成平台那句提示。
  Map<String, dynamic> _envelope(
    http.Response response, {
    required String action,
  }) {
    if (response.statusCode >= 500) {
      _log.warning('Unione $action answered ${response.statusCode}');
      throw UnionePortalException('登录服务器暂时不可用，请稍后重试');
    }
    final Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(response.bodyBytes));
    } on FormatException catch (error) {
      _log.warning('Unione $action returned unreadable body: ${error.message}');
      throw UnionePortalException('登录服务器返回了无法识别的内容');
    }
    if (decoded is! Map<String, dynamic>) {
      throw UnionePortalException('登录服务器返回了无法识别的内容');
    }
    if (decoded['success'] != true) {
      final message = '${decoded['message'] ?? ''}'.trim();
      _log.info('Unione $action refused by platform');
      throw UnioneAuthException(message.isEmpty ? '登录失败，请重试' : message);
    }
    return decoded;
  }

  UnioneIdentity _identityFrom(Map<String, dynamic> payload) {
    final principal = payload['principal'];
    final token = payload['token'];
    if (principal is! Map<String, dynamic> ||
        token is! String ||
        token.isEmpty) {
      _log.warning('Unione login result carried no session');
      throw UnionePortalException('登录服务器没有返回会话信息');
    }
    final userId = _asInt(principal['id']);
    final tenantId = _asInt(principal['tenantId']);
    final username = '${principal['username'] ?? ''}'.trim();
    if (userId == null || tenantId == null || username.isEmpty) {
      _log.warning('Unione login result carried no identity');
      throw UnionePortalException('登录服务器没有返回账号身份');
    }
    String? text(Object? value) {
      if (value is! String) return null;
      final trimmed = value.trim();
      return trimmed.isEmpty ? null : trimmed;
    }

    return UnioneIdentity(
      userId: userId,
      tenantId: tenantId,
      username: username,
      token: token,
      realName: text(principal['realName']) ?? text(principal['aliasName']),
      orgName: text(principal['orgName']),
      email: text(principal['email']),
    );
  }

  static int? _asInt(Object? value) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value.trim());
    return null;
  }
}

/// 读取响应头：真实链路里 http 会把头名统一小写，测试替身可能保留原样，
/// 因此大小写都要能命中。
String? _header(http.Response response, String name) {
  for (final entry in response.headers.entries) {
    if (entry.key.toLowerCase() == name.toLowerCase()) {
      return entry.value;
    }
  }
  return null;
}
