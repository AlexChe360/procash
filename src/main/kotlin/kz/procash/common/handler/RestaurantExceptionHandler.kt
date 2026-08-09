package kz.procash.common.handler

import kz.procash.exception.restaurant.RestaurantNotFoundException
import org.springframework.web.bind.annotation.ControllerAdvice
import org.springframework.web.bind.annotation.ExceptionHandler
import org.springframework.web.servlet.mvc.support.RedirectAttributes

@ControllerAdvice
class RestaurantExceptionHandler {

    @ExceptionHandler(RestaurantNotFoundException::class)
    fun handleRestaurantNotFound(
        redirectAttributes: RedirectAttributes
    ): String {
        redirectAttributes.addFlashAttribute(
            "restaurantNotFound",
            true
        )

        return "redirect:/restaurants"
    }
}