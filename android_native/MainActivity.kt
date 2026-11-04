package com.example.speed_map

import android.content.Intent
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    companion object {
        const val ACTION_START_OVERLAY = "com.example.speed_map.START_OVERLAY"
        const val CHANNEL = "speed_map/launch"
    }

    private var channel: MethodChannel? = null
    private var launchedFromWidget = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        channel = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
        channel?.setMethodCallHandler { call, result ->
            if (call.method == "consumeLaunchAction") {
                val value = launchedFromWidget
                launchedFromWidget = false
                result.success(value)
            } else {
                result.notImplemented()
            }
        }
        launchedFromWidget = consume(intent)
    }

    // App was already running and the widget was tapped.
    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        if (consume(intent)) {
            channel?.invokeMethod("startOverlay", null)
        }
    }

    private fun consume(i: Intent?): Boolean {
        if (i?.action == ACTION_START_OVERLAY) {
            i.action = Intent.ACTION_MAIN
            return true
        }
        return false
    }
}
