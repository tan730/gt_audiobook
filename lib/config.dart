/// GT听书 - 应用配置
class AppConfig {
  /// SharedPreferences键名
  static const String keyServerUrl = 'server_url';
  static const String keyBookList = 'cached_book_list';
  static const String keyLastBook = 'last_book';
  static const String keyBookmarkPrefix = 'bookmark_';

  /// 下载管理键名
  static const String keyDownloadedChapters = 'downloaded_chapters';

  /// 流式缓存保留的最近章节数
  static const int maxStreamCacheChapters = 20;

  /// 音频文件格式
  static const List<String> audioExtensions = ['mp3', 'm4a', 'ogg', 'wav', 'aac', 'flac'];
}
