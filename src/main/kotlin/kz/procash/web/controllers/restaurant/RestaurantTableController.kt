package kz.procash.web.controllers.restaurant

import jakarta.validation.Valid
import kz.procash.service.restaurant.RestaurantService
import kz.procash.service.restaurant.RestaurantTableQrService
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
import org.springframework.http.CacheControl
import org.springframework.http.ContentDisposition
import org.springframework.http.HttpHeaders
import org.springframework.http.MediaType
import org.springframework.http.ResponseEntity
import org.springframework.web.bind.annotation.RequestParam
import java.util.concurrent.TimeUnit
import java.security.Principal
import java.util.UUID

@Controller
@RequestMapping("/restaurants/{restaurantId}/tables")
class RestaurantTableController(
    private val tableService: RestaurantTableService,
    private val restaurantService: RestaurantService,
    private val qrService: RestaurantTableQrService
) {
    @GetMapping
    fun index(
        @PathVariable restaurantId: UUID,
        principal: Principal,
        model: Model
    ): String {
        val restaurant = restaurantService.findForUser(
            restaurantId = restaurantId,
            email = principal.name
        )

        val tables = tableService.findAllForUser(
            restaurantId = restaurantId,
            email = principal.name
        )

        model.addAttribute("email", principal.name)
        model.addAttribute("restaurant", restaurant)
        model.addAttribute("tables", tables)

        return "restaurants/tables/index"
    }

    @GetMapping("/new")
    fun newTable(
        @PathVariable restaurantId: UUID,
        principal: Principal,
        model: Model
    ): String {
        val restaurant = restaurantService.findForUser(
            restaurantId = restaurantId,
            email = principal.name
        )

        model.addAttribute("email", principal.name)
        model.addAttribute("restaurant", restaurant)

        if (!model.containsAttribute("tableForm")) {
            model.addAttribute(
                "tableForm",
                CreateRestaurantTableForm()
            )
        }

        return "restaurants/tables/new"
    }

    @PostMapping
    fun create(
        @PathVariable restaurantId: UUID,
        principal: Principal,
        @Valid
        @ModelAttribute("tableForm")
        form: CreateRestaurantTableForm,
        bindingResult: BindingResult,
        model: Model,
        redirectAttributes: RedirectAttributes
    ): String {
        if (
            form.tableNumber.isNotBlank() &&
            tableService.tableNumberExists(
                restaurantId = restaurantId,
                email = principal.name,
                tableNumber = form.tableNumber
            )
        ) {
            bindingResult.rejectValue(
                "tableNumber",
                "tableNumber.exists",
                "Стол с таким номером уже существует"
            )
        }

        if (bindingResult.hasErrors()) {
            val restaurant =
                restaurantService.findForUser(
                    restaurantId = restaurantId,
                    email = principal.name
                )

            model.addAttribute("email", principal.name)
            model.addAttribute("restaurant", restaurant)

            return "restaurants/tables/new"
        }

        tableService.create(
            restaurantId = restaurantId,
            email = principal.name,
            form = form
        )

        redirectAttributes.addFlashAttribute(
            "tableCreated",
            true
        )

        return "redirect:/restaurants/$restaurantId/tables"
    }

    @GetMapping("/{tableId}")
    fun show(
        @PathVariable restaurantId: UUID,
        @PathVariable tableId: UUID,
        principal: Principal,
        model: Model
    ): String {
        val restaurant = restaurantService.findForUser(
            restaurantId = restaurantId,
            email = principal.name
        )

        val table = tableService.findForUser(
            restaurantId = restaurantId,
            tableId = tableId,
            email = principal.name
        )

        val publicUrl = qrService.createPublicUrl(
            restaurantSlug = restaurant.slug,
            table.qrToken.toString()
        )

        model.addAttribute("email", principal.name)
        model.addAttribute("restaurant", restaurant)
        model.addAttribute("table", table)
        model.addAttribute("publicUrl", publicUrl)

        return "restaurants/tables/show"
    }

    @GetMapping("/{tableId}/qr.png")
    fun qrPng(
        @PathVariable restaurantId: UUID,
        @PathVariable tableId: UUID,
        @RequestParam(
            required = false,
            defaultValue = "640"
        )
        size: Int,
        principal: Principal
    ): ResponseEntity<ByteArray> {
        val table = tableService.findForUser(
            restaurantId = restaurantId,
            tableId = tableId,
            email = principal.name
        )

        val restaurant = table.restaurant
            ?: throw IllegalStateException("Ресторан не найден")

        val publicUrl = qrService.createPublicUrl(
            restaurantSlug = restaurant.slug,
            table.qrToken.toString()
        )

        val png = qrService.generatePng(
            content = publicUrl,
            size = size
        )

        val fileName =
            "procash-table-${table.tableNumber}.png"

        val headers = HttpHeaders().apply {
            contentType = MediaType.IMAGE_PNG

            contentDisposition =
                ContentDisposition.attachment()
                    .filename(fileName)
                    .build()

            cacheControl = CacheControl
                .maxAge(1, TimeUnit.HOURS)
                .cachePublic()
                .headerValue
        }

        return ResponseEntity
            .ok()
            .headers(headers)
            .body(png)
    }
    
}