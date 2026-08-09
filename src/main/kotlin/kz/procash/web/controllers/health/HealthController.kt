package kz.procash.web.controllers.health

import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RestController

data class HealthResponse(
    val status: String,
    val service: String
)

@RestController
@RequestMapping("/api/v1")
class HealthController {

    @GetMapping("/health")
    fun health(): HealthResponse {
        return HealthResponse(
            status = "UP",
            service = "procash"
        )
    }
}