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

class _DownloadScreenState extends State<DownloadScreen> with SingleTickerProviderStateMixin {
  Map<String, List<_DownloadEntry>> _books = {};
  bool _loading = true;

  // 多选删除模式
  bool _selectionMode = false;
  final Set<String> _selectedFiles = {}; // "bookName/fileName"

  // 闪烁动画（下载中橙色圆点用）
  late AnimationController _pulseCtrl;
  // 原始回调，dispose 时还原
  void Function(String, String, double)? _origOnProgress;
  void Function()? _origOnQueueChanged;

  @override
  void initState() {
    super.initState();
    _pulseCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    )..repeat(reverse: true);

    // 链式订阅下载进度（不覆盖播放页的回调）
    _origOnProgress = widget.downloadService.onProgress;
    widget.downloadService.onProgress = (bookName, fileName, progress) {
      if (mounted) _onDownloadProgress(bookName, fileName, progress);
      _origOnProgress?.call(bookName, fileName, progress);
    };
    _origOnQueueChanged = widget.downloadService.onQueueChanged;
    widget.downloadService.onQueueChanged = () {
      // 队列变化时刷新一次（包括下载完成时清空 downloadingFiles）
      if (mounted) _loadDownloads();
      _origOnQueueChanged?.call();
    };

    _loadDownloads();
  }

  @override
  void dispose() {
    // 还原回调，避免泄漏（player_screen 退出后还指向 download_screen）
    widget.downloadService.onProgress = _origOnProgress;
    widget.downloadService.onQueueChanged = _origOnQueueChanged;
    _pulseCtrl.dispose();
    super.dispose();
  }

  void _onDownloadProgress(String bookName, String fileName, double progress) {
    final entries = _books[bookName];
    if (mounted && entries != null) {
      final idx = entries.indexWhere((e) => e.fileName == fileName);
      if (idx >= 0) {
        // 更新 entry 的 progress + state 字段
        final old = entries[idx];
        entries[idx] = _DownloadEntry(
          fileName: old.fileName,
          size: old.size,
          exists: old.exists,
          progress: progress,
          state: 'downloading',
        );
      }
    }
    // 下载完成时重新加载列表（新下载的文件可能不在 _books 里）
    if (progress >= 1.0) {
      _loadDownloads();
    } else {
      setState(() {});
    }
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
      _selectedFiles.clear();
      _selectionMode = false;
      _loadDownloads();
    }
  }

  /// 删除选中的章节
  Future<void> _deleteSelected() async {
    if (_selectedFiles.isEmpty) return;

    final count = _selectedFiles.length;
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('确认删除'),
        content: Text('确定要删除选中的 $count 个文件吗？'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false), child: const Text('取消')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true), child: const Text('删除')),
        ],
      ),
    );

    if (confirm == true) {
      // 按书分组批量删除
      final byBook = <String, List<String>>{};
      for (final key in _selectedFiles) {
        final parts = key.split('/');
        final bookName = parts[0];
        final fileName = parts.sublist(1).join('/');
        byBook.putIfAbsent(bookName, () => []).add(fileName);
      }
      for (final entry in byBook.entries) {
        await widget.downloadService.deleteChapters(entry.key, entry.value);
      }
      _selectedFiles.clear();
      _selectionMode = false;
      _loadDownloads();
    }
  }

  void _toggleSelect(String key) {
    setState(() {
      if (_selectedFiles.contains(key)) {
        _selectedFiles.remove(key);
        if (_selectedFiles.isEmpty) {
          _selectionMode = false;
        }
      } else {
        _selectedFiles.add(key);
      }
    });
  }

  void _enterSelectionMode() {
    setState(() {
      _selectionMode = true;
      _selectedFiles.clear();
    });
  }

  void _exitSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedFiles.clear();
    });
  }

  void _selectAll() {
    setState(() {
      _selectedFiles.clear();
      for (final bookEntry in _books.entries) {
        for (final entry in bookEntry.value) {
          if (entry.exists) {
            _selectedFiles.add('${bookEntry.key}/${entry.fileName}');
          }
        }
      }
    });
  }

  /// 获取选中文件的选中键（bookName/fileName）
  String _selectionKey(String bookName, String fileName) => '$bookName/$fileName';

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
            name: (e['file'] as String).replaceAll(RegExp(r'\\.[^.]+$'), ''),
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
        // 顶部操作栏
        _buildTopBar(),
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
                  final selKey = _selectionKey(bookName, entry.fileName);
                  final isDownloading = entry.state == 'downloading';
                  final isQueued = widget.downloadService.queuedFiles.contains(entry.fileName);
                  return Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      ListTile(
                        dense: true,
                        leading: _selectionMode
                            ? Checkbox(
                                value: _selectedFiles.contains(selKey),
                                onChanged: (_) => _toggleSelect(selKey),
                              )
                            : (entry.exists
                                ? const Icon(Icons.play_circle_outline,
                                    color: Colors.green, size: 20)
                                : const Icon(Icons.error,
                                    color: Colors.red, size: 20)),
                        title: Text(entry.fileName,
                            style: const TextStyle(fontSize: 14)),
                        subtitle: Text(_formatSize(entry.size),
                            style: Theme.of(context).textTheme.bodySmall),
                        // 行尾改为状态图标（不再放删除按钮，删除统一走顶部多选）
                        trailing: _selectionMode
                            ? null
                            : SizedBox(
                                width: 32,
                                height: 32,
                                child: Center(
                                  child: isDownloading
                                      ? _buildDownloadingDot()
                                      : isQueued
                                          ? const Icon(Icons.hourglass_empty,
                                              size: 18, color: Colors.blueGrey)
                                          : (!entry.exists
                                              ? const Icon(Icons.error_outline,
                                                  size: 18, color: Colors.red)
                                              : const Icon(Icons.check_circle_outline,
                                                  size: 18, color: Colors.green)),
                                ),
                              ),
                        onTap: () {
                          if (_selectionMode) {
                            _toggleSelect(selKey);
                          } else {
                            _playChapter(bookName, entry.fileName);
                          }
                        },
                      ),
                      // 下载中的条目下方加橙色细线进度条（无百分比）
                      if (isDownloading && entry.progress != null)
                        _buildProgressLine(entry.progress!),
                    ],
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

  /// 闪烁橙色圆点，跟播放页 _buildProgressIcon 一致
  Widget _buildDownloadingDot() {
    return Tooltip(
      message: '下载中',
      child: AnimatedBuilder(
        animation: _pulseCtrl,
        builder: (context, _) {
          final size = 6 + 4 * _pulseCtrl.value;
          return SizedBox(
            width: size,
            height: size,
            child: const DecoratedBox(
              decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.orange),
            ),
          );
        },
      ),
    );
  }

  /// 橙色细线进度条（无百分比）—— 给 ListTile 外面包一层 Padding 用
  Widget _buildProgressLine(double progress) {
    return Padding(
      padding: const EdgeInsets.only(left: 50, right: 16, bottom: 4),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(1),
        child: LinearProgressIndicator(
          value: progress.clamp(0.0, 1.0),
          minHeight: 2,
          backgroundColor: Colors.transparent,
          valueColor: const AlwaysStoppedAnimation<Color>(Colors.orange),
        ),
      ),
    );
  }

  Widget _buildTopBar() {
    if (_selectionMode) {
      // 多选模式下的操作栏
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        color: Theme.of(context).colorScheme.primaryContainer.withAlpha(60),
        child: Row(
          children: [
            IconButton(
              icon: const Icon(Icons.close),
              onPressed: _exitSelectionMode,
              tooltip: '退出选择',
            ),
            Text('已选 ${_selectedFiles.length} 项',
                style: Theme.of(context).textTheme.bodyMedium),
            const Spacer(),
            TextButton.icon(
              onPressed: _selectedFiles.length < _totalDownloadedCount() ? _selectAll : null,
              icon: const Icon(Icons.select_all, size: 18),
              label: const Text('全选'),
            ),
            const SizedBox(width: 4),
            FilledButton.tonalIcon(
              onPressed: _selectedFiles.isEmpty ? null : _deleteSelected,
              icon: const Icon(Icons.delete, size: 18),
              label: Text('删除 (${_selectedFiles.length})'),
            ),
          ],
        ),
      );
    }

    // 普通模式下的顶部栏
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text('共 ${_totalCount()} 个文件 · ${_totalSize()}',
              style: Theme.of(context).textTheme.bodySmall),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextButton.icon(
                onPressed: _totalDownloadedCount() > 0 ? _enterSelectionMode : null,
                icon: const Icon(Icons.checklist, size: 18),
                label: const Text('多选删除'),
              ),
              const SizedBox(width: 4),
              TextButton.icon(
                onPressed: _deleteAll,
                icon: const Icon(Icons.delete_outline, size: 18),
                label: const Text('全部删除'),
              ),
            ],
          ),
        ],
      ),
    );
  }

  /// 所有书的总文件数
  int _totalCount() {
    return _books.values.fold(0, (sum, entries) => sum + entries.length);
  }

  /// 仅已下载（存在）的文件数
  int _totalDownloadedCount() {
    return _books.values.fold<int>(
        0, (sum, entries) => sum + entries.where((e) => e.exists).length);
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
  // null = 未知/未在下载/已下载完成（无进度显示）
  // 0.0~1.0 = 当前下载进度（仅下载中条目有）
  final double? progress;
  // 状态标记：null/queued/downloading/error
  final String? state;

  const _DownloadEntry({
    required this.fileName,
    required this.size,
    required this.exists,
    this.progress,
    this.state,
  });
}
