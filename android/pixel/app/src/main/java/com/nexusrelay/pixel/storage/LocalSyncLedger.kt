package com.nexusrelay.pixel.storage

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import com.squareup.moshi.Moshi
import com.squareup.moshi.Types
import com.squareup.moshi.kotlin.reflect.KotlinJsonAdapterFactory
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map

data class LocalSyncRecord(
    val jobId: String,
    val mediaId: String,
    val fileName: String,
    val mimeType: String,
    val sizeBytes: Long,
    val sha256: String?,
    val status: LocalSyncStatus,
    val localUri: String?,
    val lastAttemptAt: Long,
    val lastError: String?
)

enum class LocalSyncStatus {
    Queued,
    Downloading,
    Imported,
    ConfirmPending,
    Confirmed,
    Failed
}

private val Context.ledgerDataStore: DataStore<Preferences> by preferencesDataStore(name = "sync_ledger")

class LocalSyncLedger(
    private val context: Context,
    private val dataStore: DataStore<Preferences> = context.ledgerDataStore
) {

    private val moshi = Moshi.Builder()
        .add(KotlinJsonAdapterFactory())
        .build()

    private val mapType = Types.newParameterizedType(
        Map::class.java,
        String::class.java,
        LocalSyncRecord::class.java
    )
    private val adapter = moshi.adapter<Map<String, LocalSyncRecord>>(mapType)

    private suspend fun getRecordsMap(): Map<String, LocalSyncRecord> {
        val json = dataStore.data.map { preferences ->
            preferences[KEY_LEDGER_DATA]
        }.first() ?: return emptyMap()

        return try {
            adapter.fromJson(json) ?: emptyMap()
        } catch (e: Exception) {
            emptyMap()
        }
    }

    private suspend fun saveRecordsMap(map: Map<String, LocalSyncRecord>) {
        val json = adapter.toJson(map)
        dataStore.edit { preferences ->
            preferences[KEY_LEDGER_DATA] = json
        }
    }

    suspend fun upsert(record: LocalSyncRecord) {
        val map = getRecordsMap().toMutableMap()
        map[record.jobId] = record
        saveRecordsMap(map)
    }

    suspend fun get(jobId: String): LocalSyncRecord? {
        return getRecordsMap()[jobId]
    }

    suspend fun markDownloading(jobId: String) {
        val record = get(jobId) ?: return
        upsert(record.copy(
            status = LocalSyncStatus.Downloading,
            lastAttemptAt = System.currentTimeMillis()
        ))
    }

    suspend fun markImported(jobId: String, localUri: String) {
        val record = get(jobId) ?: return
        upsert(record.copy(
            status = LocalSyncStatus.Imported,
            localUri = localUri,
            lastAttemptAt = System.currentTimeMillis()
        ))
    }

    suspend fun markConfirmPending(jobId: String, localUri: String) {
        val record = get(jobId) ?: return
        upsert(record.copy(
            status = LocalSyncStatus.ConfirmPending,
            localUri = localUri,
            lastAttemptAt = System.currentTimeMillis()
        ))
    }

    suspend fun markConfirmed(jobId: String) {
        val record = get(jobId) ?: return
        upsert(record.copy(
            status = LocalSyncStatus.Confirmed,
            lastAttemptAt = System.currentTimeMillis()
        ))
    }

    suspend fun markFailed(jobId: String, error: String) {
        val record = get(jobId) ?: return
        upsert(record.copy(
            status = LocalSyncStatus.Failed,
            lastError = error,
            lastAttemptAt = System.currentTimeMillis()
        ))
    }

    suspend fun listRecent(limit: Int): List<LocalSyncRecord> {
        return getRecordsMap().values
            .sortedByDescending { it.lastAttemptAt }
            .take(limit)
    }

    suspend fun clear() {
        dataStore.edit { preferences ->
            preferences.clear()
        }
    }

    companion object {
        private val KEY_LEDGER_DATA = stringPreferencesKey("ledger_data")
    }
}
