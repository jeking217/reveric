// 职责: 账号设置区 — 展示当前 Unione 平台账号、登录时间与门户地址，并提供退出登录。
// 关联文件:
//   lib/shared/providers/unione_auth_providers.dart
//   lib/shared/widgets/auth/unione_portal_url_dialog.dart
//   lib/shared/widgets/settings/settings_section_widgets.dart
//   lib/desktop/widgets/settings/settings_dialog.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/i18n.md
//

import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../components/reveric_button.dart';
import '../../localization/app_localization.dart';
import '../../localization/locale_keys.dart';
import '../../providers/unione_auth_providers.dart';
import '../../theme/theme.dart';
import '../auth/unione_portal_url_dialog.dart';
import '../confirm_dialog.dart';
import 'settings_section_widgets.dart';

/// 账号区：谁登录着、从哪里登录、以及怎么退出。
class AccountSettingsSection extends ConsumerWidget {
  const AccountSettingsSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(unioneSessionProvider).value;
    final portalUrl =
        ref.watch(unionePortalUrlProvider).value ??
        ref.read(unioneAuthClientProvider).portalUrl;
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    Future<void> editPortal() async {
      final next = await showUnionePortalUrlDialog(
        context,
        initialUrl: portalUrl,
      );
      if (next == null) {
        return;
      }
      await ref.read(unionePortalUrlProvider.notifier).savePortalUrl(next);
    }

    Future<void> signOut() async {
      final confirmed = await showConfirmDialog(
        context,
        title: context.t(LocaleKeys.authAccountSignOut),
        message: context.t(LocaleKeys.authAccountSignOutConfirm),
        confirmLabel: context.t(LocaleKeys.authAccountSignOut),
        variant: ConfirmDialogVariant.error,
      );
      if (confirmed != true) {
        return;
      }
      await ref.read(unioneSessionProvider.notifier).signOut();
    }

    return SingleChildScrollView(
      padding: const EdgeInsets.all(RevericSpacing.x4l),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SettingsSection(
            titleKey: LocaleKeys.authAccountSectionTitle,
            child: SettingsCard(
              children: [
                SettingsRow(
                  labelKey: LocaleKeys.authAccountSignedInAs,
                  child: Text(
                    session == null
                        ? '-'
                        : '${session.displayName} · ${session.username}',
                    style: typo.uiSmall.copyWith(color: colors.textPrimary),
                  ),
                ),
                const SettingsRowDivider(),
                SettingsRow(
                  labelKey: LocaleKeys.authAccountOrg,
                  child: Text(
                    session?.orgName ?? '-',
                    style: typo.uiSmall.copyWith(color: colors.textPrimary),
                  ),
                ),
                const SettingsRowDivider(),
                SettingsRow(
                  labelKey: LocaleKeys.authAccountSignedInAt,
                  child: Text(
                    session == null
                        ? '-'
                        : _formatTime(session.signedInAt.toLocal()),
                    style: typo.uiSmall.copyWith(color: colors.textPrimary),
                  ),
                ),
                const SettingsRowDivider(),
                SettingsRow(
                  labelKey: LocaleKeys.authServerLabel,
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          portalUrl,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: typo.uiSmall.copyWith(
                            color: colors.textSecondary,
                          ),
                        ),
                      ),
                      const SizedBox(width: RevericSpacing.md),
                      RevericButton.secondary(
                        label: context.t(LocaleKeys.authServerEdit),
                        size: RevericButtonSize.compact,
                        onPressed: editPortal,
                      ),
                    ],
                  ),
                ),
                const SettingsRowDivider(),
                SettingsRow(
                  labelKey: LocaleKeys.authAccountSignOut,
                  child: Align(
                    alignment: AlignmentDirectional.centerStart,
                    child: RevericButton.danger(
                      label: context.t(LocaleKeys.authAccountSignOut),
                      size: RevericButtonSize.compact,
                      onPressed: session == null ? null : signOut,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _formatTime(DateTime time) {
    String two(int value) => value.toString().padLeft(2, '0');
    return '${time.year}-${two(time.month)}-${two(time.day)} '
        '${two(time.hour)}:${two(time.minute)}';
  }
}
