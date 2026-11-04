// 职责: 验证移动端入口页展示的是 Unione 登录表单（而不是昵称/头像建档表单），
//       并校验空账号密码时的本地提示。
// 关联文件:
//   lib/mobile/pages/onboarding_page.dart
//   lib/shared/widgets/auth/unione_login_card.dart
//   lib/shared/providers/unione_auth_providers.dart
// 遵循的 Rules:
//   .agents/rules/testing.md

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:reveric/mobile/pages/onboarding_page.dart';
import 'package:reveric/shared/localization/merging_asset_loader.dart';
import 'package:reveric/shared/models/ai_provider.dart';
import 'package:reveric/shared/providers/official_skill_sync_providers.dart';
import 'package:reveric/shared/providers/settings_providers.dart';
import 'package:reveric/shared/providers/unione_auth_providers.dart';
import 'package:reveric/shared/services/official_skill_sync.dart';
import 'package:reveric/shared/services/unione/unione_auth_client.dart';
import 'package:reveric/shared/theme/theme.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await EasyLocalization.ensureInitialized();
  });

  testWidgets('entry page shows the platform sign-in form', (tester) async {
    await _pumpOnboarding(tester);

    // 账号、密码两个输入框；验证码在取图失败时不出现，但表单本身必须是登录表单。
    expect(find.byType(TextField), findsNWidgets(2));
    expect(find.text('Sign in'), findsOneWidget);
    // 旧的昵称/头像建档表单已经从这里移除。
    expect(
      find.byKey(const ValueKey('onboarding-avatar-picker')),
      findsNothing,
    );
  });

  testWidgets('empty credentials stay local and show a hint', (tester) async {
    await _pumpOnboarding(tester);

    await tester.tap(find.text('Sign in'));
    await tester.pump();

    expect(find.text('Enter your account and password'), findsOneWidget);
  });
}

/// 门户地址不可用：验证码取不到，页面走「点击刷新验证码」的降级分支，
/// 测试因此不依赖任何网络。
Future<void> _pumpOnboarding(WidgetTester tester) async {
  tester.view.physicalSize = const Size(430, 1000);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
  await tester.pumpWidget(
    ProviderScope(
      overrides: [
        appSettingsProvider.overrideWith(_Settings.new),
        officialSkillSyncProvider.overrideWith(
          (ref) => const OfficialSkillSyncResult(),
        ),
        unioneAuthClientProvider.overrideWithValue(
          UnioneAuthClient(
            portalUrl: 'http://portal.invalid/portal',
            httpClient: MockClient((_) async => http.Response('', 503)),
          ),
        ),
      ],
      child: EasyLocalization(
        supportedLocales: const [Locale('en')],
        path: 'assets/translations',
        assetLoader: const MergingAssetLoader(),
        fallbackLocale: const Locale('en'),
        startLocale: const Locale('en'),
        child: Builder(
          builder: (context) => MaterialApp(
            localizationsDelegates: context.localizationDelegates,
            supportedLocales: context.supportedLocales,
            locale: context.locale,
            theme: RevericThemeData.reveric.toThemeData(),
            builder: (_, child) =>
                RevericTheme(data: RevericThemeData.reveric, child: child!),
            home: const MobileOnboardingPage(),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

class _Settings extends AppSettingsNotifier {
  @override
  Future<AppSettings> build() async => AppSettings(
    theme: AppTheme.reveric,
    themeMode: AppThemeMode.light,
    language: 'en',
    aiSettings: AiSettings(),
  );

  @override
  Future<void> applyOnboardingDefaults({
    required AppTheme theme,
    required AppThemeMode themeMode,
    Map<AiModelRole, String>? defaultModelsForRoles,
    Map<AiModelKind, String>? defaultModelsForKinds,
  }) async {}
}
