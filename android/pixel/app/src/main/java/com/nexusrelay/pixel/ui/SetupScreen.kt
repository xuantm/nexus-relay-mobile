package com.nexusrelay.pixel.ui

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
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
import com.nexusrelay.pixel.BuildConfig
import com.nexusrelay.pixel.api.ApiClientFactory
import com.nexusrelay.pixel.api.RegisterDeviceRequest
import com.nexusrelay.pixel.auth.DeviceTokenStore
import com.nexusrelay.pixel.storage.AppSettingsStore
import com.nexusrelay.pixel.sync.PollWorker
import com.nexusrelay.pixel.sync.SyncWorker
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun SetupScreen(
    onRegistrationSuccess: () -> Unit
) {
    val context = LocalContext.current
    val coroutineScope = rememberCoroutineScope()

    var backendUrl by remember { mutableStateOf("https://") }
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
            .background(
                brush = Brush.verticalGradient(
                    colors = listOf(
                        Color(0xFF0F0F1A),
                        Color(0xFF05050A)
                    )
                )
            ),
        contentAlignment = Alignment.Center
    ) {
        Card(
            modifier = Modifier
                .fillMaxWidth()
                .padding(24.dp),
            shape = RoundedCornerShape(24.dp),
            colors = CardDefaults.cardColors(
                containerColor = Color(0xFF1E1E2F).copy(alpha = 0.9f)
            ),
            elevation = CardDefaults.cardElevation(defaultElevation = 8.dp)
        ) {
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(24.dp),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(16.dp)
            ) {
                Text(
                    text = "Register Device",
                    fontSize = 24.sp,
                    fontWeight = FontWeight.Bold,
                    color = Color.White
                )

                Text(
                    text = "Connect this device as a companion to your NexusRelay server.",
                    fontSize = 14.sp,
                    color = Color.Gray,
                    modifier = Modifier.padding(bottom = 8.dp)
                )

                OutlinedTextField(
                    value = backendUrl,
                    onValueChange = { backendUrl = it },
                    label = { Text("Backend URL", color = Color.LightGray) },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )

                OutlinedTextField(
                    value = deviceName,
                    onValueChange = { deviceName = it },
                    label = { Text("Device Name", color = Color.LightGray) },
                    singleLine = true,
                    modifier = Modifier.fillMaxWidth()
                )

                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(vertical = 8.dp),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.SpaceBetween
                ) {
                    Text(
                        text = "Sync on Wi-Fi Only",
                        color = Color.White,
                        fontSize = 16.sp
                    )
                    Switch(
                        checked = wifiOnly,
                        onCheckedChange = { wifiOnly = it }
                    )
                }

                if (errorMessage != null) {
                    Text(
                        text = errorMessage!!,
                        color = MaterialTheme.colorScheme.error,
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Medium
                    )
                }

                if (successMessage != null) {
                    Text(
                        text = successMessage!!,
                        color = Color(0xFF00E5FF),
                        fontSize = 14.sp,
                        fontWeight = FontWeight.Medium
                    )
                }

                Button(
                    onClick = {
                        if (backendUrl.isBlank() || deviceName.isBlank()) {
                            errorMessage = "All fields are required"
                            return@Button
                        }
                        isLoading = true
                        errorMessage = null
                        successMessage = null

                        coroutineScope.launch {
                            try {
                                val api = ApiClientFactory.create(backendUrl, BuildConfig.DEBUG)
                                // Fetch current FCM token if available
                                val currentFcmToken = appSettingsStore.fcmTokenFlow.first()
                                val response = api.registerDevice(
                                    RegisterDeviceRequest(
                                        deviceName = deviceName,
                                        fcmToken = currentFcmToken,
                                        wifiOnly = wifiOnly
                                    )
                                )

                                appSettingsStore.saveBackendBaseUrl(backendUrl)
                                appSettingsStore.saveDeviceName(deviceName)
                                appSettingsStore.saveWifiOnly(wifiOnly)
                                appSettingsStore.saveTargetId(response.targetId)
                                deviceTokenStore.saveDeviceToken(response.deviceToken)

                                // Schedule polling and run immediate sync
                                PollWorker.schedulePeriodicPoll(context)
                                SyncWorker.enqueueOneTimeSync(context)

                                successMessage = "Registration successful!"
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
                        .height(50.dp),
                    shape = RoundedCornerShape(12.dp),
                    enabled = !isLoading,
                    colors = ButtonDefaults.buttonColors(
                        containerColor = MaterialTheme.colorScheme.primary
                    )
                ) {
                    if (isLoading) {
                        CircularProgressIndicator(
                            color = Color.White,
                            modifier = Modifier.size(24.dp),
                            strokeWidth = 2.dp
                        )
                    } else {
                        Text(
                            text = "Register",
                            fontSize = 16.sp,
                            fontWeight = FontWeight.Bold,
                            color = Color.White
                        )
                    }
                }
            }
        }
    }
}
