package dev.beyondtv.beyond_tv

import android.app.Activity
import android.content.Context
import android.os.SystemClock
import android.view.InputDevice
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.inputmethod.InputMethodManager
import android.webkit.WebView
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugins.webviewflutter.WebViewFlutterAndroidExternalApi

/**
 * Controle remoto do site aberto: injeta toques, teclas e rolagem na WebView
 * do `webview_flutter`, como se alguém usasse a tela da TV.
 *
 * O texto não passa por aqui: entra pelo `insertText` do navegador, no Dart.
 */
class RemoteInput(private val activity: Activity, private val engine: FlutterEngine) {

    fun handle(call: MethodCall, result: MethodChannel.Result) {
        val id = call.argument<Number>("webViewId")?.toLong()
        @Suppress("DEPRECATION")
        val webView = id?.let { WebViewFlutterAndroidExternalApi.getWebView(engine, it) }
        if (webView == null || webView.width <= 0 || webView.height <= 0) {
            result.error("no_webview", "O site ainda não está na tela.", null)
            return
        }
        try {
            when (call.method) {
                "tap" -> tap(webView, fraction(call, "x"), fraction(call, "y"))
                "key" -> key(webView, call.argument<String>("key") ?: "")
                "scroll" -> scroll(
                    webView,
                    fraction(call, "x"),
                    fraction(call, "y"),
                    call.argument<Number>("dy")?.toFloat() ?: 0f,
                )
                else -> {
                    result.notImplemented()
                    return
                }
            }
            result.success(null)
        } catch (e: IllegalArgumentException) {
            result.error("bad_input", e.message, null)
        } catch (e: Exception) {
            result.error("input_failed", e.message, null)
        }
    }

    private fun fraction(call: MethodCall, name: String): Float {
        val value = call.argument<Number>(name)?.toFloat()
            ?: throw IllegalArgumentException("$name ausente")
        return value.coerceIn(0f, 1f)
    }

    private fun tap(webView: WebView, x: Float, y: Float) {
        val px = x * (webView.width - 1)
        val py = y * (webView.height - 1)
        val down = SystemClock.uptimeMillis()
        dispatchTouch(webView, down, down, MotionEvent.ACTION_DOWN, px, py)
        dispatchTouch(webView, down, down + TAP_MS, MotionEvent.ACTION_UP, px, py)
        hideKeyboardSoon(webView)
    }

    /** Arrasta o dedo [dy] telas para cima (positivo desce a página). */
    private fun scroll(webView: WebView, x: Float, y: Float, dy: Float) {
        val px = x * (webView.width - 1)
        val startY = y * (webView.height - 1)
        val distance = -dy * webView.height
        val down = SystemClock.uptimeMillis()
        dispatchTouch(webView, down, down, MotionEvent.ACTION_DOWN, px, startY)
        for (step in 1..SCROLL_STEPS) {
            val py = startY + distance * step / SCROLL_STEPS
            dispatchTouch(webView, down, down + step * STEP_MS, MotionEvent.ACTION_MOVE, px, py)
        }
        // Uma pausa antes de soltar evita o "fling", que rolaria demais.
        val end = down + SCROLL_STEPS * STEP_MS + 150
        dispatchTouch(webView, down, end, MotionEvent.ACTION_UP, px, startY + distance)
    }

    private fun key(webView: WebView, name: String) {
        if (name == "back") {
            if (webView.canGoBack()) webView.goBack()
            return
        }
        val code = KEYS[name] ?: throw IllegalArgumentException("tecla desconhecida: $name")
        val meta = if (name == "shiftTab") KeyEvent.META_SHIFT_ON or KeyEvent.META_SHIFT_LEFT_ON else 0
        val now = SystemClock.uptimeMillis()
        for (action in intArrayOf(KeyEvent.ACTION_DOWN, KeyEvent.ACTION_UP)) {
            webView.dispatchKeyEvent(
                KeyEvent(now, now, action, code, 0, meta, -1, 0, 0, InputDevice.SOURCE_KEYBOARD)
            )
        }
    }

    private fun dispatchTouch(
        webView: WebView,
        downTime: Long,
        eventTime: Long,
        action: Int,
        x: Float,
        y: Float,
    ) {
        val event = MotionEvent.obtain(downTime, eventTime, action, x, y, 0)
        event.source = InputDevice.SOURCE_TOUCHSCREEN
        try {
            webView.dispatchTouchEvent(event)
        } finally {
            event.recycle()
        }
    }

    /**
     * Tocar num campo abre o teclado da TV, que cobre a tela; quem digita é o
     * painel. Fecha depois que o campo recebeu o foco.
     */
    private fun hideKeyboardSoon(webView: WebView) {
        webView.postDelayed({
            val imm = activity.getSystemService(Context.INPUT_METHOD_SERVICE) as? InputMethodManager
            imm?.hideSoftInputFromWindow(webView.windowToken, 0)
        }, HIDE_KEYBOARD_DELAY_MS)
    }

    companion object {
        const val CHANNEL = "beyond_tv/remote_input"

        private const val TAP_MS = 60L
        private const val SCROLL_STEPS = 10
        private const val STEP_MS = 16L
        private const val HIDE_KEYBOARD_DELAY_MS = 300L

        private val KEYS = mapOf(
            "enter" to KeyEvent.KEYCODE_ENTER,
            "tab" to KeyEvent.KEYCODE_TAB,
            "shiftTab" to KeyEvent.KEYCODE_TAB,
            "backspace" to KeyEvent.KEYCODE_DEL,
            "delete" to KeyEvent.KEYCODE_FORWARD_DEL,
            "escape" to KeyEvent.KEYCODE_ESCAPE,
            "up" to KeyEvent.KEYCODE_DPAD_UP,
            "down" to KeyEvent.KEYCODE_DPAD_DOWN,
            "left" to KeyEvent.KEYCODE_DPAD_LEFT,
            "right" to KeyEvent.KEYCODE_DPAD_RIGHT,
            "pageUp" to KeyEvent.KEYCODE_PAGE_UP,
            "pageDown" to KeyEvent.KEYCODE_PAGE_DOWN,
            "home" to KeyEvent.KEYCODE_MOVE_HOME,
            "end" to KeyEvent.KEYCODE_MOVE_END,
        )
    }
}
