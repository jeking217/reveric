// 职责: 品牌加载动画（整屏等待用）— Unione 标志淡入后循环呼吸，外部标记完成后淡出。
// 关联文件:
//   assets/logo/unione_logo.jpg
//   lib/main.dart
//   lib/desktop/pages/onboarding.dart
//   test/shared/widgets/brand_loader_test.dart
// 遵循的 Rules:
//   .agents/rules/hooks.md
//   .agents/rules/design-system.md
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter_hooks/flutter_hooks.dart';

import '../theme/theme.dart';

/// 入场时长（秒）。done 早于入场结束时，等入场播完再退出。
const double _kIntro = 1.2;
const double _kLoopPeriod = 2.4;
const double _kExit = 0.45;
const double _kShowFade = 0.3;

/// 标志淡入与缩放的入场节奏（秒）。
const double _kLogoFadeIn = 0.45;
const double _kLogoScaleIn = 0.7;

/// 标志图片的宽高比（Unione 标志原图为正方形）。
const double _kLogoAspect = 1.0;

/// 整屏品牌加载动画。
///
/// [done] 变为 true 后，在入场播完的前提下淡出，结束时回调 [onExited]。
/// [skipIntro] 直接从循环态开始：用于会被反复挂载的启动占位，避免每个阶段重播入场。
/// [showDelay] 仅对 [skipIntro] 生效：这段时间内只铺背景色，超过该时长仍在加载才淡入 logo
/// 并开始循环；期间 done 到达则直接回调，用户完全看不到 logo，避免快速加载时一闪而过。
/// 系统开启「减少动态效果」时直接展示终态（有 showDelay 时保持只铺背景色），done 后立即回调。
class BrandLoader extends HookWidget {
  const BrandLoader({
    super.key,
    this.done = false,
    this.onExited,
    this.skipIntro = false,
    this.showDelay = Duration.zero,
    this.width = 220,
  });

  final bool done;
  final VoidCallback? onExited;
  final bool skipIntro;
  final Duration showDelay;
  final double width;

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    final vsync = useSingleTickerProvider();
    // 当前时间（秒）与完成请求时刻；ListenableBuilder 只重建动画子树。
    final startOffset = skipIntro ? _kIntro : 0.0;
    final delay = skipIntro
        ? showDelay.inMicroseconds / Duration.microsecondsPerSecond
        : 0.0;
    final clock = useMemoized(() => ValueNotifier<double>(startOffset));
    // logo 可见度：showDelay 期间为 0，之后淡入到 1。
    final appear = useMemoized(() => ValueNotifier<double>(delay > 0 ? 0 : 1));
    final doneAt = useRef<double?>(null);
    final rawNow = useRef(0.0);
    final exited = useRef(false);

    void exitNow() {
      if (exited.value) {
        return;
      }
      exited.value = true;
      SchedulerBinding.instance.addPostFrameCallback((_) => onExited?.call());
    }

    useEffect(() {
      if (reduceMotion) {
        clock.value = _kIntro;
        return null;
      }
      final ticker = vsync.createTicker((elapsed) {
        final raw = elapsed.inMicroseconds / Duration.microsecondsPerSecond;
        rawNow.value = raw;
        if (exited.value) {
          return;
        }
        // 隐藏期内时钟停在循环起点，淡入的同时从头进入循环。
        final t = startOffset + math.max(0.0, raw - delay);
        appear.value = delay > 0
            ? _interval(raw, delay, delay + _kShowFade)
            : 1;
        clock.value = t;
        final requested = doneAt.value;
        if (requested != null && !exited.value) {
          final exitStart = math.max(requested, _kIntro);
          if (t >= exitStart + _kExit) {
            exited.value = true;
            onExited?.call();
          }
        }
      });
      ticker.start();
      return ticker.dispose;
    }, [reduceMotion]);

    useEffect(() {
      if (!done || doneAt.value != null) {
        return null;
      }
      doneAt.value = clock.value;
      // logo 还没露面（隐藏期内）或关闭了动效：不播淡出，直接结束。
      if (reduceMotion || (delay > 0 && rawNow.value < delay)) {
        exitNow();
      }
      return null;
    }, [done]);

    useEffect(() {
      return () {
        clock.dispose();
        appear.dispose();
      };
    }, []);

    final height = width * _kLogoAspect;

    return ColoredBox(
      color: colors.canvas,
      child: Center(
        child: SizedBox(
          width: width,
          height: height,
          child: ListenableBuilder(
            listenable: Listenable.merge([clock, appear]),
            builder: (context, _) {
              if (appear.value == 0) {
                return const SizedBox.shrink();
              }
              final t = clock.value;
              final exit = _exitProgress(t, doneAt.value);
              final fadeIn = _interval(t, 0, _kLogoFadeIn, Curves.easeOut);
              final scaleIn = _interval(
                t,
                0,
                _kLogoScaleIn,
                Curves.easeOutCubic,
              );
              final looping = t >= _kIntro;
              final loopT = math.max(0.0, t - _kIntro);
              // 循环期轻微呼吸，避免静止画面看起来像卡住。
              final breathe = looping
                  ? (1 - math.cos(loopT / _kLoopPeriod * math.pi * 2)) / 2
                  : 0.0;
              return Opacity(
                opacity: appear.value * fadeIn * (1 - exit),
                child: Transform.scale(
                  scale: 0.94 + 0.06 * scaleIn + 0.015 * breathe + 0.04 * exit,
                  child: const _BrandLogo(),
                ),
              );
            },
          ),
        ),
      ),
    );
  }

  static double _exitProgress(double t, double? doneAt) {
    if (doneAt == null) {
      return 0;
    }
    final exitStart = math.max(doneAt, _kIntro);
    return _interval(t, exitStart, exitStart + _kExit, Curves.easeInCubic);
  }
}

double _interval(
  double t,
  double begin,
  double end, [
  Curve curve = Curves.linear,
]) {
  final x = ((t - begin) / (end - begin)).clamp(0.0, 1.0);
  return curve.transform(x);
}

/// 标志本体：Unione 标志（与 agenticos 同一张图），深色主题下加浅色底保证可读。
class _BrandLogo extends StatelessWidget {
  const _BrandLogo();

  @override
  Widget build(BuildContext context) {
    final colors = RevericTheme.colorsOf(context);
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: dark ? Colors.white : colors.surface,
        borderRadius: BorderRadius.circular(RevericRadius.large),
        boxShadow: dark
            ? null
            : [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.06),
                  blurRadius: 18,
                  offset: const Offset(0, 8),
                ),
              ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(RevericRadius.large),
        child: Image.asset(
          'assets/logo/unione_logo.jpg',
          fit: BoxFit.contain,
          filterQuality: FilterQuality.medium,
        ),
      ),
    );
  }
}
