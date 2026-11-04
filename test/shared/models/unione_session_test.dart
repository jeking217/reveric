// 职责: 验证 Unione 会话的序列化契约（字段缺失或类型不对时拒绝还原）。
// 关联文件:
//   lib/shared/models/unione_session.dart
// 遵循的 Rules:
//   .agents/rules/testing.md

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/models/unione_session.dart';

UnioneSession _session() => UnioneSession(
  userId: 42,
  tenantId: 7,
  username: 'zhangsan',
  token: 'tok-1',
  signedInAt: DateTime.utc(2026, 11, 4, 9, 30),
  realName: '张三',
  orgName: '总部',
);

void main() {
  test('序列化后可以还原', () {
    final json = jsonDecode(jsonEncode(_session().toJson()));
    final restored = UnioneSession.fromJson(json as Map<String, dynamic>);
    expect(restored, isNotNull);
    expect(restored!.userId, 42);
    expect(restored.tenantId, 7);
    expect(restored.subject, '7:42');
    expect(restored.realName, '张三');
    expect(restored.orgName, '总部');
    expect(restored.signedInAt, DateTime.utc(2026, 11, 4, 9, 30));
  });

  test('真实姓名缺省时展示账号', () {
    final session = UnioneSession(
      userId: 7,
      tenantId: 1,
      username: 'lisi',
      token: 'tok-2',
      signedInAt: DateTime.utc(2026),
      realName: '   ',
    );
    expect(session.displayName, 'lisi');
  });

  test('缺字段、空令牌或坏时间都拒绝还原', () {
    expect(UnioneSession.fromJson(const {}), isNull);
    expect(
      UnioneSession.fromJson({
        'user_id': 1,
        'tenant_id': 1,
        'username': 'a',
        'token': '',
        'signed_in_at': '2026-11-04T09:30:00.000Z',
      }),
      isNull,
    );
    expect(
      UnioneSession.fromJson({
        'user_id': 1,
        'tenant_id': 1,
        'username': 'a',
        'token': 't',
        'signed_in_at': 'not-a-date',
      }),
      isNull,
    );
    expect(
      UnioneSession.fromJson({
        'user_id': '1',
        'tenant_id': 1,
        'username': 'a',
        'token': 't',
        'signed_in_at': '2026-11-04T09:30:00.000Z',
      }),
      isNull,
    );
  });
}
