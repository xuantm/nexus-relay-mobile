package com.nexusrelay.pixel.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.nexusrelay.pixel.auth.DeviceTokenStore
import com.nexusrelay.pixel.storage.AppSettingsStore
import com.nexusrelay.pixel.storage.LocalSyncLedger
import com.nexusrelay.pixel.storage.LocalSyncRecord
import com.nexusrelay.pixel.storage.LocalSyncStatus
import com.nexusrelay.pixel.sync.SyncWorker
import kotlinx.coroutines.launch
import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale

@Composable
fun StatusScreen(
    onUnregister: () -> Unit
) {
    val context = LocalContext.current
    val coroutineScope = rememberCoroutineScope()

    val appSettingsStore = remember { AppSettingsStore(context) }
    val deviceTokenStore = remember { DeviceTokenStore(context) }
    val ledger = remember { LocalSyncLedger(context) }

    val backendUrl by appSettingsStore.backendBaseUrlFlow.collectAsState(initial = "")
    val deviceName by appSettingsStore.deviceNameFlow.collectAsState(initial = "")
    val targetId by appSettingsStore.targetIdFlow.collectAsState(initial = "")
    val wifiOnly by appSettingsStore.wifiOnlyFlow.collectAsState(initial = true)
    val lastSyncAt by appSettingsStore.lastSuccessfulSyncAtFlow.collectAsState(initial = 0L)
    val syncScope by appSettingsStore.syncScopeFlow.collectAsState(initial = "")
    val scopedFolderId by appSettingsStore.scopedFolderIdFlow.collectAsState(initial = "")

    val recentJobs by ledger.recentRecordsFlow.collectAsState(initial = emptyList())

    val confirmedCount = recentJobs.count { it.status == LocalSyncStatus.Confirmed }
    val failedCount = recentJobs.count { it.status == LocalSyncStatus.Failed }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(
                brush = Brush.verticalGradient(
                    colors = listOf(
                        Color(0xFF0F0F1A),
                        Color(0xFF05050A)
                    )
                )
            )
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .padding(16.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(vertical = 8.dp),
                horizontalArrangement = Arrangement.SpaceBetween,
                verticalAlignment = Alignment.CenterVertically
            ) {
                Column {
                    Text(
                        text = "Pixel Sync Companion",
                        fontSize = 20.sp,
                        fontWeight = FontWeight.Bold,
                        color = Color.White
                    )
                    Text(
                        text = deviceName ?: "Active Device",
                        fontSize = 14.sp,
                        color = Color.Gray
                    )
                }

                Button(
                    onClick = {
                        coroutineScope.launch {
                            deviceTokenStore.clear()
                            appSettingsStore.clear()
                            onUnregister()
                        }
                    },
                    colors = ButtonDefaults.buttonColors(containerColor = Color.DarkGray)
                ) {
                    Text("Unregister", color = Color.White)
                }
            }

            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(16.dp),
                colors = CardDefaults.cardColors(containerColor = Color(0xFF1E1E2F))
            ) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp)
                ) {
                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Text("Server Address", color = Color.LightGray, fontSize = 14.sp)
                        Text(backendUrl ?: "Not set", color = Color.White, fontWeight = FontWeight.SemiBold, fontSize = 14.sp)
                    }

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Text("Target ID", color = Color.LightGray, fontSize = 14.sp)
                        Text(targetId?.take(8) ?: "None", color = Color.White, fontWeight = FontWeight.SemiBold, fontSize = 14.sp)
                    }

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Text("Sync Scope", color = Color.LightGray, fontSize = 14.sp)
                        val scopeText = when (syncScope) {
                            "Folder" -> "Folder ${scopedFolderId?.take(8) ?: ""}"
                            "AccountUploads" -> "Account uploads"
                            else -> "Account uploads"
                        }
                        Text(scopeText, color = Color.White, fontWeight = FontWeight.SemiBold, fontSize = 14.sp)
                    }

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Text("Last Sync", color = Color.LightGray, fontSize = 14.sp)
                        val lastSyncString = if (lastSyncAt > 0L) {
                            SimpleDateFormat("HH:mm:ss dd/MM", Locale.getDefault()).format(Date(lastSyncAt))
                        } else {
                            "Never"
                        }
                        Text(lastSyncString, color = Color.White, fontWeight = FontWeight.SemiBold, fontSize = 14.sp)
                    }

                    HorizontalDivider(color = Color.DarkGray, modifier = Modifier.padding(vertical = 4.dp))

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        horizontalArrangement = Arrangement.SpaceBetween,
                        verticalAlignment = Alignment.CenterVertically
                    ) {
                        Text("Wi-Fi Only Sync", color = Color.White, fontSize = 15.sp)
                        Switch(
                            checked = wifiOnly,
                            onCheckedChange = {
                                coroutineScope.launch {
                                    appSettingsStore.saveWifiOnly(it)
                                }
                            }
                        )
                    }
                }
            }

            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                Card(
                    modifier = Modifier.weight(1f),
                    shape = RoundedCornerShape(12.dp),
                    colors = CardDefaults.cardColors(containerColor = Color(0xFF14221F))
                ) {
                    Column(
                        modifier = Modifier.padding(12.dp),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        Text("Confirmed", color = Color(0xFF00E5FF), fontSize = 12.sp)
                        Text("$confirmedCount", color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.Bold)
                    }
                }

                Card(
                    modifier = Modifier.weight(1f),
                    shape = RoundedCornerShape(12.dp),
                    colors = CardDefaults.cardColors(containerColor = Color(0xFF2E1C1C))
                ) {
                    Column(
                        modifier = Modifier.padding(12.dp),
                        horizontalAlignment = Alignment.CenterHorizontally
                    ) {
                        Text("Failed", color = Color(0xFFD32F2F), fontSize = 12.sp)
                        Text("$failedCount", color = Color.White, fontSize = 20.sp, fontWeight = FontWeight.Bold)
                    }
                }
            }

            Button(
                onClick = {
                    coroutineScope.launch {
                        SyncWorker.enqueueOneTimeSync(context)
                    }
                },
                modifier = Modifier
                    .fillMaxWidth()
                    .height(48.dp),
                shape = RoundedCornerShape(12.dp),
                colors = ButtonDefaults.buttonColors(containerColor = MaterialTheme.colorScheme.primary)
            ) {
                Text("Sync Now", fontWeight = FontWeight.Bold, fontSize = 16.sp, color = Color.White)
            }

            Text(
                text = "Sync Ledger",
                fontSize = 16.sp,
                fontWeight = FontWeight.Bold,
                color = Color.White,
                modifier = Modifier.padding(top = 8.dp)
            )

            LazyColumn(
                modifier = Modifier.fillMaxWidth().weight(1f),
                verticalArrangement = Arrangement.spacedBy(8.dp)
            ) {
                if (recentJobs.isEmpty()) {
                    item {
                        Box(
                            modifier = Modifier.fillMaxWidth().padding(32.dp),
                            contentAlignment = Alignment.Center
                        ) {
                            Text("No sync records found.", color = Color.Gray, fontSize = 14.sp)
                        }
                    }
                } else {
                    items(recentJobs) { record ->
                        JobItemRow(record)
                    }
                }
            }
        }
    }
}

