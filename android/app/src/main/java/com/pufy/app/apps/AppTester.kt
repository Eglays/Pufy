package com.pufy.app.apps

import android.annotation.SuppressLint
import android.app.Activity
import android.graphics.Bitmap
import android.graphics.Canvas
import android.view.ViewGroup
import android.webkit.ConsoleMessage
import android.webkit.JavascriptInterface
import android.webkit.WebChromeClient
import android.webkit.WebResourceRequest
import android.webkit.WebResourceResponse
import android.webkit.WebView
import android.webkit.WebViewClient
import android.widget.FrameLayout
import com.pufy.app.ui.miniapp.ControlSpotScript
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import java.io.ByteArrayOutputStream
import java.lang.ref.WeakReference
import kotlin.coroutines.resume
import kotlin.coroutines.suspendCoroutine

/**
 * iOS AppTester: uygulamayı görünmez bir WebView'da açar, sahte köprüyle (veri yok) çalıştırır, ekran görüntüsü alır,
 * ana düğmeye basar, konsol hatalarını toplar. Pufy ön planda değilse deneme atlanır (null).
 */
object AppTester {
    data class Run(val shots: List<ByteArray>, val errors: List<String>, val interacted: Boolean, val darkShot: Boolean = false)

    /** Ön plandaki ekran (PufyApp kaydeder) */
    var activity: WeakReference<Activity>? = null

    private val stubBridge = """
(function(){
  var mem = {};
  var log = function(m){ try { PufyTest.log(String(m)); } catch(e){} };
  window.addEventListener('error', function(e){ log(e.message + (e.lineno ? ' (satır ' + e.lineno + ')' : '')); });
  window.addEventListener('unhandledrejection', function(e){ var r = e.reason; log('Promise: ' + ((r && (r.stack || r.message)) || r)); });
  var ok = function(v){ return Promise.resolve(v); };
  window.pufy = { version: 1, platform: 'android', user: { name: 'Deneme' },
    storage: { get: function(k){ return ok(k in mem ? JSON.parse(mem[k]) : null); }, set: function(k, v){ mem[k] = JSON.stringify(v); return ok(true); },
               remove: function(k){ delete mem[k]; return ok(true); }, keys: function(){ return ok(Object.keys(mem)); } },
    haptic: function(){}, notify: function(){ return ok('t'); }, notifyDaily: function(){ return ok('t'); },
    cancelNotification: function(){ return ok(0); }, cancelAllNotifications: function(){ return ok(0); },
    remind: function(){ return ok(true); },
    ai: function(p, o){ return ok(o && o.json ? {} : ''); },
    fetch: function(){ return ok({ok: false, status: 0, headers: {}, text: '', json: null}); },
    secret: function(){ return ok(null); }, pickPhoto: function(){ return ok(null); }, takePhoto: function(){ return ok(null); },
    share: function(){ return ok(true); },
    work: { start: function(){ return ok(true); }, update: function(){ return ok(true); }, end: function(){ return ok(true); } },
    live: { start: function(){ return ok(null); }, update: function(){ return ok(true); }, end: function(){ return ok(true); } } };
  document.dispatchEvent(new Event('pufyready'));
})();
"""

    private const val CLICK = """
(function(){
  var re = /(başla|oyna|play|start|hadi|devam|yeni oyun|giriş|keşfet)/i;
  var els = Array.prototype.slice.call(document.querySelectorAll('button, [role=button], a, .btn, .button'));
  var el = els.find(function(e){ return re.test((e.innerText || e.textContent || '').trim()) && e.offsetParent !== null; });
  if (el) { el.click(); return true; }
  var c = document.elementFromPoint(innerWidth/2, innerHeight*0.6);
  if (c) { ['pointerdown','touchstart','mousedown','pointerup','touchend','mouseup','click'].forEach(function(t){
    try { c.dispatchEvent(new Event(t, {bubbles: true})); } catch(e){} }); }
  return false;
})();
"""

