import 'dart:convert';
import 'package:flutter/material.dart';
import '../models/book.dart';
import '../models/chapter.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';
import '../services/player_service.dart';
import '../services/download_service.dart';

/// 书库页 - 展示所有有声书
class BookListScreen extends StatefulWidget {
  final ApiService apiService;
  final StorageService storageService;
  final PlayerService playerService;
  final DownloadService downloadService;
  final void Function(
      String bookName, List<Chapter> chapters, int startIndex, int startMs)
      onPlayBook;

  const BookListScreen({
    super.key,
    required this.apiService,
    required this.storageService,
    required this.playerService,
    required this.downloadService,
    required this.onPlayBook,
  });

  @override
  State<BookListScreen> createState() => _BookListScreenState();
}

class _BookListScreenState extends State<BookListScreen> {
  List<Book>? _books;
  bool _loading = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _loadCachedBooks();
    _fetchBooks();
  }

  void _loadCachedBooks() {
    final cached = widget.storageService.getCachedBookList();
    if (cached != null && _books == null) {
      try {
        final list = (jsonDecode(cached) as List<dynamic>)
            .map((e) => Book.fromJson(e as Map<String, dynamic>))
            .toList();
        setState(() => _books = list);
      } catch (_) {}
    }
  }

  Future<void> _fetchBooks() async {
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final books = await widget.apiService.fetchBooks();
      // 缓存书单到本地
      final json = jsonEncode(books.map((b) => b.toJson()).toList());
      await widget.storageService.cacheBookList(json);
      if (mounted) {
        setState(() {
          _books = books;
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _error = '无法连接服务器\n${e.toString().substring(0, e.toString().length.clamp(0, 100))}';
          _loading = false;
        });
      }
    }
  }

  Future<void> _onBookTap(Book book) async {
    // 检查是否要恢复上次进度
    final progress = widget.storageService.getProgress(book.name);

    if (progress != null) {
      // 有历史进度，询问是否继续
      final chapterIdx = progress['chapterIndex'] as int;
      final posMs = progress['positionMs'] as int;
      final chapterLabel = '第${chapterIdx + 1}集';
      final posStr = _formatDuration(Duration(milliseconds: posMs));

      final action = await showModalBottomSheet<String>(
        context: context,
        builder: (ctx) => SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.play_arrow, color: Colors.green),
                title: const Text('继续上次播放'),
                subtitle: Text('$chapterLabel · $posStr'),
                onTap: () => Navigator.pop(ctx, 'resume'),
              ),
              ListTile(
                leading: const Icon(Icons.replay),
                title: const Text('从头开始'),
                onTap: () => Navigator.pop(ctx, 'restart'),
              ),
              ListTile(
                leading: const Icon(Icons.list),
                title: const Text('选择章节'),
                onTap: () => Navigator.pop(ctx, 'select'),
              ),
            ],
          ),
        ),
      );

      if (action == null) return;
      if (action == 'resume') {
        await _loadAndPlay(book.name, chapterIndex: chapterIdx, positionMs: posMs);
        return;
      }
      if (action == 'select') {
        await _showChapterList(book.name);
        return;
      }
      // 'restart' → continue to chapter list from beginning
    }

    // 从头播放或选择章节
    await _showChapterList(book.name);
  }

  /// 获取章节列表（优先网络→缓存→下载记录）
  Future<List<Chapter>> _fetchChaptersWithCache(String bookName) async {
    try {
      final chapters = await widget.apiService.fetchChapters(bookName);
      final json = jsonEncode(chapters.map((c) => c.toJson()).toList());
      await widget.storageService.cacheChapters(bookName, json);
      return chapters;
    } catch (_) {
      // 尝试缓存
      final cached = widget.storageService.getCachedChapters(bookName);
      if (cached != null) {
        return (jsonDecode(cached) as List<dynamic>)
            .map((e) => Chapter.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      // 最后兜底：从下载记录构建
      final dlData = widget.storageService.getDownloadedChaptersData(bookName);
      if (dlData.isNotEmpty) {
        return dlData.map((e) => Chapter(
          file: '$bookName/${e['file']}',
          name: (e['file'] as String).replaceAll(RegExp(r'\.[^.]+$'), ''),
          sortKey: e['sortKey'] as int,
          downloaded: true,
        )).toList()..sort((a, b) => a.sortKey.compareTo(b.sortKey));
      }
      rethrow;
    }
  }

  Future<void> _showChapterList(String bookName) async {
    try {
      final chapters = await _fetchChaptersWithCache(bookName);
      if (!mounted) return;

      final selectedIndex = await showModalBottomSheet<int>(
        context: context,
        isScrollControlled: true,
        builder: (ctx) => _ChapterListSheet(
          bookName: bookName,
          chapters: chapters,
          downloadService: widget.downloadService,
        ),
      );

      if (selectedIndex != null) {
        await _loadAndPlay(bookName, chapterIndex: selectedIndex);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('加载章节失败: $e')),
        );
      }
    }
  }

  Future<void> _loadAndPlay(String bookName,
      {int chapterIndex = 0, int positionMs = 0}) async {
    final chapters = await _fetchChaptersWithCache(bookName);
    widget.onPlayBook(bookName, chapters, chapterIndex, positionMs);
  }

  String _formatDuration(Duration d) {
    final h = d.inHours;
    final m = d.inMinutes.remainder(60);
    final s = d.inSeconds.remainder(60);
    if (h > 0) {
      return '$h:${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
    }
    return '${m.toString().padLeft(2, '0')}:${s.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    if (_loading && _books == null) {
      return const Center(child: CircularProgressIndicator());
    }

    if (_books == null && _error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off, size: 48,
                  color: Theme.of(context).colorScheme.error),
              const SizedBox(height: 16),
              Text(_error!, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton.icon(
                onPressed: _fetchBooks,
                icon: const Icon(Icons.refresh),
                label: const Text('重试'),
              ),
            ],
          ),
        ),
      );
    }

    if (_books == null || _books!.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.library_music_outlined, size: 64,
                color: Theme.of(context).colorScheme.onSurfaceVariant),
            const SizedBox(height: 16),
            Text('还没有有声书',
                style: Theme.of(context).textTheme.titleMedium),
            const Text('请确保服务器上已有音频文件'),
          ],
        ),
      );
    }

    return RefreshIndicator(
          onRefresh: _fetchBooks,
          child: ListView.builder(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: _books!.length,
            itemBuilder: (context, index) {
              final book = _books![index];
              return Card(
                margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: Theme.of(context).colorScheme.primaryContainer,
                    child: Text(book.name.isNotEmpty ? book.name[0] : '?',
                        style: TextStyle(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onPrimaryContainer)),
                  ),
                  title: Text(book.name, style: const TextStyle(fontWeight: FontWeight.w500)),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _onBookTap(book),
                ),
              );
            },
          ),
    );
  }
}

