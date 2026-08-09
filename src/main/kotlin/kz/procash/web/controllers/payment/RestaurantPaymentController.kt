package kz.procash.web.controllers.payment

import kz.procash.service.payment.PaymentService
import kz.procash.service.restaurant.RestaurantService
import org.springframework.stereotype.Controller
import org.springframework.ui.Model
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PathVariable
import java.security.Principal
import java.util.UUID

@Controller
class RestaurantPaymentController(
    private val restaurantService: RestaurantService,
    private val paymentService: PaymentService
) {
    @GetMapping("/restaurants/{restaurantId}/payments")
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

        val payments =
            paymentService.findAllForRestaurant(
                restaurant.id
            )

        model.addAttribute(
            "restaurant",
            restaurant
        )

        model.addAttribute(
            "payments",
            payments
        )

        model.addAttribute(
            "email",
            principal.name
        )

        return "payments/index"
    }
}