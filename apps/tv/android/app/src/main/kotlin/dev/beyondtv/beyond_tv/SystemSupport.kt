package dev.beyondtv.beyond_tv

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager

/** Preferências e consultas do sistema compartilhadas entre a activity e o BootReceiver. */
object SystemSupport {
    const val PREFS = "beyond_tv_system"
    const val KEY_START_ON_BOOT = "start_on_boot"
    const val KIOSK_ALIAS = "dev.beyondtv.beyond_tv.KioskLauncher"

    fun startOnBoot(context: Context): Boolean =
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .getBoolean(KEY_START_ON_BOOT, true)

    fun setStartOnBoot(context: Context, value: Boolean) {
        context.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
            .edit()
            .putBoolean(KEY_START_ON_BOOT, value)
            .apply()
    }

    fun kioskEnabled(context: Context): Boolean {
        val state = context.packageManager.getComponentEnabledSetting(
            ComponentName(context, KIOSK_ALIAS)
        )
        return state == PackageManager.COMPONENT_ENABLED_STATE_ENABLED
    }

    fun setKioskEnabled(context: Context, enabled: Boolean) {
        val state = if (enabled) {
            PackageManager.COMPONENT_ENABLED_STATE_ENABLED
        } else {
            PackageManager.COMPONENT_ENABLED_STATE_DISABLED
        }
        context.packageManager.setComponentEnabledSetting(
            ComponentName(context, KIOSK_ALIAS),
            state,
            PackageManager.DONT_KILL_APP
        )
    }

    /** `true` se o launcher padrão (HOME) do sistema é este app. */
    fun isDefaultLauncher(context: Context): Boolean {
        val intent = Intent(Intent.ACTION_MAIN).addCategory(Intent.CATEGORY_HOME)
        val info = context.packageManager.resolveActivity(intent, PackageManager.MATCH_DEFAULT_ONLY)
        return info?.activityInfo?.packageName == context.packageName
    }
}
