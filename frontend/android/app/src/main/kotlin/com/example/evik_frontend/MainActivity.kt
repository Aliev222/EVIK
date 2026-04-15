package com.example.evik_frontend

import com.yandex.mapkit.MapKitFactory
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        flutterEngine
            .platformViewsController
            .registry
            .registerViewFactory(
                "evik/yandex_map_view",
                YandexMapViewFactory(this, flutterEngine.dartExecutor.binaryMessenger)
            )

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, "evik/yandex_map_provider")
            .setMethodCallHandler { call, result ->
                when (call.method) {
                    "isAvailable" -> result.success(MainApplication.isMapKitInitialized)
                    else -> result.notImplemented()
                }
            }
    }

    override fun onStart() {
        super.onStart()
        if (MainApplication.isMapKitInitialized) {
            try {
                MapKitFactory.getInstance().onStart()
            } catch (_: Throwable) {
            }
        }
    }

    override fun onStop() {
        if (MainApplication.isMapKitInitialized) {
            try {
                MapKitFactory.getInstance().onStop()
            } catch (_: Throwable) {
            }
        }
        super.onStop()
    }
}
