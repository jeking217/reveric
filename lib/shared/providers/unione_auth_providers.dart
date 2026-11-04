// 职责: 提供 Unione 登录相关的 provider — 会话状态、门户地址、登录与退出动作、外部程序传入的交接票据。
// 关联文件:
//   lib/shared/services/unione/unione_auth_client.dart
//   lib/shared/services/unione/unione_session_store.dart
//   lib/shared/services/unione/handoff_ticket.dart
//   lib/shared/widgets/auth/unione_login_card.dart
//   lib/main.dart
// 遵循的 Rules:
//   .agents/rules/provider-naming.md
//

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../app_config.dart';
import '../logger/app_logger.dart';
import '../models/unione_session.dart';
import '../services/unione/handoff_ticket.dart';
import '../services/unione/unione_auth_client.dart';
import '../services/unione/unione_sm2.dart';
import '../services/unione/unione_session_store.dart';

final _log = AppLogger.forModule('UnioneAuth');

/// 启动时由外部程序（AgenticOS）传入的交接票据。
///
/// 默认没有；main 入口解析命令行后用 `overrideWithValue` 注入。放在 provider 里
/// 而不是读全局变量，是为了让测试能直接构造「有票据 / 无票据」两种启动。
final handoffTicketProvider = Provider<HandoffTicket?>((ref) => null);

/// 交接参数给了却用不了时的那句解释，同样由 main 注入。
///
/// 与 [handoffTicketErrorProvider] 分开：那句「参数不成立」在核销之前就确定了，
/// 没有会话状态可供它挂靠，登录表单起来时要能直接读到。
final handoffProblemProvider = Provider<String?>((ref) => null);

/// 交接票据核销失败的提示，登录表单首次显示时读取一次。
///
/// 失败要落在登录页上而不是一闪而过的提示：票据失效意味着用户需要自己登录，
/// 而登录表单正是他接下来要操作的地方。
class HandoffTicketError extends Notifier<String?> {
  @override
  String? build() => null;

  void report(String message) => state = message;

  /// 登录表单把它显示过之后清掉，重新登录时不再挂着上一次的失败。
  void clear() => state = null;
}

final handoffTicketErrorProvider =
    NotifierProvider<HandoffTicketError, String?>(HandoffTicketError.new);

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
  Future<UnioneSession?> build() async {
    final store = ref.watch(unioneSessionStoreProvider);
    final saved = await store.load();
    // 本地已有登录信息：直接进入首页，交接票据连核销都不必（票据是一次性的，
    // 白白花掉只会让签发方以为这次登录失败）。
    if (saved != null) {
      return saved;
    }

    final handoff = ref.watch(handoffTicketProvider);
    if (handoff == null) {
      return null;
    }

    // 外部程序带票启动：核销票据换身份，成功即等同于刚刚登录过。
    try {
      final identity = await ref
          .read(unioneAuthClientProvider)
          .redeemHandoffTicket(
            ticket: handoff.ticket,
            issuerUrl: handoff.issuer,
          );
      final session = identity.toSession(signedInAt: DateTime.now());
      await store.save(session);
      _log.info('Handoff ticket redeemed for ${session.subject}');
      return session;
    } on UnioneAuthException catch (error) {
      _log.warning('Handoff ticket refused: ${error.message}');
      ref.read(handoffTicketErrorProvider.notifier).report(error.message);
      return null;
    } on UnionePortalException catch (error) {
      _log.warning('Handoff ticket could not be redeemed: ${error.message}');
      ref.read(handoffTicketErrorProvider.notifier).report(error.message);
      return null;
    } on Object catch (error, stackTrace) {
      _log.error(
        'Handoff ticket redemption failed unexpectedly',
        error: error,
        stackTrace: stackTrace,
      );
      ref.read(handoffTicketErrorProvider.notifier).report('一次性登录票据核销失败，请手动登录');
      return null;
    }
  }

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
