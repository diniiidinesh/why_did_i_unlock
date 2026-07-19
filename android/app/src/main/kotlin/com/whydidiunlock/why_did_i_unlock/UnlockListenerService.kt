package com.whydidiunlock.why_did_i_unlock

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Intent
import android.content.IntentFilter
import android.os.IBinder
import io.flutter.FlutterInjector
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.embedding.engine.FlutterEngineCache
import io.flutter.embedding.engine.dart.DartExecutor
import io.flutter.plugin.common.MethodChannel

/**
 * Foreground service that (a) listens for lock/unlock system broadcasts and
 * (b) HOSTS THE PERSISTENT BACKGROUND FLUTTER ENGINE.
 *
 * Why the engine lives here and not in MainActivity: when the user swipes the
 * app out of Recents, MainActivity (and its Flutter engine) is destroyed, but
 * this foreground service survives — so the unlock-reaction logic must run in
 * an engine tied to the service's lifecycle, not the Activity's. That engine
 * runs the `backgroundMain` Dart entry point and, because it auto-registers
 * plugins, can call `flutter_overlay_window` (showOverlay) even with no
 * Activity alive. See docs/ARCHITECTURE.md for the full engine topology.
 */
class UnlockListenerService : Service() {

    private lateinit var unlockReceiver: UnlockReceiver

    companion object {
        private const val CHANNEL_ID = "unlock_listener"
        private const val NOTIFICATION_ID = 1
        private const val BG_ENGINE_ID = "wdiu_background_engine"
        private const val METHOD_CHANNEL = "com.whydidiunlock/unlock"

        // Set once the background engine is up; UnlockReceiver invokes through it.
        private var methodChannel: MethodChannel? = null

        // Screen size is passed from native because the background engine is
        // headless and can't read display metrics itself (see UnlockReceiver).
        fun onPhoneUnlocked(width: Int, height: Int) {
            methodChannel?.invokeMethod(
                "onUnlock",
                mapOf("width" to width, "height" to height)
            )
        }

        fun onPhoneLocked() {
            methodChannel?.invokeMethod("onLock", null)
        }
    }

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
        startForeground(NOTIFICATION_ID, buildNotification())
        ensureBackgroundEngine()
        unlockReceiver = UnlockReceiver()
        val filter = IntentFilter().apply {
            addAction(Intent.ACTION_USER_PRESENT)
            addAction(Intent.ACTION_SCREEN_OFF)
        }
        registerReceiver(unlockReceiver, filter)
    }

    /**
     * Create (or reuse across START_STICKY restarts) the background engine and
     * wire the method channel UnlockReceiver invokes. Cached so a service
     * restart doesn't spin up a second background isolate.
     */
    private fun ensureBackgroundEngine() {
        var engine = FlutterEngineCache.getInstance().get(BG_ENGINE_ID)
        if (engine == null) {
            // Constructing the engine also starts the Flutter loader if needed
            // and auto-registers plugins (so showOverlay works from Dart here).
            engine = FlutterEngine(applicationContext)
            val entrypoint = DartExecutor.DartEntrypoint(
                FlutterInjector.instance().flutterLoader().findAppBundlePath(),
                "backgroundMain"
            )
            engine.dartExecutor.executeDartEntrypoint(entrypoint)
            FlutterEngineCache.getInstance().put(BG_ENGINE_ID, engine)
        }
        methodChannel = MethodChannel(engine.dartExecutor.binaryMessenger, METHOD_CHANNEL)
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        return START_STICKY
    }

    override fun onDestroy() {
        super.onDestroy()
        unregisterReceiver(unlockReceiver)
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Unlock Listener",
            NotificationManager.IMPORTANCE_MIN
        ).apply {
            setShowBadge(false)
        }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    private fun buildNotification(): Notification {
        return Notification.Builder(this, CHANNEL_ID)
            .setContentTitle("Why Did I Unlock?")
            .setContentText("Monitoring unlock events")
            .setSmallIcon(android.R.drawable.ic_lock_idle_lock)
            .setOngoing(true)
            .build()
    }
}
