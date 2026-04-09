class DownloadTask {
  final String id;
  final String title;
  final String videoUrl;
  final String audioUrl;
  final String savePath;
  final int totalSize;
  int downloadedSize;
  DownloadStatus status;
  double progress;
  final DateTime createdAt;
  DateTime? completedAt;
  final String videoGid;
  final String audioGid;
  
  // Collection/series support fields
  final String? collectionId; // ID of the collection/series this task belongs to
  final String? collectionName; // Name of the collection/series
  final int? partIndex; // Index in multi-part video or collection (1-based)
  final int? totalParts; // Total number of parts
  final String? mergedFilePath; // Path to the merged file after completion
  final String? errorMessage; // Error message if download failed

  DownloadTask({
    required this.id,
    required this.title,
    required this.videoUrl,
    required this.audioUrl,
    required this.savePath,
    required this.totalSize,
    this.downloadedSize = 0,
    this.status = DownloadStatus.pending,
    this.progress = 0.0,
    required this.createdAt,
    this.completedAt,
    required this.videoGid,
    required this.audioGid,
    this.collectionId,
    this.collectionName,
    this.partIndex,
    this.totalParts,
    this.mergedFilePath,
    this.errorMessage,
  });

  DownloadTask copyWith({
    String? id,
    String? title,
    String? videoUrl,
    String? audioUrl,
    String? savePath,
    int? totalSize,
    int? downloadedSize,
    DownloadStatus? status,
    double? progress,
    DateTime? createdAt,
    DateTime? completedAt,
    String? videoGid,
    String? audioGid,
    String? collectionId,
    String? collectionName,
    int? partIndex,
    int? totalParts,
    String? mergedFilePath,
    String? errorMessage,
  }) {
    return DownloadTask(
      id: id ?? this.id,
      title: title ?? this.title,
      videoUrl: videoUrl ?? this.videoUrl,
      audioUrl: audioUrl ?? this.audioUrl,
      savePath: savePath ?? this.savePath,
      totalSize: totalSize ?? this.totalSize,
      downloadedSize: downloadedSize ?? this.downloadedSize,
      status: status ?? this.status,
      progress: progress ?? this.progress,
      createdAt: createdAt ?? this.createdAt,
      completedAt: completedAt ?? this.completedAt,
      videoGid: videoGid ?? this.videoGid,
      audioGid: audioGid ?? this.audioGid,
      collectionId: collectionId ?? this.collectionId,
      collectionName: collectionName ?? this.collectionName,
      partIndex: partIndex ?? this.partIndex,
      totalParts: totalParts ?? this.totalParts,
      mergedFilePath: mergedFilePath ?? this.mergedFilePath,
      errorMessage: errorMessage ?? this.errorMessage,
    );
  }
  
  /// Convert task to JSON for persistence
  Map<String, dynamic> toJson() {
    return {
      'id': id,
      'title': title,
      'videoUrl': videoUrl,
      'audioUrl': audioUrl,
      'savePath': savePath,
      'totalSize': totalSize,
      'downloadedSize': downloadedSize,
      'status': status.index,
      'progress': progress,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'completedAt': completedAt?.millisecondsSinceEpoch,
      'videoGid': videoGid,
      'audioGid': audioGid,
      'collectionId': collectionId,
      'collectionName': collectionName,
      'partIndex': partIndex,
      'totalParts': totalParts,
      'mergedFilePath': mergedFilePath,
      'errorMessage': errorMessage,
    };
  }
  
  /// Create task from JSON
  factory DownloadTask.fromJson(Map<String, dynamic> json) {
    return DownloadTask(
      id: json['id'] as String,
      title: json['title'] as String,
      videoUrl: json['videoUrl'] as String,
      audioUrl: json['audioUrl'] as String,
      savePath: json['savePath'] as String,
      totalSize: json['totalSize'] as int,
      downloadedSize: json['downloadedSize'] as int? ?? 0,
      status: DownloadStatus.values[json['status'] as int],
      progress: (json['progress'] as num?)?.toDouble() ?? 0.0,
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
      completedAt: json['completedAt'] != null 
          ? DateTime.fromMillisecondsSinceEpoch(json['completedAt'] as int)
          : null,
      videoGid: json['videoGid'] as String,
      audioGid: json['audioGid'] as String,
      collectionId: json['collectionId'] as String?,
      collectionName: json['collectionName'] as String?,
      partIndex: json['partIndex'] as int?,
      totalParts: json['totalParts'] as int?,
      mergedFilePath: json['mergedFilePath'] as String?,
      errorMessage: json['errorMessage'] as String?,
    );
  }
  
  /// Check if this task is part of a collection
  bool get isPartOfCollection => collectionId != null && collectionId!.isNotEmpty;
  
  /// Get display path (merged file if available, otherwise save path)
  String get displayPath => mergedFilePath ?? savePath;
}

enum DownloadStatus {
  pending,
  downloading,
  paused,
  completed,
  failed,
  cancelled,
}