package com.local.pictorialhomesync;

import android.content.Context;
import android.os.Looper;
import android.util.Log;
import java.lang.reflect.Method;

/**
 * Root/Magisk entry via {@code app_process}. No Activity, no flash.
 *
 * Usage:
 *   CLASSPATH=...apk app_process /system/bin com.local.pictorialhomesync.WallpaperCli &lt;path&gt; &lt;md5&gt;
 */
public final class WallpaperCli {
    private static final String TAG = "PictorialHomeSync";

    public static void main(String[] args) {
        String path = args != null && args.length > 0 ? args[0] : null;
        String md5 = args != null && args.length > 1 ? args[1] : null;
        int code = 1;
        try {
            Looper.prepareMainLooper();
            Class<?> atClz = Class.forName("android.app.ActivityThread");
            Method systemMain = atClz.getMethod("systemMain");
            Object at = systemMain.invoke(null);
            Method getSysCtx = atClz.getMethod("getSystemContext");
            Context ctx = (Context) getSysCtx.invoke(at);
            if (ctx == null) {
                Method curApp = atClz.getMethod("currentApplication");
                ctx = (Context) curApp.invoke(null);
            }
            if (ctx == null) {
                Log.e(TAG, "WallpaperCli: no context");
                System.exit(2);
                return;
            }
            Context pkg = null;
            try {
                pkg = ctx.createPackageContext(
                        "com.local.pictorialhomesync", Context.CONTEXT_IGNORE_SECURITY);
            } catch (Throwable ignored) {
            }
            String err = WallpaperApply.apply(pkg != null ? pkg : ctx, path, md5);
            code = (err == null) ? 0 : 3;
            if (err != null) Log.e(TAG, "WallpaperCli fail: " + err);
            else Log.i(TAG, "WallpaperCli OK md5=" + md5);
        } catch (Throwable t) {
            Log.e(TAG, "WallpaperCli crash", t);
            t.printStackTrace();
            code = 4;
        }
        System.exit(code);
    }

    private WallpaperCli() {}
}
