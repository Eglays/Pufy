package com.pufy.app.core

object LegalLinks {
    const val BASE = "https://eglays.github.io"
    const val SUPPORT_EMAIL = "ahmt.yacel@gmail.com"
    val REPORT_ENDPOINT: String? = null // ileride doldurulacak, şimdilik null

    fun isTurkish(): Boolean = !AppLocales.isEnglish()

    fun privacy(tr: Boolean = isTurkish()): String =
        BASE + if (tr) "/tr/gizlilik/" else "/en/privacy/"

    fun terms(tr: Boolean = isTurkish()): String =
        BASE + if (tr) "/tr/kosullar/" else "/en/terms/"

    fun deletion(tr: Boolean = isTurkish()): String =
        BASE + if (tr) "/tr/veri-silme/" else "/en/delete-data/"

    fun support(tr: Boolean = isTurkish()): String =
        BASE + if (tr) "/tr/destek/" else "/en/support/"
}
