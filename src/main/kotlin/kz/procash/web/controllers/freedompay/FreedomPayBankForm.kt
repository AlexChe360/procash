package kz.procash.web.controllers.freedompay

import jakarta.validation.constraints.NotBlank
import jakarta.validation.constraints.Pattern
import jakarta.validation.constraints.Size

data class FreedomPayBankForm(

    @field:NotBlank(
        message = "Укажите банковский счёт IBAN"
    )
    @field:Pattern(
        regexp = "(?i)^KZ\\d{2}(?:\\s?[A-Z0-9]){16}$",
        message = "IBAN должен начинаться с KZ и содержать 20 символов"
    )
    var iban: String = "",

    @field:NotBlank(
        message = "Укажите название банка"
    )
    @field:Size(
        max = 255,
        message = "Название банка не должно превышать 255 символов"
    )
    var bankName: String = "",

    @field:NotBlank(
        message = "Укажите БИК банка"
    )
    @field:Pattern(
        regexp = "(?i)^[A-Z0-9]{8,11}$",
        message = "БИК должен содержать от 8 до 11 латинских букв или цифр"
    )
    var bankBic: String = ""
)
