package com.whydidiunlock.why_did_i_unlock

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Restarts the foreground service (and with it, the persistent background
 * engine — see UnlockListenerService) after the device reboots. Without this,
 * the app is completely asleep after any restart until the user manually
 * reopens it.
 *
 * Listens for LOCKED_BOOT_COMPLETED (fires BEFORE the first post-reboot
 * unlock, direct-boot-aware components only — see the directBootAware note
 * in AndroidManifest.xml) plus the standard BOOT_COMPLETED and OEM "quick
 * boot" variants as a fallback/redundant trigger (harmless if it fires
 * twice on one boot — UnlockListenerService's engine-cache guard and normal
 * Service.onCreate() semantics make the second call a no-op).
 *
 * This does NOT help on OEMs (Xiaomi/Oppo/Vivo) that block auto-start
 * entirely unless the user has manually granted it in that OEM's own
 * settings — that's a separate, not-yet-built onboarding task (P1 backlog).
 * See docs/ARCHITECTURE.md.
 */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        Log.d("WDIUBoot", "📦 onReceive fired: ${intent.action}")
        when (intent.action) {
            Intent.ACTION_LOCKED_BOOT_COMPLETED,
            Intent.ACTION_BOOT_COMPLETED,
            "android.intent.action.QUICKBOOT_POWERON",
            "com.htc.intent.action.QUICKBOOT_POWERON" -> {
                Log.d("WDIUBoot", "🔁 Restarting UnlockListenerService after boot")
                context.startForegroundService(Intent(context, UnlockListenerService::class.java))
            }
        }
    }
}
