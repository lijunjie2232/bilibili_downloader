import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:path_provider/path_provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:bilibili_downloader/services/aria2_controller_interface.dart';

/// Configuration constants for Aria2
abstract class Aria2Config {
  static const int defaultRpcPort = 6800;
  static const int connectionTimeoutSeconds = 3;
  static const int startupRetryAttempts = 15;
  static const int startupRetryIntervalMs = 500;
  static const int gracefulShutdownTimeoutSeconds = 3;
  static const int sessionSaveIntervalSeconds = 60;
  static const int maxConcurrentDownloads = 5;
  static const int splitCount = 10;
  static const int maxConnectionsPerServer = 10;
  static const String minSplitSize = '1M';
  static const String rpcHost = '127.0.0.1'; // Use IPv4 to avoid resolution issues
  static const String rpcEndpoint = '/jsonrpc';
  static const String sessionFileName = 'aria2.session';
  static const String aria2DataDirName = 'aria2';
}

/// Represents Aria2 configuration settings
class Aria2Settings {
  int rpcPort;
  String rpcSecret;
  bool useExternalAria2;
  String downloadDir;
  
  Aria2Settings({
    required this.rpcPort,
    required this.rpcSecret,
    required this.useExternalAria2,
    required this.downloadDir,
  });
  
  @override
  String toString() {
    return 'Aria2Settings(port: $rpcPort, hasSecret: ${rpcSecret.isNotEmpty}, '
        'external: $useExternalAria2, dir: $downloadDir)';
  }
}

class Aria2Service with ChangeNotifier implements IAria2Controller {
  static final Aria2Service _instance = Aria2Service._internal();
  factory Aria2Service() => _instance;
  Aria2Service._internal();

  bool _isRunning = false;
  bool _isAvailable = false;
  int _rpcPort = Aria2Config.defaultRpcPort;
  String _downloadDir = '';
  String _aria2DataDir = '';
  String _rpcSecret = '';
  bool _useExternalAria2 = false;
  Process? _aria2Process;
  
  // Reusable HTTP client for RPC calls
  HttpClient? _rpcClient;

  @override
  bool get isRunning => _isRunning;
  @override
  bool get isAvailable => _isAvailable;
  int get rpcPort => _rpcPort;
  @override
  String get downloadDir => _downloadDir;
  String get rpcSecret => _rpcSecret;
  bool get useExternalAria2 => _useExternalAria2;

