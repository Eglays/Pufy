package com.pufy.app.data

import com.pufy.app.core.Settings
import com.pufy.app.core.sha256Hex
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import java.io.File

/** Kullanıcının adı ve profil fotoğrafı (eşitlenir: settings/profile, settings/avatar) */
object Profile {
    private val _name = MutableStateFlow(Settings.string(Settings.USER_NAME) ?: "")
    val nameFlow: StateFlow<String> = _name.asStateFlow()
    private val _avatarVersion = MutableStateFlow(0)
    val avatarVersion: StateFlow<Int> = _avatarVersion.asStateFlow()
    var onChange: (() -> Unit)? = null

    val name: String get() = _name.value
    private val avatarFile get() = File(AppFiles.root, "avatar.jpg")

    fun reload() { _name.value = Settings.string(Settings.USER_NAME) ?: "" }

    fun setName(value: String) {
        val v = value.trim()
        Settings.setString(Settings.USER_NAME, v)
        _name.value = v
        onChange?.invoke()
    }

    fun avatarBytes(): ByteArray? = avatarFile.takeIf { it.exists() }?.readBytes()
    fun avatarPath(): File? = avatarFile.takeIf { it.exists() }
    fun avatarName(data: ByteArray) = sha256Hex(data).take(32) + ".jpg"

    /** Kullanıcı fotoğrafı değiştirdi (eşitleme ayrıca bildirilir: SyncService.avatarChanged) */
    fun setAvatar(data: ByteArray?) {
        if (data == null) avatarFile.delete() else avatarFile.writeBytes(data)
        _avatarVersion.value++
    }

    fun applyRemoteName(value: String) { Settings.setString(Settings.USER_NAME, value); _name.value = value }
    fun applyRemoteAvatar(data: ByteArray?) { if (data == null) avatarFile.delete() else avatarFile.writeBytes(data); _avatarVersion.value++ }
}
