package com.pufy.app.core

import android.content.Context
import android.content.SharedPreferences
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey

/**
 * Uygulama ayarları. Anahtarlar (yapay zeka anahtarı, oturum) şifreli depoda — iOS'taki Keychain'in karşılığı.
 * Anahtar adları iOS'takiyle aynı (taşıma/teşhis kolay olsun).
 */
object Settings {
    private lateinit var prefs: SharedPreferences
    private lateinit var secure: SharedPreferences

    fun init(context: Context) {
        prefs = context.getSharedPreferences("pufy", Context.MODE_PRIVATE)
        secure = runCatching {
            val key = MasterKey.Builder(context).setKeyScheme(MasterKey.KeyScheme.AES256_GCM).build()
            EncryptedSharedPreferences.create(
                context, "pufy_secure", key,
                EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
                EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
            )
        }.getOrElse { context.getSharedPreferences("pufy_secure_fallback", Context.MODE_PRIVATE) }
    }

    fun string(key: String): String? = prefs.getString(key, null)
    fun setString(key: String, value: String?) = prefs.edit().apply { if (value == null) remove(key) else putString(key, value) }.apply()
    fun bool(key: String, default: Boolean = false): Boolean = prefs.getBoolean(key, default)
    fun setBool(key: String, value: Boolean) = prefs.edit().putBoolean(key, value).apply()
    fun int(key: String, default: Int = 0): Int = prefs.getInt(key, default)
    fun setInt(key: String, value: Int) = prefs.edit().putInt(key, value).apply()
    fun has(key: String): Boolean = prefs.contains(key)
    fun stringSet(key: String): Set<String> = prefs.getStringSet(key, emptySet()) ?: emptySet()
    fun setStringSet(key: String, value: Set<String>) = prefs.edit().putStringSet(key, value).apply()

    fun secret(key: String): String? = secure.getString(key, null)?.takeIf { it.isNotEmpty() }
    fun setSecret(key: String, value: String?) =
        secure.edit().apply { if (value.isNullOrEmpty()) remove(key) else putString(key, value) }.apply()

    fun clearAll() {
        prefs.edit().clear().apply()
        secure.edit().clear().apply()
    }

    // Ortak anahtarlar
    const val USER_NAME = "pufy_agent_user_name"
    const val ONBOARDING_DONE = "pufy_onboarding_done"
    const val COACH_MARKS_COMPLETED = "coach_marks_completed"
    const val HINT_NEW_APP_SHOWN = "hint_new_app_shown"
    const val HINT_MINI_EXIT_SHOWN = "hint_mini_exit_shown"
    const val HINT_MEMORY_SHOWN = "hint_memory_shown"
}
