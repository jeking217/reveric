// 职责: 提供 Unione 登录相关的 provider — 会话状态、门户地址、登录与退出动作。
// 关联文件:
//   lib/shared/services/unione/unione_auth_client.dart
//   lib/shared/services/unione/unione_session_store.dart
//   lib/shared/widgets/auth/unione_login_card.dart
//   lib/main.dart
// 遵循的 Rules:
//   .agents/rules/provider-naming.md
//

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_config.dart';
import '../models/unione_session.dart';
import '../services/unione/unione_auth_client.dart';
import '../services/unione/unione_sm2.dart';
import '../services/unione/unione_session_store.dart';

/// 会话与门户地址的本地存档。
final unioneSessionStoreProvider = Provider<UnioneSessionStore>(
  (ref) => UnioneSessionStore(),
);

/// 当前门户地址；改动后重建客户端，下一次请求即用新地址。
class UnionePortalUrlController extends AsyncNotifier<String> {
  @override
  Future<String> build() => ref.watch(unioneSessionStoreProvider).portalUrl();

  /// 保存门户地址；空串表示恢复编译期默认值。
  Future<void> savePortalUrl(String url) async {
    final store = ref.read(unioneSessionStoreProvider);
    await store.savePortalUrl(url);
    state = AsyncData(await store.portalUrl());
  }
}

final unionePortalUrlProvider =
    AsyncNotifierProvider<UnionePortalUrlController, String>(
      UnionePortalUrlController.new,
    );

/// 按当前门户地址构造的平台客户端，随地址变化重建。
final unioneAuthClientProvider = Provider<UnioneAuthClient>((ref) {
  final url =
      ref.watch(unionePortalUrlProvider).value ?? unioneDefaultPortalUrl;
  final client = UnioneAuthClient(portalUrl: url);
  ref.onDispose(client.close);
  return client;
});

/// 当前登录的账号：[null] 表示未登录，需要走平台登录。
class UnioneSessionController extends AsyncNotifier<UnioneSession?> {
  @override
  Future<UnioneSession?> build() =>
      ref.watch(unioneSessionStoreProvider).load();

  /// 用平台账号密码登录，并把身份保存到本地。
  ///
  /// 明文密码只在本方法内存在：先做 SM2 加密，随即只把密文交给客户端。
  /// 平台的拒绝（密码错、验证码不符）以 [UnioneAuthException] 抛给界面。
  Future<void> signIn({
    required String username,
    required String plainPassword,
    String? captcha,
    String? captchaId,
  }) async {
    final ciphertext = encryptSm2(plainPassword, unioneSm2PublicKey);
    final identity = await ref
        .read(unioneAuthClientProvider)
        .signIn(
          username: username,
          passwordCiphertext: ciphertext,
          captcha: captcha,
          captchaId: captchaId,
        );
    final session = identity.toSession(signedInAt: DateTime.now());
    await ref.read(unioneSessionStoreProvider).save(session);
    state = AsyncData(session);
  }

  /// 退出登录：清掉本地会话，界面回到登录页。
  Future<void> signOut() async {
    await ref.read(unioneSessionStoreProvider).clear();
    state = const AsyncData(null);
  }
}

final unioneSessionProvider =
    AsyncNotifierProvider<UnioneSessionController, UnioneSession?>(
      UnioneSessionController.new,
    );
