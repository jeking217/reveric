// 职责: 验证启动参数里一次性票据与签发方地址的解析规则。
// 关联文件:
//   lib/shared/services/unione/handoff_ticket.dart
// 遵循的 Rules:
//   .agents/rules/testing.md

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/services/unione/handoff_ticket.dart';

const _ticket = 'tk-0123456789abcdef0123456789abcdef';
const _issuer = 'http://10.0.0.7:3000';

HandoffAttempt _attempt(List<String> arguments, [Map<String, String>? env]) {
  return HandoffTicket.fromArguments(arguments, environment: env ?? const {});
}

HandoffTicket? _parse(List<String> arguments, [Map<String, String>? env]) {
  return _attempt(arguments, env).ticket;
}

void main() {
  group('命令行解析', () {
    test('等号形式：票据与签发方都取到，末尾斜杠去掉', () {
      final handoff = _parse([
        '--unione-ticket=$_ticket',
        '--unione-issuer=$_issuer/',
      ]);

      expect(handoff, isNotNull);
      expect(handoff!.ticket, _ticket);
      // 核销路径由客户端拼在后面，多一个斜杠会拼出 `//api`。
      expect(handoff.issuer, _issuer);
    });

    test('空格形式：参数分两个给出', () {
      final handoff = _parse([
        '--unione-ticket',
        _ticket,
        '--unione-issuer',
        _issuer,
      ]);

      expect(handoff?.ticket, _ticket);
      expect(handoff?.issuer, _issuer);
    });

    test('没有票据参数时当作普通启动：既没有票据，也没有要解释的问题', () {
      final plain = _attempt(const []);
      expect(plain.ticket, isNull);
      // 双击图标启动就走这条路，不该因为「没有票据」弹任何提示。
      expect(plain.problem, isNull);

      expect(_attempt(const ['--fullscreen']).problem, isNull);
    });

    test('只有票据没有签发方、或反过来，都没有票据但留下原因', () {
      final noIssuer = _attempt(['--unione-ticket=$_ticket']);
      expect(noIssuer.ticket, isNull);
      expect(noIssuer.problem, contains('签发方'));

      final noTicket = _attempt(['--unione-issuer=$_issuer']);
      expect(noTicket.ticket, isNull);
      expect(noTicket.problem, contains('票据'));
    });

    test('不是票据形状的值被拒绝，避免把普通参数当凭据', () {
      for (final bogus in ['abc', 'tk-']) {
        final attempt = _attempt([
          '--unione-ticket=$bogus',
          '--unione-issuer=$_issuer',
        ]);
        expect(attempt.ticket, isNull);
        // 调用方明明给了票据却不能用，用户需要知道为何停在登录页。
        expect(attempt.problem, contains('票据无效'));
      }
    });

    test('签发方必须是 http(s) 且带主机', () {
      for (final issuer in ['ftp://x', 'localhost', '']) {
        final attempt = _attempt([
          '--unione-ticket=$_ticket',
          '--unione-issuer=$issuer',
        ]);
        expect(attempt.ticket, isNull, reason: issuer);
        expect(attempt.problem, isNotNull, reason: issuer);
      }
    });

    test('可用的交接不带问题', () {
      final attempt = _attempt([
        '--unione-ticket=$_ticket',
        '--unione-issuer=$_issuer',
      ]);
      expect(attempt.ticket, isNotNull);
      expect(attempt.problem, isNull);
    });
  });

  group('环境变量兜底', () {
    test('没有命令行参数时读环境变量', () {
      final handoff = _parse(const [], {
        'UNIONE_TICKET': _ticket,
        'UNIONE_ISSUER': _issuer,
      });

      expect(handoff?.ticket, _ticket);
      expect(handoff?.issuer, _issuer);
    });

    test('命令行优先于环境变量', () {
      final handoff = _parse(
        ['--unione-issuer=https://drama.example.com'],
        {'UNIONE_TICKET': _ticket, 'UNIONE_ISSUER': _issuer},
      );

      expect(handoff?.issuer, 'https://drama.example.com');
    });
  });

  test('toString 不带票据：日志里不该有一次性凭据', () {
    const handoff = HandoffTicket(ticket: _ticket, issuer: _issuer);

    expect(handoff.toString(), contains(_issuer));
    expect(handoff.toString(), isNot(contains(_ticket)));
  });
}
