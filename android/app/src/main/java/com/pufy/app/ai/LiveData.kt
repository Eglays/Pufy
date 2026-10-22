package com.pufy.app.ai

import com.pufy.app.core.PufyJson
import com.pufy.app.core.Settings
import com.pufy.app.core.TR
import com.pufy.app.core.TURKEY
import com.pufy.app.core.arr
import com.pufy.app.core.num
import com.pufy.app.core.obj
import com.pufy.app.core.str
import com.pufy.app.data.MemoryStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.Request
import java.text.Normalizer
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.util.concurrent.TimeUnit
import kotlin.math.roundToInt

/** Yapay zekaya eklenen anlık veriler: canlı skor (sunucu) ve hava durumu (Open-Meteo) — iOS LiveScores / WeatherService */
object LiveData {
    private val http = AiClient.http.newBuilder().callTimeout(5, TimeUnit.SECONDS).build()

    // MARK: Canlı skor

    private fun normalize(s: String) = Normalizer.normalize(s.lowercase(TR).replace("ı", "i"), Normalizer.Form.NFD).replace(Regex("\\p{M}"), "")

    fun isScoreQuery(query: String): Boolean {
        val q = normalize(query)
        return listOf("mac", "skor", "kac kac", "canli", "gol", "dakika", "devre", "ilk yari", "ikinci yari",
            "kazandi", "bitti", "oynuyor", "lig", "score", "match", "live").any { q.contains(it) }
    }

    /** Canlı skor verisi yalnızca özel sunucuyla gelir; Pufy'de sunucu yok */
    suspend fun scores(query: String): String? = null

    // MARK: Hava durumu

    private val stopWords = setOf("bugün", "bugünkü", "yarın", "yarınki", "öbür", "ertesi", "gün", "günü", "günler", "hafta", "haftaya", "haftası",
        "sonu", "sonunda", "akşam", "akşamki", "sabah", "sabahki", "öğle", "öğlen", "öğleden", "gece", "geceki", "şimdi",
        "şu", "an", "anda", "bu", "o", "ne", "neler", "nasıl", "olacak", "olur", "oluyor", "mu", "mı", "mü", "mi", "kaç",
        "derece", "hava", "havalar", "havası", "havada", "durumu", "durum", "yağmur", "yağmurlu", "yağacak", "yağar",
        "yağıyor", "kar", "karlı", "şemsiye", "alayım", "almalı", "almalıyım", "lazım", "sıcaklık", "sıcaklığı", "rüzgar",
        "rüzgarlı", "fırtına", "var", "için", "de", "da", "ki", "bana", "söyle", "söyler", "bak", "bakar", "peki", "ya",
        "acaba", "burada", "burda", "evde", "dışarı", "dışarıda", "saat", "saatte", "kaçta", "pazartesi", "salı",
        "çarşamba", "perşembe", "cuma", "cumartesi", "pazar", "ay", "yüzde", "ihtimal", "ihtimali", "olasılık", "soğuk",
        "sıcak", "serin", "ılık", "nem", "nemli", "güneşli", "güneş", "bulutlu", "bulut", "mont", "ceket", "giy",
        "giyeyim", "giymeli", "çıkacağım", "çıkıcam", "gideceğim", "gidicem", "gideceğiz", "dolu", "fazla", "çok", "biraz",
        "durumunu", "verir", "misin", "musun", "lütfen", "bi", "bir", "nedir", "ve", "ile", "sonra", "önce", "kadar",
        "boyunca", "günlük", "haftalık", "tahmin", "tahmini", "nası", "naber", "dün", "dünkü", "gelecek",
        "önümüzdeki", "iyi", "kötü", "güzel", "uygun", "mıdır", "midir", "olacakmış", "yağacakmış", "kaçtan", "kaça",
        "benim", "bizim", "orada", "orda", "orası", "burası", "sence", "acil", "şemsiyeye", "gerek", "dışarda", "evden")

    fun isWeatherQuery(query: String): Boolean {
        val q = query.lowercase(TR) + " "
        return QueryRouter.has(q, Cues.weatherCues) && !QueryRouter.has(q, Cues.notWeatherCues)
    }

    data class Place(val name: String, val region: String?, val country: String?, val lat: Double, val lon: Double)

    suspend fun weather(query: String, history: List<AiTurn>): String? = withContext(Dispatchers.IO) {
        var asked = isWeatherQuery(query)
        if (!asked && query.split(" ").size <= 4) history.lastOrNull { it.role == "user" }?.let { if (isWeatherQuery(it.text)) asked = true }
        if (!asked) return@withContext null
        val candidates = placeCandidates(query)
        val place = if (candidates.isEmpty()) homePlace() else {
            var found: Place? = null
            outer@ for (variants in candidates.take(2)) for (w in variants) { found = geocode(w); if (found != null) break@outer }
            found ?: return@withContext null
        }
        place?.let { runCatching { forecast(it) }.getOrNull() }
    }

