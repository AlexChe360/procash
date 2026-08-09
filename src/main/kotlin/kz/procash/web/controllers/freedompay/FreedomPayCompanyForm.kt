package kz.procash.web.controllers.freedompay

import jakarta.validation.constraints.NotBlank
import jakarta.validation.constraints.Pattern
import jakarta.validation.constraints.Size

data class FreedomPayCompanyForm(
    @field:NotBlank(
        message = "Выберите форму организации"
    )
    var organizationType: String = "",

    @field:NotBlank(
        message = "Укажите наименование компании"
    )
    @field:Size(
        max = 255,
        message = "Наименование не должно превышать 255 символов"
    )
    var companyName: String = "",

    @field:NotBlank(
        message = "Укажите БИН или ИИН"
    )
    @field:Pattern(
        regexp = "^\\d{12}$",
        message = "БИН или ИИН должен содержать 12 цифр"
    )
    var bin: String = ""
)
