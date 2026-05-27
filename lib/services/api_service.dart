import 'dart:convert';
import 'package:http/http.dart' as http;
import '../models/book.dart';
import '../models/chapter.dart';

/// API服务 - 与PHP后端通信
class ApiService {
  String _baseUrl;

  ApiService(this._baseUrl);

  /// 更新服务器地址
  void updateBaseUrl(String url) {
    _baseUrl = url.endsWith('/') ? url.substring(0, url.length - 1) : url;
  }

  String get baseUrl => _baseUrl;

  /// 获取书单
  Future<List<Book>> fetchBooks() async {
    final uri = Uri.parse('$_baseUrl/api.php?action=books');
    final response = await http.get(uri).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception('服务器错误: ${response.statusCode}');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final list = data['books'] as List<dynamic>;
    return list.map((e) => Book.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 获取某本书的章节列表
  Future<List<Chapter>> fetchChapters(String bookName) async {
    final uri = Uri.parse('$_baseUrl/api.php?action=chapters&book=${Uri.encodeComponent(bookName)}');
    final response = await http.get(uri).timeout(const Duration(seconds: 10));
    if (response.statusCode != 200) {
      throw Exception('服务器错误: ${response.statusCode}');
    }
    final data = jsonDecode(response.body) as Map<String, dynamic>;
    final list = data['chapters'] as List<dynamic>;
    return list.map((e) => Chapter.fromJson(e as Map<String, dynamic>)).toList();
  }

  /// 获取音频文件的完整URL（自动对中文路径编码）
  String getAudioUrl(String relativePath) {
    final segments = relativePath.split('/');
    final encoded = segments.map((s) => Uri.encodeComponent(s)).join('/');
    return '$_baseUrl/$encoded';
  }
}
