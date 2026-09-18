package com.local.pictorialhomesync;

import android.app.Activity;
import android.app.WallpaperManager;
import android.os.Bundle;
import android.util.Log;
import java.io.File;
import java.io.FileInputStream;
import java.io.FileOutputStream;

public class SetActivity extends Activity {
    private static final String TAG = "PictorialHomeSync";

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        String path = getIntent() != null ? getIntent().getStringExtra("path") : null;
        if (path == null || path.length() == 0) {
            path = "/data/data/com.local.pictorialhomesync/files/wall.jpg";
        }
        String expect = getIntent() != null ? getIntent().getStringExtra("md5") : null;
        File ok = new File(getFilesDir(), "last_ok");
        File fail = new File(getFilesDir(), "last_fail");
        try {
            File f = new File(path);
            if (f.exists() && f.length() > 1024) {
                FileInputStream in = new FileInputStream(f);
                WallpaperManager.getInstance(this).setStream(
                        in, null, true, WallpaperManager.FLAG_SYSTEM);
                in.close();
                writeText(ok, (expect != null ? expect : String.valueOf(f.length())) + "\n");
                fail.delete();
                Log.i(TAG, "SetActivity OK len=" + f.length() + " md5=" + expect);
            } else {
                writeText(fail, "missing\n");
                Log.e(TAG, "SetActivity missing file " + path);
            }
        } catch (Throwable t) {
            try { writeText(fail, t.getClass().getSimpleName() + "\n"); } catch (Throwable ignored) {}
            Log.e(TAG, "SetActivity fail", t);
        }
        finish();
    }

    private static void writeText(File file, String text) throws Exception {
        FileOutputStream out = new FileOutputStream(file, false);
        out.write(text.getBytes("UTF-8"));
        out.close();
    }
}
