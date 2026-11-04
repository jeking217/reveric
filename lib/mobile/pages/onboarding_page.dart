// 职责: 移动端入口页 — 品牌欢迎语 + Unione 登录表单；登录成功后用平台身份补齐
//       本地资料并直接进入移动壳，不再单独要求填写称呼与头像。
// 关联文件:
//   lib/shared/widgets/auth/unione_login_card.dart
//   lib/shared/hooks/use_onboarding_setup.dart
//   lib/shared/providers/unione_auth_providers.dart
//   lib/shared/localization/locale_keys.dart
//   assets/translations/en/onboarding.json
//   assets/translations/zh-CN/onboarding.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/state-management.md
//   .agents/rules/design-system.md
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../shared/app_config.dart';
import '../../shared/hooks/use_onboarding_setup.dart';
import '../../shared/localization/app_localization.dart';
import '../../shared/localization/locale_keys.dart';
import '../../shared/logger/app_logger.dart';
import '../../shared/models/unione_session.dart';
import '../../shared/providers/unione_auth_providers.dart';
import '../../shared/theme/theme.dart';
import '../../shared/widgets/auth/unione_login_card.dart';
import '../../shared/widgets/brand_loader.dart';

final _log = AppLogger.forModule('MobileOnboarding');

class MobileOnboardingPage extends HookConsumerWidget {
  const MobileOnboardingPage({
    super.key,
    this.firstRun = true,
    this.onCompleted,
  });

  /// 真正的首次启动：只有此时才静默套用初始主题与模型默认值。
  final bool firstRun;

  /// 本地资料落库、引导标记写入后通知外层重建。
  final VoidCallback? onCompleted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final setup = useOnboardingSetup(ref, applyDefaults: firstRun);
    final finishing = useRef(false);
    final session = ref.watch(unioneSessionProvider).value;

    Future<void> finishWithSession(UnioneSession session) async {
      if (finishing.value) {
        return;
      }
      finishing.value = true;
      try {
        await setup.completeWithSession(session);
        onCompleted?.call();
      } catch (error, stackTrace) {
        finishing.value = false;
        _log.error(
          'Mobile local setup failed',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }

    useEffect(() {
      if (session != null) {
        unawaited(finishWithSession(session));
      }
      return null;
    }, [session]);

    if (session != null) {
      return Scaffold(
        backgroundColor: colors.canvas,
        body: const BrandLoader(
          skipIntro: true,
          showDelay: Duration(milliseconds: 400),
        ),
      );
    }

    return Scaffold(
      backgroundColor: colors.canvas,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: RevericSpacing.x4l),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const Spacer(),
              // 品牌名单独一行：与「欢迎使用」混排时会被挤断在单词中间。
              Text(
                context.t(LocaleKeys.onboardingBrandWelcome),
                style: typo.display.copyWith(
                  color: colors.textPrimary,
                  fontWeight: FontWeight.w800,
                ),
              ),
              Text(
                appDisplayName,
                style: typo.display.copyWith(
                  color: colors.accentWarm,
                  fontWeight: FontWeight.w800,
                ),
              ),
              const SizedBox(height: RevericSpacing.md),
              Text(
                context.t(LocaleKeys.onboardingBrandTagline),
                style: typo.body.copyWith(color: colors.textSecondary),
              ),
              const SizedBox(height: RevericSpacing.x5l),
              UnioneLoginCard(onSignedIn: finishWithSession),
              const Spacer(flex: 2),
            ],
          ),
        ),
      ),
    );
  }
}
