package kz.procash.web.controllers.restaurant

import jakarta.validation.constraints.NotBlank
import jakarta.validation.constraints.Size

data class CreateRestaurantTableForm(
    @field:NotBlank(
        message = "Укажите номер стола"
    )
    @field:Size(
        max = 50,
        message = "Номер стола не должен превышать 50 символов"
    )
    var tableNumber: String = "",

    @field:Size(
        max = 150,
        message = "Название не должно превышать 150 символов"
    )
    var displayName: String = ""
)
