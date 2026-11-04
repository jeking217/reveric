// 职责: 解析外部程序（AgenticOS）启动本应用时传入的一次性登录票据与签发方地址。
// 关联文件:
//   lib/shared/services/unione/unione_auth_client.dart
//   lib/shared/providers/unione_auth_providers.dart
//   lib/main.dart
// 遵循的 Rules:
//   .agents/rules/error-handling.md
//
// 交接只有两个值：票据本身，和该去哪里核销它。两者都由启动方在命令行上给出：
//
//     reveric.exe --unione-ticket tk-xxxx --unione-issuer http://10.0.0.7:3000
//
// 命令行是刻意选的：票据两分钟、一次性的，泄露窗口最短；而且它跟着这一次启动
// 走，不会像环境变量那样被后续任何子进程继承。环境变量仍保留为兜底，供不方便
// 改命令行的启动器使用。
//
// 正常启动本来就没有参数，所以「一个交接参数都没有」不是错误，静默按未登录
// 处理。但只要调用方明确给了参数却用不了（票据形状不对、缺签发方），就是一次
// 本该自动登录却没成功的启动，必须让用户看见原因：他会照着提示手动登录，而不是
// 对着一个凭空出现的登录页发愣。

import 'dart:io';

import '../../logger/app_logger.dart';

final _log = AppLogger.forModule('Handoff');

/// 票据前缀。签发方与核销方都按它判断这个值是不是票据。
const _kTicketPrefix = 'tk-';

/// 平台一次性票据的开始，以及它指向的核销地址。
class HandoffTicket {
  const HandoffTicket({required this.ticket, required this.issuer});

  /// `tk-` 开头的一次性票据，两分钟内有效、只能核销一次。
  final String ticket;

  /// 签发方地址，形如 `http://10.0.0.7:3000`，末尾没有斜杠。
  final String issuer;

  /// 从启动参数（以及兜底的环境变量）里读出交接信息；没有或不完整时为 null。
  static HandoffAttempt fromArguments(
    List<String> arguments, {
    Map<String, String>? environment,
  }) {
    final env = environment ?? Platform.environment;
    final ticket =
        _flag(arguments, '--unione-ticket') ?? env['UNIONE_TICKET']?.trim();
    final issuer =
        _flag(arguments, '--unione-issuer') ?? env['UNIONE_ISSUER']?.trim();

    if (ticket == null && issuer == null) {
      return const HandoffAttempt.none();
    }
    if (ticket == null || ticket.isEmpty) {
      return _reject('issued without a ticket', '启动参数缺少一次性登录票据，请手动登录');
    }
    if (!ticket.startsWith(_kTicketPrefix) || ticket.length < 12) {
      return _reject(
        'ticket does not look like a ticket',
        '启动参数里的一次性登录票据无效，请手动登录',
      );
    }
    if (issuer == null || issuer.isEmpty) {
      return _reject('ticket given without an issuer', '启动参数缺少签发方地址，请手动登录');
    }
    final normalized = _normalizeIssuer(issuer);
    if (normalized == null) {
      return _reject(
        'issuer is not an http(s) address',
        '一次性登录的签发方地址不可用，请手动登录',
      );
    }
    return HandoffAttempt.usable(
      HandoffTicket(ticket: ticket, issuer: normalized),
    );
  }

  /// 日志里只留签发方：票据本身等同于一次登录凭据，不进日志。
  @override
  String toString() => 'HandoffTicket(issuer: $issuer)';
}

/// 一次启动的交接结果：有票据就核销，没有票据就按未登录处理。
///
/// [problem] 只在调用方给了交接参数却不能被使用时才有值：它是登录页横幅上那句
/// 解释，说明为什么本该自动登录的启动停在了登录页。
class HandoffAttempt {
  const HandoffAttempt.usable(HandoffTicket this.ticket) : problem = null;

  const HandoffAttempt.none() : ticket = null, problem = null;

  const HandoffAttempt.rejected(this.problem) : ticket = null;

  final HandoffTicket? ticket;
  final String? problem;
}

HandoffAttempt _reject(String reason, String message) {
  _log.warning('Handoff parameters rejected: $reason');
  return HandoffAttempt.rejected(message);
}

/// `--name=value` 或 `--name value`，取第一个命中的。
String? _flag(List<String> arguments, String name) {
  for (var index = 0; index < arguments.length; index++) {
    final argument = arguments[index];
    if (argument == name) {
      final next = index + 1 < arguments.length ? arguments[index + 1] : null;
      return next?.trim();
    }
    if (argument.startsWith('$name=')) {
      return argument.substring(name.length + 1).trim();
    }
  }
  return null;
}

/// 只接受 http/https 且带主机的地址，并去掉末尾斜杠：核销路径由客户端拼在后面。
String? _normalizeIssuer(String value) {
  final uri = Uri.tryParse(value.trim());
  if (uri == null || !uri.hasScheme || uri.host.isEmpty) {
    return null;
  }
  if (uri.scheme != 'http' && uri.scheme != 'https') {
    return null;
  }
  var normalized = value.trim();
  while (normalized.endsWith('/')) {
    normalized = normalized.substring(0, normalized.length - 1);
  }
  return normalized;
}
