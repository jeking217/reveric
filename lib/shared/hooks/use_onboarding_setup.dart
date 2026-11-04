// 职责: 入口页的跨端状态 — 首次启动静默应用默认配置，并把 Unione 登录结果落成本地资料。
// 关联文件:
//   lib/desktop/pages/onboarding.dart
//   lib/mobile/pages/onboarding_page.dart
//   lib/shared/providers/settings_providers.dart
//   lib/shared/services/app_initialization.dart
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/state-management.md
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../models/unione_session.dart';
import '../providers/novel_providers.dart';
import '../providers/settings_providers.dart';
import '../services/app_initialization.dart';

class OnboardingSetup {
  const OnboardingSetup({
    required this.defaultsReady,
    required this.completeWithSession,
  });

  /// 默认主题与模型是否已应用。
  final bool defaultsReady;

  /// 用 Unione 登录结果补齐本地资料并标记引导完成。
  ///
  /// 登录已经是「认证过一次」：本地称呼直接取平台身份，不再让用户重填一遍；
  /// 头像留空，之后可在用户资料里改。
  final Future<void> Function(UnioneSession session) completeWithSession;
}

/// [applyDefaults] 只在真正的首次启动为 true：退出登录后入口页会再次出现，
/// 那时不能再把用户改过的主题和模型默认值重置回初始配置。
OnboardingSetup useOnboardingSetup(WidgetRef ref, {bool applyDefaults = true}) {
  final settingsNotifier = ref.read(appSettingsProvider.notifier);
  final defaultsReady = useState(false);

  useEffect(() {
    if (!applyDefaults) {
      defaultsReady.value = true;
      return null;
    }
    () async {
      await settingsNotifier.applyOnboardingDefaults(
        theme: AppTheme.classic,
        themeMode: AppThemeMode.system,
      );
      defaultsReady.value = true;
    }();
    return null;
  }, []);

  /// 平台身份即本地称呼：保留用户已改过的称呼，没有才用平台显示名兜底。
  Future<void> completeWithSession(UnioneSession session) async {
    final settings = ref.read(appSettingsProvider).asData?.value;
    final existing = settings?.username.trim() ?? '';
    if (existing.isEmpty) {
      await settingsNotifier.setUsername(_localNameFor(session));
    }
    await markOnboardingCompleted(ref.read(appDatabaseProvider));
  }

  return OnboardingSetup(
    defaultsReady: defaultsReady.value,
    completeWithSession: completeWithSession,
  );
}

/// 本地称呼沿用「20 字以内」的既有上限，超长的平台姓名截断而不是报错。
String _localNameFor(UnioneSession session) {
  final name = session.displayName.trim();
  if (name.isEmpty) {
    return session.username;
  }
  final runes = name.runes.toList();
  if (runes.length <= 20) {
    return name;
  }
  return String.fromCharCodes(runes.take(20));
}
