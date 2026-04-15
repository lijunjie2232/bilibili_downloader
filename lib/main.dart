import 'package:bilibili_downloader/app.dart';
import 'package:bilibili_downloader/services/auth_service.dart';
import 'package:bilibili_downloader/services/download_service.dart';
import 'package:bilibili_downloader/services/aria2_service.dart';
import 'package:bilibili_downloader/services/theme_service.dart';
import 'package:bilibili_downloader/services/tray_service.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:io';

// Global references to services for cleanup
late Aria2Service _aria2Service;
late DownloadService _downloadService;
late TrayService _trayService;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  
  final authService = AuthService();
  _aria2Service = Aria2Service();
  _downloadService = DownloadService();
  final themeService = ThemeService();
  _trayService = TrayService();
  
  await authService.loadCookie();
  
  // Initialize aria2 service (loads settings only, doesn't start aria2)
  await _aria2Service.init();
  
  // Check if auto-start is enabled and start aria2 if needed
  final prefs = await SharedPreferences.getInstance();
  final autoStart = prefs.getBool('aria2_auto_start') ?? false;
  if (autoStart && !_aria2Service.useExternalAria2) {
    debugPrint('Auto-starting internal Aria2...');
    try {
      await _aria2Service.startInternalAria2();
      debugPrint('Aria2 auto-started successfully');
    } catch (e) {
      debugPrint('Failed to auto-start Aria2: $e');
    }
  }
  
  // Inject aria2 controller into download service
  // DownloadService will use this interface to interact with aria2
  // but cannot control (start/stop) it - only SettingsPage can do that
  _downloadService.setAria2Controller(_aria2Service);
  
  await _downloadService.init();
  await themeService.init();
  
  // Setup cleanup function
  // Note: This is now only called from TrayService.exitApp(), not on window close
  Future<void> cleanupOnExit() async {
    debugPrint('=== App Cleanup Started ===');
    
    try {
      if (_aria2Service.isRunning) {
        debugPrint('Stopping Aria2 before exit...');
        await _aria2Service.stop();
        debugPrint('Aria2 stopped successfully');
      } else {
        debugPrint('Aria2 is not running, no cleanup needed');
      }
      
      // Double-check: ensure no aria2 process is left running on the port
      // This is a safety net in case stop() didn't fully clean up
      debugPrint('Verifying aria2 cleanup...');
      await _aria2Service.killProcessOnPort();
      debugPrint('Cleanup verification complete');
    } catch (e) {
      debugPrint('Error during cleanup: $e');
      // Try one more time with force kill
      try {
        await _aria2Service.killProcessOnPort();
      } catch (_) {}
    }
    
    debugPrint('=== App Cleanup Completed ===');
  }
  
  // Initialize tray service (only on desktop platforms)
  if (Platform.isLinux || Platform.isMacOS || Platform.isWindows) {
    try {
      await _trayService.init();
      // Set cleanup callback for when user clicks "Exit" in tray menu
      _trayService.setCleanupCallback(cleanupOnExit);
      debugPrint('Tray service initialized');
    } catch (e) {
      debugPrint('Failed to initialize tray service: $e');
      // Continue without tray service if it fails
    }
  }
  
  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => authService),
        ChangeNotifierProvider(create: (_) => _aria2Service),
        ChangeNotifierProvider(create: (_) => _downloadService),
        ChangeNotifierProvider(create: (_) => themeService),
        ChangeNotifierProvider(create: (_) => _trayService),
      ],
      child: const App(),
    ),
  );
}
