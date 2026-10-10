package com.local.pictorialhomesync;

import android.app.Activity;
import android.os.Bundle;

/** Fallback only — prefer {@link SetService} to avoid visual flash. */
public class SetActivity extends Activity {
    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        String path = getIntent() != null ? getIntent().getStringExtra("path") : null;
        String expect = getIntent() != null ? getIntent().getStringExtra("md5") : null;
        WallpaperApply.apply(this, path, expect);
        finish();
    }
}
