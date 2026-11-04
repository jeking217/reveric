// 职责: 系统托盘服务 — 管理托盘图标、菜单与关闭到托盘行为
// 关联文件:
//   lib/shared/components/reveric_dialog.dart
//   lib/shared/components/reveric_button.dart
//   lib/shared/widgets/confirm_dialog.dart
//   lib/main.dart
//   lib/shared/services/window_state_service.dart
//   lib/desktop/widgets/novel_form_dialog.dart
//   lib/desktop/pages/workspace_editor_page.dart
//   lib/shared/providers/novel_providers.dart
//   lib/shared/models/novel_type.dart
//   lib/shared/database/app_database.dart
//   lib/shared/database/novel_content_database.dart

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:window_manager/window_manager.dart';
import 'package:tray_manager/tray_manager.dart';

import '../components/dialog_feedback.dart';
import '../database/app_database.dart';
import '../database/novel_content_database.dart';
import '../localization/app_localization.dart';
import '../localization/locale_keys.dart';
import '../logger/app_logger.dart';
import '../logger/startup_failure_reporter.dart';
import 'crash_reporting/crash_sentinel.dart';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'single_instance_service.dart';
import '../../desktop/widgets/novel_form_dialog.dart';
import '../providers/novel_providers.dart';
import '../../desktop/pages/workspace_editor_page.dart';
import '../components/reveric_dialog.dart';
import '../widgets/confirm_dialog.dart';
import '../components/reveric_button.dart';
import '../app_config.dart';

final _log = AppLogger.forModule('SystemTray');

class SystemTrayService with TrayListener {
  final List<Future<bool> Function()> _exitGuards = [];
  VoidCallback registerExitGuard(Future<bool> Function() guard) {
    _exitGuards.add(guard);
    return () => _exitGuards.remove(guard);
  }

  static String get _iconPath {
    if (Platform.isWindows) {
      return 'assets/logo/unione_mark_32.ico';
    }
    return 'assets/logo/unione_mark_32.png';
  }

  static final SystemTrayService _instance = SystemTrayService._internal();
  factory SystemTrayService() => _instance;
  SystemTrayService._internal() {
    trayManager.addListener(this);
  }

  GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

  bool _initialized = false;

  /// 菜单是否已成功写进原生托盘；没写进去时右键不会有任何反应。
  bool _menuInstalled = false;

  /// 当前托盘文案用的语言，用于避免每次校正都重设一遍菜单。
  Locale? _menuLocale;

  /// 应用启动时的界面语言：`EasyLocalization.startLocale`，与 `main.dart` 一致。
  /// 启动占位阶段读不到 widget 树，只能先按它装一份菜单。
  static const Locale _startupLocale = Locale('zh', 'CN');

  Future<void> init() async {
    if (_initialized) return;

    try {
      await trayManager.setIcon(_iconPath, isTemplate: true);
      await trayManager.setToolTip(appDisplayName);

      await windowManager.setPreventClose(true);
      windowManager.addListener(_WindowCloseListener());

      _initialized = true;
      // 右键弹出的是原生菜单，必须在启动阶段就装好。`init()` 早于 `runApp`，
      // 而 MaterialApp 要等启动页跑完才建，此时 `navigatorKey` 取不到 context；
      // 若把菜单推迟到首帧后写入，启动期间的右键就没有任何反应。先按启动语言
      // 装一份，界面挂载后再按真实语言校正。
      await applyLocale(_startupLocale);
      _syncLocaleWithUi();

      _log.info('System tray initialized');
    } catch (e) {
      _log.warning('Failed to initialize system tray: $e');
    }
  }

