import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:tray_manager/tray_manager.dart';
import 'package:window_manager/window_manager.dart';
import 'package:bilibili_downloader/services/aria2_service.dart';

class TrayService with ChangeNotifier implements TrayListener {
  static final TrayService _instance = TrayService._internal();
  factory TrayService() => _instance;
  TrayService._internal();

  bool _isInitialized = false;
  final Aria2Service _aria2Service = Aria2Service();
  Future<void> Function()? _cleanupCallback;

  bool get isInitialized => _isInitialized;

  /// Set cleanup callback to be called when exiting
  void setCleanupCallback(Future<void> Function() callback) {
    _cleanupCallback = callback;
  }

  Future<void> init() async {
    if (_isInitialized) return;

    try {
      // Initialize window manager to handle window close event
      await windowManager.ensureInitialized();

      // Prevent window from closing, just hide it
      WindowOptions windowOptions = const WindowOptions(
        skipTaskbar: false,
      );
      await windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.setPreventClose(true);
        await windowManager.show();
        await windowManager.focus();
      });

      // Setup tray icon
      await _setupTray();

      // Add listeners
      trayManager.addListener(this);
      windowManager.addListener(_WindowCloseListener());
      
      // Listen to Aria2Service changes to update tray menu
      _aria2Service.addListener(_onAria2StatusChanged);

      _isInitialized = true;
      debugPrint('TrayService initialized successfully');
    } catch (e) {
      debugPrint('Failed to initialize TrayService: $e');
      rethrow;
    }
  }

  void _onAria2StatusChanged() {
    debugPrint('Aria2 status changed, updating tray menu...');
    // Update the context menu to reflect new aria2 status
    _updateContextMenu().catchError((e) {
      debugPrint('Failed to update context menu: $e');
    });
  }

  Future<void> _setupTray() async {
    try {
      // Set tray icon - use different icons for different platforms
      String iconPath;
      if (Platform.isWindows) {
        iconPath = 'assets/icons/tray_icon.ico';
      } else {
        iconPath = 'assets/icons/tray_icon.png';
      }

      // Try to set icon, fallback to default if not found
      try {
        await trayManager.setIcon(iconPath);
      } catch (e) {
        debugPrint('Custom icon not found, using default: $e');
        // Use a simple default icon
        await trayManager.setIcon('assets/icons/app_icon.png');
      }

      // Set tooltip (not supported on Linux)
      if (!Platform.isLinux) {
        try {
          await trayManager.setToolTip('B站视频下载器');
        } catch (e) {
          debugPrint('Failed to set tooltip: $e');
        }
      }

      // Create context menu
      await _updateContextMenu();

      debugPrint('Tray icon setup completed');
    } catch (e) {
      debugPrint('Failed to setup tray: $e');
      rethrow;
    }
  }

  Future<void> _updateContextMenu() async {
    final Menu menu = Menu(
      items: [
        MenuItem(
          key: 'show_window',
          label: '显示窗口',
        ),
        MenuItem.separator(),
        MenuItem(
          key: 'aria2_status',
          label: _aria2Service.isRunning ? 'Aria2: 运行中' : 'Aria2: 已停止',
          disabled: true,
        ),
        MenuItem.separator(),
        MenuItem(
          key: 'exit_app',
          label: '完全退出',
        ),
      ],
    );
    await trayManager.setContextMenu(menu);
  }

  /// Show the main window
  Future<void> showWindow() async {
    await windowManager.show();
    await windowManager.focus();
    await windowManager.setSkipTaskbar(false);
  }

  /// Hide the main window to tray
  Future<void> hideWindow() async {
    await windowManager.hide();
    await windowManager.setSkipTaskbar(true);
  }

  /// Exit the application completely
  Future<void> exitApp() async {
    debugPrint('=== Exiting App Completely ===');
    
    try {
      // Call cleanup callback if set (from main.dart)
      if (_cleanupCallback != null) {
        await _cleanupCallback!();
      } else {
        // Fallback: stop aria2 directly
        if (_aria2Service.isRunning) {
          debugPrint('Stopping Aria2 before exit...');
          await _aria2Service.stop();
          debugPrint('Aria2 stopped successfully');
        }

        // Double-check: ensure no aria2 process is left running
        debugPrint('Verifying aria2 cleanup...');
        await _aria2Service.killProcessOnPort();
        debugPrint('Cleanup verification complete');
      }

      debugPrint('=== Cleanup Completed, Exiting ===');
      
      // Destroy tray icon
      await trayManager.destroy();
      
      // Exit the app
      exit(0);
    } catch (e) {
      debugPrint('Error during exit: $e');
      // Force exit even if there's an error
      exit(1);
    }
  }

  @override
  void onTrayIconMouseDown() {
    debugPrint('Tray icon left clicked');
    // Left click shows/hides window
    windowManager.isVisible().then((isVisible) {
      if (isVisible) {
        hideWindow();
      } else {
        showWindow();
      }
    });
  }

  @override
  void onTrayIconRightMouseDown() {
    debugPrint('Tray icon right clicked');
    // Right click shows context menu
    trayManager.popUpContextMenu();
  }

  @override
  void onTrayIconMouseUp() {
    // Optional: handle mouse up event
  }

  @override
  void onTrayIconRightMouseUp() {
    // Optional: handle right mouse up event
  }

  @override
  void onTrayMenuItemClick(MenuItem menuItem) {
    debugPrint('Tray menu item clicked: ${menuItem.key}');
    
    switch (menuItem.key) {
      case 'show_window':
        showWindow();
        break;
      case 'exit_app':
        exitApp();
        break;
    }
  }

  /// Update tray menu when aria2 status changes
  Future<void> updateAria2Status() async {
    await _updateContextMenu();
  }

  @override
  void dispose() {
    // Remove listeners
    trayManager.removeListener(this);
    _aria2Service.removeListener(_onAria2StatusChanged);
    super.dispose();
  }
}

/// Listener for window close events
class _WindowCloseListener with WindowListener {
  @override
  void onWindowClose() async {
    debugPrint('Window close button clicked - hiding to tray instead');
    // Don't actually close, just hide to tray
    await windowManager.hide();
    await windowManager.setSkipTaskbar(true);
  }
}
