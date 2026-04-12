/// Interface for Aria2 controller
/// This abstraction allows DownloadService to use aria2 without directly depending on Aria2Service
/// Only SettingsPage should control the actual Aria2Service implementation
abstract class IAria2Controller {
  /// Whether aria2 RPC is available and responding
  bool get isAvailable;
  
  /// Whether aria2 process is currently running
  bool get isRunning;
  
  /// The download directory path
  String get downloadDir;
  
  /// Whether auto-start is enabled in settings
  Future<bool> shouldAutoStart();
  
  /// Start internal aria2 (only works when not in external mode)
  Future<void> startInternalAria2();
  
  /// Add a URI download task
  /// Returns the GID of the created task, or null if failed
  Future<String?> addUriDownload(List<String> uris, {Map<String, dynamic>? options});
  
  /// Get the status of a download task by GID
  Future<Map<String, dynamic>?> getDownloadStatus(String gid);
  
  /// Get all active downloads
  Future<List<dynamic>?> getActiveDownloads();
  
  /// Pause a download task
  Future<bool> pauseDownload(String gid);
  
  /// Resume a paused download task
  Future<bool> unpauseDownload(String gid);
  
  /// Remove a download task
  Future<bool> removeDownload(String gid);
}
