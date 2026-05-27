import 'dart:async';
import 'dart:io';
import 'package:dio/dio.dart';
import 'package:path_provider/path_provider.dart';
import '../models/chapter.dart';
import 'api_service.dart';
import 'storage_service.dart';

/// 下载管理服务
class DownloadService {
  final Dio _dio = Dio();
  final ApiService _apiService;
  final StorageService _storageService;

  // 下载中的任务：fileName -> 取消函数
  final Map<String, CancelToken> _activeDownloads = {};
  // 下载进度：fileName -> 0.0~1.0
  final Map<String, double> downloadProgress = {};
  // 进度回调
  void Function(String bookName, String fileName, double progress)? onProgress;

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

  /// 下载一个章节
  Future<void> downloadChapter(String bookName, Chapter chapter) async {
    // 防御性空值检查
    if (bookName.isEmpty) throw Exception('下载失败: bookName为空');
    final fileName = chapter.fileName;
    if (fileName.isEmpty) throw Exception('下载失败: fileName为空');
    if (chapter.file.isEmpty) throw Exception('下载失败: file路径为空');

    final savePath = await getLocalPath(bookName, fileName);
    if (savePath.isEmpty) throw Exception('下载失败: savePath为空');

    final url = _apiService.getAudioUrl(chapter.file);
    final cancelToken = CancelToken();

    _activeDownloads[fileName] = cancelToken;

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
      _activeDownloads.remove(fileName);
    }
  }

  /// 取消下载
  void cancelDownload(String fileName) {
    _activeDownloads[fileName]?.cancel();
    _activeDownloads.remove(fileName);
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
  }
}
