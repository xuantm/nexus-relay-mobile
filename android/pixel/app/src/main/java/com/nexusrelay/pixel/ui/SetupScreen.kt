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
import androidx.compose.material3.SegmentedButton
import androidx.compose.material3.SegmentedButtonDefaults
import androidx.compose.material3.SingleChoiceSegmentedButtonRow
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
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import com.nexusrelay.pixel.BuildConfig
import com.nexusrelay.pixel.api.ApiClientFactory
import com.nexusrelay.pixel.api.DeviceSyncScope
import com.nexusrelay.pixel.api.LoginRequest
import com.nexusrelay.pixel.api.RegisterDeviceRequest
import com.nexusrelay.pixel.auth.DeviceTokenStore
import com.nexusrelay.pixel.storage.AppSettingsStore
import com.nexusrelay.pixel.sync.PollWorker
import com.nexusrelay.pixel.sync.SyncWorker
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
    var username by remember { mutableStateOf("") }
    var password by remember { mutableStateOf("") }
    var deviceName by remember { mutableStateOf("Pixel Client") }
    var wifiOnly by remember { mutableStateOf(true) }
    var syncScope by remember { mutableStateOf(DeviceSyncScope.AccountUploads) }
    var scopedFolderId by remember { mutableStateOf("") }

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
                lastSyncLabel = "Not registered",
                scopeLabel = "Choose during setup"
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
                        "Use your NexusRelay account once. This app stores a device token for future sync.",
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
                        value = username,
                        onValueChange = { username = it },
                        label = { Text("Username") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth()
                    )

                    OutlinedTextField(
                        value = password,
                        onValueChange = { password = it },
                        label = { Text("Password") },
                        singleLine = true,
                        modifier = Modifier.fillMaxWidth(),
                        visualTransformation = PasswordVisualTransformation()
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

                    SingleChoiceSegmentedButtonRow(modifier = Modifier.fillMaxWidth()) {
                        SegmentedButton(
                            selected = syncScope == DeviceSyncScope.AccountUploads,
                            onClick = { syncScope = DeviceSyncScope.AccountUploads },
                            shape = SegmentedButtonDefaults.itemShape(index = 0, count = 2)
                        ) {
                            Text("Account")
                        }
                        SegmentedButton(
                            selected = syncScope == DeviceSyncScope.Folder,
                            onClick = { syncScope = DeviceSyncScope.Folder },
                            shape = SegmentedButtonDefaults.itemShape(index = 1, count = 2)
                        ) {
                            Text("Folder")
                        }
                    }

                    if (syncScope == DeviceSyncScope.Folder) {
                        OutlinedTextField(
                            value = scopedFolderId,
                            onValueChange = { scopedFolderId = it },
                            label = { Text("Folder ID") },
                            singleLine = true,
                            modifier = Modifier.fillMaxWidth()
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
                            if (backendUrl.isBlank() || deviceName.isBlank() || username.isBlank() || password.isBlank()) {
                                errorMessage = "Server, account, and device name are required"
                                return@Button
                            }
                            if (syncScope == DeviceSyncScope.Folder && scopedFolderId.isBlank()) {
                                errorMessage = "Folder ID is required for folder sync"
                                return@Button
                            }
                            isLoading = true
                            errorMessage = null
                            successMessage = null

                            coroutineScope.launch {
                                try {
                                    val api = ApiClientFactory.create(backendUrl, BuildConfig.DEBUG)
                                    val loginResponse = api.login(LoginRequest(username = username, password = password))
                                    val storedFcmToken = appSettingsStore.fcmTokenFlow.first()
                                    val currentFcmToken = resolveFcmTokenForRegistration(
                                        storedFcmToken = storedFcmToken,
                                        fetchCurrentFcmToken = ::fetchCurrentFcmToken,
                                        saveFcmToken = appSettingsStore::saveFcmToken
                                    )
                                    val response = api.registerDevice(
                                        authorization = "Bearer ${loginResponse.token}",
                                        request = RegisterDeviceRequest(
                                            deviceName = deviceName,
                                            fcmToken = currentFcmToken,
                                            wifiOnly = wifiOnly,
                                            syncScope = syncScope,
                                            scopedFolderId = scopedFolderId.takeIf {
                                                syncScope == DeviceSyncScope.Folder && it.isNotBlank()
                                            }
                                        )
                                    )

                                    appSettingsStore.saveBackendBaseUrl(backendUrl)
                                    appSettingsStore.saveDeviceName(deviceName)
                                    appSettingsStore.saveWifiOnly(wifiOnly)
                                    appSettingsStore.saveTargetId(response.targetId)
                                    appSettingsStore.saveSyncScope(response.syncScope.name)
                                    appSettingsStore.saveScopedFolderId(response.scopedFolderId)
                                    deviceTokenStore.saveDeviceToken(response.deviceToken)

                                    // Schedule polling and run immediate sync
                                    PollWorker.schedulePeriodicPoll(context)
                                    SyncWorker.enqueueOneTimeSync(context)

                                    successMessage = "Pixel registered"
                                    onRegistrationSuccess()
                                } catch (e: Exception) {
                                    errorMessage = "Registration failed: ${e.localizedMessage ?: "Unknown error"}"
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
                            Text("Registering…", fontWeight = FontWeight.Bold)
                        } else {
                            Text("Register Pixel", fontWeight = FontWeight.Bold)
                        }
                    }
                }
            }
        }
    }
}
