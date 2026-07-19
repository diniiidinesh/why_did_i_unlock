package com.whydidiunlock.why_did_i_unlock

import android.content.Intent
import android.os.Bundle
import io.flutter.embedding.android.FlutterActivity

/**
 * Launcher activity — hosts the settings/permission UI only.
 *
 * It intentionally no longer owns the unlock method channel: unlock/lock events
 * are handled by the persistent background engine hosted in
 * UnlockListenerService, so they keep working after this Activity (and its
 * engine) is destroyed by a swipe-away. All this does is kick the foreground
 * service alive on launch. See docs/ARCHITECTURE.md.
 */
class MainActivity : FlutterActivity() {

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        startForegroundService(Intent(this, UnlockListenerService::class.java))
    }
}