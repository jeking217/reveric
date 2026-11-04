// 职责: 桌面端首页侧栏顶部品牌栏 — 云形标记 + 产品名单行展示（永远不折行）
// 关联文件:
//   lib/desktop/pages/home.dart
//   lib/desktop/widgets/desktop_window_frame.dart
//   lib/shared/app_config.dart
//   assets/logo/unione_mark.png
// 遵循的 Rules:
//   .agents/rules/design-system.md
//   .agents/rules/desktop-window-frame.md

import 'package:flutter/material.dart';

import '../../../shared/app_config.dart';
import '../../../shared/theme/theme.dart';
import '../../widgets/desktop_window_frame.dart';

/// 侧栏顶部的品牌栏：logo 与产品名并排，占用标题栏覆盖区。
///
/// 只做展示，不拦截窗口拖拽热区。产品名恒定单行：宽度不够时省略，
/// 绝不折成两行把标题栏撑高。
class HomeBrandHeader extends StatelessWidget {
  const HomeBrandHeader({super.key});

  /// 标记边长：与侧栏首个图标同高，避免视觉上比导航行更重。
  static const double markSize = 24;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return SizedBox(
      height: DesktopWindowFrame.sidebarTopInset,
      child: Padding(
        padding: EdgeInsets.only(
          left: DesktopWindowFrame.sidebarLeadingInset + RevericSpacing.x2l,
          right: RevericSpacing.lg,
        ),
        child: Row(
          children: [
            const _BrandMark(size: markSize),
            const SizedBox(width: RevericSpacing.sm),
            Expanded(
              child: Text(
                appDisplayName,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.ellipsis,
                style: typo.uiSemibold.copyWith(color: colors.textPrimary),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// 标记本体：Unione 云形图案（与 agenticos 同一张图）裁掉文字后的小图标。
/// 原图底色为白，深色主题下靠圆角白底保持可读。
class _BrandMark extends StatelessWidget {
  const _BrandMark({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(RevericRadius.medium),
      child: Image.asset(
        'assets/logo/unione_mark.png',
        width: size,
        height: size,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
      ),
    );
  }
}
