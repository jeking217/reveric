// 职责: 系统托盘退出回归测试 — 确保关闭流程不被原生窗口回包阻塞。
// 关联文件:
//   lib/shared/services/system_tray_service.dart

import 'dart:async';
import 'dart:ui' show Locale;

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:reveric/shared/services/system_tray_service.dart';
import 'package:reveric/shared/logger/startup_failure_reporter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const windowManagerChannel = MethodChannel('window_manager');
  const trayManagerChannel = MethodChannel('tray_manager');
  final calls = <String>[];
  Completer<Object?>? pendingWindowClose;
  Completer<Object?>? pendingTrayDestroy;
  var windowVisible = true;
  var windowMinimized = false;
  String? trayTooltip;
  List<String> trayLabels = const [];

  setUp(() {
    SystemTrayService().resetForTesting();
    calls.clear();
    trayTooltip = null;
    trayLabels = const [];
    pendingWindowClose = null;
    pendingTrayDestroy = null;
    windowVisible = true;
    windowMinimized = false;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(windowManagerChannel, (call) async {
          calls.add('window.${call.method}');
          if (call.method == 'isVisible') {
            return windowVisible;
          }
          if (call.method == 'restore') {
            windowMinimized = false;
          }
          if (call.method == 'isMinimized') {
            return windowMinimized;
          }
          if (call.method == 'close' && pendingWindowClose != null) {
            return pendingWindowClose!.future;
          }
          return true;
        });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(trayManagerChannel, (call) async {
          calls.add('tray.${call.method}');
          if (call.method == 'setToolTip') {
            trayTooltip = (call.arguments as Map)['toolTip'] as String?;
          }
          if (call.method == 'setContextMenu') {
            final menu = (call.arguments as Map)['menu'] as Map;
            trayLabels = ((menu['items'] as List?) ?? const [])
                .map((item) => (item as Map)['label'] as String? ?? '')
                .toList();
          }
          if (call.method == 'destroy' && pendingTrayDestroy != null) {
            return pendingTrayDestroy!.future;
          }
          return true;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(windowManagerChannel, null);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(trayManagerChannel, null);
  });

  test('exit guard cancels shutdown until its owner unregisters', () async {
    final unregister = SystemTrayService().registerExitGuard(() async => false);
    await SystemTrayService().exitApplicationForTesting(
      (code) => calls.add('exit.$code'),
    );
    expect(calls, isEmpty);
    unregister();
    await SystemTrayService().exitApplicationForTesting(
      (code) => calls.add('exit.$code'),
    );
    expect(calls, contains('exit.0'));
  });

  test('the context menu is installed before any UI frame', () async {
    // 托盘初始化早于 runApp，此刻还不能从 widget 树取语言。菜单必须在启动阶段
    // 就写进原生托盘，否则右键从启动到界面挂载之间完全没反应。
    await SystemTrayService().init();

    expect(calls, contains('tray.setContextMenu'));
    expect(trayLabels, isNotEmpty);
  });

  test(
    'a missing menu is installed on right click instead of nothing',
    () async {
      var allowMenu = false;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(trayManagerChannel, (call) async {
            calls.add('tray.${call.method}');
            if (call.method == 'setContextMenu' && !allowMenu) {
              throw PlatformException(code: 'unavailable');
            }
            return true;
          });

      final service = SystemTrayService();
      await service.init();
      expect(calls, isNot(contains('tray.popUpContextMenu')));

      allowMenu = true;
      service.onTrayIconRightMouseDown();
      await Future<void>.delayed(Duration.zero);

      expect(calls, contains('tray.popUpContextMenu'));
    },
  );

  test('tray name, tooltip and menu follow the app language', () async {
    final service = SystemTrayService();
    await service.init();

    await service.applyLocale(const Locale('zh', 'CN'));

    expect(trayTooltip, 'Unione AI Drama');
    expect(trayLabels, containsAll(<String>['新建小说', '隐藏', '显示', '退出']));
    expect(trayLabels, isNot(contains('New Novel')));

    await service.applyLocale(const Locale('en'));

    expect(
      trayLabels,
      containsAll(<String>['New Novel', 'Hide', 'Show', 'Quit']),
    );
    expect(trayLabels, isNot(contains('新建小说')));
  });

  test('tray exit closes the window without invoking destroy', () async {
    await SystemTrayService().exitApplicationForTesting(
      (code) => calls.add('exit.$code'),
    );

    expect(calls, <String>[
      'window.setPreventClose',
      'tray.destroy',
      'window.close',
      'exit.0',
    ]);
    expect(calls, isNot(contains('window.destroy')));
  });

  test('window activation waits for the native visibility to settle', () async {
    // 原生窗口在 show() 之后要过一会儿才真的可见；先报不可见是常态。
    windowVisible = false;
    var reads = 0;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(windowManagerChannel, (call) async {
          calls.add('window.${call.method}');
          if (call.method == 'isMinimized') {
            return false;
          }
          if (call.method == 'isVisible') {
            reads++;
            if (reads > 2) {
              windowVisible = true;
            }
            return windowVisible;
          }
          if (call.method == 'close' && pendingWindowClose != null) {
            return pendingWindowClose!.future;
          }
          return true;
        });

    await SystemTrayService().showMainWindow();

    expect(reads, greaterThan(2));
    expect(
      calls,
      containsAllInOrder(['window.show', 'window.focus', 'window.isVisible']),
    );
  });

  test(
    'a window that never reports visible does not fail activation',
    () async {
      // 第二实例的唤起请求会等这个 Future；抛出就是给用户弹「启动失败」。
      windowVisible = false;
      await SystemTrayService().showMainWindow();
      expect(calls, containsAllInOrder(['window.show', 'window.focus']));
    },
  );

  test('a minimized window is restored before it is shown', () async {
    windowMinimized = true;
    await SystemTrayService().showMainWindow();
    expect(calls.first, 'window.isMinimized');
    expect(
      calls,
      containsAllInOrder(['window.restore', 'window.show', 'window.focus']),
    );
  });

  test(
    'failed instance cleanup is reported without stranding tray exit',
    () async {
      await SystemTrayService().exitApplicationForTesting(
        (code) => calls.add('exit.$code'),
        unlock: () => throw StateError('cleanup failed'),
        failureReporter: _Reporter(calls),
      );
      expect(
        calls,
        containsAllInOrder([
          'report:tray_exit:release_instance_failed',
          'exit.0',
        ]),
      );
    },
  );

  test('tray exit does not wait for the native close reply', () async {
    pendingWindowClose = Completer<Object?>();

    await SystemTrayService()
        .exitApplicationForTesting((code) => calls.add('exit.$code'))
        .timeout(const Duration(milliseconds: 100));

    expect(calls, <String>[
      'window.setPreventClose',
      'tray.destroy',
      'window.close',
      'exit.0',
    ]);
  });

  test('tray exit does not wait for the native destroy reply', () async {
    pendingTrayDestroy = Completer<Object?>();

    await SystemTrayService()
        .exitApplicationForTesting((code) => calls.add('exit.$code'))
        .timeout(const Duration(milliseconds: 100));

    expect(calls, <String>[
      'window.setPreventClose',
      'tray.destroy',
      'window.close',
      'exit.0',
    ]);
  });

  test(
    'tray exit removes the marker before releasing the instance lock',
    () async {
      await SystemTrayService().exitApplicationForTesting(
        (code) => calls.add('exit.$code'),
        cleanExit: () async => calls.add('marker.clean'),
        unlock: () => calls.add('instance.unlock'),
      );

      expect(
        calls.indexOf('marker.clean'),
        lessThan(calls.indexOf('instance.unlock')),
      );
    },
  );
}

class _Reporter extends StartupFailureReporter {
  _Reporter(this.calls);
  final List<String> calls;

  @override
  Future<void> reportLifecycleFailure({
    required String phase,
    required String reason,
    required Object error,
    required StackTrace stackTrace,
  }) async {
    calls.add('report:$phase:$reason');
  }
}
