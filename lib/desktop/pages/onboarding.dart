// 职责: 桌面端入口页 — 背景插画 + 品牌欢迎语 + Unione 登录卡片；登录成功后用
//       平台身份补齐本地资料并直接进入主界面，不再单独弹出「设置个人空间」表单。
// 关联文件:
//   lib/shared/widgets/auth/unione_login_card.dart
//   lib/shared/hooks/use_onboarding_setup.dart
//   lib/shared/providers/unione_auth_providers.dart
//   lib/desktop/widgets/desktop_window_frame.dart
//   lib/shared/localization/locale_keys.dart
//   assets/images/onboarding-background.webp
//   lib/shared/widgets/brand_loader.dart
//   assets/translations/en/onboarding.json
//   assets/translations/zh-CN/onboarding.json
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/state-management.md
//   .agents/rules/design-system.md
//   .agents/rules/desktop-window-frame.md
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
import '../../shared/widgets/app_background.dart';
import '../../shared/widgets/auth/unione_login_card.dart';
import '../../shared/widgets/brand_loader.dart';
import '../widgets/desktop_window_frame.dart';

final _log = AppLogger.forModule('Onboarding');

const double _kCardWidth = 420;
const double _kContentColumnWidth = 456;

class OnboardingPage extends HookConsumerWidget {
  const OnboardingPage({super.key, this.firstRun = true, this.onCompleted});

  /// 真正的首次启动：只有此时才静默套用初始主题与模型默认值。
  final bool firstRun;

  /// 本地资料落库、引导标记写入后通知外层重建，界面随之切到主界面。
  final VoidCallback? onCompleted;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final colors = RevericTheme.colorsOf(context);
    final setup = useOnboardingSetup(ref, applyDefaults: firstRun);
    final showIntro = useState(true);
    final replayRequest = useState(0);
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
          'Onboarding local setup failed',
          error: error,
          stackTrace: stackTrace,
        );
      }
    }

    // 已登录但引导标记还没写入（升级上来的老用户、或上次在写入前退出）：
    // 直接用平台身份补齐本地资料，不要再让用户看到一次「登录/建档案」。
    useEffect(() {
      if (session != null) {
        unawaited(finishWithSession(session));
      }
      return null;
    }, [session]);

    final appBackgroundActive = ref.watch(appBackgroundActiveProvider);

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
      backgroundColor: appScaffoldBackgroundColor(colors, appBackgroundActive),
      body: DesktopWindowFrame(
        child: Stack(
          fit: StackFit.expand,
          children: [
            const _OnboardingBackground(),
            Align(
              alignment: Alignment.centerRight,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: RevericSpacing.x6l,
                ),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(
                    maxWidth: _kContentColumnWidth,
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      if (!showIntro.value) ...[
                        Align(
                          alignment: Alignment.centerRight,
                          child: _ReplayIntroButton(
                            onPressed: () {
                              replayRequest.value++;
                              showIntro.value = true;
                            },
                          ),
                        ),
                        const SizedBox(height: RevericSpacing.lg),
                      ],
                      const _WelcomeBlock(),
                      const SizedBox(height: RevericSpacing.x3l),
                      _EntryCard(
                        child: UnioneLoginCard(onSignedIn: finishWithSession),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            // 入场动画同时覆盖默认模型配置的加载：配置就绪且入场播完后淡出。
            if (showIntro.value)
              BrandLoader(
                key: ValueKey(replayRequest.value),
                done: setup.defaultsReady,
                onExited: () {
                  showIntro.value = false;
                },
              ),
          ],
        ),
      ),
    );
  }
}

/// 入口卡片容器：沿用原「个人空间」卡片的浮起样式，内容换成登录表单。
class _EntryCard extends StatelessWidget {
  const _EntryCard({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);

    return Container(
      width: _kCardWidth,
      padding: const EdgeInsets.symmetric(
        horizontal: RevericSpacing.x4l,
        vertical: RevericSpacing.x4l,
      ),
      decoration: BoxDecoration(
        color: colors.surface.withValues(alpha: 0.88),
        borderRadius: BorderRadius.circular(RevericRadius.large),
        border: Border.all(
          color: colors.accentWarm.withValues(alpha: 0.28),
          width: 1,
        ),
        boxShadow: [
          BoxShadow(
            color: colors.accentWarm.withValues(alpha: 0.14),
            blurRadius: 36,
            spreadRadius: 2,
            offset: const Offset(0, 10),
          ),
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 24,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: child,
    );
  }
}

class _OnboardingBackground extends StatelessWidget {
  const _OnboardingBackground();

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    const backgroundProvider = AssetImage(
      'assets/images/onboarding-background.webp',
    );
    return ColoredBox(
      color: colors.canvas,
      child: Stack(
        fit: StackFit.expand,
        children: [
          Image(
            image: backgroundProvider,
            fit: BoxFit.cover,
            alignment: Alignment.centerLeft,
            errorBuilder: (_, _, _) => ColoredBox(color: colors.canvas),
          ),
          _OnboardingBackgroundScrim(colors: colors),
        ],
      ),
    );
  }
}

class _OnboardingBackgroundScrim extends StatelessWidget {
  const _OnboardingBackgroundScrim({required this.colors});

