/// 章节模型
class Chapter {
  final String file;   // 相对路径，如 "三体/第01章.mp3"
  final String name;   // 原始文件名（无扩展名）
  final int sortKey;   // 提取的数字排序键
  bool downloaded;     // 是否已下载到本地

  Chapter({
    required this.file,
    required this.name,
    required this.sortKey,
    this.downloaded = false,
  });

  factory Chapter.fromJson(Map<String, dynamic> json) {
    return Chapter(
      file: json['file'] as String,
      name: json['name'] as String,
      sortKey: json['sortKey'] as int,
    );
  }

  Map<String, dynamic> toJson() => {
    'file': file,
    'name': name,
    'sortKey': sortKey,
  };

  /// 获取显示名称：
  /// 如果原始文件名包含非数字字符，显示原始名
  /// 如果只有数字（如 "001"），显示"第N集"
  String get displayName {
    final hasLetters = RegExp(r'[a-zA-Z\u4e00-\u9fff]').hasMatch(name);
    if (hasLetters) return name;
    return '第$sortKey集';
  }

  /// 从文件名提取章节文件名（用于本地存储）
  String get fileName {
    return file.split('/').last;
  }
}
