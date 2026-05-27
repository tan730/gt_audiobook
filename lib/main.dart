import 'package:flutter/material.dart';
import 'package:audio_service/audio_service.dart';
import 'package:audio_session/audio_session.dart';
import 'services/api_service.dart';
import 'services/storage_service.dart';
import 'services/player_service.dart';
import 'services/download_service.dart';
import 'services/audio_handler.dart';
import 'screens/setup_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/book_list_screen.dart';
import 'screens/player_screen.dart';
import 'screens/download_screen.dart';

/// 全局 handler 引用，main() 创建，AppShell 连接
AudioPlayerHandler? globalHandler;

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  globalHandler = AudioPlayerHandler();
  try {
    await AudioService.init(
      builder: () => globalHandler!,
      config: AudioServiceConfig(
        androidNotificationChannelId: 'com.gtmatch.audiobook',
        androidNotificationChannelName: 'GT听书',
        androidNotificationOngoing: true,
        androidStopForegroundOnPause: false,
      ),
    );
  } catch (e) {
    // AudioService 初始化失败，通知栏不可用但app正常运行
    debugPrint('AudioService init: $e');
    globalHandler = null;
  }

  runApp(const GTAudiobookApp());
}

class GTAudiobookApp extends StatelessWidget {
  const GTAudiobookApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'GT听书',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A73E8),
          brightness: Brightness.light,
        ),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF1A73E8),
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const AppShell(),
    );
  }
}

class AppShell extends StatefulWidget {
  const AppShell({super.key});

  @override
  State<AppShell> createState() => _AppShellState();
}

class _AppShellState extends State<AppShell> {
  int _currentTab = 0;
  bool _initialized = false;
  bool _hasServerUrl = false;

  late ApiService _apiService;
  late StorageService _storageService;
  late PlayerService _playerService;
  late DownloadService _downloadService;

  @override
  void initState() {
    super.initState();
    _initialize();
  }

  Future<void> _initialize() async {
    _storageService = await StorageService.getInstance();
    final url = await _storageService.getServerUrl();

    if (url != null && url.isNotEmpty) {
      _apiService = ApiService(url);
      _hasServerUrl = true;
    } else {
      _apiService = ApiService('');
      _hasServerUrl = false;
    }

    _downloadService = DownloadService(_apiService, _storageService);
    _playerService = PlayerService(_apiService, downloadService: _downloadService, storageService: _storageService);

    // 配置 audio_session（允许后台播放）
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration(
      avAudioSessionCategory: AVAudioSessionCategory.playback,
      avAudioSessionCategoryOptions: AVAudioSessionCategoryOptions.mixWithOthers,
      avAudioSessionMode: AVAudioSessionMode.defaultMode,
      avAudioSessionRouteSharingPolicy: AVAudioSessionRouteSharingPolicy.defaultPolicy,
      androidAudioAttributes: AndroidAudioAttributes(
        contentType: AndroidAudioContentType.music,
        usage: AndroidAudioUsage.media,
      ),
      androidAudioFocusGainType: AndroidAudioFocusGainType.gain,
      androidWillPauseWhenDucked: true,
    ));

    // 将全局 handler 连接到播放器
    globalHandler?.bindPlayer(_playerService.player);
    _playerService.setHandler(globalHandler);

    _playerService.onPlayStateChanged = () {
      if (mounted) setState(() {});
    };
    _playerService.onChapterChanged = () {
      if (mounted) setState(() {});
    };
    _playerService.onProgressChanged = () {
      if (mounted) setState(() {});
    };

    _downloadService.onProgress = (bookName, fileName, progress) {
      if (mounted) setState(() {});
    };

    setState(() => _initialized = true);
  }

  Future<void> _onServerConfigured(String url) async {
    await _storageService.setServerUrl(url);
    _apiService.updateBaseUrl(url);
    setState(() => _hasServerUrl = true);
  }

  void _openSettings() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SettingsScreen(
          apiService: _apiService,
          storageService: _storageService,
          onUrlChanged: (url) {
            _apiService.updateBaseUrl(url);
            setState(() {});
          },
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!_initialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (!_hasServerUrl) {
      return SetupScreen(onConfigured: _onServerConfigured);
    }

    return Scaffold(
      appBar: AppBar(
        title: Text(_getAppBarTitle()),
        actions: [
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: _openSettings,
          ),
        ],
      ),
      body: _buildBody(),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _currentTab,
        onDestinationSelected: (index) => setState(() => _currentTab = index),
        destinations: const [
          NavigationDestination(
            icon: Icon(Icons.library_books_outlined),
            selectedIcon: Icon(Icons.library_books),
            label: '书库',
          ),
          NavigationDestination(
            icon: Icon(Icons.play_circle_outlined),
            selectedIcon: Icon(Icons.play_circle_filled),
            label: '正在播放',
          ),
          NavigationDestination(
            icon: Icon(Icons.download_outlined),
            selectedIcon: Icon(Icons.download),
            label: '下载',
          ),
        ],
      ),
    );
  }

  String _getAppBarTitle() {
    switch (_currentTab) {
      case 0:
        return 'GT听书';
      case 1:
        return _playerService.bookName.isNotEmpty ? _playerService.bookName : '正在播放';
      case 2:
        return '下载管理';
      default:
        return 'GT听书';
    }
  }

  Widget _buildBody() {
    switch (_currentTab) {
      case 0:
        return BookListScreen(
          apiService: _apiService,
          storageService: _storageService,
          playerService: _playerService,
          downloadService: _downloadService,
          onPlayBook: (bookName, chapters, startIndex, startMs) {
            _playerService.loadBook(bookName, chapters,
                startIndex: startIndex, startPositionMs: startMs);
            setState(() => _currentTab = 1);
          },
        );
      case 1:
        return PlayerScreen(
          playerService: _playerService,
          downloadService: _downloadService,
          storageService: _storageService,
        );
      case 2:
        return DownloadScreen(
          storageService: _storageService,
          downloadService: _downloadService,
          apiService: _apiService,
          onPlayChapter: (bookName, chapters, chapterIndex) async {
            _playerService.loadBook(bookName, chapters,
                startIndex: chapterIndex);
            setState(() => _currentTab = 1);
          },
        );
      default:
        return const SizedBox.shrink();
    }
  }
}
