package com.nexusrelay.pixel

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import com.nexusrelay.pixel.auth.DeviceTokenStore
import com.nexusrelay.pixel.ui.SetupScreen
import com.nexusrelay.pixel.ui.theme.NexusRelayPixelTheme

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            NexusRelayPixelTheme {
                Surface(
                    modifier = Modifier.fillMaxSize(),
                    color = MaterialTheme.colorScheme.background
                ) {
                    val context = LocalContext.current
                    val tokenStore = remember { DeviceTokenStore(context) }
                    var isRegistered by remember { mutableStateOf<Boolean?>(null) }

                    LaunchedEffect(Unit) {
                        val token = tokenStore.getDeviceToken()
                        isRegistered = token != null
                    }

                    when (isRegistered) {
                        null -> {
                            Box(
                                modifier = Modifier.fillMaxSize(),
                                contentAlignment = Alignment.Center
                            ) {
                                CircularProgressIndicator()
                            }
                        }
                        false -> {
                            SetupScreen(
                                onRegistrationSuccess = {
                                    isRegistered = true
                                }
                            )
                        }
                        true -> {
                            com.nexusrelay.pixel.ui.StatusScreen(
                                onUnregister = {
                                    com.nexusrelay.pixel.sync.BackgroundSyncWatchdogReceiver.cancel(context)
                                    com.nexusrelay.pixel.sync.PollWorker.cancelPeriodicPoll(context)
                                    isRegistered = false
                                }
                            )
                        }
                    }
                }
            }
        }
    }
}
