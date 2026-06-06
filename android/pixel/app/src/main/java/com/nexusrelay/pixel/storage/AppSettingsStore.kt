package com.nexusrelay.pixel.storage

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.longPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.map

val Context.dataStore: DataStore<Preferences> by preferencesDataStore(name = "app_settings")

class AppSettingsStore(private val context: Context) {

    val backendBaseUrlFlow: Flow<String?> = context.dataStore.data.map { preferences ->
        preferences[KEY_BACKEND_BASE_URL]
    }

    suspend fun saveBackendBaseUrl(url: String) {
        context.dataStore.edit { preferences ->
            preferences[KEY_BACKEND_BASE_URL] = url
        }
    }

    val targetIdFlow: Flow<String?> = context.dataStore.data.map { preferences ->
        preferences[KEY_TARGET_ID]
    }

    suspend fun saveTargetId(targetId: String) {
        context.dataStore.edit { preferences ->
            preferences[KEY_TARGET_ID] = targetId
        }
    }

    val deviceNameFlow: Flow<String?> = context.dataStore.data.map { preferences ->
        preferences[KEY_DEVICE_NAME]
    }

    suspend fun saveDeviceName(name: String) {
        context.dataStore.edit { preferences ->
            preferences[KEY_DEVICE_NAME] = name
        }
    }

    val wifiOnlyFlow: Flow<Boolean> = context.dataStore.data.map { preferences ->
        preferences[KEY_WIFI_ONLY] ?: true
    }

    suspend fun saveWifiOnly(wifiOnly: Boolean) {
        context.dataStore.edit { preferences ->
            preferences[KEY_WIFI_ONLY] = wifiOnly
        }
    }

    val lastSuccessfulSyncAtFlow: Flow<Long> = context.dataStore.data.map { preferences ->
        preferences[KEY_LAST_SYNC_AT] ?: 0L
    }

    suspend fun saveLastSuccessfulSyncAt(timestamp: Long) {
        context.dataStore.edit { preferences ->
            preferences[KEY_LAST_SYNC_AT] = timestamp
        }
    }

    val fcmTokenFlow: Flow<String?> = context.dataStore.data.map { preferences ->
        preferences[KEY_FCM_TOKEN]
    }

    suspend fun saveFcmToken(token: String) {
        context.dataStore.edit { preferences ->
            preferences[KEY_FCM_TOKEN] = token
        }
    }

    val syncScopeFlow: Flow<String?> = context.dataStore.data.map { preferences ->
        preferences[KEY_SYNC_SCOPE]
    }

    suspend fun saveSyncScope(scope: String) {
        context.dataStore.edit { preferences ->
            preferences[KEY_SYNC_SCOPE] = scope
        }
    }

    val scopedFolderIdFlow: Flow<String?> = context.dataStore.data.map { preferences ->
        preferences[KEY_SCOPED_FOLDER_ID]
    }

    suspend fun saveScopedFolderId(folderId: String?) {
        context.dataStore.edit { preferences ->
            if (folderId.isNullOrBlank()) {
                preferences.remove(KEY_SCOPED_FOLDER_ID)
            } else {
                preferences[KEY_SCOPED_FOLDER_ID] = folderId
            }
        }
    }

    suspend fun clear() {
        context.dataStore.edit { preferences ->
            preferences.clear()
        }
    }

    companion object {
        private val KEY_BACKEND_BASE_URL = stringPreferencesKey("backend_base_url")
        private val KEY_TARGET_ID = stringPreferencesKey("target_id")
        private val KEY_DEVICE_NAME = stringPreferencesKey("device_name")
        private val KEY_WIFI_ONLY = booleanPreferencesKey("wifi_only")
        private val KEY_LAST_SYNC_AT = longPreferencesKey("last_sync_at")
        private val KEY_FCM_TOKEN = stringPreferencesKey("fcm_token")
        private val KEY_SYNC_SCOPE = stringPreferencesKey("sync_scope")
        private val KEY_SCOPED_FOLDER_ID = stringPreferencesKey("scoped_folder_id")
    }
}