    @SuppressLint("SetJavaScriptEnabled")
    suspend fun run(folder: String, entry: String = "index.html"): Run? = withContext(Dispatchers.Main) {
        val act = activity?.get()?.takeIf { !it.isFinishing } ?: return@withContext null
        val errors = mutableListOf<String>()
        val loaded = CompletableDeferred<Unit>()
        val density = act.resources.displayMetrics.density
        val w = (393 * density).toInt(); val h = (852 * density).toInt()
        val web = WebView(act)
        web.settings.javaScriptEnabled = true
        web.settings.domStorageEnabled = true
        web.settings.mediaPlaybackRequiresUserGesture = false
        web.addJavascriptInterface(object { @JavascriptInterface fun log(m: String) { synchronized(errors) { if (!m.contains("should not be used in production")) errors.add(m.take(300)) } } }, "PufyTest")
        web.webChromeClient = object : WebChromeClient() {
            override fun onConsoleMessage(m: ConsoleMessage): Boolean {
                if (m.messageLevel() == ConsoleMessage.MessageLevel.ERROR) synchronized(errors) { errors.add(m.message().take(300)) }
                return true
            }
        }
        web.webViewClient = object : WebViewClient() {
            override fun shouldInterceptRequest(view: WebView, request: WebResourceRequest): WebResourceResponse? = LocalServer.serve(request.url, folder, entry)
            override fun onPageStarted(view: WebView, url: String?, favicon: Bitmap?) { view.evaluateJavascript(stubBridge, null) }
            override fun onPageFinished(view: WebView, url: String?) {
                view.evaluateJavascript(stubBridge, null)
                view.evaluateJavascript(ControlSpotScript.SOURCE.replace("PufyNative.layout(i)", "0"), null)
                loaded.complete(Unit)
            }
            override fun shouldOverrideUrlLoading(view: WebView, request: WebResourceRequest) = request.url.host != LocalServer.host(folder)
        }
        // Ekranın en altına (Pufy arayüzünün arkasına) eklenir: görünmez ama çizilir
        val content = act.findViewById<ViewGroup>(android.R.id.content)
        content.addView(web, 0, FrameLayout.LayoutParams(w, h))
        try {
            web.measure(android.view.View.MeasureSpec.makeMeasureSpec(w, android.view.View.MeasureSpec.EXACTLY), android.view.View.MeasureSpec.makeMeasureSpec(h, android.view.View.MeasureSpec.EXACTLY))
            web.layout(0, 0, w, h)
            delay(50)
            web.loadUrl(LocalServer.url(folder, entry))
            withTimeoutOrNull(12_000) { loaded.await() }
            delay(2500)
            val shots = mutableListOf<ByteArray>()
            snapshot(web, w, h)?.let(shots::add)
            val clicked = suspendCoroutine { c -> web.evaluateJavascript(CLICK) { c.resume(it == "true") } }
            delay(2500)
            snapshot(web, w, h)?.let(shots::add)
            val free = suspendCoroutine { c -> web.evaluateJavascript("window.__pufyFreeSpot ? window.__pufyFreeSpot() : 0") { c.resume(it?.toIntOrNull() ?: 0) } }
            if (free != 0) errors.add("Sağ alt köşede (Pufy düğmesinin yeri: sağdan ~64px, alttan güvenli alan + ~50px) dokunulabilir bir öğe var; " +
                "o köşeyi boş bırak (yüzen butonu sola/ortaya al, alt çubukta sağdan boşluk bırak).")
            Run(shots, synchronized(errors) { errors.distinct().take(10) }, clicked)
        } finally {
            content.removeView(web)
            web.destroy()
        }
    }

    private fun snapshot(web: WebView, w: Int, h: Int): ByteArray? = runCatching {
        val bmp = Bitmap.createBitmap(w, h, Bitmap.Config.ARGB_8888)
        web.draw(Canvas(bmp))
        val scaled = Bitmap.createScaledBitmap(bmp, w * 2 / 3, h * 2 / 3, true)
        ByteArrayOutputStream().also { scaled.compress(Bitmap.CompressFormat.JPEG, 70, it) }.toByteArray()
    }.getOrNull()
}
