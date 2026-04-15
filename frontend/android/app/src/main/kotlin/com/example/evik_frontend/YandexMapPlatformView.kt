package com.example.evik_frontend

import android.app.Activity
import android.content.Context
import android.util.Log
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.TextView
import com.yandex.mapkit.Animation
import com.yandex.mapkit.geometry.Point
import com.yandex.mapkit.map.CameraPosition
import com.yandex.mapkit.mapview.MapView
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory

class YandexMapViewFactory(
    private val activity: Activity,
    private val messenger: BinaryMessenger
) : PlatformViewFactory(StandardMessageCodec.INSTANCE) {
    override fun create(context: Context, viewId: Int, args: Any?): PlatformView {
        return YandexMapPlatformView(activity, context, messenger, viewId, args)
    }
}

class YandexMapPlatformView(
    private val activity: Activity,
    private val context: Context,
    messenger: BinaryMessenger,
    private val viewId: Int,
    args: Any?
) : PlatformView, MethodChannel.MethodCallHandler {

    private val fallbackView: View by lazy { buildFallbackView() }
    private var mapView: MapView? = null
    private var channel: MethodChannel? = null

    init {
        if (MainApplication.isMapKitInitialized) {
            try {
                mapView = MapView(context)
                mapView?.onStart()

                applyInitialCamera(args)

                channel = MethodChannel(messenger, "evik/yandex_map_$viewId")
                channel?.setMethodCallHandler(this)
            } catch (t: Throwable) {
                Log.e(TAG, "Failed to create Yandex MapView. Falling back.", t)
                mapView = null
            }
        } else {
            Log.w(TAG, "MapKit is unavailable. Placeholder view will be used.")
        }
    }

    override fun getView(): View = mapView ?: fallbackView

    override fun dispose() {
        channel?.setMethodCallHandler(null)
        channel = null

        try {
            mapView?.onStop()
        } catch (t: Throwable) {
            Log.e(TAG, "Error while stopping MapKit view", t)
        }
        mapView = null
    }

    override fun onMethodCall(call: MethodCall, result: MethodChannel.Result) {
        when (call.method) {
            "moveCamera" -> {
                val lat = (call.argument<Number>("lat")?.toDouble()) ?: return result.success(null)
                val lng = (call.argument<Number>("lng")?.toDouble()) ?: return result.success(null)
                val zoom = (call.argument<Number>("zoom")?.toFloat()) ?: 15f
                moveCamera(lat, lng, zoom)
                result.success(null)
            }
            else -> result.notImplemented()
        }
    }

    private fun applyInitialCamera(args: Any?) {
        val params = args as? Map<*, *> ?: return
        val lat = (params["initialLat"] as? Number)?.toDouble() ?: return
        val lng = (params["initialLng"] as? Number)?.toDouble() ?: return
        val zoom = (params["initialZoom"] as? Number)?.toFloat() ?: 14f
        moveCamera(lat, lng, zoom)
    }

    private fun moveCamera(lat: Double, lng: Double, zoom: Float) {
        val mv = mapView ?: return
        activity.runOnUiThread {
            mv.mapWindow.map.move(
                CameraPosition(Point(lat, lng), zoom, 0f, 0f),
                Animation(Animation.Type.SMOOTH, 0.35f),
                null
            )
        }
    }

    private fun buildFallbackView(): View {
        val container = FrameLayout(context)
        container.setBackgroundColor(0xFFE8EEF5.toInt())

        val textView = TextView(context)
        textView.text = "Map"
        textView.textSize = 20f
        textView.setTextColor(0xFF12406A.toInt())
        textView.gravity = Gravity.CENTER

        container.addView(
            textView,
            FrameLayout.LayoutParams(
                FrameLayout.LayoutParams.MATCH_PARENT,
                FrameLayout.LayoutParams.MATCH_PARENT
            )
        )
        return container
    }

    companion object {
        private const val TAG = "EVIK.YandexPlatformView"
    }
}
