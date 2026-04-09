class CollectionInfo {
  final String id; // season_id or series_id
  final String name;
  final String description;
  final String coverUrl;
  final int mid; // creator ID
  final List<CollectionVideo> videos;
  final bool isArchives; // true=合集(archives), false=系列(series)
  final int totalVideos; // Total number of videos in collection

  CollectionInfo({
    required this.id,
    required this.name,
    required this.description,
    required this.coverUrl,
    required this.mid,
    required this.videos,
    required this.isArchives,
    this.totalVideos = 0,
  });

  factory CollectionInfo.fromJson(Map<String, dynamic> json, bool isArchives) {
    List<CollectionVideo> videos = [];
    
    if (isArchives) {
      // For archives (合集)
      if (json['data'] != null && json['data']['archives'] != null) {
        for (var video in json['data']['archives']) {
          videos.add(CollectionVideo.fromJson(video));
        }
      }
      
      // Get metadata
      final meta = json['data']?['meta'];
      final page = json['data']?['page'];
      
      return CollectionInfo(
        id: meta?['season_id']?.toString() ?? '',
        name: meta?['name'] ?? '',
        description: meta?['description'] ?? '',
        coverUrl: meta?['cover'] ?? '',
        mid: meta?['mid'] ?? 0,
        videos: videos,
        isArchives: true,
        totalVideos: page?['total'] ?? meta?['total'] ?? videos.length,
      );
    } else {
      // For series (系列) - this will be handled differently
      // Series API returns a list of series, we need to extract the specific one
      return CollectionInfo(
        id: '',
        name: '',
        description: '',
        coverUrl: '',
        mid: 0,
        videos: [],
        isArchives: false,
      );
    }
  }
}

class CollectionVideo {
  final String bvid;
  final String aid;
  final String title;
  final String coverUrl;
  final int duration;
  final int page; // Position in collection (1-based)
  final int viewCount; // View count

  CollectionVideo({
    required this.bvid,
    required this.aid,
    required this.title,
    required this.coverUrl,
    required this.duration,
    required this.page,
    this.viewCount = 0,
  });

  factory CollectionVideo.fromJson(Map<String, dynamic> json) {
    return CollectionVideo(
      bvid: json['bvid'] ?? '',
      aid: json['aid']?.toString() ?? '',
      title: json['title'] ?? '',
      coverUrl: json['pic'] ?? '',
      duration: json['duration'] ?? 0,
      page: 0, // Will be set by the service
      viewCount: json['stat']?['view'] ?? 0,
    );
  }
  
  /// Format duration as HH:MM:SS or MM:SS
  String get formattedDuration {
    final hours = duration ~/ 3600;
    final minutes = (duration % 3600) ~/ 60;
    final seconds = duration % 60;
    
    if (hours > 0) {
      return '$hours:${minutes.toString().padLeft(2, '0')}:${seconds.toString().padLeft(2, '0')}';
    } else {
      return '$minutes:${seconds.toString().padLeft(2, '0')}';
    }
  }
}