/// 章节选择底部抽屉
class _ChapterListSheet extends StatefulWidget {
  final String bookName;
  final List<Chapter> chapters;
  final DownloadService downloadService;

  const _ChapterListSheet({
    required this.bookName,
    required this.chapters,
    required this.downloadService,
  });

  @override
  State<_ChapterListSheet> createState() => _ChapterListSheetState();
}

class _ChapterListSheetState extends State<_ChapterListSheet> {
  int? _selectedChapter;

  @override
  void initState() {
    super.initState();
    _checkDownloads();
  }

  Future<void> _checkDownloads() async {
    for (final ch in widget.chapters) {
      ch.downloaded = await widget.downloadService.isDownloaded(
          widget.bookName, ch.fileName);
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.3,
      maxChildSize: 0.95,
      builder: (ctx, scrollController) => Scaffold(
        appBar: AppBar(
          title: Text(widget.bookName),
          actions: [
            if (_selectedChapter != null)
              TextButton(
                onPressed: () => Navigator.pop(context, _selectedChapter),
                child: const Text('开始播放'),
              ),
          ],
        ),
        body: ListView.builder(
          controller: scrollController,
          itemCount: widget.chapters.length,
          itemBuilder: (ctx, index) {
            final ch = widget.chapters[index];
            final isSelected = _selectedChapter == index;

            return ListTile(
              selected: isSelected,
              leading: CircleAvatar(
                  radius: 16,
                child: Text('${index + 1}',
                    style: const TextStyle(fontSize: 13)),
              ),
              title: Text(
                ch.displayName,
                style: TextStyle(
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                ),
              ),
              trailing: ch.downloaded
                  ? const Icon(Icons.download_done, size: 20, color: Colors.green)
                  : null,
              onTap: () {
                setState(() => _selectedChapter = index);
                Navigator.pop(context, index);
              },
            );
          },
        ),
      ),
    );
  }
}
