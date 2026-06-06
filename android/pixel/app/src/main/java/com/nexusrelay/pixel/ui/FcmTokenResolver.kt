package com.nexusrelay.pixel.ui

/**
 * Resolves the FCM token for device registration.
 * Attempts to fetch the current FCM token, and if successful, saves it.
 * If fetching the current token fails, falls back to the stored FCM token.
 */
suspend fun resolveFcmTokenForRegistration(
    storedFcmToken: String?,
    fetchCurrentFcmToken: suspend () -> String,
    saveFcmToken: suspend (String) -> Unit
): String? {
    return try {
        val current = fetchCurrentFcmToken()
        if (current != storedFcmToken) {
            saveFcmToken(current)
        }
        current
    } catch (e: Exception) {
        storedFcmToken
    }
}
