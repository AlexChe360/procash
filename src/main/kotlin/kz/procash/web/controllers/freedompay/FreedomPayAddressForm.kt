package kz.procash.web.controllers.freedompay

import jakarta.validation.constraints.NotBlank
import jakarta.validation.constraints.Pattern
import jakarta.validation.constraints.Size

data class FreedomPayAddressForm (
    @field:NotBlank(
        message = "Укажите юридический адрес"
    )
    @field:Size(
        max = 500,
        message = "Адрес не должен превышать 500 символов"
    )
    var legalAddress: String = "",

    @field:NotBlank(
        message = "Укажите город"
    )
    @field:Size(
        max = 100,
        message = "Название города не должно превышать 100 символов"
    )
    var city: String = "",

    @field:NotBlank(
        message = "Укажите почтовый индекс"
    )
    @field:Pattern(
        regexp = "^\\d{6}$",
        message = "Почтовый индекс должен содержать 6 цифр"
    )
    var postalCode: String = ""
)