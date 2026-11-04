// 职责: 首页侧栏品牌栏测试 — 验证 logo 与产品名同行、产品名恒定单行不折行。
// 关联文件:
//   lib/desktop/widgets/home/home_brand_header.dart
//   lib/shared/app_config.dart
//   assets/logo/unione_mark.png
// 遵循的 Rules:
//   .agents/rules/testing.md

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:reveric/desktop/widgets/home/home_brand_header.dart';
import 'package:reveric/shared/app_config.dart';
import 'package:reveric/shared/theme/theme.dart';

const double _sidebarWidth = 240;

Widget _wrap({double width = _sidebarWidth}) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    builder: (context, child) => RevericTheme(
      data: RevericThemeData.reveric,
      child: child!,
    ),
    home: Scaffold(
      body: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(width: width, child: const HomeBrandHeader()),
      ),
    ),
  );
}

void main() {
  testWidgets('shows the mark and the product name on one row', (tester) async {
    await tester.pumpWidget(_wrap());

    expect(find.byType(Image), findsOneWidget);
    expect(find.text(appDisplayName), findsOneWidget);

    // 标记与文字居于同一水平线：纵向中心差不超过 1px。
    final markCenter = tester.getCenter(find.byType(Image));
    final textCenter = tester.getCenter(find.text(appDisplayName));
    expect((markCenter.dy - textCenter.dy).abs(), lessThanOrEqualTo(1));

    // 标记在左、文字在右，不重叠。
    expect(markCenter.dx, lessThan(textCenter.dx));
    expect(
      tester.getTopLeft(find.text(appDisplayName)).dx,
      greaterThan(tester.getTopRight(find.byType(Image)).dx),
    );
  });

  testWidgets('product name never wraps, even when the sidebar is narrow', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(width: 120));

    final paragraph = tester.renderObject<RenderParagraph>(
      find.text(appDisplayName),
    );
    expect(paragraph.maxLines, 1);
    expect(paragraph.softWrap, isFalse);
    // 单行：实际高度不超过字号的两倍；折成两行会明显超过。
    final fontSize = paragraph.text.style!.fontSize!;
    expect(paragraph.size.height, lessThan(fontSize * 2));
  });
}
