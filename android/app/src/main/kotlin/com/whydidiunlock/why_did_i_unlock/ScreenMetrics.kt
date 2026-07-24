package com.whydidiunlock.why_did_i_unlock

import android.content.Context
import android.os.Build
import android.util.DisplayMetrics
import android.util.Log
import android.view.WindowManager

/**
 * True full display size in raw pixels (including system bars).
 *
 * Shared by [UnlockReceiver] (unlock) and [UnlockListenerService]
 * (orientation): the background Flutter engine is headless and cannot read
 * display metrics itself — see docs/ARCHITECTURE.md.
 *
 * Uses WindowManager.maximumWindowMetrics (API 30+), which is documented as
 * the largest possible bounds regardless of current window/inset state —
 * more robust than Display.getRealMetrics() from a non-Activity context.
 */
object ScreenMetrics {
    fun getRealScreenSize(context: Context): Pair<Int, Int> {
        val wm = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val maxMetrics = wm.maximumWindowMetrics
            val bounds = maxMetrics.bounds
            Log.d(
                "ScreenMetrics",
                "📐 maximumWindowMetrics.bounds = ${bounds.width()}x${bounds.height()}"
            )
            return Pair(bounds.width(), bounds.height())
        }

        val metrics = DisplayMetrics()
        @Suppress("DEPRECATION")
        wm.defaultDisplay.getRealMetrics(metrics)
        Log.d(
            "ScreenMetrics",
            "📐 getRealMetrics (pre-API30) = ${metrics.widthPixels}x${metrics.heightPixels}"
        )
        return Pair(metrics.widthPixels, metrics.heightPixels)
    }
}
