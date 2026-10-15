package dev.beyondtv.beyond_tv

import android.content.ActivityNotFoundException
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Canvas
import android.view.SurfaceView
import android.view.View
import android.view.ViewGroup
import android.webkit.WebView
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
        val remoteInput = RemoteInput(this, flutterEngine)
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, RemoteInput.CHANNEL)
            .setMethodCallHandler { call, result -> remoteInput.handle(call, result) }
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

    /**
     * Captura a tela e devolve um JPEG.
     *
     * O Flutter desenha tudo (inclusive a WebView e o vídeo, como texturas)
     * numa SurfaceView, que é uma camada separada da janela: copiar a janela
     * sai preto. Por isso copia a própria SurfaceView. Se mesmo assim vier
     * preto e houver uma WebView, desenha a WebView direto.
     */
    private fun captureScreen(maxWidth: Int, result: MethodChannel.Result) {
        val surface = findView(window.decorView) { it is SurfaceView && it.isShown } as SurfaceView?
        val source: View = surface ?: window.decorView
        val width = source.width
        val height = source.height
        if (width <= 0 || height <= 0) {
            result.error("capture_failed", "Tela sem tamanho", null)
            return
        }
        val bitmap: Bitmap
        try {
            bitmap = Bitmap.createBitmap(width, height, Bitmap.Config.ARGB_8888)
        } catch (e: Exception) {
            result.error("capture_failed", e.message, null)
            return
        }
        val onCopied = PixelCopy.OnPixelCopyFinishedListener { status ->
            when {
                status != PixelCopy.SUCCESS -> {
                    bitmap.recycle()
                    captureWebView(maxWidth, result, "PixelCopy: $status")
                }
                isMostlyBlack(bitmap) && hasWebView() -> {
                    bitmap.recycle()
                    captureWebView(maxWidth, result, "cópia preta")
                }
                // Tela escura de verdade (ex.: "Aguardando conteúdo").
                else -> compressInBackground(bitmap, maxWidth, result)
            }
        }
        try {
            when {
                surface != null -> PixelCopy.request(surface, bitmap, onCopied, Handler(Looper.getMainLooper()))
                Build.VERSION.SDK_INT >= Build.VERSION_CODES.O ->
                    PixelCopy.request(window, bitmap, onCopied, Handler(Looper.getMainLooper()))
                else -> {
                    bitmap.recycle()
                    captureWebView(maxWidth, result, "sem SurfaceView")
                }
            }
        } catch (e: Exception) {
            bitmap.recycle()
            captureWebView(maxWidth, result, e.message ?: "erro")
        }
    }

    private fun findWebView(): View? =
        findView(window.decorView) { it is WebView && it.width > 0 && it.height > 0 }

    private fun hasWebView(): Boolean = findWebView() != null

    /** Reserva: desenha a WebView visível num bitmap. */
    private fun captureWebView(maxWidth: Int, result: MethodChannel.Result, reason: String) {
        val webView = findWebView()
        if (webView == null) {
            result.error("capture_failed", "Captura falhou ($reason) e não há site na tela", null)
            return
        }
        try {
            val bitmap = Bitmap.createBitmap(webView.width, webView.height, Bitmap.Config.ARGB_8888)
            webView.draw(Canvas(bitmap))
            compressInBackground(bitmap, maxWidth, result)
        } catch (e: Exception) {
            result.error("capture_failed", e.message, null)
        }
    }

    /** Primeira view da árvore de [root] que satisfaz [match]. */
    private fun findView(root: View, match: (View) -> Boolean): View? {
        if (match(root)) return root
        if (root is ViewGroup) {
            for (i in 0 until root.childCount) {
                findView(root.getChildAt(i), match)?.let { return it }
            }
        }
        return null
    }

    /** Amostra uma grade de pixels: tela preta (ou quase) é falha de captura. */
    private fun isMostlyBlack(bitmap: Bitmap): Boolean {
        val steps = 16
        for (i in 1 until steps) {
            for (j in 1 until steps) {
                val pixel = bitmap.getPixel(bitmap.width * i / steps, bitmap.height * j / steps)
                val r = (pixel shr 16) and 0xFF
                val g = (pixel shr 8) and 0xFF
                val b = pixel and 0xFF
                if (r + g + b > 30) return false
            }
        }
        return true
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
