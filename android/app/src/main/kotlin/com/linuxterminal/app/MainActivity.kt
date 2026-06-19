package com.linuxterminal.app

import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel
import android.content.pm.PackageManager

class MainActivity : FlutterActivity() {
    private val CHANNEL = "com.linuxterminal.app/native"

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, CHANNEL)
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "getNativeLibDir" -> {
                        try {
                            val ai = applicationContext.packageManager.getApplicationInfo(
                                applicationContext.packageName,
                                PackageManager.GET_META_DATA
                            )
                            result.success(ai.nativeLibDir)
                        } catch (e: Exception) {
                            result.success("")
                        }
                    }
                    else -> result.notImplemented()
                }
            }
    }
}