    private fun homePlace(): Place? {
        val homeWords = listOf("yaşıyor", "yaşar", "oturuyor", "ikamet", "evi ", "evim", "yaşadığı", "oturduğu", "konum")
        val items = MemoryStore.items.value
        val ranked = items.filter { i -> val all = ((i.str("text") ?: "") + " " + (i.str("detail") ?: "")).lowercase(TR) + " "; homeWords.any { all.contains(it) } } +
            items.filter { MemoryStore.category(it) == "places" }
        val tried = mutableSetOf<String>()
        for (item in ranked) for (name in placeNames(item)) {
            if (!tried.add(name.lowercase(TR))) continue
            geocode(name)?.let { return it }
            if (tried.size >= 4) return null
        }
        return null
    }

    private fun placeNames(item: JsonObject): List<String> {
        val names = mutableListOf<String>()
        for (source in listOf(item.str("entity") ?: "", item.str("detail") ?: "", item.str("text") ?: "")) {
            for (raw in source.split(Regex("[\\s,.;:!?()]+")).filter { it.isNotEmpty() }) {
                val apostrophe = raw.indexOfFirst { it == '\'' || it == '’' }
                val word = if (apostrophe >= 0) raw.substring(0, apostrophe) else raw
                if (word.length < 3 || !word.first().isUpperCase() || word in setOf("Kullanıcı", "Kullanıcının", "Kendisi", "Ev", "Evi")) continue
                if (apostrophe >= 0) names.add(0, word) else names.add(word)
            }
        }
        return names
    }

    private fun placeCandidates(query: String): List<List<String>> {
        val words = query.lowercase(TR).split(Regex("[^\\p{L}'’]+")).filter { it.isNotEmpty() }
        val out = mutableListOf<List<String>>()
        for (raw in words) {
            val apostrophe = raw.indexOfFirst { it == '\'' || it == '’' }
            val word = if (apostrophe >= 0) raw.substring(0, apostrophe) else raw
            if (word.length < 3 || word in stopWords || raw in stopWords) continue
            val variants = mutableListOf(word)
            if (apostrophe < 0) for (suffix in listOf("deki", "daki", "teki", "taki", "de", "da", "te", "ta", "ya", "ye")) {
                if (word.endsWith(suffix)) { val stem = word.dropLast(suffix.length); if (stem.length >= 3 && stem !in stopWords) variants.add(stem); break }
            }
            out.add(variants)
        }
        return out
    }

    private fun norm(s: String) = normalize(s)
    private val geoCache = mutableMapOf<String, Place?>()

    private fun geocode(name: String): Place? {
        val key = norm(name)
        if (geoCache.containsKey(key)) return geoCache[key]
        Settings.string("geo_$key")?.let { s -> PufyJson.parseToJsonElement(s).let { it as? JsonObject }?.let { o ->
            return Place(o.str("name")!!, o.str("region"), o.str("country"), o.num("lat")!!, o.num("lon")!!).also { geoCache[key] = it } } }
        val url = "https://geocoding-api.open-meteo.com/v1/search".toHttpUrl().newBuilder()
            .addQueryParameter("name", name).addQueryParameter("count", "10").addQueryParameter("language", "tr").addQueryParameter("format", "json").build()
        val json = runCatching { http.newCall(Request.Builder().url(url).build()).execute().use { PufyJson.parseToJsonElement(it.body.string()) as? JsonObject } }.getOrNull() ?: return null
        val important = setOf("PPLC", "PPLA", "PPLA2", "PPLA3", "ADM1", "ADM2", "ADM3")
        val best = json.arr("results")?.mapNotNull { it as? JsonObject }?.filter { r ->
            norm(r.str("name") ?: "") == key && (r.str("feature_code") in important || ((r["population"] as? JsonPrimitive)?.intOrNull ?: 0) >= 10_000)
        }?.maxByOrNull { (it["population"] as? JsonPrimitive)?.intOrNull ?: 0 } ?: return null
        val place = Place(best.str("name") ?: name, best.str("admin1"), best.str("country"), best.num("latitude") ?: return null, best.num("longitude") ?: return null)
        geoCache[key] = place
        Settings.setString("geo_$key", "{\"name\":${JsonPrimitive(place.name)},\"region\":${JsonPrimitive(place.region)},\"country\":${JsonPrimitive(place.country)},\"lat\":${place.lat},\"lon\":${place.lon}}")
        return place
    }

