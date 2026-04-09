import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:bilibili_downloader/models/video_info.dart';
import 'package:bilibili_downloader/models/collection_info.dart';
import 'package:bilibili_downloader/services/analyze_service.dart';
import 'package:bilibili_downloader/services/collection_service.dart';
import 'package:bilibili_downloader/services/download_service.dart';

class AnalyzePage extends StatefulWidget {
  const AnalyzePage({super.key});

  @override
  _AnalyzePageState createState() => _AnalyzePageState();
}

class _AnalyzePageState extends State<AnalyzePage> with TickerProviderStateMixin {
  late TabController _tabController;
  final List<_AnalyzeTabData> _tabs = [];
  int _currentTabIndex = 0;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 0, vsync: this);
    // Add initial tab
    _addNewTab();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  void _addNewTab() {
    setState(() {
      final newTab = _AnalyzeTabData();
      _tabs.add(newTab);
      _currentTabIndex = _tabs.length - 1;
      _tabController = TabController(
        length: _tabs.length,
        vsync: this,
        initialIndex: _currentTabIndex,
      );
    });
  }

  void _closeTab(int index) {
    if (_tabs.length <= 1) {
      // Don't close the last tab, just reset it
      setState(() {
        _tabs[0].reset();
      });
      return;
    }

    setState(() {
      _tabs.removeAt(index);
      if (_currentTabIndex >= _tabs.length) {
        _currentTabIndex = _tabs.length - 1;
      }
      _tabController = TabController(
        length: _tabs.length,
        vsync: this,
        initialIndex: _currentTabIndex,
      );
    });
  }

  void _onTabChanged(int index) {
    setState(() {
      _currentTabIndex = index;
    });
  }

  // Get current tab data
  _AnalyzeTabData get _currentTab => _tabs[_currentTabIndex];

  // Check if download button should be enabled
  bool get _canDownload {
    if (_currentTab.contentType == 'video') {
      return _currentTab.selectedParts.isNotEmpty && 
             _currentTab.selectedParts.every((index) => _currentTab.analyzedParts.containsKey(index));
    } else if (_currentTab.contentType == 'collection' || _currentTab.contentType == 'series') {
      return _currentTab.selectedVideos.isNotEmpty;
    }
    return false;
  }

  // Calculate analysis progress percentage
  String get _progressText {
    if (_currentTab.totalToAnalyze == 0) return '0%';
    final percentage = (_currentTab.analyzedCount / _currentTab.totalToAnalyze * 100).toStringAsFixed(0);
    return '$percentage% (${_currentTab.analyzedCount}/${_currentTab.totalToAnalyze})';
  }

  // Start analyzing selected parts
  Future<void> _startAnalysis() async {
    if (_currentTab.videoInfo == null || _currentTab.selectedParts.isEmpty) return;

    // Determine which parts to analyze based on reanalyze option
    List<int> partsToAnalyze;
    if (_currentTab.reanalyzeSuccessful) {
      // Reanalyze all selected parts (including already successful ones)
      partsToAnalyze = _currentTab.selectedParts.toList();
      
      // Clear analyzed parts for selected indices
      setState(() {
        for (final index in _currentTab.selectedParts) {
          _currentTab.analyzedParts.remove(index);
        }
      });
    } else {
      // Only analyze parts that haven't been analyzed yet
      partsToAnalyze = _currentTab.selectedParts
          .where((index) => !_currentTab.analyzedParts.containsKey(index))
          .toList();
      
      if (partsToAnalyze.isEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('所有选中的分P已经分析完成')),
        );
        return;
      }
    }

    setState(() {
      _currentTab.isAnalyzing = true;
      _currentTab.analyzedCount = 0;
      _currentTab.totalToAnalyze = partsToAnalyze.length;
      _currentTab.analysisProgress = 0.0;
    });

    try {
      // Get the ID info for API calls
      final analyzeService = AnalyzeService();
      final idInfo = analyzeService.parseUrl(_currentTab.urlController.text.trim());
      
      // Analyze each selected part sequentially to avoid rate limiting
      for (final index in partsToAnalyze) {
        if (index >= _currentTab.videoInfo!.parts.length) continue;
        
        final part = _currentTab.videoInfo!.parts[index];
        
        try {
          final detail = await _currentTab.analyzeService.getVideoDetail(
            idInfo['id'] as String,
            part.cid,
            fnval: 16,
          );
          
          setState(() {
            _currentTab.analyzedParts[index] = detail;
            _currentTab.analyzedCount++;
            _currentTab.analysisProgress = _currentTab.analyzedCount / _currentTab.totalToAnalyze;
          });
        } catch (e) {
          debugPrint('Failed to analyze part ${index + 1}: $e');
          // Continue with next part even if one fails
        }
      }
      
      setState(() {
        _currentTab.isAnalyzing = false;
      });
      
      // Show completion message
      if (mounted) {
        final message = _currentTab.reanalyzeSuccessful
            ? '重新分析完成！已分析 ${_currentTab.analyzedCount}/${partsToAnalyze.length} 个分P'
            : '分析完成！本次分析 ${_currentTab.analyzedCount}/${partsToAnalyze.length} 个新分P';
        
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(message),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } catch (e) {
      setState(() {
        _currentTab.isAnalyzing = false;
        _currentTab.errorMessage = '分析失败: $e';
      });
    }
  }

  // Selection helper methods
  void _selectAllParts() {
    setState(() {
      if (_currentTab.videoInfo != null) {
        _currentTab.selectedParts = Set.from(List.generate(_currentTab.videoInfo!.parts.length, (i) => i));
      }
    });
  }

  void _deselectAllParts() {
    setState(() {
      _currentTab.selectedParts.clear();
    });
  }

  void _reverseSelection() {
    setState(() {
      if (_currentTab.videoInfo != null) {
        final allIndices = Set<int>.from(List.generate(_currentTab.videoInfo!.parts.length, (i) => i));
        _currentTab.selectedParts = allIndices.difference(_currentTab.selectedParts);
      }
    });
  }

  // Show download dialog with quality selection
  void _showDownloadDialog() {
    if (_currentTab.analyzedParts.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('请先分析选中的分P')),
      );
      return;
    }

    // Store selected qualities for each part
    final Map<int, int> selectedVideoQualities = {};
    final Map<int, int> selectedAudioQualities = {};
    
    // Initialize with highest quality for each SELECTED and analyzed part
    for (final index in _currentTab.selectedParts) {
      if (!_currentTab.analyzedParts.containsKey(index)) continue;
      
      final detail = _currentTab.analyzedParts[index]!;
      
      // Sort videos by id (higher id = higher quality) and select the highest
      if (detail.videos.isNotEmpty) {
        final sortedVideos = detail.videos.toList()..sort((a, b) => b.id.compareTo(a.id));
        selectedVideoQualities[index] = sortedVideos.first.id;
      }
      
      // Sort audios by id (higher id = higher quality) and select the highest
      if (detail.audios.isNotEmpty) {
        final sortedAudios = detail.audios.toList()..sort((a, b) => b.id.compareTo(a.id));
        selectedAudioQualities[index] = sortedAudios.first.id;
      }
    }
    
    // Get union of all video and audio qualities
    final allVideoQualities = _getAllVideoQualities();
    final allAudioQualities = _getAllAudioQualities();
    
    // Default to highest quality
    int? defaultVideoQuality = allVideoQualities.isNotEmpty 
        ? allVideoQualities.reduce((a, b) => a.id > b.id ? a : b).id 
        : null;
    int? defaultAudioQuality = allAudioQualities.isNotEmpty 
        ? allAudioQualities.reduce((a, b) => a.id > b.id ? a : b).id 
        : null;
    
    // State for "apply to all" dropdowns
    int? applyToAllVideoQuality = defaultVideoQuality;
    int? applyToAllAudioQuality = defaultAudioQuality;

    showDialog(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) {
          return AlertDialog(
            title: const Text('选择画质'),
            content: SizedBox(
              width: double.maxFinite,
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Apply to all section
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.blue.shade50,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Text(
                            '应用到全部',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                            ),
                          ),
                          const SizedBox(height: 8),
                          
                          // Video quality dropdown
                          if (allVideoQualities.isNotEmpty)
                            Row(
                              children: [
                                const Text('视频:', style: TextStyle(fontSize: 13)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: DropdownButton<int>(
                                    value: applyToAllVideoQuality,
                                    isExpanded: true,
                                    items: allVideoQualities.map((quality) {
                                      return DropdownMenuItem<int>(
                                        value: quality.id,
                                        child: Text(quality.quality),
                                      );
                                    }).toList(),
                                    onChanged: (value) {
                                      setDialogState(() {
                                        applyToAllVideoQuality = value;
                                        // Apply to all SELECTED parts
                                        if (value != null) {
                                          for (final index in _currentTab.selectedParts) {
                                            if (!_currentTab.analyzedParts.containsKey(index)) continue;
                                            final detail = _currentTab.analyzedParts[index]!;
                                            // Try to find exact match, otherwise use best available
                                            final matchedVideo = detail.videos.firstWhere(
                                              (v) => v.id == value,
                                              orElse: () => detail.videos.reduce((a, b) => a.id > b.id ? a : b),
                                            );
                                            selectedVideoQualities[index] = matchedVideo.id;
                                          }
                                        }
                                      });
                                    },
                                  ),
                                ),
                              ],
                            ),
                          
                          const SizedBox(height: 8),
                          
                          // Audio quality dropdown
                          if (allAudioQualities.isNotEmpty)
                            Row(
                              children: [
                                const Text('音频:', style: TextStyle(fontSize: 13)),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: DropdownButton<int>(
                                    value: applyToAllAudioQuality,
                                    isExpanded: true,
                                    items: allAudioQualities.map((quality) {
                                      return DropdownMenuItem<int>(
                                        value: quality.id,
                                        child: Text(quality.quality),
                                      );
                                    }).toList(),
                                    onChanged: (value) {
                                      setDialogState(() {
                                        applyToAllAudioQuality = value;
                                        // Apply to all SELECTED parts
                                        if (value != null) {
                                          for (final index in _currentTab.selectedParts) {
                                            if (!_currentTab.analyzedParts.containsKey(index)) continue;
                                            final detail = _currentTab.analyzedParts[index]!;
                                            // Try to find exact match, otherwise use best available
                                            final matchedAudio = detail.audios.firstWhere(
                                              (a) => a.id == value,
                                              orElse: () => detail.audios.reduce((a, b) => a.id > b.id ? a : b),
                                            );
                                            selectedAudioQualities[index] = matchedAudio.id;
                                          }
                                        }
                                      });
                                    },
                                  ),
                                ),
                              ],
                            ),
                        ],
                      ),
                    ),
                    
                    const SizedBox(height: 16),
                    const Text(
                      '各分P画质设置',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    const SizedBox(height: 8),
                    
                    // List of parts with quality selection
                    ..._currentTab.analyzedParts.entries
                        .where((entry) => _currentTab.selectedParts.contains(entry.key))
                        .map((entry) {
                      final index = entry.key;
                      final detail = entry.value;
                      final part = _currentTab.videoInfo!.parts[index];
                      
                      return Card(
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'P${index + 1}: ${part.title}',
                                style: const TextStyle(
                                  fontWeight: FontWeight.bold,
                                  fontSize: 14,
                                ),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                              ),
                              const SizedBox(height: 8),
                              
                              // Video quality selection
                              if (detail.videos.isNotEmpty) ...[
                                const Text('视频画质:', style: TextStyle(fontSize: 12)),
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 4,
                                  children: () {
                                    final sortedVideos = detail.videos.toList()
                                      ..sort((a, b) => b.id.compareTo(a.id));
                                    return sortedVideos.map((video) {
                                      final isSelected = selectedVideoQualities[index] == video.id;
                                      return ChoiceChip(
                                        label: Text(video.quality),
                                        selected: isSelected,
                                        onSelected: (selected) {
                                          if (selected) {
                                            setDialogState(() {
                                              selectedVideoQualities[index] = video.id;
                                            });
                                          }
                                        },
                                      );
                                    }).toList();
                                  }(),
                                ),
                              ],
                              
                              const SizedBox(height: 8),
                              
                              // Audio quality selection
                              if (detail.audios.isNotEmpty) ...[
                                const Text('音频画质:', style: TextStyle(fontSize: 12)),
                                const SizedBox(height: 4),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 4,
                                  children: () {
                                    final sortedAudios = detail.audios.toList()
                                      ..sort((a, b) => b.id.compareTo(a.id));
                                    return sortedAudios.map((audio) {
                                      final isSelected = selectedAudioQualities[index] == audio.id;
                                      return ChoiceChip(
                                        label: Text(audio.quality),
                                        selected: isSelected,
                                        onSelected: (selected) {
                                          if (selected) {
                                            setDialogState(() {
                                              selectedAudioQualities[index] = audio.id;
                                            });
                                          }
                                        },
                                      );
                                    }).toList();
                                  }(),
                                ),
                              ],
                            ],
                          ),
                        ),
                      );
                    }),
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('取消'),
              ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(dialogContext);
                  _startDownloadWithQualities(
                    selectedVideoQualities,
                    selectedAudioQualities,
                  );
                },
                child: const Text('开始下载'),
              ),
            ],
          );
        },
      ),
    );
  }

  // Get union of all video qualities across all analyzed parts
  List<VideoStream> _getAllVideoQualities() {
    if (_currentTab.analyzedParts.isEmpty) return [];
    
    final Map<int, VideoStream> qualityMap = {};
    
    for (final detail in _currentTab.analyzedParts.values) {
      for (final video in detail.videos) {
        if (!qualityMap.containsKey(video.id)) {
          qualityMap[video.id] = video;
        }
      }
    }
    
    // Sort by ID (higher ID = better quality)
    final qualities = qualityMap.values.toList();
    qualities.sort((a, b) => b.id.compareTo(a.id));
    return qualities;
  }

  // Get union of all audio qualities across all analyzed parts
  List<AudioStream> _getAllAudioQualities() {
    if (_currentTab.analyzedParts.isEmpty) return [];
    
    final Map<int, AudioStream> qualityMap = {};
    
    for (final detail in _currentTab.analyzedParts.values) {
      for (final audio in detail.audios) {
        if (!qualityMap.containsKey(audio.id)) {
          qualityMap[audio.id] = audio;
        }
      }
    }
    
    // Sort by ID (higher ID = better quality)
    final qualities = qualityMap.values.toList();
    qualities.sort((a, b) => b.id.compareTo(a.id));
    return qualities;
  }

  // Get common video qualities across all analyzed parts
  Set<String> _getCommonVideoQualities() {
    if (_currentTab.analyzedParts.isEmpty) return {};
    
    var commonQualities = _currentTab.analyzedParts.values.first.videos
        .map((v) => v.quality)
        .toSet();
    
    for (final detail in _currentTab.analyzedParts.values.skip(1)) {
      final qualities = detail.videos.map((v) => v.quality).toSet();
      commonQualities = commonQualities.intersection(qualities);
    }
    
    return commonQualities;
  }

  // Apply common quality to all parts
  void _applyQualityToAll(
    Map<int, int> videoQualities,
    Map<int, int> audioQualities,
    StateSetter setDialogState,
  ) {
    final commonQualities = _getCommonVideoQualities();
    if (commonQualities.isEmpty) return;
    
    // Use the highest common quality
    // Assuming higher ID means better quality
    final bestQuality = _currentTab.analyzedParts.values.first.videos
        .where((v) => commonQualities.contains(v.quality))
        .reduce((a, b) => a.id > b.id ? a : b);
    
    setDialogState(() {
      for (final index in _currentTab.analyzedParts.keys) {
        final detail = _currentTab.analyzedParts[index]!;
        
        // Try to apply the same quality, or use best available
        final targetQuality = detail.videos.firstWhere(
          (v) => v.quality == bestQuality.quality,
          orElse: () => detail.videos.reduce((a, b) => a.id > b.id ? a : b),
        );
        
        videoQualities[index] = targetQuality.id;
        
        // For audio, use highest quality available
        if (detail.audios.isNotEmpty) {
          audioQualities[index] = detail.audios
              .reduce((a, b) => a.id > b.id ? a : b)
              .id;
        }
      }
    });
  }

  // Start download with selected qualities
  Future<void> _startDownloadWithQualities(
    Map<int, int> videoQualities,
    Map<int, int> audioQualities,
  ) async {
    final downloadService = Provider.of<DownloadService>(context, listen: false);
    
    int successCount = 0;
    int failCount = 0;
    
    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('准备下载'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('正在准备 ${videoQualities.length} 个视频...'),
          ],
        ),
      ),
    );
    
    try {
      for (final entry in videoQualities.entries) {
        final index = entry.key;
        final videoId = entry.value;
        final audioId = audioQualities[index];
        
        if (!_currentTab.analyzedParts.containsKey(index)) continue;
        
        final detail = _currentTab.analyzedParts[index]!;
        
        try {
          // Find selected video and audio streams
          final video = detail.videos.firstWhere(
            (v) => v.id == videoId,
            orElse: () => detail.videos.first,
          );
          
          final audio = detail.audios.firstWhere(
            (a) => a.id == audioId,
            orElse: () => detail.audios.first,
          );
          
          await downloadService.downloadVideo(
            detail,
            video,
            audio,
            collectionId: null,
            collectionName: null,
            partIndex: index + 1,
            totalParts: videoQualities.length,
          );
          
          successCount++;
        } catch (e) {
          debugPrint('Failed to download part ${index + 1}: $e');
          failCount++;
        }
      }
      
      // Close loading dialog
      if (mounted) {
        Navigator.of(context).pop();
        
        // Show result
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已添加 $successCount 个下载任务${failCount > 0 ? "，$failCount 个失败" : ""}'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('下载准备失败: $e')),
        );
      }
    }
  }

  Future<void> _analyzeVideo() async {
    if (_currentTab.urlController.text.trim().isEmpty) {
      setState(() {
        _currentTab.errorMessage = '请输入B站链接';
      });
      return;
    }

    setState(() {
      _currentTab.isLoading = true;
      _currentTab.errorMessage = null;
      _currentTab.videoInfo = null;
      _currentTab.videoDetails = [];
      _currentTab.analyzedParts.clear();
      _currentTab.selectedParts.clear();
      _currentTab.collectionInfo = null;
      _currentTab.selectedVideos = {};
      _currentTab.contentType = null;
      _currentTab.isAnalyzing = false;
      _currentTab.analysisProgress = 0.0;
      _currentTab.totalToAnalyze = 0;
      _currentTab.analyzedCount = 0;
    });

    try {
      final url = _currentTab.urlController.text.trim();
      
      // Try to parse as collection/series first
      final parsed = _currentTab.collectionService.parseUrl(url);
      
      if (parsed.type == 'collection' || parsed.type == 'series') {
        // Handle collection/series - get basic info only
        final collection = await _currentTab.collectionService.getInfoFromParsedUrl(parsed);
        
        setState(() {
          _currentTab.collectionInfo = collection;
          _currentTab.contentType = parsed.type;
          _currentTab.isLoading = false;
          _currentTab.showResults = true;
          // Select all videos by default
          _currentTab.selectedVideos = Set.from(List.generate(collection.videos.length, (i) => i));
        });
      } else {
        // Handle single video - get basic info and parts list only
        final videoInfo = await _currentTab.analyzeService.getVideoInfo(url);

        setState(() {
          _currentTab.videoInfo = videoInfo;
          _currentTab.contentType = 'video';
          _currentTab.isLoading = false;
          _currentTab.showResults = true;
          // Auto-select all parts initially
          _currentTab.selectedParts = Set.from(List.generate(videoInfo.parts.length, (i) => i));
        });
      }
    } catch (e) {
      setState(() {
        _currentTab.errorMessage = e.toString();
        _currentTab.isLoading = false;
        _currentTab.showResults = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: _tabs.length > 1 ? kToolbarHeight : 0,
        bottom: _tabs.length > 1
            ? TabBar(
                controller: _tabController,
                isScrollable: true,
                labelColor: Colors.white,
                unselectedLabelColor: Colors.white70,
                indicatorColor: Colors.white,
                tabs: _tabs.asMap().entries.map((entry) {
                  final index = entry.key;
                  final tabData = entry.value;
                  return Tab(
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Flexible(
                          child: Text(
                            tabData.tabTitle,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (_tabs.length > 1)
                          IconButton(
                            icon: const Icon(Icons.close, size: 16),
                            padding: EdgeInsets.zero,
                            constraints: const BoxConstraints(),
                            onPressed: () => _closeTab(index),
                          ),
                      ],
                    ),
                  );
                }).toList(),
                onTap: _onTabChanged,
              )
            : null,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _addNewTab,
        tooltip: '新建标签页',
        child: const Icon(Icons.add),
      ),
      body: _tabs.isEmpty
          ? const Center(child: Text('没有标签页'))
          : IndexedStack(
              index: _currentTabIndex,
              children: _tabs.map((tab) => _buildTabContent(tab)).toList(),
            ),
    );
  }

  Widget _buildTabContent(_AnalyzeTabData tab) {
    // 初始状态：只有居中的输入框
    if (!tab.showResults && !tab.isLoading && tab.errorMessage == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 32.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text('输入B站视频链接', style: TextStyle(fontSize: 18)),
              const SizedBox(height: 16),
              TextField(
                controller: tab.urlController,
                decoration: const InputDecoration(
                  hintText: 'B站链接、BV号或AV号',
                  border: OutlineInputBorder(),
                  contentPadding: EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 12,
                  ),
                ),
                onSubmitted: (_) => _analyzeVideo(),
              ),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _analyzeVideo,
                style: ElevatedButton.styleFrom(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 12,
                  ),
                ),
                child: const Text('解析视频'),
              ),
            ],
          ),
        ),
      );
    }

    // 加载状态
    if (tab.isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    // 错误状态
    if (tab.errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline, color: Colors.red.shade400, size: 64),
              const SizedBox(height: 16),
              Text(
                '解析失败',
                style: TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                  color: Colors.red.shade600,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                tab.errorMessage!,
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.red.shade600),
              ),
              const SizedBox(height: 24),
              ElevatedButton(
                onPressed: () {
                  setState(() {
                    tab.errorMessage = null;
                    tab.showResults = false;
                  });
                },
                child: const Text('重新输入'),
              ),
            ],
          ),
        ),
      );
    }

    // 结果状态：显示视频列表或合集
    if (tab.contentType == 'video' && tab.videoInfo != null) {
      return _buildVideoResult(tab);
    } else if ((tab.contentType == 'collection' || tab.contentType == 'series') && tab.collectionInfo != null) {
      return _buildCollectionResult(tab);
    }
    
    return const Center(child: Text('未知内容类型'));
  }
  
  Widget _buildVideoResult(_AnalyzeTabData tab) {
    return Column(
      children: [
        // 视频信息头部
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          color: Colors.grey.shade100,
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(4),
                child: Image.network(
                  tab.videoInfo!.coverUrl,
                  width: 100,
                  height: 75,
                  fit: BoxFit.cover,
                  errorBuilder: (context, error, stackTrace) {
                    return Container(
                      width: 100,
                      height: 75,
                      color: Colors.grey.shade300,
                      child: const Icon(Icons.image),
                    );
                  },
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      tab.videoInfo!.title,
                      style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'BV号: ${tab.videoInfo!.bvid}',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                    Text(
                      '共 ${tab.videoInfo!.parts.length} 个分P',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade600,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),

        // 分析进度条（如果正在分析）
        if (tab.isAnalyzing)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: Colors.blue.shade50,
            child: Column(
              children: [
                Row(
                  children: [
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                    const SizedBox(width: 8),
                    Text('正在分析选中分P: $_progressText'),
                  ],
                ),
                const SizedBox(height: 8),
                LinearProgressIndicator(value: tab.analysisProgress),
              ],
            ),
          ),

        // 选择控制按钮
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(
            color: Colors.white,
            border: Border(bottom: BorderSide(color: Colors.grey.shade300)),
          ),
          child: Column(
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      '已选择 ${tab.selectedParts.length}/${tab.videoInfo!.parts.length} 个分P',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                  TextButton(
                    onPressed: _selectAllParts,
                    child: const Text('全选'),
                  ),
                  TextButton(
                    onPressed: _deselectAllParts,
                    child: const Text('全不选'),
                  ),
                  TextButton(
                    onPressed: _reverseSelection,
                    child: const Text('反选'),
                  ),
                ],
              ),
              // Reanalyze option
              if (tab.analyzedParts.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Row(
                    children: [
                      Icon(
                        Icons.refresh,
                        size: 18,
                        color: Colors.grey.shade600,
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                          '重新分析已成功的分P',
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade700,
                          ),
                        ),
                      ),
                        Switch(
                        value: tab.reanalyzeSuccessful,
                        onChanged: (value) {
                          setState(() {
                            tab.reanalyzeSuccessful = value;
                          });
                        },
                        activeThumbColor: Colors.blue,
                      ),
                    ],
                  ),
                ),
            ],
          ),
        ),

        // 视频分P列表
        Expanded(
          child: ListView.builder(
            itemCount: tab.videoInfo!.parts.length,
            itemBuilder: (context, index) {
              final part = tab.videoInfo!.parts[index];
              final isSelected = tab.selectedParts.contains(index);
              final isAnalyzed = tab.analyzedParts.containsKey(index);
              final detail = tab.analyzedParts[index];
              
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: ListTile(
                  contentPadding: const EdgeInsets.all(8),
                  leading: ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Container(
                      width: 80,
                      height: 50,
                      color: Colors.grey.shade200,
                      child: isAnalyzed && detail != null && detail.picUrl.isNotEmpty
                          ? Image.network(
                              detail.picUrl,
                              fit: BoxFit.cover,
                              loadingBuilder: (context, child, loadingProgress) {
                                if (loadingProgress == null) return child;
                                return Center(
                                  child: CircularProgressIndicator(
                                    value: loadingProgress.expectedTotalBytes != null
                                        ? loadingProgress.cumulativeBytesLoaded /
                                            loadingProgress.expectedTotalBytes!
                                        : null,
                                    strokeWidth: 2,
                                  ),
                                );
                              },
                              errorBuilder: (context, error, stackTrace) {
                                return Icon(Icons.broken_image, color: Colors.grey.shade400);
                              },
                            )
                          : Icon(Icons.video_library, color: Colors.grey.shade400),
                    ),
                  ),
                  title: Text(
                    'P${index + 1}: ${part.title}',
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontWeight: FontWeight.w500),
                  ),
                  subtitle: Row(
                    children: [
                      Text('时长: ${_formatDuration(part.duration)}'),
                      if (isAnalyzed)
                        Padding(
                          padding: const EdgeInsets.only(left: 8),
                          child: Icon(
                            Icons.check_circle,
                            size: 16,
                            color: Colors.green,
                          ),
                        ),
                    ],
                  ),
                  trailing: Checkbox(
                    value: isSelected,
                    onChanged: (value) {
                      setState(() {
                        if (value == true) {
                          tab.selectedParts.add(index);
                        } else {
                          tab.selectedParts.remove(index);
                        }
                      });
                    },
                  ),
                ),
              );
            },
          ),
        ),

        // 底部操作按钮
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.1),
                blurRadius: 4,
                offset: const Offset(0, -2),
              ),
            ],
          ),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: tab.selectedParts.isEmpty || tab.isAnalyzing
                      ? null
                      : _startAnalysis,
                  icon: const Icon(Icons.analytics),
                  label: Text(tab.isAnalyzing ? '分析中...' : '开始分析'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.blue,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _canDownload ? _showDownloadDialog : null,
                  icon: const Icon(Icons.download),
                  label: const Text('下载'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _canDownload ? Colors.green : Colors.grey,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
  
  Widget _buildCollectionResult(_AnalyzeTabData tab) {
    return Column(
      children: [
        // 合集信息头部
        Container(
          width: double.infinity,
          padding: const EdgeInsets.all(16),
          color: Colors.blue.shade50,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(4),
                    child: Image.network(
                      tab.collectionInfo!.coverUrl,
                      width: 100,
                      height: 75,
                      fit: BoxFit.cover,
                      errorBuilder: (context, error, stackTrace) {
                        return Container(
                          width: 100,
                          height: 75,
                          color: Colors.grey.shade300,
                          child: const Icon(Icons.video_library),
                        );
                      },
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(
                              tab.collectionInfo!.isArchives 
                                ? Icons.collections 
                                : Icons.playlist_play,
                              size: 20,
                              color: Colors.blue,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              tab.collectionInfo!.isArchives ? '合集' : '系列',
                              style: TextStyle(
                                fontSize: 12,
                                color: Colors.blue.shade700,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 4),
                        Text(
                          tab.collectionInfo!.name,
                          style: const TextStyle(
                            fontSize: 16,
                            fontWeight: FontWeight.bold,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '共 ${tab.collectionInfo!.totalVideos} 个视频',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (tab.collectionInfo!.description.isNotEmpty) ...[
                const SizedBox(height: 8),
                Text(
                  tab.collectionInfo!.description,
                  style: TextStyle(
                    fontSize: 12,
                    color: Colors.grey.shade700,
                  ),
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
              const SizedBox(height: 8),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    '已选择 ${tab.selectedVideos.length}/${tab.collectionInfo!.videos.length}',
                    style: const TextStyle(fontSize: 12),
                  ),
                  Row(
                    children: [
                      TextButton(
                        onPressed: () {
                          setState(() {
                            if (tab.selectedVideos.length == tab.collectionInfo!.videos.length) {
                              tab.selectedVideos.clear();
                            } else {
                              tab.selectedVideos = Set.from(
                                List.generate(tab.collectionInfo!.videos.length, (i) => i)
                              );
                            }
                          });
                        },
                        child: Text(
                          tab.selectedVideos.length == tab.collectionInfo!.videos.length
                            ? '取消全选'
                            : '全选',
                        ),
                      ),
                      ElevatedButton.icon(
                        onPressed: tab.selectedVideos.isEmpty 
                          ? null 
                          : _downloadSelectedVideos,
                        icon: const Icon(Icons.download, size: 18),
                        label: const Text('下载选中'),
                      ),
                    ],
                  ),
                ],
              ),
            ],
          ),
        ),

        // 视频列表
        Expanded(
          child: ListView.builder(
            itemCount: tab.collectionInfo!.videos.length,
            itemBuilder: (context, index) {
              final video = tab.collectionInfo!.videos[index];
              final isSelected = tab.selectedVideos.contains(index);
              
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: CheckboxListTile(
                  value: isSelected,
                  onChanged: (value) {
                    setState(() {
                      if (value == true) {
                        tab.selectedVideos.add(index);
                      } else {
                        tab.selectedVideos.remove(index);
                      }
                    });
                  },
                  title: Text(
                    video.title,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                  subtitle: Text(
                    'P${video.page} · ${video.formattedDuration}',
                  ),
                  secondary: CircleAvatar(
                    backgroundImage: NetworkImage(video.coverUrl),
                    onBackgroundImageError: (_, _) {},
                    child: video.coverUrl.isEmpty ? const Icon(Icons.videocam) : null,
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  String _formatDuration(int seconds) {
    final hours = seconds ~/ 3600;
    final minutes = (seconds % 3600) ~/ 60;
    final secs = seconds % 60;

    if (hours > 0) {
      return '$hours:$minutes:${secs.toString().padLeft(2, '0')}';
    } else {
      return '$minutes:${secs.toString().padLeft(2, '0')}';
    }
  }

  void _showVideoOptions(VideoDetail detail) {
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                detail.name,
                style: const TextStyle(
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),

              // 视频质量选项
              if (detail.videos.isNotEmpty) ...[
                const Text(
                  '视频质量',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                ...detail.videos.map(
                  (video) => RadioListTile(
                    title: Text('${video.quality} (${video.codec})'),
                    subtitle: Text(
                      '带宽: ${(video.bandwidth / 1000).toStringAsFixed(0)}kb/s',
                    ),
                    value: video.id,
                    groupValue: detail.videos.first.id,
                    onChanged: (value) {
                      Navigator.pop(context);
                      _selectVideoQuality(detail, video);
                    },
                  ),
                ),
                const SizedBox(height: 16),
              ],

              // 音频质量选项
              if (detail.audios.isNotEmpty) ...[
                const Text(
                  '音频质量',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w500),
                ),
                const SizedBox(height: 8),
                ...detail.audios.map(
                  (audio) => RadioListTile(
                    title: Text(audio.quality),
                    subtitle: Text(
                      '带宽: ${(audio.bandwidth / 1000).toStringAsFixed(0)}kb/s',
                    ),
                    value: audio.id,
                    groupValue: detail.audios.first.id,
                    onChanged: (value) {
                      Navigator.pop(context);
                      _selectAudioQuality(detail, audio);
                    },
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  void _selectVideoQuality(VideoDetail detail, VideoStream video) {
    // Show audio selection dialog
    showModalBottomSheet(
      context: context,
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '选择音频质量',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
              ),
              const SizedBox(height: 16),
              ...detail.audios.map(
                (audio) => ListTile(
                  title: Text(audio.quality),
                  subtitle: Text(
                    '带宽: ${(audio.bandwidth / 1000).toStringAsFixed(0)}kb/s',
                  ),
                  onTap: () {
                    Navigator.pop(context);
                    _startDownload(detail, video, audio);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _selectAudioQuality(VideoDetail detail, AudioStream audio) {
    // This won't be called directly anymore
  }
  
  void _startDownload(VideoDetail detail, VideoStream video, AudioStream audio) {
    final downloadService = Provider.of<DownloadService>(context, listen: false);
    downloadService.downloadVideo(detail, video, audio);
    
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('开始下载...')),
    );
  }
  
  void _downloadSelectedVideos() async {
    if (_currentTab.collectionInfo == null || _currentTab.selectedVideos.isEmpty) return;
    
    final downloadService = Provider.of<DownloadService>(context, listen: false);
    
    // Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => AlertDialog(
        title: const Text('准备下载'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 16),
            Text('正在准备 ${_currentTab.selectedVideos.length} 个视频...'),
          ],
        ),
      ),
    );
    
    try {
      int successCount = 0;
      int failCount = 0;
      
      // Download each selected video
      for (final index in _currentTab.selectedVideos.toList()) {
        if (index >= _currentTab.collectionInfo!.videos.length) continue;
        
        final video = _currentTab.collectionInfo!.videos[index];
        
        try {
          // Get video details for this specific video
          // First, we need to get the CID for this video
          final videoInfo = await _currentTab.analyzeService.getVideoInfo(video.bvid);
          
          if (videoInfo.parts.isNotEmpty) {
            // Use the first part's CID (for collection videos, usually only one part)
            final cid = videoInfo.parts.first.cid;
            
            final detail = await _currentTab.analyzeService.getVideoDetail(
              video.aid,
              cid,
              fnval: 16,
            );
            
            // Select first available video and audio quality
            if (detail.videos.isNotEmpty && detail.audios.isNotEmpty) {
              await downloadService.downloadVideo(
                detail,
                detail.videos.first,
                detail.audios.first,
                collectionId: _currentTab.collectionInfo!.id,
                collectionName: _currentTab.collectionInfo!.name,
                partIndex: index + 1,
                totalParts: _currentTab.selectedVideos.length,
              );
              successCount++;
            } else {
              failCount++;
            }
          } else {
            failCount++;
          }
        } catch (e) {
          debugPrint('Failed to prepare video ${video.title}: $e');
          failCount++;
        }
      }
      
      // Close loading dialog
      if (mounted) {
        Navigator.of(context).pop();
        
        // Show result
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('已添加 $successCount 个下载任务${failCount > 0 ? "，$failCount 个失败" : ""}'),
            duration: const Duration(seconds: 3),
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        Navigator.of(context).pop();
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('下载准备失败: $e')),
        );
      }
    }
  }
}

// Tab data class to hold state for each analyze tab
class _AnalyzeTabData {
  final TextEditingController urlController = TextEditingController();
  final AnalyzeService analyzeService = AnalyzeService();
  final CollectionService collectionService = CollectionService();
  
  bool isLoading = false;
  bool showResults = false;
  
  // For single video
  VideoInfo? videoInfo;
  List<VideoDetail> videoDetails = []; // All analyzed details
  Set<int> selectedParts = {}; // Selected part indices
  final Map<int, VideoDetail> analyzedParts = {}; // Index -> VideoDetail for analyzed parts
  
  // Analysis progress tracking
  bool isAnalyzing = false;
  double analysisProgress = 0.0;
  int totalToAnalyze = 0;
  int analyzedCount = 0;
  bool reanalyzeSuccessful = false; // Whether to reanalyze already successful parts
  
  // For collection/series
  CollectionInfo? collectionInfo;
  Set<int> selectedVideos = {}; // Selected video indices in collection
  
  String? errorMessage;
  String? contentType; // 'video', 'collection', or 'series'
  
  // Get tab title based on content
  String get tabTitle {
    if (contentType == 'video' && videoInfo != null) {
      return videoInfo!.title.length > 10 
          ? '${videoInfo!.title.substring(0, 10)}...' 
          : videoInfo!.title;
    } else if ((contentType == 'collection' || contentType == 'series') && collectionInfo != null) {
      return collectionInfo!.name.length > 10 
          ? '${collectionInfo!.name.substring(0, 10)}...' 
          : collectionInfo!.name;
    } else if (urlController.text.isNotEmpty) {
      final text = urlController.text.trim();
      return text.length > 15 ? '${text.substring(0, 15)}...' : text;
    }
    return '新标签页';
  }
  
  void reset() {
    urlController.clear();
    isLoading = false;
    showResults = false;
    videoInfo = null;
    videoDetails = [];
    analyzedParts.clear();
    selectedParts.clear();
    isAnalyzing = false;
    analysisProgress = 0.0;
    totalToAnalyze = 0;
    analyzedCount = 0;
    reanalyzeSuccessful = false;
    collectionInfo = null;
    selectedVideos = {};
    errorMessage = null;
    contentType = null;
  }
  
  void dispose() {
    urlController.dispose();
  }
}
