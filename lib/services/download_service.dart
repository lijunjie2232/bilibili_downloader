import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:bilibili_downloader/models/download_task.dart';
import 'package:bilibili_downloader/services/merge_service.dart';
import 'package:bilibili_downloader/services/aria2_controller_interface.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Sanitize filename to remove invalid characters for Aria2
String _sanitizeFileName(String fileName) {
  String sanitized = fileName;
  
  // First, replace Chinese punctuation with ASCII equivalents
  sanitized = sanitized
      .replaceAll('！', '!')
      .replaceAll('，', ',')
      .replaceAll('。', '.')
      .replaceAll('？', '?')
      .replaceAll('；', ';')
      .replaceAll('：', ':')
      .replaceAll('\u201c', '"')  // left double quotation mark
      .replaceAll('\u201d', '"')  // right double quotation mark
      .replaceAll('\u2018', "'")  // left single quotation mark
      .replaceAll('\u2019', "'")  // right single quotation mark
      .replaceAll('（', '(')
      .replaceAll('）', ')')
      .replaceAll('【', '[')
      .replaceAll('】', ']')
      .replaceAll('《', '<')
      .replaceAll('》', '>')
      .replaceAll('、', ',')
      .replaceAll('…', '...')
      .replaceAll('—', '-')
      .replaceAll('～', '~');
  
  // Remove characters that are invalid for filenames (but keep Chinese and other Unicode letters)
  // Invalid chars: < > : " / \ | ? * and control characters
  sanitized = sanitized.replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1f]'), '');
  
  // Replace spaces with underscores for better compatibility
  sanitized = sanitized.replaceAll(' ', '_');
  
  // Trim whitespace
  sanitized = sanitized.trim();
  
  // Ensure not empty
  if (sanitized.isEmpty) {
    sanitized = 'unnamed';
  }
  
  return sanitized;
}

class DownloadService with ChangeNotifier {
  static final DownloadService _instance = DownloadService._internal();
  factory DownloadService() => _instance;
  DownloadService._internal();

  IAria2Controller? _aria2Controller;
  final _mergeService = MergeService();
  final List<DownloadTask> _tasks = [];
  final Set<String> _mergingTasks = {}; // Track tasks that are currently merging
  Timer? _monitorTimer;
  
  List<DownloadTask> get tasks => List.unmodifiable(_tasks);
  
  /// Set the aria2 controller - should only be called by main.dart after settings page initializes it
  void setAria2Controller(IAria2Controller controller) {
    _aria2Controller = controller;
    debugPrint('DownloadService: Aria2 controller set');
  }
  
  Future<void> init() async {
    // Don't initialize aria2 here - it should only be controlled by settings page
    // Just check if aria2 is available (controller should have been set by main.dart)
    
    // Check if aria2 controller is set
    if (_aria2Controller == null) {
      debugPrint('DownloadService: Aria2 controller not set. Please initialize from Settings page.');
      return;
    }
    
    // Check if aria2 is available
    if (!_aria2Controller!.isAvailable) {
      debugPrint('DownloadService: Aria2 is not available. Downloads will not work.');
      debugPrint('DownloadService: Please configure and start Aria2 from Settings page.');
    }
    
    await _loadTasks();
    _startMonitoring();
  }

