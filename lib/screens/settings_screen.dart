import 'package:flutter/material.dart';
import '../services/api_service.dart';
import '../services/storage_service.dart';

/// 设置页 - 修改服务器地址
class SettingsScreen extends StatefulWidget {
  final ApiService apiService;
  final StorageService storageService;
  final void Function(String url) onUrlChanged;

  const SettingsScreen({
    super.key,
    required this.apiService,
    required this.storageService,
    required this.onUrlChanged,
  });

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final _controller = TextEditingController();
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _controller.text = widget.apiService.baseUrl;
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _saving = true);
    final url = _controller.text.trim();
    await widget.storageService.setServerUrl(url);
    widget.onUrlChanged(url);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('服务器地址已更新')),
      );
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('设置')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
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
                const SizedBox(height: 16),
                FilledButton(
                  onPressed: _saving ? null : _save,
                  child: _saving
                      ? const SizedBox(height: 20, width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2))
                      : const Text('保存'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 32),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('关于'),
            subtitle: const Text('GT听书 v1.0.0\n基于 Flutter 构建'),
          ),
        ],
      ),
    );
  }
}
