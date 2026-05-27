import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

/// 本地存储服务 - 播放进度、设置、书库缓存
class StorageService {
  static StorageService? _instance;
  late SharedPreferences _prefs;

  StorageService._();

  static Future<StorageService> getInstance() async {
    if (_instance == null) {
      _instance = StorageService._();
      _instance!._prefs = await SharedPreferences.getInstance();
    }
    return _instance!;
  }

  // ======= 服务器地址 =======
  Future<String?> getServerUrl() async => _prefs.getString('server_url');

  Future<void> setServerUrl(String url) async {
    await _prefs.setString('server_url', url);
  }

  // ======= 书库缓存 =======
  Future<void> cacheBookList(String json) async {
    await _prefs.setString('cached_book_list', json);
  }

  String? getCachedBookList() => _prefs.getString('cached_book_list');

  // ======= 章节缓存（离线支持） =======
  Future<void> cacheChapters(String bookName, String json) async {
    await _prefs.setString('chapters_$bookName', json);
  }

  String? getCachedChapters(String bookName) {
    return _prefs.getString('chapters_$bookName');
  }

  // ======= 播放进度（每本书独立） =======
  Future<void> saveProgress(String bookName, int chapterIndex, int positionMs) async {
    final key = 'progress_$bookName';
    final data = jsonEncode({
      'chapterIndex': chapterIndex,
      'positionMs': positionMs,
      'updatedAt': DateTime.now().millisecondsSinceEpoch,
    });
    await _prefs.setString(key, data);
    await _prefs.setString('last_book', bookName);

    // 同时保存每个章节的独立进度
    final cpKey = 'cpos_${bookName}_$chapterIndex';
    await _prefs.setInt(cpKey, positionMs);
  }

  Map<String, dynamic>? getProgress(String bookName) {
    final key = 'progress_$bookName';
    final data = _prefs.getString(key);
    if (data == null) return null;
    return jsonDecode(data) as Map<String, dynamic>;
  }

  /// 获取某章节的保存位置（毫秒），没有则返回0
  int getChapterPosition(String bookName, int chapterIndex) {
    final key = 'cpos_${bookName}_$chapterIndex';
    return _prefs.getInt(key) ?? 0;
  }

  /// 清除某章节的保存位置（播完时调用）
  Future<void> clearChapterPosition(String bookName, int chapterIndex) async {
    final key = 'cpos_${bookName}_$chapterIndex';
    await _prefs.remove(key);
  }

  // ======= 播放速度（每本书独立） =======
  double getSpeed(String bookName) => _prefs.getDouble('speed_$bookName') ?? 1.0;

  Future<void> setSpeed(String bookName, double speed) async {
    await _prefs.setDouble('speed_$bookName', speed);
  }

  String? getLastBook() => _prefs.getString('last_book');

  // ======= 下载记录 =======
  Future<void> addDownload(String bookName, String fileName, int sortKey) async {
    final key = 'downloads_$bookName';
    final list = getDownloadsRaw(bookName);
    // 检查是否已存在
    final exists = list.any((e) => e['file'] == fileName);
    if (!exists) {
      list.add({'file': fileName, 'sortKey': sortKey});
      await _prefs.setString(key, jsonEncode(list));
    }
  }

  Future<void> removeDownload(String bookName, String fileName) async {
    final key = 'downloads_$bookName';
    final list = getDownloadsRaw(bookName);
    list.removeWhere((e) => e['file'] == fileName);
    await _prefs.setString(key, jsonEncode(list));
  }

  List<Map<String, dynamic>> getDownloadsRaw(String bookName) {
    final key = 'downloads_$bookName';
    final data = _prefs.getString(key);
    if (data == null) return [];
    try {
      final decoded = jsonDecode(data);
      if (decoded is List) {
        if (decoded.isEmpty) return [];
        // 兼容旧格式（纯字符串列表）
        if (decoded.first is String) {
          return decoded
              .map((e) => {'file': e as String, 'sortKey': 0})
              .toList();
        }
        return decoded
            .map((e) => Map<String, dynamic>.from(e as Map))
            .toList();
      }
    } catch (_) {}
    return [];
  }

  List<String> getDownloads(String bookName) {
    return getDownloadsRaw(bookName).map((e) => e['file'] as String).toList();
  }

  /// 从下载记录构建章节列表（离线备用）
  List<Map<String, dynamic>> getDownloadedChaptersData(String bookName) {
    return getDownloadsRaw(bookName);
  }

  /// 获取所有有下载记录的书名
  List<String> getBooksWithDownloads() {
    final keys = _prefs.getKeys().where((k) => k.startsWith('downloads_'));
    return keys.map((k) => k.replaceFirst('downloads_', '')).toList();
  }
}
