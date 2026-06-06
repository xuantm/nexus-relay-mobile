package com.nexusrelay.pixel.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.List
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.DeleteSweep
import androidx.compose.material.icons.outlined.ErrorOutline
import androidx.compose.material.icons.outlined.Settings
import androidx.compose.material.icons.outlined.Sync
import androidx.compose.material.icons.outlined.Wifi
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Scaffold
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
import androidx.compose.material3.SnackbarHost
import androidx.compose.material3.SnackbarHostState
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.nexusrelay.pixel.auth.DeviceTokenStore
import com.nexusrelay.pixel.storage.AppSettingsStore
import com.nexusrelay.pixel.storage.LocalSyncLedger
import com.nexusrelay.pixel.storage.LocalSyncRecord
import com.nexusrelay.pixel.sync.DeviceSyncRepository
import com.nexusrelay.pixel.sync.SyncWorker
import kotlinx.coroutines.launch

@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
fun StatusScreen(
    onUnregister: () -> Unit
) {
    val context = LocalContext.current
    val coroutineScope = rememberCoroutineScope()

    val appSettingsStore = remember { AppSettingsStore(context) }
    val deviceTokenStore = remember { DeviceTokenStore(context) }
    val ledger = remember { LocalSyncLedger(context) }
    val repository = remember { DeviceSyncRepository(context) }

    val backendUrl by appSettingsStore.backendBaseUrlFlow.collectAsState(initial = "")
    val deviceName by appSettingsStore.deviceNameFlow.collectAsState(initial = "")
    val targetId by appSettingsStore.targetIdFlow.collectAsState(initial = "")
    val wifiOnly by appSettingsStore.wifiOnlyFlow.collectAsState(initial = true)
    val lastSyncAt by appSettingsStore.lastSuccessfulSyncAtFlow.collectAsState(initial = 0L)
    val syncScope by appSettingsStore.syncScopeFlow.collectAsState(initial = "")
    val scopedFolderId by appSettingsStore.scopedFolderIdFlow.collectAsState(initial = "")
    val autoDeleteEnabled by appSettingsStore.autoDeleteEnabledFlow.collectAsState(initial = false)
    val autoDeleteDelayMinutes by appSettingsStore.autoDeleteDelayMinutesFlow.collectAsState(initial = 24 * 60)
    val recentJobs by ledger.recentRecordsFlow.collectAsState(initial = emptyList())

    val scopeLabel = when (syncScope) {
        "Folder" -> "Folder ${scopedFolderId?.take(8) ?: ""}"
        "AccountUploads" -> "Account uploads"
        else -> "Account uploads"
    }

    val snackbarHostState = remember { SnackbarHostState() }
    var showCleanupDialog by remember { mutableStateOf(false) }
    var selectedTab by rememberSaveable(stateSaver = PixelTabSaver) { mutableStateOf(PixelTab.Sync) }
    val cleanupPreview = buildCleanupPreview(recentJobs)

    if (showCleanupDialog) {
        CleanupConfirmDialog(
            preview = cleanupPreview,
            onConfirm = {
                showCleanupDialog = false
                coroutineScope.launch {
                    val result = repository.cleanUpSpaceNow()
                    snackbarHostState.showSnackbar(
                        "Cleaned ${result.deletedCount} files, freed ${formatBytes(result.freedBytes)}"
                    )
                }
            },
            onDismiss = { showCleanupDialog = false }
        )
    }

    Scaffold(
        topBar = {
            androidx.compose.foundation.layout.Box(
                modifier = Modifier.padding(horizontal = 16.dp, vertical = 12.dp)
            ) {
                PixelScreenHeader(
                    title = deviceName?.takeIf { it.isNotBlank() } ?: "Pixel Client",
                    subtitle = scopeLabel
                )
            }
        },
        bottomBar = {
            NavigationBar {
                NavigationBarItem(
                    selected = selectedTab == PixelTab.Sync,
                    onClick = { selectedTab = PixelTab.Sync },
                    icon = { Icon(Icons.Outlined.Sync, contentDescription = null) },
                    label = { Text("Sync") }
                )
                NavigationBarItem(
                    selected = selectedTab == PixelTab.Ledger,
                    onClick = { selectedTab = PixelTab.Ledger },
                    icon = { Icon(Icons.AutoMirrored.Outlined.List, contentDescription = null) },
                    label = { Text("Ledger") }
                )
                NavigationBarItem(
                    selected = selectedTab == PixelTab.Settings,
                    onClick = { selectedTab = PixelTab.Settings },
                    icon = { Icon(Icons.Outlined.Settings, contentDescription = null) },
                    label = { Text("Settings") }
                )
            }
        },
        snackbarHost = { SnackbarHost(snackbarHostState) }
    ) { padding ->
        when (selectedTab) {
            PixelTab.Sync -> SyncTab(
                modifier = Modifier.padding(padding),
                recentJobs = recentJobs,
                lastSyncAt = lastSyncAt,
                scopeLabel = scopeLabel,
                onSyncNow = {
                    coroutineScope.launch {
                        SyncWorker.enqueueOneTimeSync(context)
                        snackbarHostState.showSnackbar("Sync queued")
                    }
                }
            )
            PixelTab.Ledger -> LedgerTab(
                modifier = Modifier.padding(padding),
                recentJobs = recentJobs
            )
            PixelTab.Settings -> SettingsTab(
                modifier = Modifier.padding(padding),
                backendUrl = backendUrl,
                targetId = targetId,
                syncScopeLabel = scopeLabel,
                wifiOnly = wifiOnly,
                autoDeleteEnabled = autoDeleteEnabled,
                autoDeleteDelayMinutes = autoDeleteDelayMinutes,
                cleanupPreview = cleanupPreview,
                onWifiOnlyChanged = { coroutineScope.launch { appSettingsStore.saveWifiOnly(it) } },
                onAutoDeleteChanged = { coroutineScope.launch { appSettingsStore.saveAutoDeleteEnabled(it) } },
                onAutoDeleteDelayChanged = { coroutineScope.launch { appSettingsStore.saveAutoDeleteDelayMinutes(it) } },
                onCleanUpSpace = { showCleanupDialog = true },
                onUnregister = {
                    coroutineScope.launch {
                        deviceTokenStore.clear()
                        appSettingsStore.clear()
                        onUnregister()
                    }
                }
            )
        }
    }
}

