/// 有声书模型
class Book {
  final String name;
  final String cover;

  const Book({
    required this.name,
    this.cover = '',
  });

  factory Book.fromJson(Map<String, dynamic> json) {
    return Book(
      name: json['name'] as String,
      cover: json['cover'] as String? ?? '',
    );
  }

  Map<String, dynamic> toJson() => {'name': name, 'cover': cover};
}
