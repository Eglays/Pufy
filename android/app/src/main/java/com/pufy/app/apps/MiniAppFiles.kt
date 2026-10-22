package com.pufy.app.apps

import com.pufy.app.data.AppFiles
import java.io.File

/**
 * Mini uygulama dosyaları ve sürümleri (iOS MiniAppFiles).
 * Dosyalar: files/MiniApps/<klasör>/   Sürümler: files/MiniAppVersions/<klasör>/<zaman>/   Veri: files/MiniAppData/<klasör>.json
 */
object MiniAppFiles {
    val versionsRoot get() = File(AppFiles.root, "MiniAppVersions")
    const val KIT = "pufy-ui.css"

    fun folder(folder: String) = File(AppFiles.miniApps, folder)

    /** Yapay zekanın verdiği yol güvenli mi? ("../" ile klasör dışına çıkılamaz) */
    fun sanitized(path: String): String? {
        val parts = path.replace("\\", "/").split("/").map { it.trim() }.filter { it.isNotEmpty() && it != "." }
        if (parts.isEmpty() || ".." in parts) return null
        return parts.joinToString("/")
    }

    fun hasFiles(folder: String) = File(folder(folder), "index.html").exists()
    fun read(path: String, folder: String): String? = sanitized(path)?.let { File(folder(folder), it).takeIf { f -> f.isFile }?.readText() }

    fun write(path: String, content: String, folder: String): Boolean {
        val safe = sanitized(path) ?: return false
        return runCatching { File(folder(folder), safe).apply { parentFile?.mkdirs() }.writeText(content); true }.getOrDefault(false)
    }

    fun delete(path: String, folder: String) { sanitized(path)?.let { File(folder(folder), it).delete() } }

    private val textExtensions = setOf("html", "htm", "css", "js", "mjs", "json", "txt", "svg", "md")

    fun textFiles(folder: String): List<Pair<String, String>> {
        val base = folder(folder).takeIf { it.isDirectory } ?: return emptyList()
        return base.walkTopDown().filter { it.isFile && !it.name.startsWith(".") && it.extension.lowercase() in textExtensions }
            .map { it.relativeTo(base).path.replace(File.separatorChar, '/') to it.readText() }
            .sortedWith(compareBy({ it.first != "index.html" }, { it.first })).toList()
    }

    /** Yapay zekaya gönderilecek "mevcut dosyalar" metni */
    fun promptText(folder: String) = textFiles(folder).filter { it.first != "pufy-card.html" && it.first != KIT }
        .joinToString("\n\n") { "<<<FILE ${it.first}>>>\n${it.second}\n<<<END>>>" }

    fun existingAssets(folder: String): List<String> =
        File(folder(folder), "assets").listFiles()?.filter { it.extension.lowercase() in setOf("png", "jpg", "jpeg", "webp") }
            ?.map { "assets/${it.name}" }?.sorted() ?: emptyList()

    // MARK: Sürümler

    data class Version(val id: String, val dateMillis: Long, val label: String, val dir: File)

    fun snapshot(folder: String, label: String): Version? {
        if (!hasFiles(folder)) return null
        val now = System.currentTimeMillis()
        val dir = File(versionsRoot, "$folder/$now")
        return runCatching {
            folder(folder).copyRecursively(dir, overwrite = true)
            File(dir, ".pufy-version-label").writeText(label.take(120))
            versions(folder).drop(20).forEach { it.dir.deleteRecursively() }
            Version(now.toString(), now, label, dir)
        }.getOrNull()
    }

    fun versions(folder: String): List<Version> = File(versionsRoot, folder).listFiles()?.mapNotNull { d ->
        val ms = d.name.toLongOrNull() ?: return@mapNotNull null
        Version(d.name, ms, File(d, ".pufy-version-label").takeIf { it.exists() }?.readText() ?: "", d)
    }?.sortedByDescending { it.dateMillis } ?: emptyList()

    fun restore(version: Version, folder: String) {
        snapshot(folder, "Geri dönmeden önceki hal")
        val target = folder(folder)
        target.deleteRecursively()
        version.dir.copyRecursively(target, overwrite = true)
        File(target, ".pufy-version-label").delete()
    }

    fun deleteAll(folder: String) {
        folder(folder).deleteRecursively()
        File(versionsRoot, folder).deleteRecursively()
        File(AppFiles.miniAppData, "$folder.json").delete()
        MiniAppSecrets.removeAll(folder)
    }

    /** Tasarım kitini klasöre yazar (yoksa ya da eskiyse) */
    fun ensureKit(folder: String) {
        val kit = runCatching { com.pufy.app.PufyApp.instance.assets.open(KIT).use { it.readBytes() } }.getOrNull() ?: return
        val file = File(folder(folder), KIT)
        if (!file.exists() || !file.readBytes().contentEquals(kit)) { file.parentFile?.mkdirs(); file.writeBytes(kit) }
    }
}
