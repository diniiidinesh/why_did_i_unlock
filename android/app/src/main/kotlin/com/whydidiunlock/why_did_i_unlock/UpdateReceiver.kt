package com.whydidiunlock.why_did_i_unlock

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

/**
 * Restarts the foreground service (and with it, the persistent background
 * engine — see UnlockListenerService) immediately after the app itself is
 * updated.
 *
 * Installing an update always kills every running process of the app being
 * updated — the OS cannot hot-swap running code — so UnlockListenerService
 * dies along with everything else. This is a DIFFERENT mechanism from the
 * reboot case BootReceiver handles: an update does NOT put the app into
 * Android's "stopped" broadcast-withholding state (that state is reserved
 * for apps never launched, or explicitly force-stopped by the user), so no
 * directBootAware handling is needed here — the app is still considered
 * "launched" from the OS's perspective. The problem is simpler and more
 * direct: the process is dead, and nothing restarts it unless something
 * listens for ACTION_MY_PACKAGE_REPLACED, which is exactly what this class
 * does.
 *
 * Without this, every real-world update — a Play Store push during the
 * closed test, or a manually installed newer APK — leaves monitoring dead
 * until the user happens to reopen the app, with no indication anything is
 * wrong. Confirmed missing and added 2026-07-23, found via an on-device
 * build push during Sprint 4 (dev builds via `flutter run` never exposed
 * this gap, since `flutter run` auto-launches the app after installing —
 * see docs/TEST_PLAN.md for the on-device case that actually exercises it).
 *
 * No RECEIVE_BOOT_COMPLETED-style permission needed: MY_PACKAGE_REPLACED is
 * a protected broadcast the OS delivers only to receivers inside the very
 * package that was just updated, so no other app can spoof or intercept it.
 */
class UpdateReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        if (intent.action == Intent.ACTION_MY_PACKAGE_REPLACED) {
            Log.d("WDIUUpdate", "🔁 Restarting UnlockListenerService after app update")
            context.startForegroundService(Intent(context, UnlockListenerService::class.java))
        }
    }
}
