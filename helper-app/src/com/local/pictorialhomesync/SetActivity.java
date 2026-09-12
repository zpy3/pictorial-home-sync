package com.local.pictorialhomesync;

import android.app.Activity;
import android.app.WallpaperManager;
import android.os.Bundle;
import android.util.Log;
import java.io.File;
import java.io.FileInputStream;

public class SetActivity extends Activity {
    private static final String TAG = "PictorialHomeSync";
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        String path = getIntent() != null ? getIntent().getStringExtra("path") : null;
        if (path == null || path.length() == 0) {
            path = "/data/data/com.local.pictorialhomesync/files/wall.jpg";
        }
        try {
            File f = new File(path);
            if (f.exists() && f.length() > 1024) {
                FileInputStream in = new FileInputStream(f);
                WallpaperManager.getInstance(this).setStream(in, null, true, WallpaperManager.FLAG_SYSTEM);
                in.close();
                Log.i(TAG, "SetActivity OK " + f.length());
            }
        } catch (Throwable t) {
            Log.e(TAG, "SetActivity fail", t);
        }
        finish();
    }
}