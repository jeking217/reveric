// 职责: Unione 平台登录页 — 未登录时拦在应用入口，账号密码登录成功后写入本地会话。
// 关联文件:
//   lib/shared/providers/unione_auth_providers.dart
//   lib/shared/services/unione/unione_auth_client.dart
//   lib/shared/services/unione/unione_sm2.dart
//   lib/desktop/widgets/desktop_window_frame.dart
//   lib/main.dart
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/i18n.md
//

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../desktop/widgets/desktop_window_frame.dart';
import '../../components/reveric_button.dart';
import '../../localization/app_localization.dart';
import '../../localization/locale_keys.dart';
import '../../providers/unione_auth_providers.dart';
import '../../services/unione/unione_auth_client.dart';
import '../../services/unione/unione_sm2.dart';
import '../../theme/theme.dart';
import 'unione_portal_url_dialog.dart';

const double _kCardWidth = 420;

bool get _isDesktop =>
    Platform.isWindows || Platform.isMacOS || Platform.isLinux;

/// 登录页：账号、密码与平台图形验证码。
///
/// 密码在提交时先用平台公钥做 SM2 加密，明文不会离开本机；验证码图片通过
/// `CAPTCHAID` 头与答案绑定，因此由客户端取回后直接显示，提交时把 id 一并带上。
/// 平台的拒绝原样展示——它比本地任何猜测都清楚问题出在密码、验证码还是锁定。
class UnioneLoginPage extends ConsumerStatefulWidget {
  const UnioneLoginPage({super.key});

  @override
  ConsumerState<UnioneLoginPage> createState() => _UnioneLoginPageState();
}

class _UnioneLoginPageState extends ConsumerState<UnioneLoginPage> {
  final _usernameController = TextEditingController();
  final _passwordController = TextEditingController();
  final _captchaController = TextEditingController();

  UnioneCaptcha? _captcha;
  bool _fetchingCaptcha = false;
  bool _submitting = false;
  String _error = '';

  @override
  void initState() {
    super.initState();
    unawaited(_refreshCaptcha());
  }

  @override
  void dispose() {
    _usernameController.dispose();
    _passwordController.dispose();
    _captchaController.dispose();
    super.dispose();
  }

  /// 取一张新验证码；取不到时只是不显示验证码框，不阻止尝试登录
  /// （平台会自己说缺什么）。
  Future<void> _refreshCaptcha() async {
    if (_fetchingCaptcha) {
      return;
    }
    setState(() => _fetchingCaptcha = true);
    try {
      final captcha = await ref.read(unioneAuthClientProvider).fetchCaptcha();
      if (!mounted) return;
      setState(() {
        _captcha = captcha;
        _captchaController.clear();
      });
    } on Object {
      if (!mounted) return;
      setState(() => _captcha = null);
    } finally {
      if (mounted) {
        setState(() => _fetchingCaptcha = false);
      }
    }
  }

  Future<void> _submit() async {
    if (_submitting) {
      return;
    }
    final username = _usernameController.text.trim();
    final password = _passwordController.text;
    if (username.isEmpty || password.isEmpty) {
      setState(() => _error = context.t(LocaleKeys.authCredentialsRequired));
      return;
    }

    setState(() {
      _submitting = true;
      _error = '';
    });
    try {
      await ref
          .read(unioneSessionProvider.notifier)
          .signIn(
            username: username,
            plainPassword: password,
            captcha: _captcha == null ? null : _captchaController.text.trim(),
            captchaId: _captcha?.captchaId,
          );
      // 成功后由入口处的会话状态切换到主界面，本页随之卸载。
    } on UnioneSm2Exception {
      if (!mounted) return;
      setState(() => _error = context.t(LocaleKeys.authEncryptFailed));
    } on UnioneAuthException catch (error) {
      if (!mounted) return;
      setState(() {
        _error = error.message;
        _submitting = false;
      });
      // 平台校验过一次的验证码即作废，下一次必须换新图。
      unawaited(_refreshCaptcha());
      return;
    } on UnionePortalException catch (error) {
      if (!mounted) return;
      setState(() => _error = error.message);
    } on Object {
      if (!mounted) return;
      setState(() => _error = context.t(LocaleKeys.authLoginFailed));
    }
    if (mounted) {
      setState(() => _submitting = false);
    }
  }

