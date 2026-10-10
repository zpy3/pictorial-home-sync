package com.local.pictorialhomesync;

import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.util.Log;

/**
 * Explicit broadcast entry. ColorOS 17 blocks {@code am start-service} from shell,
 * but an in-app {@link Context#startService} from this receiver works.
 */
public class SetReceiver extends BroadcastReceiver {
    private static final String TAG = "PictorialHomeSync";

    @Override
    public void onReceive(Context context, Intent intent) {
        final PendingResult pr = goAsync();
        final String path = intent != null ? intent.getStringExtra("path") : null;
        final String md5 = intent != null ? intent.getStringExtra("md5") : null;
        // Prefer starting our Service (not subject to shell start-service block)
        try {
            Intent svc = new Intent(context, SetService.class);
            if (path != null) svc.putExtra("path", path);
            if (md5 != null) svc.putExtra("md5", md5);
            context.startService(svc);
            pr.finish();
            return;
        } catch (Throwable t) {
            Log.w(TAG, "startService failed, apply inline", t);
        }
        new Thread(() -> {
            try {
                String err = WallpaperApply.apply(context, path, md5);
                if (err != null) Log.e(TAG, "SetReceiver fail: " + err);
            } finally {
                pr.finish();
            }
        }, "phs-set").start();
    }
}