  @override
  Future<bool> shouldAutoStart() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('aria2_auto_start') ?? false;
  }

  /// Get or create reusable HTTP client for RPC calls
  HttpClient _getRpcClient() {
    _rpcClient ??= HttpClient()
      ..connectionTimeout = Duration(seconds: Aria2Config.connectionTimeoutSeconds);
    return _rpcClient!;
  }
  
  /// Close the RPC client to free resources
  void _closeRpcClient() {
    _rpcClient?.close(force: true);
    _rpcClient = null;
  }

  Future<void> init() async {
    // Load settings from SharedPreferences
    await _loadSettings();
    
    // 获取下载目录 - 先尝试从设置中加载，如果没有则使用默认值
    final prefs = await SharedPreferences.getInstance();
    final userDownloadPath = prefs.getString('download_path');
    
    if (userDownloadPath != null && userDownloadPath.isNotEmpty) {
      _downloadDir = userDownloadPath;
      debugPrint('Using user-defined download directory: $_downloadDir');
    } else {
      // 获取系统默认下载目录
      final downloadsDir = await getDownloadsDirectory();
      _downloadDir = '${downloadsDir!.path}/BilibiliDownloader';
      debugPrint('Using default download directory: $_downloadDir');
    }
    
    // 创建下载目录
    final dir = Directory(_downloadDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    
    // 获取应用数据目录用于存储 aria2 session 文件
    final appDataDir = await getApplicationSupportDirectory();
    _aria2DataDir = '${appDataDir.path}/aria2';
    final aria2DataDirObj = Directory(_aria2DataDir);
    if (!await aria2DataDirObj.exists()) {
      await aria2DataDirObj.create(recursive: true);
      debugPrint('Created Aria2 data directory: $_aria2DataDir');
    }
    
    // Don't auto-control aria2 here - only settings page should control it
    // Just load settings and prepare the service
    debugPrint('Aria2Service initialized. Settings loaded:');
    debugPrint('  - Mode: ${_useExternalAria2 ? "External" : "Internal"}');
    debugPrint('  - Port: $_rpcPort');
    debugPrint('  - Has secret: ${_rpcSecret.isNotEmpty}');
    debugPrint('  - Download dir: $_downloadDir');
    debugPrint('  - Aria2 data dir: $_aria2DataDir');
    debugPrint('Use settings page to start/stop/configure Aria2.');
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    _rpcPort = prefs.getInt('aria2_rpc_port') ?? 6800;
    _rpcSecret = prefs.getString('aria2_rpc_secret') ?? '';
    _useExternalAria2 = prefs.getBool('aria2_use_external') ?? false;
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('aria2_rpc_port', _rpcPort);
    await prefs.setString('aria2_rpc_secret', _rpcSecret);
    await prefs.setBool('aria2_use_external', _useExternalAria2);
  }

  /// Update download directory
  Future<void> updateDownloadDir(String newDir) async {
    if (newDir.isEmpty) return;
    
    _downloadDir = newDir;
    
    // Create directory if it doesn't exist
    final dir = Directory(_downloadDir);
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    
    debugPrint('Download directory updated to: $_downloadDir');
    notifyListeners();
  }

  /// Save settings without restarting aria2
  Future<void> saveSettingsOnly({int? port, String? secret, bool? useExternal}) async {
    if (port != null) _rpcPort = port;
    if (secret != null) _rpcSecret = secret;
    if (useExternal != null) _useExternalAria2 = useExternal;
    
    await _saveSettings();
    debugPrint('Settings saved without restart');
  }

  Future<void> updateSettings({int? port, String? secret, bool? useExternal}) async {
    bool settingsChanged = false;
    
    if (port != null && port != _rpcPort) {
      _rpcPort = port;
      settingsChanged = true;
    }
    if (secret != null && secret != _rpcSecret) {
      _rpcSecret = secret;
      settingsChanged = true;
    }
    if (useExternal != null && useExternal != _useExternalAria2) {
      _useExternalAria2 = useExternal;
      settingsChanged = true;
    }
    
    await _saveSettings();
    
    // Only restart aria2 if settings actually changed
    if (settingsChanged) {
      if (_useExternalAria2) {
        // Switching to external mode - stop internal instance and kill any process on port
        debugPrint('Switching to external mode. Stopping internal aria2...');
        await stop();
        await killProcessOnPort();
        await _checkExternalAria2();
      } else {
        // Switching to internal mode - start internal instance
        debugPrint('Switching to internal mode. Starting aria2...');
        await stop();
        await _startAria2();
      }
    }
  }

  /// Start internal aria2 manually (called from settings page)
  @override
  Future<void> startInternalAria2() async {
    if (_useExternalAria2) {
      throw Exception('Cannot start internal aria2 when using external mode');
    }
    
    if (_isRunning) {
      debugPrint('Aria2 is already running');
      return;
    }
    
    debugPrint('Starting internal aria2 manually...');
    await _startAria2();
  }

  Future<void> _checkExternalAria2() async {
    try {
      final request = {
        'jsonrpc': '2.0',
        'id': 'bilibili-downloader-check',
        'method': 'aria2.getVersion',
        'params': _rpcSecret.isNotEmpty ? ['token:$_rpcSecret'] : [],
      };
      
      final response = await _sendRpcRequestRaw(request);
      
      if (response['result'] != null || response['error'] == null) {
        _isAvailable = true;
        _isRunning = true;
        debugPrint('Aria2 detected on port $_rpcPort');
      } else {
        _isAvailable = false;
        _isRunning = false;
        debugPrint('Aria2 error: ${response['error']}');
      }
      
      notifyListeners();
    } catch (e) {
      debugPrint('Failed to connect to aria2: $e');
      _isAvailable = false;
      _isRunning = false;
      notifyListeners();
    }
  }
  
  /// Send raw RPC request and return decoded response
  Future<Map<String, dynamic>> _sendRpcRequestRaw(Map<String, dynamic> request) async {
    final client = _getRpcClient();
    final uri = Uri.parse('http://${Aria2Config.rpcHost}:$_rpcPort${Aria2Config.rpcEndpoint}');
    
    final httpRequest = await client.postUrl(uri);
    final jsonData = jsonEncode(request);
    
    httpRequest.headers.set('Content-Type', 'application/json');
    httpRequest.headers.set('Content-Length', jsonData.length.toString());
    httpRequest.write(jsonData);
    
    final httpResponse = await httpRequest.close();
    final responseBody = await httpResponse.transform(utf8.decoder).join();
    
    if (httpResponse.statusCode != 200) {
      throw Exception('HTTP ${httpResponse.statusCode}: $responseBody');
    }
    
    return jsonDecode(responseBody) as Map<String, dynamic>;
  }

  Future<void> _startAria2() async {
    try {
      // Check if aria2 is installed
      final result = await Process.run('which', ['aria2c']);
      if (result.exitCode != 0) {
        throw Exception('Aria2 not found. Please install aria2 first.');
      }
      
      _isAvailable = true;

      // Check if port is already in use
      if (await _isPortInUse(_rpcPort)) {
        debugPrint('Port $_rpcPort in use, checking for existing aria2...');
        await _checkExternalAria2();
        
        if (_isRunning) {
          debugPrint('Using existing aria2 instance on port $_rpcPort');
          return;
        }
        
        debugPrint('Port $_rpcPort occupied by non-aria2 process, killing...');
        await killProcessOnPort();
        await Future.delayed(const Duration(seconds: 1));
        
        if (await _isPortInUse(_rpcPort)) {
          throw Exception('Port $_rpcPort still in use. Please choose a different port.');
        }
      }

      // Ensure session file exists
      final sessionFile = File('$_aria2DataDir/${Aria2Config.sessionFileName}');
      if (!await sessionFile.exists()) {
        await sessionFile.create(recursive: true);
      }

      // Build aria2 arguments
      final args = [
        '--enable-rpc=true',
        '--rpc-listen-all=false',
        '--rpc-listen-port=$_rpcPort',
        '--dir=$_downloadDir',
        '--continue=true',
        '--max-concurrent-downloads=${Aria2Config.maxConcurrentDownloads}',
        '--split=${Aria2Config.splitCount}',
        '--max-connection-per-server=${Aria2Config.maxConnectionsPerServer}',
        '--min-split-size=${Aria2Config.minSplitSize}',
        '--input-file=$_aria2DataDir/${Aria2Config.sessionFileName}',
        '--save-session=$_aria2DataDir/${Aria2Config.sessionFileName}',
        '--save-session-interval=${Aria2Config.sessionSaveIntervalSeconds}',
        '--force-save=true',
        '--daemon=false',
        '--log-level=notice',
      ];
      
      if (_rpcSecret.isNotEmpty) {
        args.add('--rpc-secret=$_rpcSecret');
      }

      // Start aria2 process
      _aria2Process = await Process.start('aria2c', args);
      _setupProcessStreams();

      // Wait for aria2 to start with retry logic
      await _waitForAria2Startup();
      
      debugPrint('Aria2 started successfully on port $_rpcPort');
    } catch (e) {
      debugPrint('Failed to start aria2: $e');
      _isRunning = false;
      _isAvailable = false;
      notifyListeners();
      rethrow;
    }
  }
  
  /// Setup stdout/stderr listeners for aria2 process
  void _setupProcessStreams() {
    _aria2Process!.stdout.transform(utf8.decoder).listen(
      (data) => debugPrint('Aria2: $data'),
      onError: (error) => debugPrint('Aria2 stdout error: $error'),
    );

    _aria2Process!.stderr.transform(utf8.decoder).listen(
      (data) => debugPrint('Aria2: $data'),
      onError: (error) => debugPrint('Aria2 stderr error: $error'),
    );

    // Listen for process exit
    _aria2Process!.exitCode.then((code) {
      debugPrint('Aria2 exited with code: $code');
      _isRunning = false;
      notifyListeners();
    });
  }
  
  /// Wait for aria2 to start up with retry logic
  Future<void> _waitForAria2Startup() async {
    Exception? lastException;
    
    for (int i = 0; i < Aria2Config.startupRetryAttempts; i++) {
      await Future.delayed(Duration(milliseconds: Aria2Config.startupRetryIntervalMs));
      
      try {
        await _checkExternalAria2();
        if (_isRunning) {
          debugPrint('Aria2 connected on attempt ${i + 1}');
          return;
        }
      } catch (e) {
        lastException = e is Exception ? e : Exception(e.toString());
      }
    }
    
    // Failed to start - check if process is still running
    if (_aria2Process != null) {
      final exitCode = await _aria2Process!.exitCode.timeout(
        const Duration(seconds: 1),
        onTimeout: () => -1,
      );
      
      if (exitCode != -1) {
        throw Exception('Aria2 exited with code $exitCode');
      }
    }
    
    throw lastException ?? Exception('Aria2 RPC not responding after ${Aria2Config.startupRetryAttempts} attempts');
  }

  Future<void> stop() async {
    if (_aria2Process == null) {
      _isRunning = false;
      _isAvailable = false;
      notifyListeners();
      return;
    }
    
    debugPrint('Stopping aria2 process (PID: ${_aria2Process!.pid})...');
    
    try {
      await _gracefulShutdown();
    } catch (e) {
      debugPrint('Error during shutdown: $e, force killing...');
      _forceKill();
    }
    
    _aria2Process = null;
    _isRunning = false;
    _isAvailable = false;
    notifyListeners();
    debugPrint('Aria2 stopped');
  }
  
  /// Attempt graceful shutdown with SIGTERM
  Future<void> _gracefulShutdown() async {
    if (Platform.isLinux || Platform.isMacOS) {
      Process.killPid(_aria2Process!.pid, ProcessSignal.sigterm);
      
      final exitCode = await _aria2Process!.exitCode.timeout(
        Duration(seconds: Aria2Config.gracefulShutdownTimeoutSeconds),
        onTimeout: () {
          debugPrint('Graceful shutdown timeout, force killing...');
          return -999;
        },
      );
      
      if (exitCode == -999) {
        _forceKill();
      } else {
        debugPrint('Aria2 stopped gracefully (code: $exitCode)');
      }
    } else if (Platform.isWindows) {
      await Process.run('taskkill', ['/PID', '${_aria2Process!.pid}']);
      await _aria2Process!.exitCode;
    } else {
      _forceKill();
    }
  }
  
  /// Force kill the process
  void _forceKill() {
    debugPrint('Force killing aria2...');
    _aria2Process!.kill();
  }

  /// Kill any aria2c process running on the configured port
  Future<void> killProcessOnPort() async {
    try {
      if (Platform.isLinux || Platform.isMacOS) {
        await _killProcessesOnPortUnix();
      } else if (Platform.isWindows) {
        await _killProcessesOnPortWindows();
      }
    } catch (e) {
      debugPrint('Failed to kill process on port $_rpcPort: $e');
    }
  }
  
  /// Kill processes on port for Unix systems
  Future<void> _killProcessesOnPortUnix() async {
    final result = await Process.run('lsof', ['-ti', ':$_rpcPort']);
    if (result.exitCode != 0 || result.stdout.toString().trim().isEmpty) {
      return;
    }
    
    final pids = result.stdout.toString().trim().split('\n');
    for (final pid in pids) {
      if (pid.trim().isEmpty) continue;
      
      try {
        final pidNum = int.parse(pid.trim());
        Process.killPid(pidNum, ProcessSignal.sigterm);
        await Future.delayed(const Duration(milliseconds: 500));
        
        // Check if still running
        final checkResult = await Process.run('kill', ['-0', pid.trim()]);
        if (checkResult.exitCode == 0) {
          await Process.run('kill', ['-9', pid.trim()]);
        }
      } catch (e) {
        await Process.run('kill', ['-9', pid.trim()]);
      }
    }
  }
  
  /// Kill processes on port for Windows
  Future<void> _killProcessesOnPortWindows() async {
    final result = await Process.run('netstat', ['-ano']);
    if (result.exitCode != 0) return;
    
    final lines = result.stdout.toString().split('\n');
    for (final line in lines) {
      if (line.contains(':$_rpcPort') && line.contains('LISTENING')) {
        final parts = line.trim().split(RegExp(r'\s+'));
        if (parts.length >= 5) {
          final pid = parts[parts.length - 1];
          await Process.run('taskkill', ['/F', '/PID', pid]);
        }
      }
    }
  }

  @override
  Future<String?> addUriDownload(List<String> uris, {Map<String, dynamic>? options}) async {
    if (!_isRunning) return null;

    try {
      final response = await _sendRpcRequest('aria2.addUri', [uris, options ?? {}]);
      return response['result'] as String?;
    } catch (e) {
      debugPrint('Failed to add download: $e');
      return null;
    }
  }

  @override
  Future<Map<String, dynamic>?> getDownloadStatus(String gid) async {
    if (!_isRunning) return null;

    try {
      final response = await _sendRpcRequest('aria2.tellStatus', [gid]);
      return response['result'] as Map<String, dynamic>?;
    } catch (e) {
      debugPrint('Failed to get status: $e');
      return null;
    }
  }

  @override
  Future<List<dynamic>?> getActiveDownloads() async {
    if (!_isRunning) return null;

    try {
      final response = await _sendRpcRequest('aria2.tellActive', []);
      return response['result'] as List<dynamic>?;
    } catch (e) {
      debugPrint('Failed to get active downloads: $e');
      return null;
    }
  }

  @override
  Future<bool> pauseDownload(String gid) async {
    if (!_isRunning) return false;

    try {
      final response = await _sendRpcRequest('aria2.pause', [gid]);
      return response['result'] != null;
    } catch (e) {
      debugPrint('Failed to pause: $e');
      return false;
    }
  }

  @override
  Future<bool> unpauseDownload(String gid) async {
    if (!_isRunning) return false;

    try {
      final response = await _sendRpcRequest('aria2.unpause', [gid]);
      return response['result'] != null;
    } catch (e) {
      debugPrint('Failed to unpause: $e');
      return false;
    }
  }

  @override
  Future<bool> removeDownload(String gid) async {
    if (!_isRunning) return false;

    try {
      final response = await _sendRpcRequest('aria2.remove', [gid]);
      return response['result'] != null;
    } catch (e) {
      debugPrint('Failed to remove: $e');
      return false;
    }
  }

  /// Send RPC request with authentication
  Future<Map<String, dynamic>> _sendRpcRequest(String method, List<dynamic> params) async {
    final request = {
      'jsonrpc': '2.0',
      'id': 'bilibili-downloader',
      'method': method,
      'params': _buildRpcParams(params),
    };

    return await _sendRpcRequestRaw(request);
  }
  
  /// Build RPC params with authentication token if needed
  List<dynamic> _buildRpcParams(List<dynamic> params) {
    if (_rpcSecret.isEmpty) return params;
    
    final newParams = <dynamic>['token:$_rpcSecret'];
    newParams.addAll(params);
    return newParams;
  }

  @override
  void dispose() {
    debugPrint('Aria2Service disposing...');
    _closeRpcClient();
    
    if (_aria2Process != null) {
      stop();
    }
    
    super.dispose();
  }

  /// Check if a port is currently in use
  Future<bool> _isPortInUse(int port) async {
    try {
      final server = await ServerSocket.bind(InternetAddress.loopbackIPv4, port);
      await server.close();
      return false; // Port is available
    } catch (e) {
      return true; // Port is in use
    }
  }
}