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

/// 侧栏顶部的品牌栏：logo 与产品名并排，占满标题栏高度，底部一条极浅的分隔线。
///
/// 只做展示，不拦截窗口拖拽热区。产品名恒定单行：宽度不够时省略，
/// 绝不折成两行把标题栏撑高。
///
/// 分隔线紧跟标题栏高度之后（y = [DesktopWindowFrame.titleBarHeight]），
/// 与内容区页头（同样 48px 高）下方的分隔线处在同一水平线、同一颜色，
/// 跨过侧栏与内容区之间的竖线时是一条连续的线。
class HomeBrandHeader extends StatelessWidget {
  const HomeBrandHeader({super.key});

  /// 标记边长：与侧栏首个图标同高，避免视觉上比导航行更重。
  static const double markSize = 24;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final typo = RevericTheme.typographyOf(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SizedBox(
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
        ),
        Divider(height: RevericSizes.dividerThickness, color: colors.border),
      ],
    );
  }
}

/// 标记本体：红色圆角方块里的白色云形与胶片，与 agenticos 的云形同一个来源。
/// 底色本身就是品牌红，深浅主题下都不用再垫白底。
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
