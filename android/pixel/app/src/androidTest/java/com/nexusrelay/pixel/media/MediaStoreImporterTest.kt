package com.nexusrelay.pixel.media

import android.content.Context
import android.provider.MediaStore
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.ByteArrayInputStream

@RunWith(AndroidJUnit4::class)
class MediaStoreImporterTest {

    private val context: Context = ApplicationProvider.getApplicationContext()
    private val importer = MediaStoreImporter(context)
    private var insertedUri: String? = null

    @After
    fun cleanup() {
        insertedUri?.let { uriString ->
            try {
                val uri = android.net.Uri.parse(uriString)
                context.contentResolver.delete(uri, null, null)
            } catch (_: Exception) {
                // Ignore cleanup errors
            }
        }
    }

    @Test
    fun importImageReturnsNonNullUri() = runBlocking {
        // Create a tiny PNG byte stream (1x1 pixel)
        val pngHeader = byteArrayOf(
            0x89.toByte(), 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, // PNG signature
            0x00, 0x00, 0x00, 0x0D, // IHDR length
            0x49, 0x48, 0x44, 0x52  // "IHDR"
        )
        val inputStream = ByteArrayInputStream(pngHeader)

        val uri = importer.importMedia(
            fileName = "test_image_instrumentation.png",
            mimeType = "image/png",
            inputStream = inputStream,
            sizeBytes = pngHeader.size.toLong()
        )

        insertedUri = uri
        assertNotNull("importMedia should return a non-null content URI", uri)
        assertTrue("URI should be a content:// URI", uri.startsWith("content://"))
    }

    @Test(expected = IllegalArgumentException::class)
    fun importUnsupportedMimeTypeThrows() = runBlocking {
        val inputStream = ByteArrayInputStream(byteArrayOf(0x00))
        importer.importMedia(
            fileName = "test.txt",
            mimeType = "text/plain",
            inputStream = inputStream,
            sizeBytes = 1L
        )
        Unit
    }
}
