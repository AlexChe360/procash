package kz.procash.web.controllers.restaurant

import jakarta.validation.constraints.NotBlank
import jakarta.validation.constraints.Pattern
import jakarta.validation.constraints.Size

data class CreateRestaurantForm(
    @field:NotBlank(
        message = "Укажите название ресторана"
    )
    @field:Size(
        max = 150,
        message = "Название не должно превышать 150 символов"
    )
    var name: String = "",

    @field:NotBlank(
        message = "Укажите адрес страницы"
    )
    @field:Pattern(
        regexp = "^[a-z0-9]+(?:-[a-z0-9]+)*$",
        message = "Используйте строчные латинские буквы, цифры и дефисы"
    )
    @field:Size(
        max = 150,
        message = "Адрес не должен превыщать 150 символов"
    )
    var slug: String = "",

    @field:Size(
        max = 1000,
        message = "Описание не должен превыщать 1000 символов"
    )
    var description: String = "",

    @field:Size(
        max = 30,
        message = "Телефон не должен превышать 30 символов"
    )
    var phone: String = "",

    @field:Size(
        max = 100,
        message = "Название города не должно превыщать 100 символов"
    )
    var city: String = ""
)