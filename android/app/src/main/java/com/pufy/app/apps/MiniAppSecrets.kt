package com.pufy.app.apps

import com.pufy.app.core.PufyJson
import com.pufy.app.core.Settings
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

/**
 * Mini uygulama gizli anahtarları (iOS MiniAppSecrets / Keychain karşılığı).
 * Kullanıcının verdiği API anahtarları doğrudan koda yazılmaz; uygulamaya özel saklanır.
 * Sayfa `await pufy.secret("AD")` ile anahtarı alır.
 * Anahtarlar eşitlemeye ve paylaşıma girmez.
 */
object MiniAppSecrets {
    private fun key(folder: String): String = "miniapp.secrets.$folder"

    fun all(folder: String): Map<String, String> {
        val raw = Settings.secret(key(folder)) ?: return emptyMap()
        return runCatching {
            val json = PufyJson.parseToJsonElement(raw).jsonObject
            json.entries.mapNotNull { (k, v) ->
                val str = (v as? JsonPrimitive)?.content ?: v.jsonPrimitive.content
                if (str.isNotBlank()) k to str.trim() else null
            }.toMap()
        }.getOrElse { emptyMap() }
    }

    fun get(name: String, folder: String): String? = all(folder)[name]

    fun merge(secrets: Map<String, String>, folder: String) {
        if (secrets.isEmpty()) return
        val current = all(folder).toMutableMap()
        current.putAll(secrets)
        val json = buildJsonObject {
            current.forEach { (k, v) -> put(k, JsonPrimitive(v)) }
        }.toString()
        Settings.setSecret(key(folder), json)
    }

    fun removeAll(folder: String) {
        Settings.setSecret(key(folder), null)
    }
}
