package com.gtmatch.audiobook

import android.content.ComponentName
import android.os.Bundle
import androidx.media3.session.MediaController
import androidx.media3.session.SessionToken
import com.google.common.util.concurrent.MoreExecutors
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.gtmatch.audiobook/player"
    private var controller: MediaController? = null
    private var methodChannel: MethodChannel? = null

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        connectToService()
    }

    private fun connectToService() {
        val sessionToken = SessionToken(this, ComponentName(this, MediaPlaybackService::class.java))
        val futureController = MediaController.Builder(this, sessionToken).buildAsync()
        futureController.addListener({
            try {
                controller = futureController.get()
                setupMethodChannel()
            } catch (e: Exception) {
                android.util.Log.e("MainActivity", "MediaController error: ${e.message}")
            }
        }, MoreExecutors.directExecutor())
    }

    private fun setupMethodChannel() {
        val c = controller ?: return
        // 监听原生播放器状态，转发到Dart
        c.addListener(object : androidx.media3.common.Player.Listener {
            override fun onIsPlayingChanged(isPlaying: Boolean) {
                runOnUiThread {
                    methodChannel?.invokeMethod("onPlayingChanged", isPlaying)
                }
            }
            override fun onPositionDiscontinuity(
                oldPosition: androidx.media3.common.Player.PositionInfo,
                newPosition: androidx.media3.common.Player.PositionInfo,
                reason: Int
            ) {
                runOnUiThread {
                    methodChannel?.invokeMethod("onPositionDiscontinuity", null)
                }
            }
        })
    }

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        methodChannel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        methodChannel?.setMethodCallHandler { call, result ->
            val cc = controller
            if (cc == null && call.method != "isReady") {
                result.error("NOT_READY", "MediaController未就绪", null)
                return@setMethodCallHandler
            }
            try {
                when (call.method) {
                    "isReady" -> result.success(true)
                    "loadBook" -> {
                        val chapters = call.argument<List<String>>("chapterUrls") ?: listOf()
                        val titles = call.argument<List<String>>("chapterTitles") ?: listOf()
                        val startIndex = call.argument<Int>("startIndex") ?: 0
                        val startMs = call.argument<Int>("startMs") ?: 0
                        if (chapters.isEmpty()) {
                            result.error("EMPTY", "无章节", null)
                            return@setMethodCallHandler
                        }
                        val items = chapters.mapIndexed { i, url ->
                            androidx.media3.common.MediaItem.Builder()
                                .setUri(url)
                                .setMediaId(i.toString())
                                .setMediaMetadata(
                                    androidx.media3.common.MediaMetadata.Builder()
                                        .setTitle(titles.getOrNull(i) ?: "")
                                        .build()
                                )
                                .build()
                        }
                        cc!!.setMediaItems(items, startIndex, (startMs).toLong())
                        cc.prepare()
                        cc.playWhenReady = true
                        result.success(true)
                    }
                    "play" -> { cc!!.play(); result.success(true) }
                    "pause" -> { cc!!.pause(); result.success(true) }
                    "seek" -> {
                        val ms = call.argument<Int>("ms") ?: 0
                        cc!!.seekTo(ms.toLong())
                        result.success(true)
                    }
                    "seekToChapter" -> {
                        val idx = call.argument<Int>("index") ?: 0
                        cc!!.seekToDefaultPosition(idx)
                        result.success(true)
                    }
                    "setSpeed" -> {
                        val speed = (call.argument<Double>("speed") ?: 1.0).toFloat()
                        cc!!.setPlaybackSpeed(speed)
                        result.success(true)
                    }
                    "skipNext" -> { if (cc!!.hasNextMediaItem()) cc.seekToNextMediaItem(); result.success(true) }
                    "skipPrev" -> { if (cc!!.hasPreviousMediaItem()) cc.seekToPreviousMediaItem(); result.success(true) }
                    "getState" -> {
                        val state = mapOf(
                            "isPlaying" to cc!!.isPlaying,
                            "currentIndex" to cc.currentMediaItemIndex,
                            "positionMs" to cc.currentPosition,
                            "durationMs" to cc.duration.coerceAtLeast(0),
                            "speed" to cc.playbackParameters.speed.toDouble()
                        )
                        result.success(state)
                    }
                    "stop" -> { cc!!.stop(); cc.clearMediaItems(); result.success(true) }
                    else -> result.notImplemented()
                }
            } catch (e: Exception) {
                result.error("EXCEPTION", e.message, null)
            }
        }
    }

    override fun onDestroy() {
        controller?.release()
        controller = null
        methodChannel = null
        super.onDestroy()
    }
}
