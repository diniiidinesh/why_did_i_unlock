package com.whydidiunlock.why_did_i_unlock

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.DisplayMetrics
import android.util.Log
import android.view.WindowManager
import android.os.Build

class UnlockReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        Log.d("UnlockReceiver", "🔓 onReceive fired: ${intent.action}")
        when (intent.action) {
            Intent.ACTION_USER_PRESENT -> {
                Log.d("UnlockReceiver", "✅ ACTION_USER_PRESENT confirmed")
                // The unlock reaction runs in the HEADLESS background engine,
                // which has no display surface — so Flutter's PlatformDispatcher
                // reports a 0x0 physical size there. Compute the true screen
                // size natively (always available from a Context) and hand it to
                // Dart so it can size the full-screen capture overlay correctly.
                val (width, height) = getRealScreenSize(context)
                UnlockListenerService.onPhoneUnlocked(width, height)
            }
            Intent.ACTION_SCREEN_OFF -> {
                Log.d("UnlockReceiver", "🔒 ACTION_SCREEN_OFF confirmed")
                UnlockListenerService.onPhoneLocked()
            }
        }
    }

    /**
     * True full display size in raw pixels (including system bars).
     *
     * Uses WindowManager.maximumWindowMetrics (API 30+), which is explicitly
     * documented as the largest possible bounds regardless of current window/
     * inset state — more robust than the older Display.getRealMetrics(), which
     * has a history of inconsistent behavior when called from a non-Activity
     * (Service) context, which is exactly our situation here. Falls back to
     * getRealMetrics on pre-API-30 devices.
     */
    private fun getRealScreenSize(context: Context): Pair<Int, Int> {
        val wm = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager

        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            val maxMetrics = wm.maximumWindowMetrics
            val bounds = maxMetrics.bounds
            Log.d(
                "UnlockReceiver",
                "📐 maximumWindowMetrics.bounds = ${bounds.width()}x${bounds.height()}"
            )
            // Diagnostic only: compare against currentWindowMetrics + its insets,
            // in case the discrepancy is coming from somewhere other than the
            // choice of metrics API.
            val curMetrics = wm.currentWindowMetrics
            val curBounds = curMetrics.bounds
            val insets = curMetrics.windowInsets.getInsetsIgnoringVisibility(
                android.view.WindowInsets.Type.systemBars()
            )
            Log.d(
                "UnlockReceiver",
                "📐 currentWindowMetrics.bounds = ${curBounds.width()}x${curBounds.height()}, " +
                    "systemBars insets (L,T,R,B) = ${insets.left},${insets.top},${insets.right},${insets.bottom}"
            )
            return Pair(bounds.width(), bounds.height())
        }

        val metrics = DisplayMetrics()
        @Suppress("DEPRECATION")
        wm.defaultDisplay.getRealMetrics(metrics)
        Log.d(
            "UnlockReceiver",
            "📐 getRealMetrics (pre-API30 fallback) = ${metrics.widthPixels}x${metrics.heightPixels}"
        )
        return Pair(metrics.widthPixels, metrics.heightPixels)
    }
}
