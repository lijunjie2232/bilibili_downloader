import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:bilibili_downloader/models/download_task.dart';
import 'package:bilibili_downloader/services/download_service.dart';

class DownloadManagerPage extends StatelessWidget {
  const DownloadManagerPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        toolbarHeight: 0,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              // Refresh downloads
            },
          ),
        ],
      ),
      body: Consumer<DownloadService>(
        builder: (context, downloadService, child) {
          final tasks = downloadService.tasks;
          
          if (tasks.isEmpty) {
            return const Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.download_outlined, size: 64, color: Colors.grey),
                  SizedBox(height: 16),
                  Text('暂无下载任务', style: TextStyle(fontSize: 18)),
                  SizedBox(height: 8),
                  Text('前往解析页面开始下载视频', style: TextStyle(color: Colors.grey)),
                ],
              ),
            );
          }
          
          return ListView.builder(
            itemCount: tasks.length,
            itemBuilder: (context, index) {
              final task = tasks[index];
              return DownloadTaskCard(task: task);
            },
          );
        },
      ),
    );
  }
}

class DownloadTaskCard extends StatelessWidget {
  final DownloadTask task;
  
  const DownloadTaskCard({super.key, required this.task});
  
  @override
  Widget build(BuildContext context) {
    final downloadService = Provider.of<DownloadService>(context, listen: false);
    
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        task.title,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (task.isPartOfCollection) ...[
                        const SizedBox(height: 2),
                        Text(
                          '${task.collectionName} - P${task.partIndex}/${task.totalParts}',
                          style: TextStyle(
                            fontSize: 12,
                            color: Colors.blue.shade700,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                      const SizedBox(height: 4),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            _getStatusText(task.status),
                            style: TextStyle(
                              color: _getStatusColor(task.status),
                              fontSize: 14,
                            ),
                          ),
                          if (task.errorMessage != null && task.errorMessage!.isNotEmpty)
                            Text(
                              task.errorMessage!,
                              style: TextStyle(
                                fontSize: 11,
                                color: Colors.red.shade600,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          if (task.status == DownloadStatus.downloading)
                            Text(
                              '${(task.progress * 100).toStringAsFixed(1)}%',
                              style: const TextStyle(
                                fontSize: 12,
                                color: Colors.grey,
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
                _buildActionButtons(context, downloadService, task),
              ],
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(
              value: task.progress,
              backgroundColor: Colors.grey[300],
              valueColor: AlwaysStoppedAnimation<Color>(
                _getProgressColor(task.status),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  '${(task.progress * 100).toStringAsFixed(1)}%',
                  style: const TextStyle(fontSize: 12),
                ),
                Text(
                  _formatDateTime(task.createdAt),
                  style: const TextStyle(fontSize: 12, color: Colors.grey),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
  
  Widget _buildActionButtons(BuildContext context, DownloadService service, DownloadTask task) {
    switch (task.status) {
      case DownloadStatus.pending:
      case DownloadStatus.paused:
        return IconButton(
          icon: const Icon(Icons.play_arrow),
          onPressed: () => service.resumeDownload(task.id),
        );
      case DownloadStatus.downloading:
        return IconButton(
          icon: const Icon(Icons.pause),
          onPressed: () => service.pauseDownload(task.id),
        );
      case DownloadStatus.completed:
        return IconButton(
          icon: const Icon(Icons.check, color: Colors.green),
          onPressed: () {
            // Open file or show file location
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('文件已下载完成')),
            );
          },
        );
      case DownloadStatus.failed:
      case DownloadStatus.cancelled:
        return IconButton(
          icon: const Icon(Icons.refresh),
          onPressed: () => service.resumeDownload(task.id),
        );
    }
  }
  
  String _getStatusText(DownloadStatus status) {
    switch (status) {
      case DownloadStatus.pending:
        return '等待中';
      case DownloadStatus.downloading:
        return '下载中';
      case DownloadStatus.paused:
        return '已暂停';
      case DownloadStatus.completed:
        return '已完成';
      case DownloadStatus.failed:
        return '下载失败';
      case DownloadStatus.cancelled:
        return '已取消';
    }
  }
  
  Color _getStatusColor(DownloadStatus status) {
    switch (status) {
      case DownloadStatus.pending:
        return Colors.orange;
      case DownloadStatus.downloading:
        return Colors.blue;
      case DownloadStatus.paused:
        return Colors.grey;
      case DownloadStatus.completed:
        return Colors.green;
      case DownloadStatus.failed:
        return Colors.red;
      case DownloadStatus.cancelled:
        return Colors.grey;
    }
  }
  
  Color _getProgressColor(DownloadStatus status) {
    switch (status) {
      case DownloadStatus.completed:
        return Colors.green;
      case DownloadStatus.failed:
        return Colors.red;
      default:
        return Colors.blue;
    }
  }
  
  String _formatDateTime(DateTime dateTime) {
    return '${dateTime.year}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}';
  }
}
