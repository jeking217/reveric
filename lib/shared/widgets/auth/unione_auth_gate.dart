// 职责: 登录门禁 — 本地已保存 Unione 会话时放行，否则显示入口页（入口页里就是登录表单）。
// 关联文件:
//   lib/shared/providers/unione_auth_providers.dart
//   lib/shared/widgets/auth/unione_login_card.dart
//   lib/main.dart
// 遵循的 Rules:
//   .agents/rules/state-management.md

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../providers/unione_auth_providers.dart';
import '../brand_loader.dart';

/// 包在业务界面外的一层门禁。
///
/// 用「切换子界面」而不是「切换导航目标」实现：MaterialApp 的 `home` 只在启动
/// 时生成一次路由，运行中替换它并不会换页；这里的 widget 重建才会。
class UnioneAuthGate extends ConsumerWidget {
  const UnioneAuthGate({
    super.key,
    required this.signedOut,
    required this.child,
  });

  /// 未登录时展示的入口页。登录表单就在这个页面里，登录成功后它会被 [child] 替换。
  final Widget signedOut;

  /// 已登录后要展示的业务界面。
  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(unioneSessionProvider);
    return session.when(
      loading: () => const Scaffold(
        body: BrandLoader(
          skipIntro: true,
          showDelay: Duration(milliseconds: 400),
        ),
      ),
      // 读取本地会话失败等同于未登录：重新走一次平台登录即可。
      error: (error, stack) => signedOut,
      data: (value) => value == null ? signedOut : child,
    );
  }
}
