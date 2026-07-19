package com.whydidiunlock.why_did_i_unlock

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.DisplayMetrics
import android.util.Log
import android.view.WindowManager

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

    /** True full display size in raw pixels (including system bars). */
    private fun getRealScreenSize(context: Context): Pair<Int, Int> {
        val wm = context.getSystemService(Context.WINDOW_SERVICE) as WindowManager
        val metrics = DisplayMetrics()
        @Suppress("DEPRECATION")
        wm.defaultDisplay.getRealMetrics(metrics)
        return Pair(metrics.widthPixels, metrics.heightPixels)
    }
}
