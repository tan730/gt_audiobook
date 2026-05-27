import 'package:flutter/material.dart';
import 'package:dio/dio.dart';

/// 首次启动 - 服务器地址配置
class SetupScreen extends StatefulWidget {
  final Future<void> Function(String url) onConfigured;

  const SetupScreen({super.key, required this.onConfigured});

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _testing = false;
  bool _saving = false;
  String? _testResult;
  bool? _testSuccess;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _testConnection() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _testing = true;
      _testResult = null;
    });

    try {
      final url = _controller.text.trim();
      final dio = Dio();
      final response = await dio.get(
        '$url/api.php?action=books',
        options: Options(
          connectTimeout: const Duration(seconds: 5),
          receiveTimeout: const Duration(seconds: 5),
        ),
      );
      if (response.statusCode == 200) {
        setState(() {
          _testResult = '连接成功！';
          _testSuccess = true;
        });
      } else {
        setState(() {
          _testResult = '服务器返回错误: ${response.statusCode}';
          _testSuccess = false;
        });
      }
    } catch (e) {
      setState(() {
        _testResult = '连接失败: 请检查地址和网络';
        _testSuccess = false;
      });
    } finally {
      setState(() => _testing = false);
    }
  }

  Future<void> _save() async {
    if (_formKey.currentState!.validate()) {
      setState(() => _saving = true);
      await widget.onConfigured(_controller.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('GT听书 - 初始设置')),
      body: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Icon(Icons.headphones, size: 64,
                    color: Theme.of(context).colorScheme.primary),
                const SizedBox(height: 16),
                Text('欢迎使用GT听书',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.headlineSmall),
                const SizedBox(height: 8),
                Text('请配置有声书服务器地址',
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant)),
                const SizedBox(height: 32),
                TextFormField(
                  controller: _controller,
                  decoration: const InputDecoration(
                    labelText: '服务器地址',
                    hintText: '如 http://192.168.1.100/audiobook',
                    prefixIcon: Icon(Icons.link),
                    border: OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.url,
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) return '请输入服务器地址';
                    if (!v.trim().startsWith('http')) return '地址需以 http:// 或 https:// 开头';
                    return null;
                  },
                ),
                const SizedBox(height: 12),
                if (_testResult != null)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: Row(
                      children: [
                        Icon(_testSuccess == true ? Icons.check_circle : Icons.error,
                            color: _testSuccess == true ? Colors.green : Colors.red,
                            size: 18),
                        const SizedBox(width: 8),
                        Expanded(child: Text(_testResult!,
                            style: TextStyle(color: _testSuccess == true
                                ? Colors.green : Colors.red))),
                      ],
                    ),
                  ),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: _testing ? null : _testConnection,
                        child: _testing
                            ? const SizedBox(height: 20, width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('测试连接'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: FilledButton(
                        onPressed: _saving ? null : _save,
                        child: _saving
                            ? const SizedBox(height: 20, width: 20,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : const Text('保存并进入'),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
