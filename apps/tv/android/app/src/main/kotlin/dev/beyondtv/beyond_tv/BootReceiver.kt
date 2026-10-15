package dev.beyondtv.beyond_tv

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Build
import android.provider.Settings
import android.util.Log

/** Reabre o app ao ligar a TV e após atualizar o app, se a opção estiver ativa. */
class BootReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent?) {
        val action = intent?.action
        if (action != Intent.ACTION_BOOT_COMPLETED && action != Intent.ACTION_MY_PACKAGE_REPLACED) {
            return
        }
        try {
            if (!SystemSupport.startOnBoot(context)) return
            // No Android 10+ abrir activity em segundo plano é bloqueado, salvo
            // com "sobrepor a outros apps" ou sendo o launcher padrão.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q &&
                !Settings.canDrawOverlays(context) &&
                !SystemSupport.isDefaultLauncher(context)
            ) {
                Log.w(TAG, "Sem permissão de sobreposição nem launcher padrão; não abre")
                return
            }
            val launch = Intent(context, MainActivity::class.java)
                .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            context.startActivity(launch)
        } catch (e: Exception) {
            Log.w(TAG, "Falha ao abrir o app após $action", e)
        }
    }

    companion object {
        private const val TAG = "BootReceiver"
    }
}
