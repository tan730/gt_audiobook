import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import '../models/chapter.dart';
import '../services/storage_service.dart';
import '../services/download_service.dart';
import '../services/api_service.dart';

/// 下载管理页 - 查看/删除已下载的章节，点击可播放
class DownloadScreen extends StatefulWidget {
  final StorageService storageService;
  final DownloadService downloadService;
  final ApiService apiService;
  final Future<void> Function(String bookName, List<Chapter> chapters, int chapterIndex)? onPlayChapter;

  const DownloadScreen({
    super.key,
    required this.storageService,
    required this.downloadService,
    required this.apiService,
    this.onPlayChapter,
  });

  @override
  State<DownloadScreen> createState() => _DownloadScreenState();
}

class _DownloadScreenState extends State<DownloadScreen> {
  Map<String, List<_DownloadEntry>> _books = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadDownloads();
  }

  Future<void> _loadDownloads() async {
    setState(() => _loading = true);
    final bookNames = widget.storageService.getBooksWithDownloads();
    final result = <String, List<_DownloadEntry>>{};

    for (final name in bookNames) {
      final downloads = widget.storageService.getDownloads(name);
      final entries = <_DownloadEntry>[];
      for (final fileName in downloads) {
        final path = await widget.downloadService.getLocalPath(name, fileName);
        final file = File(path);
        final exists = await file.exists();
        final size = exists ? await file.length() : 0;
        entries.add(_DownloadEntry(
          fileName: fileName,
          size: size,
          exists: exists,
        ));
      }
      if (entries.isNotEmpty) {
        result[name] = entries;
      }
    }

    if (mounted) {
      setState(() {
        _books = result;
        _loading = false;
      });
    }
  }

  Future<void> _deleteChapter(String bookName, String fileName) async {
    await widget.downloadService.deleteChapter(bookName, fileName);
    _loadDownloads();
  }

  Future<void> _deleteAll() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: const Text('确定要删除所有下载内容吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );

    if (confirm == true) {
      for (final name in _books.keys) {
        await widget.downloadService.deleteBookDownloads(name);
      }
      _loadDownloads();
    }
  }

  Future<void> _playChapter(String bookName, String fileName) async {
    if (widget.onPlayChapter == null) return;
    try {
      List<Chapter> chapters;
      try {
        chapters = await widget.apiService.fetchChapters(bookName);
      } catch (_) {
        // 离线：缓存→下载记录
        final cached = widget.storageService.getCachedChapters(bookName);
        if (cached != null) {
          chapters = (jsonDecode(cached) as List<dynamic>)
              .map((e) => Chapter.fromJson(e as Map<String, dynamic>))
              .toList();
        } else {
          final dlData = widget.storageService.getDownloadedChaptersData(bookName);
          if (dlData.isEmpty) rethrow;
          chapters = dlData.map((e) => Chapter(
            file: '$bookName/${e['file']}',
            name: (e['file'] as String).replaceAll(RegExp(r'\.[^.]+$'), ''),
            sortKey: e['sortKey'] as int,
            downloaded: true,
          )).toList()..sort((a, b) => a.sortKey.compareTo(b.sortKey));
        }
      }
      final index = chapters.indexWhere((c) => c.fileName == fileName);
      if (index >= 0) {
        await widget.onPlayChapter!(bookName, chapters, index);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('无法播放: $e')),
        );
      }
    }
  }

  String _formatSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_books.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.download_outlined, size: 64,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            const Text('还没有下载内容'),
            const SizedBox(height: 8),
            Text('在播放页点击章节旁的下载按钮',
                style: Theme.of(context).textTheme.bodySmall),
          ],
        ),
      );
    }

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text('共 ${_totalCount()} 个文件 · ${_totalSize()}',
                  style: Theme.of(context).textTheme.bodySmall),
              TextButton.icon(
                onPressed: _deleteAll,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('全部删除'),
              ),
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListView.builder(
            itemCount: _books.length,
            itemBuilder: (context, index) {
              final bookName = _books.keys.elementAt(index);
              final entries = _books[bookName]!;
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: ExpansionTile(
                  leading: const Icon(Icons.folder_open),
                  title: Text(bookName,
                      style: const TextStyle(fontWeight: FontWeight.w500)),
                  subtitle: Text('${entries.length} 个文件 · 点击可播放'),
                  children: entries.map((entry) {
                    return ListTile(
                      dense: true,
                      leading: entry.exists
                          ? const Icon(Icons.play_circle_outline,
                              color: Colors.green, size: 20)
                          : const Icon(Icons.error,
                              color: Colors.red, size: 20),
                      title: Text(entry.fileName,
                          style: const TextStyle(fontSize: 14)),
                      subtitle: Text(_formatSize(entry.size),
                          style: Theme.of(context).textTheme.bodySmall),
                      trailing: IconButton(
                        icon: const Icon(Icons.delete_outline, size: 20),
                        onPressed: () => _deleteChapter(bookName, entry.fileName),
                      ),
                      onTap: () => _playChapter(bookName, entry.fileName),
                    );
                  }).toList(),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  int _totalCount() {
    return _books.values.fold(0, (sum, entries) => sum + entries.length);
  }

  String _totalSize() {
    final total = _books.values.fold<int>(
        0, (sum, entries) => sum + entries.fold<int>(0, (s, e) => s + e.size));
    return _formatSize(total);
  }
}

class _DownloadEntry {
  final String fileName;
  final int size;
  final bool exists;

  const _DownloadEntry({
    required this.fileName,
    required this.size,
    required this.exists,
  });
}
