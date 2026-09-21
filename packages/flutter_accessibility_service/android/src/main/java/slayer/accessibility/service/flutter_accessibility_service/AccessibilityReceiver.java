package slayer.accessibility.service.flutter_accessibility_service;

import static android.content.Context.MODE_PRIVATE;
import static slayer.accessibility.service.flutter_accessibility_service.Constants.*;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;
import android.util.Log;

import io.flutter.plugin.common.EventChannel;

public class AccessibilityReceiver extends BroadcastReceiver {

    private volatile EventChannel.EventSink eventSink;

    public AccessibilityReceiver(EventChannel.EventSink eventSink) {
        this.eventSink = eventSink;
    }

    public void setEventSink(EventChannel.EventSink sink) {
        this.eventSink = sink;
    }

    @Override
    public void onReceive(Context context, Intent intent) {
        EventChannel.EventSink sink = eventSink;
        if (sink == null) return;
        // LOCAL PATCH: take the payload from the in-process queue. Reading it back from the
        // shared slot means a later event can overwrite this one before we get here; putting it
        // on the Intent instead would expose it to every app on the device (see the queue's
        // declaration in AccessibilityListener).
        String json = AccessibilityListener.PAYLOADS.poll();
        if (json == null || json.isEmpty()) {
            SharedPreferences sharedPreferences = context.getSharedPreferences(SHARED_PREFS_TAG, MODE_PRIVATE);
            json = sharedPreferences.getString(ACCESSIBILITY_NODE, "");
        }
        try {
            sink.success(json);
        } catch (Exception e) {
            Log.w("AccessibilityReceiver", "Failed to deliver event, engine may be detached: " + e.getMessage());
        }
    }
}
