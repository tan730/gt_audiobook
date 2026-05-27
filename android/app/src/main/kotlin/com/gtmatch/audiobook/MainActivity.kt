package com.gtmatch.audiobook

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.gtmatch.audiobook/foreground"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startForeground" -> {
                    val title = call.argument<String>("title") ?: "正在播放"
                    val intent = Intent(this, AudioForegroundService::class.java).apply {
                        action = AudioForegroundService.ACTION_START
                        putExtra(AudioForegroundService.EXTRA_TITLE, title)
                    }
                    startForegroundService(intent)
                    result.success(true)
                }
                "stopForeground" -> {
                    val intent = Intent(this, AudioForegroundService::class.java).apply {
                        action = AudioForegroundService.ACTION_STOP
                    }
                    stopService(intent)
                    result.success(true)
                }
                else -> result.notImplemented()
            }
        }
    }
}
