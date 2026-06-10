package com.nexusrelay.pixel.sync

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.os.PowerManager
import android.provider.Settings
import androidx.core.content.getSystemService

internal fun isIgnoringBatteryOptimizations(context: Context): Boolean {
    if (Build.VERSION.SDK_INT < Build.VERSION_CODES.M) {
        return true
    }

    val powerManager = context.getSystemService<PowerManager>() ?: return false
    return powerManager.isIgnoringBatteryOptimizations(context.packageName)
}

internal fun batteryOptimizationIntent(context: Context): Intent {
    val appContext = context.applicationContext
    return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M &&
        !isIgnoringBatteryOptimizations(appContext)
    ) {
        Intent(Settings.ACTION_REQUEST_IGNORE_BATTERY_OPTIMIZATIONS).apply {
            data = Uri.parse("package:${appContext.packageName}")
        }
    } else {
        Intent(Settings.ACTION_IGNORE_BATTERY_OPTIMIZATION_SETTINGS)
    }
}
