package com.aquasofts.cithub_flutter

import android.graphics.BitmapFactory
import android.util.Base64
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.text.TextRecognition
import com.google.mlkit.vision.text.latin.TextRecognizerOptions
import java.util.concurrent.TimeUnit

internal class CaptchaRecognizer {
    private val client by lazy {
        TextRecognition.getClient(TextRecognizerOptions.DEFAULT_OPTIONS)
    }

    fun recognize(base64Image: String): String {
        if (base64Image.isBlank()) return ""
        val bytes = Base64.decode(base64Image.substringAfter(',', base64Image), Base64.DEFAULT)
        val bitmap = BitmapFactory.decodeByteArray(bytes, 0, bytes.size) ?: return ""
        val result = Tasks.await(client.process(InputImage.fromBitmap(bitmap, 0)), 5, TimeUnit.SECONDS)
        val candidates = result.textBlocks.flatMap { it.lines }
            .map { it.text.filter(Char::isLetterOrDigit) }
            .filter { it.length >= 4 }
        // The HAR confirms that the academic RANDOMCODE is exactly four
        // characters; extra OCR noise makes a correct reading fail.
        return (candidates.firstOrNull() ?: result.text.filter(Char::isLetterOrDigit)).take(4)
    }
}
