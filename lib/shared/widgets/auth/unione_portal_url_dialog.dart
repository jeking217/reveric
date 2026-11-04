// 职责: 修改 Unione 门户地址的通用对话框（登录页与设置页共用）。
// 关联文件:
//   lib/shared/widgets/auth/unione_login_page.dart
//   lib/shared/widgets/settings/account_settings_section.dart
//   lib/shared/providers/unione_auth_providers.dart
// 遵循的 Rules:
//   .agents/rules/i18n.md
//

import 'package:flutter/material.dart';

import '../../localization/app_localization.dart';
import '../../localization/locale_keys.dart';
import '../../theme/theme.dart';

/// 让用户修改门户地址；确认返回新地址，取消返回 null，"恢复默认"返回空串。
Future<String?> showUnionePortalUrlDialog(
  BuildContext context, {
  required String initialUrl,
}) {
  return showDialog<String>(
    context: context,
    builder: (_) => _UnionePortalUrlDialog(initialUrl: initialUrl),
  );
}

class _UnionePortalUrlDialog extends StatefulWidget {
  const _UnionePortalUrlDialog({required this.initialUrl});

  final String initialUrl;

  @override
  State<_UnionePortalUrlDialog> createState() => _UnionePortalUrlDialogState();
}

class _UnionePortalUrlDialogState extends State<_UnionePortalUrlDialog> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.initialUrl,
  );
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _save() {
    final value = _controller.text.trim();
    final uri = Uri.tryParse(value);
    if (uri == null ||
        !uri.hasScheme ||
        uri.host.isEmpty ||
        (uri.scheme != 'http' && uri.scheme != 'https')) {
      setState(() => _error = context.t(LocaleKeys.authServerInvalid));
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return AlertDialog(
      backgroundColor: colors.surface,
      title: Text(
        context.t(LocaleKeys.authServerTitle),
        style: typo.uiSemibold.copyWith(
          color: colors.textPrimary,
          fontSize: 16,
        ),
      ),
      content: SizedBox(
        width: 380,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _controller,
              autofocus: true,
              autocorrect: false,
              style: typo.uiSmall.copyWith(color: colors.textPrimary),
              onSubmitted: (_) => _save(),
              decoration: InputDecoration(
                hintText: context.t(LocaleKeys.authServerHint),
                hintStyle: typo.uiSmall.copyWith(color: colors.textMuted),
                filled: true,
                fillColor: colors.canvas,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(RevericRadius.medium),
                  borderSide: BorderSide(color: colors.borderInput),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(RevericRadius.medium),
                  borderSide: BorderSide(color: colors.borderInput),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(RevericRadius.medium),
                  borderSide: BorderSide(color: colors.accent),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: RevericSpacing.md,
                  vertical: RevericSpacing.md,
                ),
              ),
            ),
            const SizedBox(height: RevericSpacing.sm),
            Text(
              _error ?? context.t(LocaleKeys.authServerHintDetail),
              style: typo.uiSmall.copyWith(
                color: _error == null ? colors.textMuted : colors.error,
              ),
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(''),
          child: Text(context.t(LocaleKeys.authServerReset)),
        ),
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(context.t(LocaleKeys.commonCancel)),
        ),
        FilledButton(
          onPressed: _save,
          child: Text(context.t(LocaleKeys.commonSave)),
        ),
      ],
    );
  }
}