@Composable
fun JobItemRow(record: LocalSyncRecord) {
    val statusColor = when (record.status) {
        LocalSyncStatus.Confirmed -> Color(0xFF00E5FF)
        LocalSyncStatus.Failed -> Color(0xFFD32F2F)
        LocalSyncStatus.Downloading -> Color(0xFFFFB300)
        LocalSyncStatus.ConfirmPending -> Color(0xFF8E24AA)
        else -> Color.Gray
    }

    Card(
        modifier = Modifier.fillMaxWidth(),
        shape = RoundedCornerShape(8.dp),
        colors = CardDefaults.cardColors(containerColor = Color(0xFF1E1E2F).copy(alpha = 0.5f))
    ) {
        Row(
            modifier = Modifier.padding(12.dp),
            horizontalArrangement = Arrangement.SpaceBetween,
            verticalAlignment = Alignment.CenterVertically
        ) {
            Column(modifier = Modifier.weight(1f)) {
                Text(record.fileName, color = Color.White, fontSize = 14.sp, fontWeight = FontWeight.Medium)
                Text(
                    text = "${record.mimeType} • ${(record.sizeBytes / 1024.0 / 1024.0).let { "%.2f".format(it) }} MB",
                    color = Color.Gray,
                    fontSize = 12.sp
                )
                if (record.status == LocalSyncStatus.Failed && !record.lastError.isNullOrBlank()) {
                    Text("Error: ${record.lastError}", color = Color(0xFFD32F2F), fontSize = 11.sp)
                }
            }

            Surface(
                color = statusColor.copy(alpha = 0.2f),
                shape = RoundedCornerShape(4.dp),
                modifier = Modifier.padding(start = 8.dp)
            ) {
                Text(
                    text = record.status.name,
                    color = statusColor,
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Bold,
                    modifier = Modifier.padding(horizontal = 6.dp, vertical = 2.dp)
                )
            }
        }
    }
}
