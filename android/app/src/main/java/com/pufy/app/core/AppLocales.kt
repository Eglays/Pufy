package com.pufy.app.core

import androidx.appcompat.app.AppCompatDelegate
import androidx.core.os.LocaleListCompat
import java.util.Locale

object AppLocales {
    const val AUTO = "auto"
    const val TURKISH = "tr"
    const val ENGLISH = "en"

    fun getSelectedLanguage(): String {
        val currentLocales = AppCompatDelegate.getApplicationLocales()
        if (currentLocales.isEmpty) return AUTO
        val tag = currentLocales.toLanguageTags()
        return if (tag.startsWith("en", ignoreCase = true)) ENGLISH else if (tag.startsWith("tr", ignoreCase = true)) TURKISH else AUTO
    }

    fun setLanguage(language: String) {
        val localeList = when (language) {
            TURKISH -> LocaleListCompat.forLanguageTags("tr")
            ENGLISH -> LocaleListCompat.forLanguageTags("en")
            else -> LocaleListCompat.getEmptyLocaleList()
        }
        AppCompatDelegate.setApplicationLocales(localeList)
    }

    fun isEnglish(): Boolean {
        val currentLocales = AppCompatDelegate.getApplicationLocales()
        if (!currentLocales.isEmpty) {
            return currentLocales.toLanguageTags().startsWith("en", ignoreCase = true)
        }
        return !Locale.getDefault().language.equals("tr", ignoreCase = true)
    }

    fun currentLocale(): Locale {
        val currentLocales = AppCompatDelegate.getApplicationLocales()
        if (!currentLocales.isEmpty) {
            val first = currentLocales.get(0)
            if (first != null) return first
        }
        return if (Locale.getDefault().language.equals("tr", ignoreCase = true)) Locale("tr", "TR") else Locale.US
    }

    fun uiFormat(millis: Long, pattern: String): String =
        java.time.format.DateTimeFormatter.ofPattern(pattern, currentLocale())
            .format(java.time.Instant.ofEpochMilli(millis).atZone(TURKEY))
}

