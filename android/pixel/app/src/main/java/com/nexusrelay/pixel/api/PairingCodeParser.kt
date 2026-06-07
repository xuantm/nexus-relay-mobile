package com.nexusrelay.pixel.api

import com.squareup.moshi.Moshi
import com.squareup.moshi.kotlin.reflect.KotlinJsonAdapterFactory

object PairingCodeParser {
    private val moshi = Moshi.Builder()
        .add(KotlinJsonAdapterFactory())
        .build()

    private val adapter = moshi.adapter(PairingCodePayload::class.java)

    fun parse(text: String): PairingCodePayload? {
        val trimmed = text.trim()
        if (trimmed.isEmpty()) return null

        if (trimmed.startsWith("{")) {
            return try {
                adapter.fromJson(trimmed)?.let { payload ->
                    val cleanBaseUrl = payload.baseUrl.trim()
                    val cleanCode = payload.code.trim()
                    if (cleanCode.isEmpty()) null
                    else PairingCodePayload(cleanBaseUrl, cleanCode)
                }
            } catch (e: Exception) {
                null
            }
        }

        return PairingCodePayload(baseUrl = "", code = trimmed)
    }
}
