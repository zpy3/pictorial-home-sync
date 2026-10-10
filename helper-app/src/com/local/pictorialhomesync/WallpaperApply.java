package com.local.pictorialhomesync;

import android.app.WallpaperManager;
import android.content.Context;
import android.util.Log;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;

final class WallpaperApply {
    private static final String TAG = "PictorialHomeSync";

    private WallpaperApply() {}

    /** @return null on success, otherwise a short error token */
    static String apply(Context ctx, String path, String expectMd5) {
        File ok = new File(ctx.getFilesDir(), "last_ok");
        File fail = new File(ctx.getFilesDir(), "last_fail");
        try {
            if (path == null || path.length() == 0) {
                path = "/data/data/com.local.pictorialhomesync/files/wall.jpg";
            }
            File f = new File(path);
            if (!f.exists() || f.length() <= 1024) {
                writeText(fail, "missing\n");
                return "missing";
            }
            long t0 = System.nanoTime();
            FileInputStream in = new FileInputStream(f);
            try {
                // allowBackup=false — skip ColorOS backup duplicate write
                WallpaperManager.getInstance(ctx).setStream(
                        in, null, false, WallpaperManager.FLAG_SYSTEM);
            } finally {
                in.close();
            }
            long ms = (System.nanoTime() - t0) / 1000000L;
            writeText(ok, (expectMd5 != null ? expectMd5 : String.valueOf(f.length())) + "\n");
            //noinspection ResultOfMethodCallIgnored
            fail.delete();
            Log.i(TAG, "apply OK setStreamMs=" + ms + " len=" + f.length() + " md5=" + expectMd5);
            return null;
        } catch (Throwable t) {
            try {
                writeText(fail, t.getClass().getSimpleName() + "\n");
            } catch (Throwable ignored) {
            }
            Log.e(TAG, "apply fail", t);
            return t.getClass().getSimpleName();
        }
    }

    private static void writeText(File file, String text) throws Exception {
        FileOutputStream out = new FileOutputStream(file, false);
        out.write(text.getBytes("UTF-8"));
        out.close();
    }
}
