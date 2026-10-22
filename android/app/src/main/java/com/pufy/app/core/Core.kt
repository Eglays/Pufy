package com.pufy.app.core

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.longOrNull
import java.security.MessageDigest
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.util.Locale
import java.util.UUID

// iOS ile veri uyumu (Pufy aynı sunucudan iPhone ile eşitlenir):
//  • Swift'in JSONEncoder'ı tarihleri 1 Ocak 2001'den bu yana saniye (Double) olarak yazar
//  • UUID'ler BÜYÜK harf
//  • Belge özetleri: anahtarları sıralı JSON'un SHA-256'sı (iOS JSONSerialization .sortedKeys ile aynı)

val PufyJson = Json {
    ignoreUnknownKeys = true
    explicitNulls = false
    encodeDefaults = true
    isLenient = true
}

const val SWIFT_EPOCH = 978_307_200.0

fun nowSwift(): Double = System.currentTimeMillis() / 1000.0 - SWIFT_EPOCH
fun swiftToEpochMillis(value: Double): Long = ((value + SWIFT_EPOCH) * 1000).toLong()
fun epochMillisToSwift(millis: Long): Double = millis / 1000.0 - SWIFT_EPOCH

fun newID(): String = UUID.randomUUID().toString().uppercase()

val TR: Locale = Locale.forLanguageTag("tr-TR")
val TURKEY: ZoneId = ZoneId.of("Europe/Istanbul")

fun String.trLower(): String = lowercase(TR)

/** "2026-10-15T21:30:00" — Türkiye saatiyle (etiketlerdeki tarih biçimi) */
fun turkeyISO(millis: Long = System.currentTimeMillis()): String =
    DateTimeFormatter.ofPattern("yyyy-MM-dd'T'HH:mm:ss").format(Instant.ofEpochMilli(millis).atZone(TURKEY))

fun parseTurkeyISO(text: String): Long? {
    val m = Regex("""^(\d{4})-(\d{2})-(\d{2})[T ](\d{2}):(\d{2})(?::(\d{2}))?""").find(text.trim()) ?: return null
    val (y, mo, d, h, mi) = m.destructured
    val s = m.groupValues[6].ifEmpty { "0" }
    return LocalDateTime.of(y.toInt(), mo.toInt(), d.toInt(), h.toInt(), mi.toInt(), s.toInt())
        .atZone(TURKEY).toInstant().toEpochMilli()
}

fun turkeyFormat(millis: Long, pattern: String): String =
    DateTimeFormatter.ofPattern(pattern, TR).format(Instant.ofEpochMilli(millis).atZone(TURKEY))

fun sha256Hex(bytes: ByteArray): String =
    MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }

/** Anahtarları sıralı JSON — aynı içerik aynı özeti verir (iOS .sortedKeys ile uyumlu) */
fun stableJson(element: JsonElement): String = when (element) {
    is JsonObject -> element.entries.filter { it.value !is JsonNull || true }
        .sortedBy { it.key }
        .joinToString(",", "{", "}") { PufyJson.encodeToString(JsonElement.serializer(), JsonPrimitive(it.key)) + ":" + stableJson(it.value) }
    is JsonArray -> element.joinToString(",", "[", "]") { stableJson(it) }
    else -> PufyJson.encodeToString(JsonElement.serializer(), element)
}

// JsonObject okuma kısayolları
fun JsonObject.str(key: String): String? = (this[key] as? JsonPrimitive)?.takeIf { it.isString }?.content
fun JsonObject.num(key: String): Double? = (this[key] as? JsonPrimitive)?.doubleOrNull
fun JsonObject.int(key: String): Int? = (this[key] as? JsonPrimitive)?.intOrNull
fun JsonObject.long(key: String): Long? = (this[key] as? JsonPrimitive)?.longOrNull
fun JsonObject.bool(key: String): Boolean? = (this[key] as? JsonPrimitive)?.booleanOrNull
fun JsonObject.obj(key: String): JsonObject? = this[key] as? JsonObject
fun JsonObject.arr(key: String): JsonArray? = this[key] as? JsonArray
fun JsonObject.strings(key: String): List<String> =
    arr(key)?.mapNotNull { (it as? JsonPrimitive)?.takeIf { p -> p.isString }?.content } ?: emptyList()

fun JsonElement?.asString(): String? = (this as? JsonPrimitive)?.takeIf { it.isString }?.content
fun JsonElement?.asObject(): JsonObject? = this as? JsonObject

fun parseJsonObject(text: String): JsonObject? =
    runCatching { PufyJson.parseToJsonElement(text) as? JsonObject }.getOrNull()

/** Model JSON'un etrafına açıklama/kod bloğu eklese bile ilk {...} bloğunu çıkarır */
fun extractJsonObject(text: String): JsonObject? {
    val start = text.indexOf('{')
    val end = text.lastIndexOf('}')
    if (start < 0 || end <= start) return null
    return parseJsonObject(text.substring(start, end + 1))
}

fun JsonElement.primitiveContent(): String? = (this as? JsonPrimitive)?.content

/** Arka plan işlerinde beklenmeyen hata uygulamayı kapatmasın: kaydedilir, iş sessizce biter */
val SafeErrors = kotlinx.coroutines.CoroutineExceptionHandler { _, e -> android.util.Log.e("Pufy", "Arka plan hatası", e) }
