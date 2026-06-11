package com.nexusrelay.pixel.media

import android.content.ContentValues
import android.content.Context
import android.net.Uri
import android.os.Build
import android.provider.MediaStore
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.InputStream

interface MediaImporter {
    suspend fun importMedia(
        fileName: String,
        mimeType: String,
        inputStream: InputStream,
        sizeBytes: Long,
        onBytesCopied: suspend (Long) -> Unit = {}
    ): String
}

class MediaStoreImporter(private val context: Context) : MediaImporter {

    override
    suspend fun importMedia(
        fileName: String,
        mimeType: String,
        inputStream: InputStream,
        sizeBytes: Long,
        onBytesCopied: suspend (Long) -> Unit
    ): String = withContext(Dispatchers.IO) {
        val resolver = context.contentResolver
        val contentValues = ContentValues().apply {
            put(MediaStore.MediaColumns.DISPLAY_NAME, fileName)
            put(MediaStore.MediaColumns.MIME_TYPE, mimeType)
            put(MediaStore.MediaColumns.SIZE, sizeBytes)
            
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                put(MediaStore.MediaColumns.IS_PENDING, 1)
            }
        }

        val collectionUri: Uri
        if (mimeType.startsWith("image/")) {
            collectionUri = MediaStore.Images.Media.EXTERNAL_CONTENT_URI
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                contentValues.put(MediaStore.Images.Media.RELATIVE_PATH, "Pictures/NexusRelay")
            }
        } else if (mimeType.startsWith("video/")) {
            collectionUri = MediaStore.Video.Media.EXTERNAL_CONTENT_URI
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                contentValues.put(MediaStore.Video.Media.RELATIVE_PATH, "Movies/NexusRelay")
            }
        } else {
            throw IllegalArgumentException("Unsupported media type: $mimeType")
        }

        val itemUri = resolver.insert(collectionUri, contentValues)
            ?: throw IllegalStateException("Failed to insert media row in MediaStore for $fileName")

        try {
            resolver.openOutputStream(itemUri).use { outputStream ->
                if (outputStream == null) {
                    throw IllegalStateException("Failed to open output stream for MediaStore item: $itemUri")
                }
                val buffer = ByteArray(8192)
                var bytesRead: Int
                var bytesCopied = 0L
                inputStream.use { input ->
                    while (input.read(buffer).also { bytesRead = it } != -1) {
                        outputStream.write(buffer, 0, bytesRead)
                        bytesCopied += bytesRead
                        onBytesCopied(bytesCopied)
                    }
                }
                outputStream.flush()
            }

            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                val updateValues = ContentValues().apply {
                    put(MediaStore.MediaColumns.IS_PENDING, 0)
                }
                resolver.update(itemUri, updateValues, null, null)
            }

            itemUri.toString()
        } catch (e: Exception) {
            try {
                resolver.delete(itemUri, null, null)
            } catch (deleteEx: Exception) {
                // Ignore exception on delete
            }
            throw e
        }
    }
}