@Composable
private fun SyncTab(
    modifier: Modifier = Modifier,
    recentJobs: List<LocalSyncRecord>,
    lastSyncAt: Long,
    scopeLabel: String,
    onSyncNow: () -> Unit
) {
    val metrics = buildSyncMetrics(recentJobs)
    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item {
            ReadyStatusPanel(
                lastSyncLabel = formatLastSyncTime(lastSyncAt),
                scopeLabel = scopeLabel
            )
        }
        item {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp), modifier = Modifier.fillMaxWidth()) {
                MetricCard("Confirmed", metrics.confirmed.toString(), Icons.Outlined.CheckCircle, Color(0xFF16856A), Modifier.weight(1f))
                MetricCard("Pending", metrics.pending.toString(), Icons.Outlined.Sync, Color(0xFFA76613), Modifier.weight(1f))
                MetricCard("Failed", metrics.failed.toString(), Icons.Outlined.ErrorOutline, Color(0xFFBA2F45), Modifier.weight(1f))
            }
        }
        item {
            Button(
                onClick = onSyncNow,
                modifier = Modifier.fillMaxWidth().height(52.dp),
                shape = RoundedCornerShape(8.dp)
            ) {
                Icon(Icons.Outlined.Sync, contentDescription = null)
                Spacer(Modifier.size(8.dp))
                Text("Sync now", fontWeight = FontWeight.Bold)
            }
        }
        item {
            Text("Recent ledger", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
        }
        if (recentJobs.isEmpty()) {
            item {
                Text("No sync records yet.", color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        } else {
            items(recentJobs.take(5), key = { it.jobId }) { record ->
                LedgerRecordRow(record)
            }
        }
    }
}

@Composable
private fun LedgerTab(
    modifier: Modifier = Modifier,
    recentJobs: List<LocalSyncRecord>
) {
    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(8.dp)
    ) {
        item {
            Text("Sync ledger", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
        }
        if (recentJobs.isEmpty()) {
            item {
                Text("No sync records found.", color = MaterialTheme.colorScheme.onSurfaceVariant)
            }
        } else {
            items(recentJobs, key = { it.jobId }) { record ->
                LedgerRecordRow(record)
            }
        }
    }
}

@Composable
private fun SettingsTab(
    modifier: Modifier = Modifier,
    backendUrl: String?,
    targetId: String?,
    syncScopeLabel: String,
    wifiOnly: Boolean,
    autoDeleteEnabled: Boolean,
    autoDeleteDelayMinutes: Int,
    cleanupPreview: CleanupPreview,
    onWifiOnlyChanged: (Boolean) -> Unit,
    onAutoDeleteChanged: (Boolean) -> Unit,
    onAutoDeleteDelayChanged: (Int) -> Unit,
    onCleanUpSpace: () -> Unit,
    onUnregister: () -> Unit
) {
    LazyColumn(
        modifier = modifier.fillMaxSize(),
        contentPadding = PaddingValues(16.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp)
    ) {
        item {
            Card(
                shape = RoundedCornerShape(8.dp),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
            ) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Device target", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                    Text("Server: ${backendUrl?.takeIf { it.isNotBlank() } ?: "Not set"}")
                    Text("Target: ${targetId?.take(8) ?: "None"}")
                    Text("Scope: $syncScopeLabel")
                }
            }
        }
        item {
            Card(
                shape = RoundedCornerShape(8.dp),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
            ) {
                Column(Modifier.padding(16.dp)) {
                    SettingsRow("Wi-Fi only", "Avoid mobile data downloads", Icons.Outlined.Wifi) {
                        Switch(checked = wifiOnly, onCheckedChange = onWifiOnlyChanged)
                    }
                    SettingsRow("Auto-delete after sync", "Clean local copies after a delay", Icons.Outlined.DeleteSweep) {
                        Switch(checked = autoDeleteEnabled, onCheckedChange = onAutoDeleteChanged)
                    }
                    if (autoDeleteEnabled) {
                        DelaySelector(autoDeleteDelayMinutes, onAutoDeleteDelayChanged)
                    }
                    Spacer(Modifier.height(8.dp))
                    OutlinedButton(
                        onClick = onCleanUpSpace,
                        enabled = cleanupPreview.cleanableCount > 0,
                        modifier = Modifier.fillMaxWidth()
                    ) {
                        Icon(Icons.Outlined.DeleteSweep, contentDescription = null)
                        Spacer(Modifier.size(8.dp))
                        Text("Clean up ${cleanupPreview.cleanableBytesLabel}")
                    }
                }
            }
        }
        item {
            Card(
                shape = RoundedCornerShape(8.dp),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
            ) {
                Column(Modifier.padding(16.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
                    Text("Background sync", style = MaterialTheme.typography.titleMedium, fontWeight = FontWeight.Bold)
                    Text("Push wake-up: Firebase Cloud Messaging")
                    Text("Fallback polling: every 15 minutes")
                }
            }
        }
        item {
            OutlinedButton(onClick = onUnregister, modifier = Modifier.fillMaxWidth()) {
                Text("Unregister device")
            }
        }
    }
}

@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
private fun DelaySelector(selectedMinutes: Int, onSelected: (Int) -> Unit) {
    val options = listOf(30, 120, 360, 1440)
    SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
        options.forEachIndexed { index, minutes ->
            SegmentedButton(
                selected = selectedMinutes == minutes,
                onClick = { onSelected(minutes) },
                shape = SegmentedButtonDefaults.itemShape(index = index, count = options.size)
            ) {
                Text(
                    when (minutes) {
                        30 -> "30m"
                        120 -> "2h"
                        360 -> "6h"
                        else -> "24h"
                    }
                )
            }
        }
    }
}
