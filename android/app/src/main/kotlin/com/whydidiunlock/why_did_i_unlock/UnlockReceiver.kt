package com.whydidiunlock.why_did_i_unlock

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.util.Log

class UnlockReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        Log.d("UnlockReceiver", "🔓 onReceive fired: ${intent.action}")
        if (intent.action == Intent.ACTION_USER_PRESENT) {
            Log.d("UnlockReceiver", "✅ ACTION_USER_PRESENT confirmed")
            MainActivity.onPhoneUnlocked()
        }
    }
}