  Future<void> downloadVideo(
    dynamic detail, 
    dynamic video, 
    dynamic audio, {
    String? collectionId,
    String? collectionName,
    int? partIndex,
    int? totalParts,
  }) async {
    // Check if aria2 is running
    if (_aria2Controller == null || !_aria2Controller!.isAvailable || !_aria2Controller!.isRunning) {
      throw Exception('aria2未启动，请检查aria2是否已安装并正常运行');
    }
    
    final taskId = DateTime.now().millisecondsSinceEpoch.toString();
    // Sanitize the filename to remove invalid characters
    final sanitizedName = _sanitizeFileName(detail.videoName);
    final fileName = '${sanitizedName}_${video.quality}';
    
    // 添加视频下载任务
    final videoGid = await _aria2Controller!.addUriDownload([video.url], 
      options: {
        'out': '${fileName}_video.mp4',
        'referer': 'https://www.bilibili.com',
        'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      }
    );
    
    // 添加音频下载任务
    final audioGid = await _aria2Controller!.addUriDownload([audio.url],
      options: {
        'out': '${fileName}_audio.m4a',
        'referer': 'https://www.bilibili.com',
        'user-agent': 'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36',
      }
    );
    
    if (videoGid == null || audioGid == null) {
      debugPrint('DownloadService: Failed to create download tasks');
      debugPrint('  Video GID: $videoGid');
      debugPrint('  Audio GID: $audioGid');
      throw Exception('创建下载任务失败，请检查aria2是否正常运行');
    }
    
    final task = DownloadTask(
        id: taskId,
        title: detail.videoName,
        videoUrl: video.url,
        audioUrl: audio.url,
        savePath: '${_aria2Controller!.downloadDir}/$fileName',
        totalSize: 0,
        videoGid: videoGid,
        audioGid: audioGid,
        createdAt: DateTime.now(),
        collectionId: collectionId,
        collectionName: collectionName,
        partIndex: partIndex,
        totalParts: totalParts,
      );
      
      _tasks.add(task);
      notifyListeners();
      await _saveTasks();
  }
  
  void _startMonitoring() {
    _monitorTimer = Timer.periodic(const Duration(seconds: 1), (timer) async {
      for (final task in _tasks) {
        if (task.status == DownloadStatus.downloading || 
            task.status == DownloadStatus.pending) {
          await _updateTaskProgress(task);
        }
      }
      notifyListeners();
    });
  }
  
  Future<void> _updateTaskProgress(DownloadTask task) async {
    try {
      final videoStatus = await _aria2Controller!.getDownloadStatus(task.videoGid);
      final audioStatus = await _aria2Controller!.getDownloadStatus(task.audioGid);
      
      if (videoStatus != null && audioStatus != null) {
        final videoCompleted = videoStatus['status'] == 'complete';
        final audioCompleted = audioStatus['status'] == 'complete';
        
        // 计算总进度
        final videoTotal = int.tryParse(videoStatus['totalLength'] ?? '1') ?? 1;
        final videoCompletedLength = int.tryParse(videoStatus['completedLength'] ?? '0') ?? 0;
        final audioTotal = int.tryParse(audioStatus['totalLength'] ?? '1') ?? 1;
        final audioCompletedLength = int.tryParse(audioStatus['completedLength'] ?? '0') ?? 0;
        
        final videoProgress = videoTotal > 0 ? videoCompletedLength / videoTotal : 0;
        final audioProgress = audioTotal > 0 ? audioCompletedLength / audioTotal : 0;
        
        final totalProgress = (videoProgress + audioProgress) / 2;
        final totalDownloaded = videoCompletedLength + audioCompletedLength;
        
        DownloadStatus newStatus;
        if (videoCompleted && audioCompleted) {
          // Start merging process (only if not already merging)
          if (!_mergingTasks.contains(task.id)) {
            newStatus = DownloadStatus.downloading; // Keep as downloading during merge
            
            // Perform merge in background
            _mergeFiles(task);
          } else {
            newStatus = task.status; // Keep current status
          }
        } else if (videoStatus['status'] == 'error' || audioStatus['status'] == 'error') {
          newStatus = DownloadStatus.failed;
        } else {
          newStatus = DownloadStatus.downloading;
        }
        
        _updateTask(task.id, 
          status: newStatus,
          progress: totalProgress,
          downloadedSize: totalDownloaded
        );
      }
    } catch (e) {
      debugPrint('Failed to update task progress: $e');
    }
  }
  
  void _updateTask(String taskId, {
    DownloadStatus? status,
    int? downloadedSize,
    double? progress,
    DateTime? completedAt,
    String? mergedFilePath,
    String? errorMessage,
  }) {
    final index = _tasks.indexWhere((task) => task.id == taskId);
    if (index != -1) {
      _tasks[index] = _tasks[index].copyWith(
        status: status,
        downloadedSize: downloadedSize,
        progress: progress,
        completedAt: completedAt,
        mergedFilePath: mergedFilePath,
        errorMessage: errorMessage,
      );
      _saveTasks();
      notifyListeners(); // Notify UI of changes
    }
  }
  
  Future<void> pauseDownload(String taskId) async {
    final task = _tasks.firstWhere((t) => t.id == taskId);
    await _aria2Controller!.pauseDownload(task.videoGid);
    await _aria2Controller!.pauseDownload(task.audioGid);
    _updateTask(taskId, status: DownloadStatus.paused);
  }
  
  Future<void> resumeDownload(String taskId) async {
    final task = _tasks.firstWhere((t) => t.id == taskId);
    await _aria2Controller!.unpauseDownload(task.videoGid);
    await _aria2Controller!.unpauseDownload(task.audioGid);
    _updateTask(taskId, status: DownloadStatus.downloading);
  }
  
  Future<void> cancelDownload(String taskId) async {
    final task = _tasks.firstWhere((t) => t.id == taskId);
    await _aria2Controller!.removeDownload(task.videoGid);
    await _aria2Controller!.removeDownload(task.audioGid);
    _updateTask(taskId, status: DownloadStatus.cancelled);
  }
  
  /// Remove a task from the list and optionally delete files
  Future<void> removeTask(String taskId, {bool deleteFiles = false}) async {
    final index = _tasks.indexWhere((task) => task.id == taskId);
    if (index == -1) return;
    
    final task = _tasks[index];
    
    // Delete files if requested and task is completed
    if (deleteFiles && task.status == DownloadStatus.completed) {
      try {
        final fileToDelete = File(task.displayPath);
        if (await fileToDelete.exists()) {
          await fileToDelete.delete();
          debugPrint('DownloadService: Deleted file ${task.displayPath}');
        }
      } catch (e) {
        debugPrint('DownloadService: Failed to delete file: $e');
      }
    }
    
    // Remove from aria2 if still downloading
    if (task.status == DownloadStatus.downloading || 
        task.status == DownloadStatus.pending ||
        task.status == DownloadStatus.paused) {
      await _aria2Controller!.removeDownload(task.videoGid);
      await _aria2Controller!.removeDownload(task.audioGid);
    }
    
    // Remove from list
    _tasks.removeAt(index);
    await _saveTasks();
    notifyListeners();
  }
  
  Future<void> _saveTasks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tasksJson = _tasks
          .map((task) => task.toJson())
          .toList();
      
      await prefs.setString('download_tasks', jsonEncode(tasksJson));
      debugPrint('DownloadService: Saved ${_tasks.length} tasks');
    } catch (e) {
      debugPrint('DownloadService: Failed to save tasks: $e');
    }
  }
  
  Future<void> _loadTasks() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final tasksStr = prefs.getString('download_tasks');
      
      if (tasksStr != null && tasksStr.isNotEmpty) {
        final tasksJson = jsonDecode(tasksStr) as List;
        _tasks.clear();
        
        for (var json in tasksJson) {
          try {
            final task = DownloadTask.fromJson(json as Map<String, dynamic>);
            _tasks.add(task);
          } catch (e) {
            debugPrint('DownloadService: Failed to load task: $e');
          }
        }
        
        debugPrint('DownloadService: Loaded ${_tasks.length} tasks');
        notifyListeners();
      }
    } catch (e) {
      debugPrint('DownloadService: Failed to load tasks: $e');
    }
  }
  
  /// Merge video and audio files after download completion
  Future<void> _mergeFiles(DownloadTask task) async {
    // Mark as merging to prevent duplicate calls
    _mergingTasks.add(task.id);
    
    try {
      debugPrint('DownloadService: Starting merge for task ${task.id}');
      
      final videoPath = '${task.savePath}_video.mp4';
      final audioPath = '${task.savePath}_audio.m4a';
      final mergedPath = '${task.savePath}.mp4';
      
      // Perform merge
      final success = await _mergeService.mergeVideoAudio(
        videoPath: videoPath,
        audioPath: audioPath,
        outputPath: mergedPath,
      );
      
      if (success) {
        debugPrint('DownloadService: Merge successful for task ${task.id}');
        
        // Clean up temporary files
        await _mergeService.cleanupTempFiles(
          videoPath: videoPath,
          audioPath: audioPath,
        );
        
        // Update task status
        _updateTask(
          task.id,
          status: DownloadStatus.completed,
          completedAt: DateTime.now(),
          mergedFilePath: mergedPath,
          progress: 1.0,
        );
        
        notifyListeners();
      } else {
        debugPrint('DownloadService: Merge failed for task ${task.id}');
        
        // Mark as failed but keep the separate files
        _updateTask(
          task.id,
          status: DownloadStatus.failed,
          errorMessage: '音视频合并失败',
        );
        
        notifyListeners();
      }
    } catch (e) {
      debugPrint('DownloadService: Exception during merge: $e');
      _updateTask(
        task.id,
        status: DownloadStatus.failed,
        errorMessage: '合并异常: $e',
      );
      notifyListeners();
    } finally {
      // Remove from merging set
      _mergingTasks.remove(task.id);
    }
  }
  
  @override
  void dispose() {
    _monitorTimer?.cancel();
    // Don't dispose aria2 here - it's controlled by settings page
    super.dispose();
  }
}