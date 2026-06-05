package com.nexusrelay.pixel.auth

import android.content.Context
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext

class DeviceTokenStore(private val context: Context) {
    private val masterKey = MasterKey.Builder(context)
        .setKeyScheme(MasterKey.KeyScheme.AES256_GCM)
        .build()

    private val sharedPreferences = EncryptedSharedPreferences.create(
        context,
        "secure_device_prefs",
        masterKey,
        EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
        EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM
    )

    suspend fun saveDeviceToken(token: String) = withContext(Dispatchers.IO) {
        sharedPreferences.edit().putString(KEY_DEVICE_TOKEN, token).apply()
    }

    suspend fun getDeviceToken(): String? = withContext(Dispatchers.IO) {
        sharedPreferences.getString(KEY_DEVICE_TOKEN, null)
    }

    suspend fun clear() = withContext(Dispatchers.IO) {
        sharedPreferences.edit().remove(KEY_DEVICE_TOKEN).apply()
    }

    companion object {
        private const val KEY_DEVICE_TOKEN = "device_token"
    }
}
