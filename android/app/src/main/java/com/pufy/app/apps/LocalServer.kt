package com.pufy.app.apps

import android.net.Uri
import android.webkit.MimeTypeMap
import android.webkit.WebResourceResponse
import java.io.File
import java.io.FileInputStream

/** Mini uygulama dosyalarını sanal bir alan adından sunar: https://<klasör>.pufyapp.local/ (iOS pufyapp://<klasör>/ ile aynı mantık) */
object LocalServer {
    private const val SUFFIX = ".pufyapp.local"

    fun host(folder: String) = folder.lowercase().replace(Regex("[^a-z0-9-]"), "-").trim('-').take(60).ifEmpty { "app" } + SUFFIX

    fun url(folder: String, entry: String) = "https://${host(folder)}/${entry.removePrefix("/")}"

    private val mimeTypes = mapOf("html" to "text/html", "htm" to "text/html", "js" to "application/javascript", "mjs" to "application/javascript",
        "css" to "text/css", "json" to "application/json", "png" to "image/png", "jpg" to "image/jpeg", "jpeg" to "image/jpeg", "gif" to "image/gif",
        "webp" to "image/webp", "svg" to "image/svg+xml", "mp3" to "audio/mpeg", "wav" to "audio/wav", "ogg" to "audio/ogg", "mp4" to "video/mp4",
        "woff" to "font/woff", "woff2" to "font/woff2", "ttf" to "font/ttf", "txt" to "text/plain")

    /** Bu alan adına gelen isteği klasörden cevaplar; başka adreslerde null (normal ağ) */
    fun serve(url: Uri, folder: String, entry: String): WebResourceResponse? {
        if (url.host != host(folder)) return null
        val root = MiniAppFiles.folder(folder).canonicalFile
        val path = url.path?.takeIf { it.isNotEmpty() && it != "/" } ?: "/$entry"
        val file = File(root, Uri.decode(path).removePrefix("/")).canonicalFile
        // Klasör dışına çıkılamaz ("../")
        if (!file.path.startsWith(root.path + File.separator) || !file.isFile) return WebResourceResponse("text/plain", "utf-8", 404, "Not Found", emptyMap(), null)
        val ext = file.extension.lowercase()
        val mime = mimeTypes[ext] ?: MimeTypeMap.getSingleton().getMimeTypeFromExtension(ext) ?: "application/octet-stream"
        return WebResourceResponse(mime, "utf-8", 200, "OK", mapOf("Cache-Control" to "no-store"), FileInputStream(file))
    }
}
