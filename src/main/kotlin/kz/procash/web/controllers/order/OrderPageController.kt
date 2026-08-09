package kz.procash.web.controllers.order

import jakarta.validation.constraints.Min
import jakarta.validation.constraints.NotBlank
import kz.procash.service.order.MockOrderSeedService
import kz.procash.service.order.OrderService
import org.springframework.stereotype.Controller
import org.springframework.ui.Model
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.RequestParam
import java.util.UUID

@Controller
class OrderPageController(
    private val orderService: OrderService,
    private val mockOrderSeedService: MockOrderSeedService
) {
    @GetMapping("/order")
    fun showOrder(
        @RequestParam
        @NotBlank(message = "restaurantId не должен быть пустым")
        restaurantId: String,

        @RequestParam
        @Min(value = 1, message = "tableNumber должен быть больше нуля")
        tableNumber: Int,

        model: Model
    ): String {
        val order = orderService.getOrder(restaurantId, tableNumber)

        model.addAttribute("order", order)

        return "order"
    }

    @PostMapping(
        "/restaurants/{restaurantId}/tables/{tableId}/mock-order",
    )
    fun createMockOrder(
        @PathVariable restaurantId: UUID,
        @PathVariable tableId: UUID,
    ): String {
        mockOrderSeedService.createMockOrder(tableId)

        return "redirect:/restaurants/$restaurantId/tables/$tableId"
    }
}