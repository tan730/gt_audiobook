import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import '../models/chapter.dart';
import 'api_service.dart';
import 'storage_service.dart';

/// 队列中的一个下载任务
class _QueuedTask {
  final String bookName;
  final Chapter chapter;

  const _QueuedTask(this.bookName, this.chapter);

  String get fileName => chapter.fileName;
}

/// 下载管理服务（带队列和并发控制）
class DownloadService {
  final Dio _dio = Dio();
  final ApiService _apiService;
  final StorageService _storageService;

  // 最大并发下载数
  static const int maxConcurrent = 3;

  // 当前正在下载的文件名集合
  final Set<String> downloadingFiles = {};
  // 等待队列（按入队顺序）
  final List<_QueuedTask> _queue = [];
  final Set<String> queuedFiles = {};
  // 下载中的任务：fileName -> CancelToken
  final Map<String, CancelToken> _activeDownloads = {};
  // 下载进度：fileName -> 0.0~1.0
  final Map<String, double> downloadProgress = {};
  // 进度回调
  void Function(String bookName, String fileName, double progress)? onProgress;
  // 队列变化回调（入队/出队/下载完成/取消）
  void Function()? onQueueChanged;

  DownloadService(this._apiService, this._storageService) {
    _dio.options.connectTimeout = const Duration(seconds: 15);
    _dio.options.receiveTimeout = const Duration(seconds: 60);
  }

  /// 获取本地存储目录
  Future<Directory> getDownloadDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/audiobook_downloads');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  /// 获取某章节的本地文件路径
  Future<String> getLocalPath(String bookName, String fileName) async {
    final dir = await getDownloadDir();
    final bookDir = Directory('${dir.path}/$bookName');
    if (!await bookDir.exists()) {
      await bookDir.create(recursive: true);
    }
    return '${bookDir.path}/$fileName';
  }

  /// 检查章节是否已下载
  Future<bool> isDownloaded(String bookName, String fileName) async {
    final path = await getLocalPath(bookName, fileName);
    return File(path).existsSync();
  }

  /// 下载一个章节（自动排队，并发数超过 maxConcurrent 则排队等待）
  Future<void> downloadChapter(String bookName, Chapter chapter) async {
    if (bookName.isEmpty) throw Exception('下载失败: bookName为空');
    final fileName = chapter.fileName;
    if (fileName.isEmpty) throw Exception('下载失败: fileName为空');
    if (chapter.file.isEmpty) throw Exception('下载失败: file路径为空');

    // 已经下载完成 → 跳过
    if (await isDownloaded(bookName, fileName)) {
      chapter.downloaded = true;
      return;
    }
    // 已经在下载中 → 跳过
    if (downloadingFiles.contains(fileName)) return;
    // 已经在队列中 → 跳过
    if (queuedFiles.contains(fileName)) return;

    // 达到并发上限 → 入队等待
    if (downloadingFiles.length >= maxConcurrent) {
      _queue.add(_QueuedTask(bookName, chapter));
      queuedFiles.add(fileName);
      onQueueChanged?.call();
      return;
    }

    // 有并发空位 → 直接开始下载
    _startDownload(bookName, chapter);
  }

  /// 实际发起下载
  Future<void> _startDownload(String bookName, Chapter chapter) async {
    final fileName = chapter.fileName;

    downloadingFiles.add(fileName);
    final savePath = await getLocalPath(bookName, fileName);
    final url = _apiService.getAudioUrl(chapter.file);
    final cancelToken = CancelToken();

    _activeDownloads[fileName] = cancelToken;
    onQueueChanged?.call();

    try {
      await _dio.download(
        url,
        savePath,
        cancelToken: cancelToken,
        onReceiveProgress: (received, total) {
          if (total > 0) {
            final progress = received / total;
            downloadProgress[fileName] = progress;
            onProgress?.call(bookName, fileName, progress);
          }
        },
      );
      // 下载完成，记录
      downloadProgress.remove(fileName);
      await _storageService.addDownload(bookName, fileName, chapter.sortKey);
      chapter.downloaded = true;
    } catch (e) {
      if (e is DioException && e.type == DioExceptionType.cancel) {
        // 用户取消
      } else {
        rethrow;
      }
    } finally {
      downloadingFiles.remove(fileName);
      _activeDownloads.remove(fileName);
      onQueueChanged?.call();
      // 检查队列，启动下一个等待的任务
      _drainQueue();
    }
  }

  /// 从队列中取出下一个任务并启动（直到并发数满或队列为空）
  void _drainQueue() {
    while (_queue.isNotEmpty && downloadingFiles.length < maxConcurrent) {
      final task = _queue.removeAt(0);
      queuedFiles.remove(task.fileName);
      // 异步启动下一个下载
      _startDownload(task.bookName, task.chapter);
    }
  }

  /// 取消下载（正在下载或队列中等待的）
  void cancelDownload(String fileName) {
    if (_activeDownloads.containsKey(fileName)) {
      _activeDownloads[fileName]?.cancel();
      _activeDownloads.remove(fileName);
    }
    // 从队列中移除
    _queue.removeWhere((t) => t.fileName == fileName);
    queuedFiles.remove(fileName);
    downloadingFiles.remove(fileName);
    downloadProgress.remove(fileName);
    onQueueChanged?.call();
    // 检查队列
    _drainQueue();
  }

  /// 删除已下载的章节文件
  Future<void> deleteChapter(String bookName, String fileName) async {
    final path = await getLocalPath(bookName, fileName);
    final file = File(path);
    if (await file.exists()) {
      await file.delete();
    }
    await _storageService.removeDownload(bookName, fileName);
  }

  /// 删除整本书的下载
  Future<void> deleteBookDownloads(String bookName) async {
    final dir = await getDownloadDir();
    final bookDir = Directory('${dir.path}/$bookName');
    if (await bookDir.exists()) {
      await bookDir.delete(recursive: true);
    }
    final downloads = _storageService.getDownloads(bookName);
    for (final f in downloads) {
      await _storageService.removeDownload(bookName, f);
    }
  }

  /// 批量删除多个文件
  Future<void> deleteChapters(String bookName, List<String> fileNames) async {
    for (final fileName in fileNames) {
      await deleteChapter(bookName, fileName);
    }
  }

  /// 获取已下载章节的本地路径
  Future<String?> getLocalFile(String bookName, String fileName) async {
    final path = await getLocalPath(bookName, fileName);
    if (await File(path).exists()) {
      return path;
    }
    return null;
  }

  /// 获取下载目录的总体大小（字节）
  Future<int> getTotalDownloadSize() async {
    final dir = await getDownloadDir();
    int total = 0;
    if (await dir.exists()) {
      await for (final entity in dir.list(recursive: true)) {
        if (entity is File) {
          total += await entity.length();
        }
      }
    }
    return total;
  }

  /// 获取流式缓存目录
  Future<Directory> getCacheDir() async {
    final appDir = await getApplicationDocumentsDirectory();
    final dir = Directory('${appDir.path}/audiobook_cache');
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    return dir;
  }

  void dispose() {
    for (final cancel in _activeDownloads.values) {
      cancel.cancel();
    }
    _activeDownloads.clear();
    downloadingFiles.clear();
    _queue.clear();
    queuedFiles.clear();
    downloadProgress.clear();
  }
}
