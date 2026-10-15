package dev.beyondtv.beyond_tv

import android.content.ActivityNotFoundException
import android.content.Intent
import android.graphics.Bitmap
import android.net.Uri
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.view.PixelCopy
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import java.io.ByteArrayOutputStream

class MainActivity : FlutterActivity() {
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SCREENSHOT_CHANNEL)
            .setMethodCallHandler { call, result ->
                if (call.method == "capture") {
                    val maxWidth = call.argument<Int>("maxWidth") ?: DEFAULT_MAX_WIDTH
                    captureScreen(maxWidth, result)
                } else {
                    result.notImplemented()
                }
            }
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SYSTEM_CHANNEL)
            .setMethodCallHandler { call, result -> handleSystem(call, result) }
    }

    private fun handleSystem(call: MethodCall, result: MethodChannel.Result) {
        try {
            when (call.method) {
                "getStatus" -> result.success(
                    mapOf(
                        "startOnBoot" to SystemSupport.startOnBoot(this),
                        "canDrawOverlays" to Settings.canDrawOverlays(this),
                        "sdkInt" to Build.VERSION.SDK_INT,
                        "kioskEnabled" to SystemSupport.kioskEnabled(this),
                        "isDefaultLauncher" to SystemSupport.isDefaultLauncher(this),
                    )
                )
                "setStartOnBoot" -> {
                    SystemSupport.setStartOnBoot(this, call.argument<Boolean>("enabled") ?: true)
                    result.success(null)
                }
                "setKioskEnabled" -> {
                    SystemSupport.setKioskEnabled(this, call.argument<Boolean>("enabled") ?: false)
                    result.success(null)
                }
                "openOverlaySettings" -> result.success(
                    openSettings(
                        Intent(
                            Settings.ACTION_MANAGE_OVERLAY_PERMISSION,
                            Uri.parse("package:$packageName")
                        ),
                        null
                    )
                )
                "openHomeSettings" -> result.success(
                    openSettings(Intent(Settings.ACTION_HOME_SETTINGS), Intent(Settings.ACTION_SETTINGS))
                )
                else -> result.notImplemented()
            }
        } catch (e: Exception) {
            result.error("system_failed", e.message, null)
        }
    }

    /** Abre [primary]; sem a tela, tenta [fallback]. `false` se nenhuma existir. */
    private fun openSettings(primary: Intent, fallback: Intent?): Boolean {
        for (intent in listOfNotNull(primary, fallback)) {
            try {
                startActivity(intent)
                return true
            } catch (e: ActivityNotFoundException) {
                // Algumas TVs não têm essa tela; tenta a próxima.
            }
        }
        return false
    }

    /** Captura a janela inteira (inclui WebView e vídeo) e devolve um JPEG. */
    private fun captureScreen(maxWidth: Int, result: MethodChannel.Result) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) {
            result.error("unsupported", "PixelCopy exige Android 8.0 ou superior", null)
            return
        }
        val width = window.decorView.width
        val height = window.decorView.height
        if (width <= 0 || height <= 0) {
            result.error("capture_failed", "Janela sem tamanho", null)
            return
        }
        val bitmap: Bitmap
        try {
            bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        } catch (e: Exception) {
            result.error("capture_failed", e.message, null)
            return
        }
        try {
            PixelCopy.request(
                window,
                bitmap,
                PixelCopy.OnPixelCopyFinishedListener { status ->
                    if (status == PixelCopy.SUCCESS) {
                        compressInBackground(bitmap, maxWidth, result)
                    } else {
                        bitmap.recycle()
                        result.error("capture_failed", "PixelCopy falhou: $status", null)
                    }
                },
                Handler(Looper.getMainLooper())
            )
        } catch (e: Exception) {
            bitmap.recycle()
            result.error("capture_failed", e.message, null)
        }
    }

    /** Reduz e comprime fora da thread principal; responde na thread principal. */
    private fun compressInBackground(bitmap: Bitmap, maxWidth: Int, result: MethodChannel.Result) {
        Thread {
            val outcome: Result<ByteArray> = try {
                Result.success(scaleAndCompress(bitmap, maxWidth))
            } catch (e: Exception) {
                Result.failure(e)
            }
            runOnUiThread {
                outcome.fold(
                    onSuccess = { bytes -> result.success(bytes) },
                    onFailure = { e ->
                        result.error("capture_failed", e.message ?: "erro ao comprimir a imagem", null)
                    },
                )
            }
        }.start()
    }

    private fun scaleAndCompress(bitmap: Bitmap, maxWidth: Int): ByteArray {
        var scaled = bitmap
        try {
            if (maxWidth > 0 && bitmap.width > maxWidth) {
                val newHeight = Math.round(bitmap.height * maxWidth.toFloat() / bitmap.width)
                scaled = Bitmap.createScaledBitmap(bitmap, maxWidth, Math.max(newHeight, 1), true)
            }
            val out = ByteArrayOutputStream()
            if (!scaled.compress(Bitmap.CompressFormat.JPEG, JPEG_QUALITY, out)) {
                throw IllegalStateException("compress retornou false")
            }
            return out.toByteArray()
        } finally {
            if (scaled !== bitmap) scaled.recycle()
            bitmap.recycle()
        }
    }

    companion object {
        private const val SCREENSHOT_CHANNEL = "beyond_tv/screenshot"
        private const val SYSTEM_CHANNEL = "beyond_tv/system"
        private const val DEFAULT_MAX_WIDTH = 1280
        private const val JPEG_QUALITY = 70
    }
}
