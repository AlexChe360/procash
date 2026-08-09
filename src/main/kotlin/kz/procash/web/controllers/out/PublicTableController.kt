package kz.procash.web.controllers.out

import kz.procash.service.order.RestaurantOrderService
import kz.procash.service.restaurant.RestaurantTableService
import org.springframework.stereotype.Controller
import org.springframework.ui.Model
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.RequestParam
import java.util.UUID

@Controller
class PublicTableController(
    private val tableService: RestaurantTableService,
    private val orderService: RestaurantOrderService
) {
    @GetMapping("/r/{slug}/q/{token}")
    fun openTable(
        @PathVariable slug: String,
        @PathVariable token: UUID,
        @RequestParam(
            required = false
        )
        payment: String?,
        model: Model
    ): String {
        val table = tableService.findActiveByQrToken(token)

        val restaurant = table.restaurant
            ?: throw IllegalStateException("Ресторан не найден")

        if (!restaurant.slug.equals(slug, ignoreCase = true)) {
            throw IllegalStateException(
                "QR-код не принадлежит ресторану"
            )
        }

        val order = orderService.findOpenOrderForTable(table.id)

        model.addAttribute("restaurant", restaurant)
        model.addAttribute("table", table)
        model.addAttribute("order", order)

        model.addAttribute(
            "paymentFailed",
            payment == "failed"
        )

        return "public/table"
    }
}