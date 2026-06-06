package com.nexusrelay.pixel.sync

import android.content.Context
import android.util.Log
import com.google.firebase.messaging.FirebaseMessaging
import com.nexusrelay.pixel.BuildConfig
import com.nexusrelay.pixel.api.ApiClientFactory
import com.nexusrelay.pixel.api.UpdateDeviceFcmTokenRequest
import com.nexusrelay.pixel.auth.DeviceTokenStore
import com.nexusrelay.pixel.storage.AppSettingsStore
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

private const val TAG = "FcmTokenSync"

suspend fun fetchCurrentFcmToken(): String = suspendCancellableCoroutine { continuation ->
    FirebaseMessaging.getInstance().token.addOnCompleteListener { task ->
        if (!continuation.isActive) {
            return@addOnCompleteListener
        }

        if (!task.isSuccessful) {
            continuation.resumeWithException(
                task.exception ?: IllegalStateException("FCM token fetch failed")
            )
            return@addOnCompleteListener
        }

        val token = task.result
        if (token.isNullOrBlank()) {
            continuation.resumeWithException(IllegalStateException("FCM token fetch returned no token"))
        } else {
            continuation.resume(token)
        }
    }
}

suspend fun refreshBackendFcmToken(context: Context, tokenOverride: String? = null): Boolean {
    val appSettingsStore = AppSettingsStore(context)
    val fcmToken = tokenOverride ?: runCatching { fetchCurrentFcmToken() }
        .onFailure { Log.w(TAG, "Unable to fetch current FCM token", it) }
        .getOrNull()

    if (fcmToken.isNullOrBlank()) {
        return false
    }

    appSettingsStore.saveFcmToken(fcmToken)

    val backendUrl = appSettingsStore.backendBaseUrlFlow.first()
    val deviceToken = DeviceTokenStore(context).getDeviceToken()
    if (backendUrl.isNullOrBlank() || deviceToken.isNullOrBlank()) {
        return false
    }

    return runCatching {
        val api = ApiClientFactory.create(backendUrl, BuildConfig.DEBUG)
        api.updateFcmToken(deviceToken, UpdateDeviceFcmTokenRequest(fcmToken))
    }.onFailure {
        Log.w(TAG, "Unable to update backend FCM token", it)
    }.isSuccess
}
