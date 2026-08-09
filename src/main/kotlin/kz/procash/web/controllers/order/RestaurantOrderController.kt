package kz.procash.web.controllers.order

import kz.procash.service.order.RestaurantOrderService
import kz.procash.service.restaurant.RestaurantService
import org.springframework.stereotype.Controller
import org.springframework.ui.Model
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PathVariable
import java.security.Principal
import java.util.UUID

@Controller
class RestaurantOrderController(
    private val restaurantService: RestaurantService,
    private val orderService: RestaurantOrderService
) {
    @GetMapping("/restaurants/{restaurantId}/orders")
    fun index(
        @PathVariable restaurantId: UUID,
        principal: Principal,
        model: Model
    ): String {

        val restaurant =
            restaurantService.findForUser(
                restaurantId,
                principal.name
            )

        val orders =
            orderService.findAllForRestaurant(
                restaurant.id
            )

        model.addAttribute("restaurant", restaurant)
        model.addAttribute("orders", orders)
        model.addAttribute("email", principal.name)

        return "orders/index"
    }
}