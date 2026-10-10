package com.local.pictorialhomesync;

import android.app.Service;
import android.content.Intent;
import android.os.IBinder;
import android.util.Log;

/**
 * Headless wallpaper apply — no Activity, no unlock flash.
 * Started from Magisk daemon via {@code am start-service}.
 */
public class SetService extends Service {
    private static final String TAG = "PictorialHomeSync";

    @Override
    public int onStartCommand(Intent intent, int flags, int startId) {
        String path = intent != null ? intent.getStringExtra("path") : null;
        String md5 = intent != null ? intent.getStringExtra("md5") : null;
        String err = WallpaperApply.apply(this, path, md5);
        if (err != null) {
            Log.e(TAG, "SetService fail: " + err);
        }
        stopSelf(startId);
        return START_NOT_STICKY;
    }

    @Override
    public IBinder onBind(Intent intent) {
        return null;
    }
}
