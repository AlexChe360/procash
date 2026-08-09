package kz.procash.web.controllers.restaurant

import jakarta.validation.Valid
import kz.procash.service.freedompay.FreedomPayApplicationService
import kz.procash.service.restaurant.RestaurantService
import kz.procash.service.restaurant.RestaurantTableService
import org.springframework.stereotype.Controller
import org.springframework.ui.Model
import org.springframework.validation.BindingResult
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.ModelAttribute
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.servlet.mvc.support.RedirectAttributes
import java.security.Principal
import java.util.UUID

@Controller
@RequestMapping("/restaurants")
class RestaurantController(
    private val restaurantService: RestaurantService,
    private val freedomPayApplicationService: FreedomPayApplicationService,
    private val restaurantTableService: RestaurantTableService
) {

    @GetMapping
    fun index(
        principal: Principal,
        model: Model
    ): String {
        val restaurants = restaurantService.findAllForUser(
            principal.name
        )

        model.addAttribute("email", principal.name)
        model.addAttribute("restaurants", restaurants)

        return "restaurants/index"
    }

    @GetMapping("/new")
    fun newRestaurant(
        principal: Principal,
        model: Model
    ): String {
        model.addAttribute("email", principal.name)

        if (!model.containsAttribute("restaurantForm")) {
            model.addAttribute(
                "restaurantForm",
                CreateRestaurantForm()
            )
        }

        return "restaurants/new"
    }

    @GetMapping("/{id}")
    fun show(
        @PathVariable id: UUID,
        principal: Principal,
        model: Model
    ): String {
        val restaurant = restaurantService.findForUser(
            restaurantId = id,
            email = principal.name
        )

        val freedomPayApplication =
            freedomPayApplicationService.findOptionalForUser(
                restaurantId = id,
                email = principal.name
            )

        val tablesCount = restaurantTableService.countForUser(
            restaurantId = id,
            email = principal.name
        )

        model.addAttribute("email", principal.name)
        model.addAttribute("restaurant", restaurant)
        model.addAttribute(
            "freedomPayApplication",
            freedomPayApplication
        )
        model.addAttribute("tablesCount", tablesCount)

        return "restaurants/show"
    }

    @PostMapping
    fun create(
        principal: Principal,
        @Valid
        @ModelAttribute("restaurantForm")
        form: CreateRestaurantForm,
        bindingResult: BindingResult,
        model: Model,
        redirectAttributes: RedirectAttributes
    ): String {
        if (
            form.slug.isNotBlank() &&
            restaurantService.slugExists(form.slug)
        ) {
            bindingResult.rejectValue(
                "slug",
                "slug.alreadyExists",
                "Этот адрес уже используется"
            )
        }

        if (bindingResult.hasErrors()) {
            model.addAttribute("email", principal.name)

            return "restaurants/new"
        }

        restaurantService.create(
            email = principal.name,
            form = form
        )

        redirectAttributes.addFlashAttribute(
            "restaurantCreated",
            true
        )

        return "redirect:/restaurants"
    }
}