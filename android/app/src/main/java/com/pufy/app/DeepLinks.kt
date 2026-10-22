package com.pufy.app

import android.net.Uri
import kotlinx.coroutines.flow.MutableStateFlow

/** pufy://app/<klasör>, pufy://share/<kod> bağlantıları (iOS onOpenURL) */
object DeepLinks {
    val pending = MutableStateFlow<Uri?>(null)
    fun handle(uri: Uri?) { if (uri?.scheme == "pufy") pending.value = uri }
}
