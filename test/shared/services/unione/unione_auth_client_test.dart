// 职责: 验证 Unione 登录客户端的请求形状、验证码映射与平台拒绝的错误转换。
// 关联文件:
//   lib/shared/services/unione/unione_auth_client.dart
// 遵循的 Rules:
//   .agents/rules/testing.md

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reveric/shared/services/unione/unione_auth_client.dart';

const _portal = 'http://10.0.0.7:8080/portal';

UnioneAuthClient _client(
  Future<http.Response> Function(http.Request request) handler, {
  String portalUrl = _portal,
}) {
  return UnioneAuthClient(
    portalUrl: portalUrl,
    httpClient: MockClient(handler),
  );
}

/// 带 UTF-8 编码的 JSON 响应；`http.Response` 的字符串构造按 latin1 编码，
/// 直接传中文会抛 ArgumentError。
http.Response _jsonResponse(Map<String, Object?> body, {int status = 200}) {
  return http.Response.bytes(
    utf8.encode(jsonEncode(body)),
    status,
    headers: {'content-type': 'application/json; charset=utf-8'},
  );
}

const _principal = {
  'id': 42,
  'tenantId': 7,
  'orgId': 3,
  'orgName': '总部',
  'username': 'zhangsan',
  'realName': '张三',
};

void main() {
  group('门户地址', () {
    test('去掉末尾斜杠，接口路径仍带 context path', () async {
      Uri? seen;
      final client = _client((request) async {
        seen = request.url;
        return http.Response('', 200);
      }, portalUrl: '$_portal/');
      expect(client.portalUrl, _portal);
      await expectLater(
        client.fetchCaptcha(),
        throwsA(isA<UnionePortalException>()),
      );
      expect(seen.toString(), '$_portal/api/security/captcha/image');
    });

    test('未配置完整地址时 isConfigured 为 false', () {
      expect(UnioneAuthClient(portalUrl: '').isConfigured, isFalse);
      expect(UnioneAuthClient(portalUrl: 'portal').isConfigured, isFalse);
      expect(UnioneAuthClient(portalUrl: _portal).isConfigured, isTrue);
    });
  });

  group('验证码', () {
    test('从 CAPTCHAID 响应头取 id，图片转成 data URL', () async {
      final client = _client((request) async {
        expect(request.url.toString(), '$_portal/api/security/captcha/image');
        return http.Response.bytes(
          [0xff, 0xd8, 0x01],
          200,
          headers: {'CAPTCHAID': 'cid-9', 'Content-Type': 'image/jpeg'},
        );
      });

      final captcha = await client.fetchCaptcha();
      expect(captcha.captchaId, 'cid-9');
      expect(captcha.contentType, 'image/jpeg');
      expect(captcha.image, [0xff, 0xd8, 0x01]);
      expect(captcha.dataUrl, startsWith('data:image/jpeg;base64,'));
    });

    test('平台没有下发 CAPTCHAID 时报环境问题，不当作登录失败', () async {
      final client = _client(
        (request) async => http.Response.bytes([1, 2, 3], 200),
      );
      await expectLater(
        client.fetchCaptcha(),
        throwsA(isA<UnionePortalException>()),
      );
    });
  });

  group('账号密码登录', () {
    test('按平台协议提交密文、验证码与 CAPTCHAID 头', () async {
      late http.Request captured;
      final client = _client((request) async {
        captured = request;
        return _jsonResponse({
          'success': true,
          'code': 200,
          'message': '登录成功',
          'token': 'tok-1',
          'principal': _principal,
        });
      });

      final identity = await client.signIn(
        username: 'zhangsan',
        passwordCiphertext: '04cafe',
        captcha: '8J2K',
        captchaId: 'captcha-1',
      );

      expect(captured.url.toString(), '$_portal/api/security/login/uname');
      expect(captured.method, 'POST');
      expect(captured.headers['CAPTCHAID'], 'captcha-1');
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body['username'], 'zhangsan');
      expect(body['password'], '04cafe');
      expect(body['captcha'], '8J2K');

      expect(identity.userId, 42);
      expect(identity.tenantId, 7);
      expect(identity.username, 'zhangsan');
      expect(identity.realName, '张三');
      expect(identity.orgName, '总部');
      expect(identity.token, 'tok-1');
    });

    test('没有验证码时不发 captcha 字段，也不发 CAPTCHAID 头', () async {
      late http.Request captured;
      final client = _client((request) async {
        captured = request;
        return _jsonResponse({
          'success': true,
          'token': 'tok-1',
          'principal': _principal,
        });
      });

      await client.signIn(username: 'zhangsan', passwordCiphertext: '04cafe');
      final body = jsonDecode(captured.body) as Map<String, dynamic>;
      expect(body.containsKey('captcha'), isFalse);
      expect(captured.headers.containsKey('CAPTCHAID'), isFalse);
    });

    test('success=false 时透出平台那句提示', () async {
      final client = _client(
        (request) async =>
            _jsonResponse({'success': false, 'code': 500, 'message': '密码错误'}),
      );

      await expectLater(
        client.signIn(username: 'zhangsan', passwordCiphertext: '04cafe'),
        throwsA(
          isA<UnioneAuthException>().having(
            (error) => error.message,
            'message',
            '密码错误',
          ),
        ),
      );
    });

    test('平台返回的会话缺身份时报环境问题', () async {
      final client = _client(
        (request) async => _jsonResponse({
          'success': true,
          'token': 'tok-1',
          'principal': {'id': 42, 'username': 'zhangsan'},
        }),
      );

      await expectLater(
        client.signIn(username: 'zhangsan', passwordCiphertext: '04cafe'),
        throwsA(isA<UnionePortalException>()),
      );
    });

    test('5xx 与不可解析的响应都算环境问题', () async {
      final serverError = _client(
        (request) async => http.Response('upstream down', 502),
      );
      await expectLater(
        serverError.signIn(username: 'zhangsan', passwordCiphertext: '04cafe'),
        throwsA(isA<UnionePortalException>()),
      );

      final garbage = _client(
        (request) async => http.Response('<html>login</html>', 200),
      );
      await expectLater(
        garbage.signIn(username: 'zhangsan', passwordCiphertext: '04cafe'),
        throwsA(isA<UnionePortalException>()),
      );
    });
  });
}
