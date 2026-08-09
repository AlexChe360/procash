package kz.procash.web.controllers.order

import jakarta.validation.constraints.Min
import jakarta.validation.constraints.NotBlank
import kz.procash.models.order.dto.RestaurantOrder
import kz.procash.service.order.OrderService
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RequestParam
import org.springframework.web.bind.annotation.RestController

@RestController
@RequestMapping("/api/v1/orders")
class OrderController(
    private val orderService: OrderService
) {
    @GetMapping("/current")
    fun getCurrentOrder(
        @RequestParam @NotBlank(message = "restaurantId не должен быть пустым")
        restaurantId: String,

        @RequestParam @Min(value = 1, message = "tableNumber должен быть больше нуля")
        tableNumber: Int
    ): RestaurantOrder {
        return orderService.getOrder(restaurantId, tableNumber)
    }
}