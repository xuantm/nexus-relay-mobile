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
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
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
    val backendFailureReportedAt: Long? = null,
    val leaseId: String? = null,
    val workerRunId: String? = null,
    val progressBytes: Long = 0L,
    val totalBytes: Long? = null,
    val stage: String? = null
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
    private val ledgerMutex = Mutex()

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

    private suspend fun readRecordsMap(): Map<String, LocalSyncRecord> {
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
        ledgerMutex.withLock {
            val map = readRecordsMap().toMutableMap()
            map[record.jobId] = record
            saveRecordsMap(map)
        }
    }

    suspend fun get(jobId: String): LocalSyncRecord? {
        return ledgerMutex.withLock {
            readRecordsMap()[jobId]
        }
    }

    suspend fun markDownloading(jobId: String) {
        val now = System.currentTimeMillis()
        updateRecord(jobId) { record ->
            record.copy(
                status = LocalSyncStatus.Downloading,
                lastError = null,
                lastAttemptAt = now,
                statusEnteredAt = now,
                retryCount = 0,
                backendFailureReportedAt = null,
                stage = "Downloading"
            )
        }
    }

    suspend fun markClaimed(
        jobId: String,
        leaseId: String,
        workerRunId: String,
        now: Long = System.currentTimeMillis()
    ) {
        updateRecord(jobId) { record ->
            record.copy(
                status = LocalSyncStatus.Queued,
                lastError = null,
                lastAttemptAt = now,
                statusEnteredAt = now,
                retryCount = 0,
                backendFailureReportedAt = null,
                leaseId = leaseId,
                workerRunId = workerRunId,
                progressBytes = 0L,
                totalBytes = record.sizeBytes,
                stage = "Claimed"
            )
        }
    }

    suspend fun markProgress(
        jobId: String,
        stage: String,
        progressBytes: Long,
        totalBytes: Long?,
        now: Long = System.currentTimeMillis()
    ) {
        updateRecord(jobId) { record ->
            val nextStatus = stageToStatus(stage, record.status)
            val nextStatusEnteredAt = if (nextStatus == record.status) {
                record.statusEnteredAt
            } else {
                now
            }

            record.copy(
                status = nextStatus,
                lastError = null,
                lastAttemptAt = now,
                statusEnteredAt = nextStatusEnteredAt,
                progressBytes = progressBytes,
                totalBytes = totalBytes ?: record.totalBytes ?: record.sizeBytes,
                stage = stage
            )
        }
    }

    suspend fun markImported(jobId: String, localUri: String) {
        val now = System.currentTimeMillis()
        updateRecord(jobId) { record ->
            record.copy(
                status = LocalSyncStatus.Imported,
                localUri = localUri,
                lastError = null,
                lastAttemptAt = now,
                statusEnteredAt = now,
                retryCount = 0,
                backendFailureReportedAt = null,
                progressBytes = record.totalBytes ?: record.sizeBytes,
                totalBytes = record.totalBytes ?: record.sizeBytes,
                stage = "Importing"
            )
        }
    }

    suspend fun markConfirmPending(jobId: String, localUri: String) {
        val now = System.currentTimeMillis()
        updateRecord(jobId) { record ->
            record.copy(
                status = LocalSyncStatus.ConfirmPending,
                localUri = localUri,
                lastError = null,
                lastAttemptAt = now,
                statusEnteredAt = now,
                retryCount = 0,
                backendFailureReportedAt = null,
                progressBytes = record.totalBytes ?: record.sizeBytes,
                totalBytes = record.totalBytes ?: record.sizeBytes,
                stage = "Confirming"
            )
        }
    }

    suspend fun markConfirmed(jobId: String) {
        val now = System.currentTimeMillis()
        updateRecord(jobId) { record ->
            record.copy(
                status = LocalSyncStatus.Confirmed,
                lastError = null,
                lastAttemptAt = now,
                statusEnteredAt = now,
                retryCount = 0,
                backendFailureReportedAt = null,
                progressBytes = record.totalBytes ?: record.sizeBytes,
                totalBytes = record.totalBytes ?: record.sizeBytes,
                stage = "Confirmed"
            )
        }
    }

    suspend fun markFailed(jobId: String, error: String) {
        val now = System.currentTimeMillis()
        updateRecord(jobId) { record ->
            record.copy(
                status = LocalSyncStatus.Failed,
                lastError = error,
                lastAttemptAt = now,
                statusEnteredAt = now,
                retryCount = 0,
                backendFailureReportedAt = null
            )
        }
    }

    suspend fun markFailureReported(jobId: String, now: Long = System.currentTimeMillis()) {
        updateRecord(jobId) { record ->
            record.copy(backendFailureReportedAt = now)
        }
    }

    suspend fun recordRetriableFailure(jobId: String, error: String, now: Long = System.currentTimeMillis()) {
        updateRecord(jobId) { record ->
            record.copy(
                lastError = error,
                lastAttemptAt = now,
                retryCount = record.retryCount + 1
            )
        }
    }

    suspend fun markQueued(jobId: String, now: Long = System.currentTimeMillis()) {
        updateRecord(jobId) { record ->
            record.copy(
                status = LocalSyncStatus.Queued,
                lastError = null,
                lastAttemptAt = now,
                statusEnteredAt = now,
                retryCount = 0,
                backendFailureReportedAt = null,
                leaseId = null,
                workerRunId = null,
                progressBytes = 0L,
                totalBytes = record.sizeBytes,
                stage = "Queued"
            )
        }
    }

    suspend fun clearHistory() {
        removeByStatuses(*historyStatuses.toTypedArray())
    }

    suspend fun removeByStatuses(vararg statuses: LocalSyncStatus) {
        val statusSet = statuses.toSet()
        ledgerMutex.withLock {
            val updated = readRecordsMap().filterValues { it.status !in statusSet }
            saveRecordsMap(updated)
        }
    }

    suspend fun hasActiveRecords(): Boolean {
        return ledgerMutex.withLock {
            readRecordsMap().values.any { it.status in activeStatuses }
        }
    }

    suspend fun markLocalDeleted(jobId: String) {
        updateRecord(jobId) { record ->
            record.copy(isLocalDeleted = true)
        }
    }

    suspend fun listRecent(limit: Int): List<LocalSyncRecord> {
        return ledgerMutex.withLock {
            readRecordsMap().values
                .sortedByDescending { it.lastAttemptAt }
                .take(limit)
        }
    }

    suspend fun listByStatuses(vararg statuses: LocalSyncStatus): List<LocalSyncRecord> {
        val statusSet = statuses.toSet()
        return ledgerMutex.withLock {
            readRecordsMap().values
                .filter { it.status in statusSet }
                .sortedByDescending { it.lastAttemptAt }
        }
    }

    suspend fun listUnreportedFailures(): List<LocalSyncRecord> {
        return ledgerMutex.withLock {
            readRecordsMap().values
                .filter { it.status == LocalSyncStatus.Failed && it.backendFailureReportedAt == null }
                .sortedByDescending { it.lastAttemptAt }
        }
    }

    suspend fun clear() {
        ledgerMutex.withLock {
            dataStore.edit { preferences ->
                preferences.clear()
            }
        }
    }

    private suspend fun updateRecord(
        jobId: String,
        transform: (LocalSyncRecord) -> LocalSyncRecord
    ) {
        ledgerMutex.withLock {
            val map = readRecordsMap().toMutableMap()
            val record = map[jobId] ?: return@withLock
            map[jobId] = transform(record)
            saveRecordsMap(map)
        }
    }

    companion object {
        private val KEY_LEDGER_DATA = stringPreferencesKey("ledger_data")
    }
}

private fun stageToStatus(stage: String, currentStatus: LocalSyncStatus): LocalSyncStatus =
    when (stage) {
        "Claimed" -> LocalSyncStatus.Queued
        "Downloading" -> LocalSyncStatus.Downloading
        "Importing" -> LocalSyncStatus.Imported
        "Confirming" -> LocalSyncStatus.ConfirmPending
        else -> currentStatus
    }