  final RevericColors colors;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
              colors: [
                colors.canvas.withValues(alpha: 0),
                colors.canvas.withValues(alpha: 0.12),
                colors.canvas.withValues(alpha: 0.68),
                colors.canvas.withValues(alpha: 0.9),
              ],
              stops: const [0, 0.48, 0.72, 1],
            ),
          ),
        ),
        DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.bottomCenter,
              end: Alignment.topCenter,
              colors: [
                colors.canvas.withValues(alpha: 0.24),
                colors.canvas.withValues(alpha: 0),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

class _ReplayIntroButton extends StatelessWidget {
  const _ReplayIntroButton({required this.onPressed});

  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return Material(
      color: colors.surface.withValues(alpha: 0.82),
      borderRadius: BorderRadius.circular(RevericRadius.pill),
      child: InkWell(
        borderRadius: BorderRadius.circular(RevericRadius.pill),
        onTap: onPressed,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: RevericSpacing.md,
            vertical: RevericSpacing.sm,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              RevericIcon(
                RevericIcons.play_arrow,
                size: 16,
                color: colors.accent,
              ),
              const SizedBox(width: RevericSpacing.xs),
              Text(
                context.t(LocaleKeys.onboardingReplayIntro),
                style: typo.uiSmallSemibold.copyWith(color: colors.textPrimary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _WelcomeBlock extends StatelessWidget {
  const _WelcomeBlock();

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    final titleStyle = typo.display.copyWith(
      fontSize: 40,
      height: 1.12,
      fontWeight: FontWeight.w800,
      color: colors.textPrimary,
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // 品牌名单独一行：它比「欢迎使用」长，混排时会被挤到下一行、断在单词中间。
        Text(context.t(LocaleKeys.onboardingBrandWelcome), style: titleStyle),
        Text(
          appDisplayName,
          style: titleStyle.copyWith(color: colors.accentWarm),
        ),
        const SizedBox(height: RevericSpacing.lg),
        Text(
          context.t(LocaleKeys.onboardingBrandTagline),
          style: typo.body.copyWith(
            color: colors.textSecondary,
            fontWeight: FontWeight.w600,
          ),
        ),
        const SizedBox(height: RevericSpacing.x2l),
        const Wrap(
          spacing: RevericSpacing.x3l,
          runSpacing: RevericSpacing.md,
          children: [
            _FeaturePill(
              icon: RevericIcons.edit_outlined,
              titleKey: LocaleKeys.onboardingFeatureFocusTitle,
              subtitleKey: LocaleKeys.onboardingFeatureFocusSubtitle,
            ),
            _FeaturePill(
              icon: RevericIcons.auto_awesome,
              titleKey: LocaleKeys.onboardingFeatureInspirationTitle,
              subtitleKey: LocaleKeys.onboardingFeatureInspirationSubtitle,
            ),
            _FeaturePill(
              icon: RevericIcons.menu_book_outlined,
              titleKey: LocaleKeys.onboardingFeatureKnowledgeTitle,
              subtitleKey: LocaleKeys.onboardingFeatureKnowledgeSubtitle,
            ),
          ],
        ),
      ],
    );
  }
}

class _FeaturePill extends StatelessWidget {
  const _FeaturePill({
    required this.icon,
    required this.titleKey,
    required this.subtitleKey,
  });

  final String icon;
  final String titleKey;
  final String subtitleKey;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: colors.surface.withValues(alpha: 0.92),
            border: Border.all(
              color: colors.accentWarm.withValues(alpha: 0.5),
              width: 1,
            ),
          ),
          child: Center(
            child: RevericIcon(icon, size: 18, color: colors.accentWarm),
          ),
        ),
        const SizedBox(width: RevericSpacing.md),
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              context.t(titleKey),
              style: typo.uiSemibold.copyWith(color: colors.textPrimary),
            ),
            const SizedBox(height: 2),
            Text(
              context.t(subtitleKey),
              style: typo.uiSmall.copyWith(
                color: colors.textSecondary,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ],
    );
  }
}
