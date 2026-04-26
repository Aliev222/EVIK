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
import com.yandex.mapkit.geometry.Polyline
import com.yandex.mapkit.map.CameraPosition
import com.yandex.mapkit.map.PlacemarkMapObject
import com.yandex.mapkit.map.PolylineMapObject
import com.yandex.mapkit.mapview.MapView
import com.yandex.runtime.Error
import com.yandex.runtime.image.ImageProvider
import io.flutter.plugin.common.BinaryMessenger
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.StandardMessageCodec
import io.flutter.plugin.platform.PlatformView
import io.flutter.plugin.platform.PlatformViewFactory
import kotlin.math.max

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
    private val markerObjects = linkedMapOf<String, PlacemarkMapObject>()
    private var routeObject: PolylineMapObject? = null

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
            mapView?.let { mv ->
                clearRouteInternal(mv)
                clearMarkersInternal(mv)
            }
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
            "setMarkers" -> {
                @Suppress("UNCHECKED_CAST")
                val markers = call.argument<List<Map<String, Any?>>>("markers") ?: emptyList()
                setMarkers(markers)
                result.success(null)
            }
            "clearMarkers" -> {
                clearMarkers()
                result.success(null)
            }
            "setRoute" -> {
                @Suppress("UNCHECKED_CAST")
                val points = call.argument<List<Map<String, Any?>>>("points") ?: emptyList()
                setRoute(points)
                result.success(null)
            }
            "clearRoute" -> {
                clearRoute()
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

    private fun setMarkers(markers: List<Map<String, Any?>>) {
        val mv = mapView ?: return
        activity.runOnUiThread {
            clearMarkersInternal(mv)
            markers.forEach { marker ->
                val id = marker["id"]?.toString().orEmpty()
                val lat = (marker["lat"] as? Number)?.toDouble() ?: return@forEach
                val lng = (marker["lng"] as? Number)?.toDouble() ?: return@forEach
                val placemark = mv.mapWindow.map.mapObjects.addPlacemark(Point(lat, lng))
                val iconRes = if (id == "driver") {
                    android.R.drawable.presence_online
                } else {
                    android.R.drawable.presence_busy
                }
                placemark.setIcon(ImageProvider.fromResource(context, iconRes))
                placemark.zIndex = 100f
                markerObjects[id.ifEmpty { "$lat:$lng" }] = placemark
            }
        }
    }

    private fun clearMarkers() {
        val mv = mapView ?: return
        activity.runOnUiThread {
            clearMarkersInternal(mv)
        }
    }

    private fun setRoute(pointsPayload: List<Map<String, Any?>>) {
        val mv = mapView ?: return
        val points = pointsPayload.mapNotNull { payload ->
            val lat = (payload["lat"] as? Number)?.toDouble() ?: return@mapNotNull null
            val lng = (payload["lng"] as? Number)?.toDouble() ?: return@mapNotNull null
            Point(lat, lng)
        }

        activity.runOnUiThread {
            if (points.size < 2) {
                clearRouteInternal(mv)
                if (points.isNotEmpty()) {
                    moveCamera(points.first().latitude, points.first().longitude, 15f)
                }
                return@runOnUiThread
            }

            clearRouteInternal(mv)
            routeObject = mv.mapWindow.map.mapObjects
                .addPolyline(Polyline(points))
                .apply { applyRouteStyle(this) }
            focusRoute(mv, points)
            dispatchRouteSummary(
                calculatePolylineDistanceMeters(points),
                null
            )
        }
    }

    private fun clearRoute() {
        val mv = mapView ?: return
        activity.runOnUiThread {
            clearRouteInternal(mv)
        }
    }

    private fun focusRoute(mv: MapView, points: List<Point>) {
        if (points.isEmpty()) return
        val minLat = points.minOf { it.latitude }
        val maxLat = points.maxOf { it.latitude }
        val minLng = points.minOf { it.longitude }
        val maxLng = points.maxOf { it.longitude }
        val center = Point((minLat + maxLat) / 2.0, (minLng + maxLng) / 2.0)
        val span = max(maxLat - minLat, maxLng - minLng)
        val zoom = when {
            span < 0.005 -> 15.5f
            span < 0.02 -> 14.2f
            span < 0.05 -> 13.2f
            span < 0.1 -> 12.2f
            else -> 11.4f
        }
        mv.mapWindow.map.move(
            CameraPosition(center, zoom, 0f, 0f),
            Animation(Animation.Type.SMOOTH, 0.35f),
            null
        )
    }

    private fun clearRouteInternal(mv: MapView) {
        routeObject?.let { mv.mapWindow.map.mapObjects.remove(it) }
        routeObject = null
        dispatchRouteSummary(null, null)
    }

    private fun applyRouteStyle(polyline: PolylineMapObject) {
        polyline.zIndex = 80f
        polyline.setStrokeWidth(5f)
        polyline.setStrokeColor(0xFF1EC6D3.toInt())
        polyline.setOutlineWidth(2f)
        polyline.setOutlineColor(0xFFFFFFFF.toInt())
    }

    private fun clearMarkersInternal(mv: MapView) {
        markerObjects.values.forEach { mv.mapWindow.map.mapObjects.remove(it) }
        markerObjects.clear()
    }

    private fun dispatchRouteSummary(distanceMeters: Double?, durationSeconds: Double?) {
        try {
            channel?.invokeMethod(
                "onRouteSummary",
                mapOf(
                    "distance_meters" to distanceMeters,
                    "duration_seconds" to durationSeconds
                )
            )
        } catch (t: Throwable) {
            Log.w(TAG, "Failed to dispatch route summary", t)
        }
    }

    private fun calculatePolylineDistanceMeters(points: List<Point>): Double {
        var total = 0.0
        for (index in 1 until points.size) {
            total += distanceMeters(points[index - 1], points[index])
        }
        return total
    }

    private fun distanceMeters(start: Point, end: Point): Double {
        val earthRadius = 6371000.0
        val dLat = Math.toRadians(end.latitude - start.latitude)
        val dLng = Math.toRadians(end.longitude - start.longitude)
        val startLat = Math.toRadians(start.latitude)
        val endLat = Math.toRadians(end.latitude)
        val a = kotlin.math.sin(dLat / 2) * kotlin.math.sin(dLat / 2) +
            kotlin.math.cos(startLat) * kotlin.math.cos(endLat) *
            kotlin.math.sin(dLng / 2) * kotlin.math.sin(dLng / 2)
        val c = 2 * kotlin.math.atan2(kotlin.math.sqrt(a), kotlin.math.sqrt(1 - a))
        return earthRadius * c
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
