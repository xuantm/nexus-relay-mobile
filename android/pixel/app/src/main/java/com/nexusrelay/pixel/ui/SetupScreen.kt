package com.nexusrelay.pixel.ui

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.systemBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Button
import androidx.compose.material3.Card
import androidx.compose.material3.CardDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Switch
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.nexusrelay.pixel.BuildConfig
import com.nexusrelay.pixel.api.ApiClientFactory
import com.nexusrelay.pixel.api.PairingCodeParser
import com.nexusrelay.pixel.api.RedeemPairingCodeRequest
import com.nexusrelay.pixel.auth.DeviceTokenStore
import com.nexusrelay.pixel.storage.AppSettingsStore
import com.nexusrelay.pixel.sync.SyncWorker
import com.nexusrelay.pixel.sync.ensureBackgroundSyncConfigured
import com.nexusrelay.pixel.sync.fetchCurrentFcmToken
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

@OptIn(androidx.compose.material3.ExperimentalMaterial3Api::class)
@Composable
fun SetupScreen(
    onRegistrationSuccess: () -> Unit
) {
    val context = LocalContext.current
    val coroutineScope = rememberCoroutineScope()

    var backendUrl by remember { mutableStateOf(BuildConfig.DEFAULT_BACKEND_BASE_URL) }
    var pairingCode by remember { mutableStateOf("") }
    var deviceName by remember { mutableStateOf("Pixel Client") }
    var wifiOnly by remember { mutableStateOf(true) }

    var isLoading by remember { mutableStateOf(false) }
    var errorMessage by remember { mutableStateOf<String?>(null) }
    var successMessage by remember { mutableStateOf<String?>(null) }

    val appSettingsStore = remember { AppSettingsStore(context) }
    val deviceTokenStore = remember { DeviceTokenStore(context) }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .systemBarsPadding()
            .padding(20.dp)
    ) {
        Column(
            modifier = Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(16.dp)
        ) {
            PixelScreenHeader(
                title = "NexusRelay Pixel",
                subtitle = "Connect this device"
            )

            ReadyStatusPanel(
                lastSyncLabel = "Not paired",
                scopeLabel = "Resolved during pairing"
            )

            Card(
                modifier = Modifier.fillMaxWidth(),
                shape = RoundedCornerShape(8.dp),
                colors = CardDefaults.cardColors(containerColor = MaterialTheme.colorScheme.surface)
            ) {
                Column(
                    modifier = Modifier.padding(16.dp),
                    verticalArrangement = Arrangement.spacedBy(12.dp)
                ) {
                    Text(
                        "Pair your Pixel",
                        style = MaterialTheme.typography.titleLarge,
                        fontWeight = FontWeight.Bold
                    )
                    Text(
                        "Create a pairing code from NexusRelay, then enter it here.",
                        color = MaterialTheme.colorScheme.onSurfaceVariant
                    )

                    if (BuildConfig.SHOW_BACKEND_URL_FIELD) {
                        OutlinedTextField(
                            value = backendUrl,
                            onValueChange = { backendUrl = it },
                            label = { Text("Server") },
                            singleLine = true,
                            modifier = Modifier.fillMaxWidth()
                        )
                    }

                    OutlinedTextField(
                        value = pairingCode,
                        onValueChange = { pairingCode = it },
                        label = { Text("Pairing code") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth()
                    )

                    OutlinedTextField(
                        value = deviceName,
                        onValueChange = { deviceName = it },
                        label = { Text("Device name") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth()
                    )

                    Row(
                        modifier = Modifier.fillMaxWidth(),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.SpaceBetween
                    ) {
                        Text("Wi-Fi only", fontWeight = FontWeight.SemiBold)
                        Switch(
                            checked = wifiOnly,
                            onCheckedChange = { wifiOnly = it }
                        )
                    }

                    if (errorMessage != null) {
                        Text(
                            text = errorMessage!!,
                            color = MaterialTheme.colorScheme.error,
                            style = MaterialTheme.typography.bodySmall
                        )
                    }

                    if (successMessage != null) {
                        Text(
                            text = successMessage!!,
                            color = MaterialTheme.colorScheme.primary,
                            style = MaterialTheme.typography.bodySmall
                        )
                    }

                    Button(
                        onClick = {
                            val parsed = PairingCodeParser.parse(pairingCode)
                            val actualCode = parsed?.code ?: pairingCode.trim()
                            val actualBackendUrl = if (!parsed?.baseUrl.isNullOrBlank()) parsed.baseUrl else backendUrl

                            if (actualBackendUrl.isBlank() || actualCode.isBlank() || deviceName.isBlank()) {
                                errorMessage = "Server, pairing code, and device name are required"
                                return@Button
                            }

                            isLoading = true
                            errorMessage = null
                            successMessage = null

                            coroutineScope.launch {
                                try {
                                    val api = ApiClientFactory.create(actualBackendUrl, BuildConfig.DEBUG)
                                    val storedFcmToken = appSettingsStore.fcmTokenFlow.first()
                                    val currentFcmToken = resolveFcmTokenForRegistration(
                                        storedFcmToken = storedFcmToken,
                                        fetchCurrentFcmToken = ::fetchCurrentFcmToken,
                                        saveFcmToken = appSettingsStore::saveFcmToken
                                    )

                                    val response = api.redeemPairingCode(
                                        RedeemPairingCodeRequest(
                                            code = actualCode,
                                            deviceName = deviceName,
                                            platform = "Android",
                                            fcmToken = currentFcmToken
                                        )
                                    )

                                    appSettingsStore.saveBackendBaseUrl(actualBackendUrl)
                                    appSettingsStore.saveDeviceName(deviceName)
                                    appSettingsStore.saveWifiOnly(response.wifiOnly)
                                    appSettingsStore.saveTargetId(response.targetId)
                                    appSettingsStore.saveSyncScope(response.syncScope.name)
                                    appSettingsStore.saveScopedFolderId(response.scopedFolderId)
                                    deviceTokenStore.saveDeviceToken(response.deviceToken)

                                    ensureBackgroundSyncConfigured(
                                        context = context,
                                        refreshBackendTokenNow = false
                                    )
                                    SyncWorker.enqueueOneTimeSync(context, expedited = true)

                                    successMessage = "Pixel paired"
                                    onRegistrationSuccess()
                                } catch (e: Exception) {
                                    errorMessage = "Pairing failed: ${e.localizedMessage ?: "Unknown error"}"
                                } finally {
                                    isLoading = false
                                }
                            }
                        },
                        modifier = Modifier
                            .fillMaxWidth()
                            .height(52.dp),
                        shape = RoundedCornerShape(8.dp),
                        enabled = !isLoading
                    ) {
                        if (isLoading) {
                            CircularProgressIndicator(
                                modifier = Modifier.size(20.dp),
                                strokeWidth = 2.dp,
                                color = MaterialTheme.colorScheme.onPrimary
                            )
                            Spacer(Modifier.size(8.dp))
                            Text("Pairing…", fontWeight = FontWeight.Bold)
                        } else {
                            Text("Pair Pixel", fontWeight = FontWeight.Bold)
                        }
                    }
                }
            }
        }
    }
}
