package com.example.mch25

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.example.mch25/audio"
    private var audioPlayer: AudioStreamPlayer? = null

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        
        audioPlayer = AudioStreamPlayer()
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "startStream" -> {
                    val url = call.argument<String>("url")
                    if (url != null) {
                        audioPlayer?.start(url)
                        result.success(null)
                    } else {
                        result.error("INVALID_ARGUMENT", "URL is required", null)
                    }
                }
                "stopStream" -> {
                    audioPlayer?.stop()
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }
    }
    
    override fun onDestroy() {
        audioPlayer?.stop()
        super.onDestroy()
    }
}
