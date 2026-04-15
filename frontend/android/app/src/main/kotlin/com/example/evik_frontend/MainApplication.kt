package com.example.evik_frontend

import android.app.Application
import android.content.pm.PackageManager
import android.util.Log
import com.yandex.mapkit.MapKitFactory

class MainApplication : Application() {
    override fun onCreate() {
        super.onCreate()

        val apiKey = readMapKitApiKey()
        if (apiKey.isBlank() || apiKey == "MISSING_KEY") {
            Log.w(TAG, "YANDEX_MAPKIT_API_KEY is missing. Falling back to placeholder map.")
            isMapKitInitialized = false
            return
        }

        try {
            MapKitFactory.setApiKey(apiKey)
            MapKitFactory.initialize(this)
            isMapKitInitialized = true
            Log.i(TAG, "Yandex MapKit initialized.")
        } catch (t: Throwable) {
            Log.e(TAG, "Failed to initialize Yandex MapKit", t)
            isMapKitInitialized = false
        }
    }

    private fun readMapKitApiKey(): String {
        return try {
            val appInfo = packageManager.getApplicationInfo(packageName, PackageManager.GET_META_DATA)
            appInfo.metaData?.getString("com.yandex.mapkit.API_KEY").orEmpty().trim()
        } catch (t: Throwable) {
            Log.e(TAG, "Failed to read MapKit API key from manifest", t)
            ""
        }
    }

    companion object {
        private const val TAG = "EVIK.MainApplication"

        @JvmStatic
        var isMapKitInitialized: Boolean = false
            private set
    }
}
