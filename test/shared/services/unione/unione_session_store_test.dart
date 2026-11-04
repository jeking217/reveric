// 职责: 验证 Unione 会话与门户地址的本地持久化（含损坏存档的回退）。
// 关联文件:
//   lib/shared/services/unione/unione_session_store.dart
//   lib/shared/models/unione_session.dart
// 遵循的 Rules:
//   .agents/rules/testing.md

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/app_config.dart';
import 'package:reveric/shared/models/unione_session.dart';
import 'package:reveric/shared/services/unione/unione_session_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

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
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('首次启动没有会话', () async {
    final store = UnioneSessionStore();
    expect(await store.load(), isNull);
  });

  test('保存后可以读回同一身份', () async {
    final store = UnioneSessionStore();
    await store.save(_session());

    final restored = await store.load();
    expect(restored, isNotNull);
    expect(restored!.userId, 42);
    expect(restored.tenantId, 7);
    expect(restored.subject, '7:42');
    expect(restored.username, 'zhangsan');
    expect(restored.displayName, '张三');
    expect(restored.orgName, '总部');
    expect(restored.token, 'tok-1');
    expect(restored.signedInAt, DateTime.utc(2026, 11, 4, 9, 30));
  });

  test('退出登录后会话被清除', () async {
    final store = UnioneSessionStore();
    await store.save(_session());
    await store.clear();
    expect(await store.load(), isNull);
  });

  test('存档损坏或字段缺失时当作未登录', () async {
    final store = UnioneSessionStore();

    SharedPreferences.setMockInitialValues({
      'unione.session.v1': 'not json at all',
    });
    expect(await store.load(), isNull);

    SharedPreferences.setMockInitialValues({
      'unione.session.v1': jsonEncode({'user_id': 42, 'username': 'zhangsan'}),
    });
    expect(await store.load(), isNull);
  });

  test('没有真实姓名时展示账号', () async {
    final store = UnioneSessionStore();
    await store.save(
      UnioneSession(
        userId: 7,
        tenantId: 1,
        username: 'lisi',
        token: 'tok-2',
        signedInAt: DateTime.utc(2026),
      ),
    );
    final restored = await store.load();
    expect(restored!.displayName, 'lisi');
  });

  test('门户地址默认取编译期配置，保存后以本地为准，空值恢复默认', () async {
    final store = UnioneSessionStore();
    expect(await store.portalUrl(), unioneDefaultPortalUrl);

    await store.savePortalUrl('http://192.168.1.10:8080/portal');
    expect(await store.portalUrl(), 'http://192.168.1.10:8080/portal');

    await store.savePortalUrl('');
    expect(await store.portalUrl(), unioneDefaultPortalUrl);
  });
}