  Future<void> _editServer() async {
    final current =
        ref.read(unionePortalUrlProvider).value ??
        ref.read(unioneAuthClientProvider).portalUrl;
    final next = await showUnionePortalUrlDialog(context, initialUrl: current);
    if (next == null || !mounted) {
      return;
    }
    await ref.read(unionePortalUrlProvider.notifier).savePortalUrl(next);
    if (!mounted) return;
    setState(() => _error = '');
    unawaited(_refreshCaptcha());
  }

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    final portalUrl =
        ref.watch(unionePortalUrlProvider).value ??
        ref.read(unioneAuthClientProvider).portalUrl;

    final card = Container(
      width: _kCardWidth,
      padding: const EdgeInsets.symmetric(
        horizontal: RevericSpacing.x4l,
        vertical: RevericSpacing.x4l,
      ),
      decoration: BoxDecoration(
        color: colors.surface,
        borderRadius: BorderRadius.circular(RevericRadius.large),
        border: Border.all(color: colors.borderSubtle),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 28,
            offset: const Offset(0, 12),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const _BrandMark(),
          const SizedBox(height: RevericSpacing.x3l),
          Text(
            context.t(LocaleKeys.authLoginTitle),
            textAlign: TextAlign.center,
            style: typo.heading2.copyWith(color: colors.textPrimary),
          ),
          const SizedBox(height: RevericSpacing.xs),
          Text(
            context.t(LocaleKeys.authLoginSubtitle),
            textAlign: TextAlign.center,
            style: typo.uiSmall.copyWith(color: colors.textMuted),
          ),
          const SizedBox(height: RevericSpacing.x4l),
          _FieldLabel(text: context.t(LocaleKeys.authUsernameLabel)),
          const SizedBox(height: RevericSpacing.xs),
          _LoginField(
            controller: _usernameController,
            hint: context.t(LocaleKeys.authUsernameHint),
            enabled: !_submitting,
            onSubmitted: (_) => _submit(),
          ),
          const SizedBox(height: RevericSpacing.lg),
          _FieldLabel(text: context.t(LocaleKeys.authPasswordLabel)),
          const SizedBox(height: RevericSpacing.xs),
          _LoginField(
            controller: _passwordController,
            hint: context.t(LocaleKeys.authPasswordHint),
            obscureText: true,
            enabled: !_submitting,
            onSubmitted: (_) => _submit(),
          ),
          if (_captcha == null && !_fetchingCaptcha) ...[
            const SizedBox(height: RevericSpacing.sm),
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: TextButton(
                onPressed: _refreshCaptcha,
                child: Text(
                  context.t(LocaleKeys.authCaptchaRefresh),
                  style: typo.uiSmall.copyWith(color: colors.accent),
                ),
              ),
            ),
          ],
          if (_captcha != null) ...[
            const SizedBox(height: RevericSpacing.lg),
            _FieldLabel(text: context.t(LocaleKeys.authCaptchaLabel)),
            const SizedBox(height: RevericSpacing.xs),
            Row(
              children: [
                Expanded(
                  child: _LoginField(
                    controller: _captchaController,
                    hint: context.t(LocaleKeys.authCaptchaHint),
                    enabled: !_submitting,
                    onSubmitted: (_) => _submit(),
                  ),
                ),
                const SizedBox(width: RevericSpacing.md),
                _CaptchaTile(
                  captcha: _captcha!,
                  loading: _fetchingCaptcha,
                  onTap: _refreshCaptcha,
                ),
              ],
            ),
          ],
          if (_error.isNotEmpty) ...[
            const SizedBox(height: RevericSpacing.lg),
            _ErrorBanner(message: _error),
          ],
          const SizedBox(height: RevericSpacing.x3l),
          RevericButton.primary(
            label: _submitting
                ? context.t(LocaleKeys.authLoggingIn)
                : context.t(LocaleKeys.authLoginAction),
            loading: _submitting,
            size: RevericButtonSize.prominent,
            onPressed: _submitting ? null : _submit,
          ),
          const SizedBox(height: RevericSpacing.x2l),
          MouseRegion(
            cursor: SystemMouseCursors.click,
            child: GestureDetector(
              onTap: _submitting ? null : _editServer,
              child: Text(
                '${context.t(LocaleKeys.authServerLabel)} · $portalUrl',
                textAlign: TextAlign.center,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: typo.uiSmall.copyWith(color: colors.textMuted),
              ),
            ),
          ),
        ],
      ),
    );

    final body = Center(child: SingleChildScrollView(child: card));
    return Scaffold(
      backgroundColor: colors.canvas,
      body: _isDesktop
          ? DesktopWindowFrame(child: body)
          : SafeArea(child: body),
    );
  }
}

