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
import com.nexusrelay.pixel.api.SyncStatus

internal data class LocalSyncRecord(
    val jobId: String,
    val mediaId: String,
    val fileName: String,
    val mimeType: String,
    val sizeBytes: Long,
    val sha256: String?,
    val status: LocalSyncStatus,
    val localUri: String?,
    val lastAttemptAt: Long,
    val lastError: String?,
    val isLocalDeleted: Boolean = false,
    val statusEnteredAt: Long = lastAttemptAt,
    val retryCount: Int = 0,
    val backendFailureReportedAt: Long? = null
)

private val activeStatuses = setOf(
    LocalSyncStatus.Queued,
    LocalSyncStatus.Downloading,
    LocalSyncStatus.Imported,
    LocalSyncStatus.ConfirmPending
)

private val historyStatuses = setOf(
    LocalSyncStatus.Confirmed,
    LocalSyncStatus.Failed
)

internal enum class LocalSyncStatus {
    Queued,
    Downloading,
    Imported,
    ConfirmPending,
    Confirmed,
    Failed
}

internal fun LocalSyncStatus.toSyncStatus(): SyncStatus =
    when (this) {
        LocalSyncStatus.Queued -> SyncStatus.Pending
        LocalSyncStatus.Downloading,
        LocalSyncStatus.Imported,
        LocalSyncStatus.ConfirmPending -> SyncStatus.Syncing
        LocalSyncStatus.Confirmed -> SyncStatus.Synced
        LocalSyncStatus.Failed -> SyncStatus.Failed
    }

private val Context.ledgerDataStore: DataStore<Preferences> by preferencesDataStore(name = "sync_ledger")

internal class LocalSyncLedger(
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

    val allRecordsFlow: kotlinx.coroutines.flow.Flow<List<LocalSyncRecord>> = dataStore.data.map { preferences ->
        val json = preferences[KEY_LEDGER_DATA] ?: return@map emptyList()
        try {
            adapter.fromJson(json)?.values
                ?.sortedByDescending { it.lastAttemptAt } ?: emptyList()
        } catch (e: Exception) {
            emptyList()
        }
    }

    val recentRecordsFlow: kotlinx.coroutines.flow.Flow<List<LocalSyncRecord>> = allRecordsFlow.map { list ->
        list.take(50)
    }

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
        val now = System.currentTimeMillis()
        upsert(record.copy(
            status = LocalSyncStatus.Downloading,
            lastError = null,
            lastAttemptAt = now,
            statusEnteredAt = now,
            retryCount = 0,
            backendFailureReportedAt = null
        ))
    }

    suspend fun markImported(jobId: String, localUri: String) {
        val record = get(jobId) ?: return
        val now = System.currentTimeMillis()
        upsert(record.copy(
            status = LocalSyncStatus.Imported,
            localUri = localUri,
            lastError = null,
            lastAttemptAt = now,
            statusEnteredAt = now,
            retryCount = 0,
            backendFailureReportedAt = null
        ))
    }

    suspend fun markConfirmPending(jobId: String, localUri: String) {
        val record = get(jobId) ?: return
        val now = System.currentTimeMillis()
        upsert(record.copy(
            status = LocalSyncStatus.ConfirmPending,
            localUri = localUri,
            lastError = null,
            lastAttemptAt = now,
            statusEnteredAt = now,
            retryCount = 0,
            backendFailureReportedAt = null
        ))
    }

    suspend fun markConfirmed(jobId: String) {
        val record = get(jobId) ?: return
        val now = System.currentTimeMillis()
        upsert(record.copy(
            status = LocalSyncStatus.Confirmed,
            lastError = null,
            lastAttemptAt = now,
            statusEnteredAt = now,
            retryCount = 0,
            backendFailureReportedAt = null
        ))
    }

    suspend fun markFailed(jobId: String, error: String) {
        val record = get(jobId) ?: return
        val now = System.currentTimeMillis()
        upsert(record.copy(
            status = LocalSyncStatus.Failed,
            lastError = error,
            lastAttemptAt = now,
            statusEnteredAt = now,
            retryCount = 0,
            backendFailureReportedAt = null
        ))
    }

    suspend fun markFailureReported(jobId: String, now: Long = System.currentTimeMillis()) {
        val record = get(jobId) ?: return
        upsert(record.copy(backendFailureReportedAt = now))
    }

    suspend fun recordRetriableFailure(jobId: String, error: String, now: Long = System.currentTimeMillis()) {
        val record = get(jobId) ?: return
        upsert(
            record.copy(
                lastError = error,
                lastAttemptAt = now,
                retryCount = record.retryCount + 1
            )
        )
    }

    suspend fun markQueued(jobId: String, now: Long = System.currentTimeMillis()) {
        val record = get(jobId) ?: return
        upsert(
            record.copy(
                status = LocalSyncStatus.Queued,
                lastError = null,
                lastAttemptAt = now,
                statusEnteredAt = now,
                retryCount = 0,
                backendFailureReportedAt = null
            )
        )
    }

    suspend fun clearHistory() {
        removeByStatuses(*historyStatuses.toTypedArray())
    }

    suspend fun removeByStatuses(vararg statuses: LocalSyncStatus) {
        val statusSet = statuses.toSet()
        val updated = getRecordsMap().filterValues { it.status !in statusSet }
        saveRecordsMap(updated)
    }

    suspend fun hasActiveRecords(): Boolean {
        return getRecordsMap().values.any { it.status in activeStatuses }
    }

    suspend fun markLocalDeleted(jobId: String) {
        val record = get(jobId) ?: return
        upsert(record.copy(
            isLocalDeleted = true
        ))
    }

    suspend fun listRecent(limit: Int): List<LocalSyncRecord> {
        return getRecordsMap().values
            .sortedByDescending { it.lastAttemptAt }
            .take(limit)
    }

    suspend fun listByStatuses(vararg statuses: LocalSyncStatus): List<LocalSyncRecord> {
        val statusSet = statuses.toSet()
        return getRecordsMap().values
            .filter { it.status in statusSet }
            .sortedByDescending { it.lastAttemptAt }
    }

    suspend fun listUnreportedFailures(): List<LocalSyncRecord> {
        return getRecordsMap().values
            .filter { it.status == LocalSyncStatus.Failed && it.backendFailureReportedAt == null }
            .sortedByDescending { it.lastAttemptAt }
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