    private fun forecast(place: Place): String? {
        val url = "https://api.open-meteo.com/v1/forecast".toHttpUrl().newBuilder()
            .addQueryParameter("latitude", "%.4f".format(java.util.Locale.US, place.lat))
            .addQueryParameter("longitude", "%.4f".format(java.util.Locale.US, place.lon))
            .addQueryParameter("current", "temperature_2m,apparent_temperature,relative_humidity_2m,precipitation,weather_code,wind_speed_10m")
            .addQueryParameter("hourly", "temperature_2m,precipitation_probability,weather_code")
            .addQueryParameter("daily", "weather_code,temperature_2m_max,temperature_2m_min,precipitation_probability_max,precipitation_sum,wind_speed_10m_max,sunrise,sunset")
            .addQueryParameter("timezone", "auto").addQueryParameter("forecast_days", "7").addQueryParameter("forecast_hours", "36").build()
        val json = http.newCall(Request.Builder().url(url).build()).execute().use { PufyJson.parseToJsonElement(it.body.string()) as? JsonObject } ?: return null
        val current = json.obj("current") ?: return null
        val daily = json.obj("daily") ?: return null
        fun n(v: Any?) = ((v as? JsonPrimitive)?.doubleOrNull)?.roundToInt()?.toString() ?: "?"
        fun list(o: JsonObject, k: String) = o.arr(k)?.toList() ?: emptyList()
        val tz = json.str("timezone") ?: "Europe/Istanbul"
        val isTurkey = tz == "Europe/Istanbul"
        val where = listOfNotNull(place.name, place.region?.takeIf { it != place.name }, place.country?.takeIf { !isTurkey }).joinToString(", ")
        val lines = mutableListOf(
            "HAVA DURUMU VERİSİ — $where için Open-Meteo'dan ŞU AN çekildi (saatler ${if (isTurkey) "TSİ" else "oranın yerel saati, $tz"}). Hava sorusunu BUNA göre cevapla, web araması gerekmez:",
            "- Şu an: ${n(current["temperature_2m"])}°C (hissedilen ${n(current["apparent_temperature"])}°C), ${describe(current["weather_code"])}, nem %${n(current["relative_humidity_2m"])}, rüzgar ${n(current["wind_speed_10m"])} km/s, yağış ${(current["precipitation"] as? JsonPrimitive)?.doubleOrNull ?: 0.0} mm"
        )
        json.obj("hourly")?.let { h ->
            val times = list(h, "time"); val temps = list(h, "temperature_2m"); val rain = list(h, "precipitation_probability"); val codes = list(h, "weather_code")
            val first = (times.firstOrNull() as? JsonPrimitive)?.content?.take(10)
            val parts = (times.indices step 3).mapNotNull { i ->
                val t = (times[i] as? JsonPrimitive)?.content ?: return@mapNotNull null
                "${if (t.take(10) == first) "" else "ertesi gün "}${t.substringAfter('T')} ${n(temps.getOrNull(i))}°C ${describe(codes.getOrNull(i))} yağış %${n(rain.getOrNull(i))}"
            }
            if (parts.isNotEmpty()) lines.add("- Saatlik: " + parts.joinToString(" · "))
        }
        val days = list(daily, "time")
        val fmt = DateTimeFormatter.ofPattern("d MMMM EEEE", TR)
        days.forEachIndexed { i, d ->
            val s = (d as? JsonPrimitive)?.content ?: return@forEachIndexed
            val label = runCatching { LocalDate.parse(s).format(fmt) }.getOrDefault(s)
            val prefix = when (i) { 0 -> "Bugün"; 1 -> "Yarın"; else -> label }
            var line = "- $prefix${if (i <= 1) " ($label)" else ""}: ${describe(list(daily, "weather_code").getOrNull(i))}, ${n(list(daily, "temperature_2m_min").getOrNull(i))}–${n(list(daily, "temperature_2m_max").getOrNull(i))}°C, yağış olasılığı %${n(list(daily, "precipitation_probability_max").getOrNull(i))} (${n(list(daily, "precipitation_sum").getOrNull(i))} mm), rüzgar en fazla ${n(list(daily, "wind_speed_10m_max").getOrNull(i))} km/s"
            if (i == 0) {
                val sr = (list(daily, "sunrise").getOrNull(0) as? JsonPrimitive)?.content?.substringAfter('T')
                val ss = (list(daily, "sunset").getOrNull(0) as? JsonPrimitive)?.content?.substringAfter('T')
                if (sr != null && ss != null) line += ", gün doğumu $sr, gün batımı $ss"
            }
            lines.add(line)
        }
        lines.add("Cevap: kısa ve doğal (2-4 cümle); sorulan zamana odaklan, gerekiyorsa pratik öneri ver (şemsiye, mont). Konumu bir kez söyle. Kart, görsel ya da kaynak listesi ekleme.")
        return lines.joinToString("\n")
    }

    private fun describe(v: Any?): String = when ((v as? JsonPrimitive)?.doubleOrNull?.toInt()) {
        0 -> "açık"; 1 -> "çoğunlukla açık"; 2 -> "parçalı bulutlu"; 3 -> "kapalı"; 45, 48 -> "sisli"
        51, 53, 55 -> "çisenti"; 56, 57 -> "dondurucu çisenti"; 61 -> "hafif yağmurlu"; 63 -> "yağmurlu"; 65 -> "kuvvetli yağmurlu"
        66, 67 -> "dondurucu yağmur"; 71 -> "hafif kar yağışlı"; 73 -> "kar yağışlı"; 75 -> "yoğun kar yağışlı"; 77 -> "kar taneli"
        80 -> "hafif sağanak"; 81 -> "sağanak yağışlı"; 82 -> "şiddetli sağanak"; 85, 86 -> "kar sağanaklı"; 95 -> "gök gürültülü fırtına"
        96, 99 -> "dolulu fırtına"; null -> "?"; else -> "değişken"
    }

    @Suppress("unused") private val zone = TURKEY
}