/// 品牌标志：与 Unione AI Drama 的应用图标同源（Unione 标志）。
class _BrandMark extends StatelessWidget {
  const _BrandMark();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ClipRRect(
        borderRadius: BorderRadius.circular(RevericRadius.large),
        child: Image.asset(
          'assets/logo/unione_logo.jpg',
          width: 88,
          height: 88,
          fit: BoxFit.cover,
          filterQuality: FilterQuality.medium,
        ),
      ),
    );
  }
}

class _FieldLabel extends StatelessWidget {
  const _FieldLabel({required this.text});

  final String text;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Text(
      text,
      style: typo.uiSmallSemibold.copyWith(color: colors.textPrimary),
    );
  }
}

class _LoginField extends StatelessWidget {
  const _LoginField({
    required this.controller,
    required this.hint,
    required this.enabled,
    required this.onSubmitted,
    this.obscureText = false,
  });

  final TextEditingController controller;
  final String hint;
  final bool enabled;
  final ValueChanged<String> onSubmitted;
  final bool obscureText;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return TextField(
      controller: controller,
      enabled: enabled,
      obscureText: obscureText,
      autocorrect: false,
      enableSuggestions: !obscureText,
      style: typo.uiSmall.copyWith(color: colors.textPrimary),
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        hintText: hint,
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
    );
  }
}

/// 验证码缩略图：点击换一张，答案与图片绑定在同一个 id 上。
class _CaptchaTile extends StatelessWidget {
  const _CaptchaTile({
    required this.captcha,
    required this.loading,
    required this.onTap,
  });

  final UnioneCaptcha captcha;
  final bool loading;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    return Tooltip(
      message: context.t(LocaleKeys.authCaptchaRefresh),
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          onTap: loading ? null : onTap,
          child: Container(
            width: 108,
            height: 44,
            decoration: BoxDecoration(
              color: colors.canvas,
              borderRadius: BorderRadius.circular(RevericRadius.medium),
              border: Border.all(color: colors.borderInput),
            ),
            clipBehavior: Clip.antiAlias,
            child: loading
                ? Center(
                    child: SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: colors.textMuted,
                      ),
                    ),
                  )
                : Image.memory(captcha.image, fit: BoxFit.contain),
          ),
        ),
      ),
    );
  }
}

class _ErrorBanner extends StatelessWidget {
  const _ErrorBanner({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: RevericSpacing.md,
        vertical: RevericSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colors.error.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(RevericRadius.medium),
        border: Border.all(color: colors.error.withValues(alpha: 0.35)),
      ),
      child: Text(
        message,
        style: typo.uiSmall.copyWith(color: colors.textPrimary),
      ),
    );
  }
}
