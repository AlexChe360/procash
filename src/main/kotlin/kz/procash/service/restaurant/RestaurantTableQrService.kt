package kz.procash.service.restaurant

import com.google.zxing.BarcodeFormat
import com.google.zxing.EncodeHintType
import com.google.zxing.client.j2se.MatrixToImageWriter
import com.google.zxing.qrcode.QRCodeWriter
import com.google.zxing.qrcode.decoder.ErrorCorrectionLevel
import org.springframework.beans.factory.annotation.Value
import org.springframework.stereotype.Service
import java.io.ByteArrayOutputStream

@Service
class RestaurantTableQrService(
    @Value("\${procash.public-base-url}")
    private val publicBaseUrl: String
) {
    fun createPublicUrl(
        restaurantSlug: String,
        qrToken: String
    ): String {
        return publicBaseUrl
            .trimEnd('/') + "/r/$restaurantSlug/q/$qrToken"
    }

    fun generatePng(
        content: String,
        size: Int = 640
    ): ByteArray {
        require(size in 200..2000) {
            "Размер QR-кода должен быть от 200 до 2000 px"
        }

        val hints = mapOf(
            EncodeHintType.CHARACTER_SET to "UTF-8",
            EncodeHintType.ERROR_CORRECTION to
                    ErrorCorrectionLevel.M,
            EncodeHintType.MARGIN to 2
        )

        val matrix = QRCodeWriter().encode(
            content,
            BarcodeFormat.QR_CODE,
            size,
            size,
            hints
        )

        return ByteArrayOutputStream().use { output ->
            MatrixToImageWriter.writeToStream(
                matrix,
                "PNG",
                output
            )

            output.toByteArray()
        }
    }
}