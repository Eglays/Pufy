package com.pufy.app.sync

/**
 * Senkron yok: Pufy'de hesap ve sunucu yoktur, tüm veriler cihazda kalır. Bu nesne uygulamanın
 * kaydetme noktalarının çağırdığı ama hiçbir şey yapmayan bir kancadır.
 *
 * There is no account and no server: all data stays on the device. This object is a no-op hook
 * the app's save points call; plug your own sync in here if you need one.
 */
object SyncService {
    var onTaskResult: ((id: String, text: String) -> Unit)? = null
    fun hookStores() {}
    fun syncInBackground() {}
    fun flushInBackground() {}
    fun avatarChanged() {}
    suspend fun fullResync() {}
}
