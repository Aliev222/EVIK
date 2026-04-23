package com.example.evik_frontend

import android.app.Activity
import android.content.Context
import android.util.Log
import android.view.Gravity
import android.view.View
import android.widget.FrameLayout
import android.widget.TextView
import com.yandex.mapkit.Animation
import com.yandex.mapkit.RequestPoint
import com.yandex.mapkit.RequestPointType
import com.yandex.mapkit.directions.DirectionsFactory
import com.yandex.mapkit.directions.driving.DrivingOptions
import com.yandex.mapkit.directions.driving.DrivingRoute
import com.yandex.mapkit.directions.driving.DrivingRouter
import com.yandex.mapkit.directions.driving.DrivingRouterType
import com.yandex.mapkit.directions.driving.DrivingSession
import com.yandex.mapkit.directions.driving.VehicleOptions
import com.yandex.mapkit.geometry.Point
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
    private var drivingRouter: DrivingRouter? = null
    private var drivingSession: DrivingSession? = null

    init {
        if (MainApplication.isMapKitInitialized) {
            try {
                mapView = MapView(context)
                mapView?.onStart()
                drivingRouter =
                    DirectionsFactory.getInstance().createDrivingRouter(DrivingRouterType.ONLINE)

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
            drivingSession?.cancel()
            drivingSession = null
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

            val requestPoints = points.map { point ->
                RequestPoint(point, RequestPointType.WAYPOINT, "", "")
            }

            drivingSession?.cancel()
            drivingSession = drivingRouter?.requestRoutes(
                requestPoints,
                DrivingOptions(),
                VehicleOptions(),
                object : DrivingSession.DrivingRouteListener {
                    override fun onDrivingRoutes(routes: MutableList<DrivingRoute>) {
                        activity.runOnUiThread {
                            val current = mapView ?: return@runOnUiThread
                            val route = routes.firstOrNull()
                            if (route == null) {
                                clearRouteInternal(current)
                                dispatchRouteSummary(null, null)
                                return@runOnUiThread
                            }
                            clearRouteInternal(current)
                            routeObject = current.mapWindow.map.mapObjects
                                .addPolyline(route.geometry)
                                .apply { applyRouteStyle(this) }
                            focusRoute(current, route.geometry.points)
                            dispatchRouteSummary(
                                extractRouteDistanceMeters(route),
                                extractRouteDurationSeconds(route)
                            )
                        }
                    }

                    override fun onDrivingRoutesError(error: Error) {
                        Log.w(TAG, "Driving route request failed: ${error.javaClass.simpleName}: $error")
                        activity.runOnUiThread {
                            val current = mapView ?: return@runOnUiThread
                            clearRouteInternal(current)
                            dispatchRouteSummary(null, null)
                        }
                    }
                }
            )
            if (drivingSession == null) {
                clearRouteInternal(mv)
                dispatchRouteSummary(null, null)
            }
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

    private fun extractRouteDistanceMeters(route: DrivingRoute): Double? {
        return extractNestedDouble(route, listOf("metadata", "weight", "distance", "value"))
    }

    private fun extractRouteDurationSeconds(route: DrivingRoute): Double? {
        return extractNestedDouble(route, listOf("metadata", "weight", "time", "value"))
    }

    private fun extractNestedDouble(root: Any?, path: List<String>): Double? {
        var current: Any? = root
        for (property in path) {
            current = readProperty(current, property) ?: return null
        }
        return when (current) {
            is Number -> current.toDouble()
            else -> null
        }
    }

    private fun readProperty(target: Any?, property: String): Any? {
        if (target == null) return null
        val capitalized = property.replaceFirstChar { if (it.isLowerCase()) it.titlecase() else it.toString() }
        val getterNames = listOf("get$capitalized", property)
        for (name in getterNames) {
            val method = target.javaClass.methods.firstOrNull {
                it.name == name && it.parameterCount == 0
            } ?: continue
            try {
                return method.invoke(target)
            } catch (_: Throwable) {
                // Try next candidate method.
            }
        }
        return null
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