  /// 界面挂载后按真实界面语言校正一次托盘文案。
  ///
  /// 启动占位阶段还没有 MaterialApp，只能逐帧等待；拿到带本地化的 context 就
  /// 停下。语言没变时不重设菜单，避免无谓地重建原生菜单。
  void _syncLocaleWithUi([int attempt = 0]) {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_initialized) return;
      final context = navigatorKey.currentContext;
      final locale = context == null
          ? null
          : Localizations.maybeLocaleOf(context);
      if (locale != null) {
        if (locale != _menuLocale) {
          unawaited(applyLocale(locale));
        }
        return;
      }
      if (attempt < 600) {
        _syncLocaleWithUi(attempt + 1);
      } else {
        _log.warning('Tray locale was never synced with the UI language');
      }
    });
  }

  /// 把托盘文案切换成 [locale] 的语言。
  ///
  /// 托盘提示与菜单是原生对象，不会随 Flutter 重建自动刷新，必须显式写入。
  /// 文案直接从该语言的翻译资源读取，不走全局 `tr()`：easy_localization 的
  /// 全局实例要等 widget 树用新语言重建后才更新，而语言切换的调用点拿到的
  /// 仍是旧语言，写进原生托盘就成了错的那一套。
  Future<void> applyLocale(Locale locale) async {
    if (!_initialized) return;
    _menuLocale = locale;
    _menuInstalled = false;
    try {
      final catalog = await _catalog(locale);
      // 翻译缺失时宁可留品牌名，也不要让托盘提示显示成 key。
      await trayManager.setToolTip(
        catalog.isEmpty ? appDisplayName : _label(catalog, LocaleKeys.appTitle),
      );
      await _updateMenu(catalog);
      _menuInstalled = true;
      _log.info('System tray menu installed (locale=$locale)');
    } catch (e) {
      _log.warning('Failed to apply system tray locale ($locale): $e');
    }
  }

  /// 各语言的托盘文案，按语言标签缓存。
  final Map<String, Map<String, dynamic>> _catalogs = {};

  /// 只读 `tray` 命名空间：托盘用到的几条文案全在这份文件里，没必要为了装
  /// 一个原生菜单去合并全部命名空间的翻译（启动阶段尤其贵）。
  Future<Map<String, dynamic>> _catalog(Locale locale) async {
    final tag = locale.toStringWithSeparator(separator: '-');
    final cached = _catalogs[tag];
    if (cached != null) return cached;
    for (final candidate in <String>[tag, 'en']) {
      try {
        final raw = await rootBundle.loadString(
          'assets/translations/$candidate/tray.json',
        );
        final parsed = jsonDecode(raw) as Map<String, dynamic>;
        return _catalogs[tag] = parsed;
      } catch (_) {
        continue;
      }
    }
    _log.warning('Missing tray translations for $tag');
    return _catalogs[tag] = const <String, dynamic>{};
  }

  /// 读取一条文案并替换 `{name}` 形式的占位符；缺该 key 时回退成 key 本身，
  /// 与 easy_localization 的行为一致。
  String _label(
    Map<String, dynamic> catalog,
    String key, [
    Map<String, String> args = const {},
  ]) {
    var value = catalog[key] as String? ?? key;
    for (final entry in args.entries) {
      value = value.replaceAll('{${entry.key}}', entry.value);
    }
    return value;
  }

  Future<void> _updateMenu(Map<String, dynamic> catalog) async {
    final menu = Menu(
      items: [
        MenuItem(
          key: 'newNovel',
          label: _label(catalog, LocaleKeys.trayNewNovel),
        ),
        MenuItem(
          key: 'about',
          label: _label(catalog, LocaleKeys.trayAbout, {
            'name': appDisplayName,
          }),
        ),
        MenuItem.separator(),
        MenuItem(key: 'hide', label: _label(catalog, LocaleKeys.trayHide)),
        MenuItem(key: 'show', label: _label(catalog, LocaleKeys.trayShow)),
        MenuItem.separator(),
        MenuItem(key: 'quit', label: _label(catalog, LocaleKeys.trayQuit)),
      ],
    );
    await trayManager.setContextMenu(menu);
  }

  /// 唤起主窗口：托盘点击、托盘菜单与第二实例激活请求共用。
  ///
  /// 原生窗口的状态不是同步更新的：`show()` 返回时 `isVisible` 可能还读到上一
  /// 帧，刚从最小化恢复时 `isMinimized` 也一样。等它稳定，而不是查一次就判定
  /// 失败 —— 这条路径同时供第二实例的唤起请求使用，抛异常会让用户看到「启动
  /// 失败」，而窗口其实已经打开了。
  Future<void> showMainWindow() async {
    _log.checkpoint('showing main window (native)');
    if (await windowManager.isMinimized()) {
      await windowManager.restore();
    }
    await windowManager.show();
    await windowManager.focus();
    for (var attempt = 0; attempt < 12; attempt++) {
      final visible = await windowManager.isVisible();
      if (visible && !await windowManager.isMinimized()) {
        _log.checkpoint('main window activation verified (native)');
        return;
      }
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
    // 窗口已经收到显示请求；这里只留一条日志，不把它升级成启动失败。
    _log.warning('Main window did not report visible after activation');
  }

  void _hideWindow() async {
    _log.checkpoint('hiding main window (native)');
    await windowManager.hide();
  }

  Future<void> _newNovel() async {
    await showMainWindow();
    final context = navigatorKey.currentState?.context;
    if (context == null || !context.mounted) {
      return;
    }
    showRevericDialog(
      context: context,
      builder: (ctx) => DialogFeedback.scope(
        builder: (ctx) => NovelFormDialog.create(
          onSubmit:
              ({
                required String title,
                required String authorName,
                required String description,
                required String category,
                required String type,
                required String contentKind,
                required int? plannedEpisodeCount,
                required String? sourceNovelId,
                required String? coverSourcePath,
                required bool removeCover,
                required List<String> tags,
              }) async {
                final container = ProviderScope.containerOf(ctx);
                final actions = container.read(novelActionsProvider);
                try {
                  final novelId = await actions.createNovel(
                    title: title,
                    authorName: authorName,
                    description: description,
                    category: category,
                    type: type,
                    contentKind: contentKind,
                    plannedEpisodeCount: plannedEpisodeCount,
                    sourceNovelId: sourceNovelId,
                    coverSourcePath: coverSourcePath,
                    tags: tags,
                  );
                  if (!ctx.mounted) return false;
                  final navigator = Navigator.of(ctx);
                  Navigator.of(ctx, rootNavigator: true).pop();
                  navigator.push(
                    MaterialPageRoute(
                      builder: (_) => WorkspaceEditorPage(novelId: novelId),
                    ),
                  );
                  return true;
                } catch (e) {
                  if (!ctx.mounted) return false;
                  ScaffoldMessenger.of(ctx).showSnackBar(
                    SnackBar(content: Text(ctx.t(LocaleKeys.trayCreateFailed))),
                  );
                  return false;
                }
              },
        ),
      ),
    );
  }

  Future<void> _about() async {
    await showMainWindow();
    final context = navigatorKey.currentState?.context;
    if (context == null || !context.mounted) {
      return;
    }
    showRevericDialog(
      context: context,
      builder: (ctx) {
        return RevericDialog(
          title: appDisplayName,
          content: Text(
            ctx.t(
              LocaleKeys.trayAboutContent,
              namedArgs: {'version': appVersion},
            ),
          ),
          actions: [
            RevericButton.secondary(
              label: ctx.t(LocaleKeys.trayClose),
              onPressed: () => Navigator.of(ctx).pop(),
            ),
          ],
        );
      },
    );
  }

  Future<void> _quit() async {
    await showMainWindow();

    final ctx = navigatorKey.currentState?.context;
    if (ctx == null || !ctx.mounted) {
      await _exitApplication();
      return;
    }

    final confirmed = await showConfirmDialog(
      ctx,
      title: ctx.t(LocaleKeys.trayQuitTitle),
      message: ctx.t(LocaleKeys.trayQuitMessage),
      confirmLabel: ctx.t(LocaleKeys.trayQuitConfirm),
      cancelLabel: ctx.t(LocaleKeys.trayQuitCancel),
      variant: ConfirmDialogVariant.warning,
    );

    if (confirmed == true) {
      await _exitApplication();
    }
  }

  Future<void> _exitApplication({
    void Function(int)? terminate,
    FutureOr<void> Function()? unlock,
    Future<void> Function()? cleanExit,
    StartupFailureReporter? failureReporter,
  }) async {
    for (final guard in List<Future<bool> Function()>.of(
      _exitGuards.reversed,
    )) {
      if (!await guard()) {
        return;
      }
    }
    _log.info('[EXIT] requested');
    _log.checkpoint('application exit requested (tray)');
    CrashSentinel.markActiveExitProgressSync(
      source: 'tray',
      phase: 'requested',
    );
    await windowManager.setPreventClose(false);

    // Close content databases first. Their normal close path can wait for
    // paused query streams; the process-exit path bypasses those listeners.
    CrashSentinel.markActiveExitProgressSync(
      source: 'tray',
      phase: 'closing_content_databases',
    );
    _log.info('[EXIT] closing content databases');
    try {
      await NovelContentDatabase.closeAllCachedForProcessExit();
    } catch (error, stackTrace) {
      _log.error(
        '[DB] table=novel_content_databases operation=CLOSE_ALL '
        'error=$error',
        error: error,
        stackTrace: stackTrace,
      );
    }
    _log.info('[EXIT] content databases closed');

    // Close databases before terminating to prevent NativeFinalizer SIGSEGV
    // during Dart isolate shutdown. The process-exit variant bypasses paused
    // Drift stream listeners while still awaiting the SQLite executor.
    CrashSentinel.markActiveExitProgressSync(
      source: 'tray',
      phase: 'closing_app_database',
    );
    _log.info('[EXIT] closing app database');
    try {
      await AppDatabase.closeCachedForProcessExit();
    } catch (error, stackTrace) {
      _log.error(
        '[DB] table=app_database operation=CLOSE_FOR_PROCESS_EXIT '
        'error=$error',
        error: error,
        stackTrace: stackTrace,
      );
    }
    _log.info('[EXIT] app database closed');

    // 正常退出：只清除当前会话 marker，待重试崩溃证据由 CrashSentinel 保留。
    // 必须在释放单实例锁之前完成，避免新进程看到旧 marker 或被旧进程删除。
    if (cleanExit != null) {
      await cleanExit();
    } else {
      CrashSentinel.markActiveSessionCleanExitSync();
    }
    // await 锁释放：确保激活 server 关闭、端口文件删除后再退出，
    // 避免残留端口文件误导下一次启动的第二实例。
    try {
      await Future<void>.sync(
        unlock ?? SingleInstanceService.unlock,
      ).timeout(const Duration(seconds: 3));
    } catch (error, stack) {
      _log.error(
        'Tray exit instance cleanup failed',
        error: error,
        stackTrace: stack,
      );
      try {
        await (failureReporter ?? StartupFailureReporter())
            .reportLifecycleFailure(
              phase: 'tray_exit',
              reason: error is TimeoutException
                  ? 'release_instance_timeout'
                  : 'release_instance_failed',
              error: error,
              stackTrace: stack,
            )
            .timeout(const Duration(seconds: 5));
      } catch (reportError) {
        _log.warning('Tray exit report did not finish: $reportError');
      }
    }

    // The tray plugin is native cleanup only; do not let its MethodChannel
    // reply prevent the process termination path on Windows.
    _log.info('[EXIT] destroying tray');
    unawaited(
      trayManager.destroy().catchError((error, stackTrace) {
        _log.warning('tray destroy failed error=$error\n$stackTrace');
      }),
    );
    // close() only posts the native close request. Awaiting its MethodChannel
    // reply can strand exit if native window teardown stops the host loop.
    unawaited(
      windowManager.close().catchError((error, stackTrace) {
        _log.warning('window close request failed error=$error\n$stackTrace');
      }),
    );
    _log.info('[EXIT] terminating');
    (terminate ?? exit)(0);
  }

  @visibleForTesting
  void resetForTesting() {
    _initialized = false;
    _menuInstalled = false;
    _menuLocale = null;
  }

  @visibleForTesting
  Future<void> exitApplicationForTesting(
    void Function(int) terminate, {
    FutureOr<void> Function()? unlock,
    Future<void> Function()? cleanExit,
    StartupFailureReporter? failureReporter,
  }) {
    return _exitApplication(
      terminate: terminate,
      unlock: unlock,
      cleanExit: cleanExit,
      failureReporter: failureReporter,
    );
  }

  @override
  void onTrayIconMouseDown() {
    showMainWindow();
  }

  @override
  void onTrayIconRightMouseDown() {
    if (_menuInstalled) {
      trayManager.popUpContextMenu();
      return;
    }
    // 菜单没装上就弹出等于什么都不发生，用户只会看到「右键失灵」。先补装再弹，
    // 把这条路径的失败兜在托盘自己身上。
    unawaited(
      applyLocale(_menuLocale ?? _startupLocale).whenComplete(() {
        if (_menuInstalled) {
          trayManager.popUpContextMenu();
        }
      }),
    );
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    switch (menuItem.key) {
      case 'newNovel':
        _newNovel();
      case 'about':
        _about();
      case 'hide':
        _hideWindow();
      case 'show':
        showMainWindow();
      case 'quit':
        _quit();
    }
  }
}

class _WindowCloseListener extends WindowListener {
  @override
  void onWindowClose() {
    // 区分"关窗最小化到托盘"与真正退出：关窗不退出进程，不应清除崩溃哨兵。
    _log.checkpoint('main window close intercepted; hiding to tray');
    Future.microtask(() async {
      await windowManager.hide();
    });
  }
}
