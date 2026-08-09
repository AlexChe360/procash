package kz.procash.web.controllers.freedompay

import jakarta.validation.constraints.Email
import jakarta.validation.constraints.NotBlank
import jakarta.validation.constraints.Pattern
import jakarta.validation.constraints.Size

data class FreedomPayDirectorForm (
    @field:NotBlank(
        message = "Укажите ФИО руководителя"
    )
    @field:Size(
        max = 255,
        message = "ФИО не должно превышать 255 символов"
    )
    var directorName: String = "",

    @field:NotBlank(
        message = "Укажите ИИН руководителя"
    )
    @field:Pattern(
        regexp = "^\\d{12}$",
        message = "ИИН должен содержать 12 цифр"
    )
    var directorIin: String = "",

    @field:NotBlank(
        message = "Укажите номер телефона"
    )
    @field:Pattern(
        regexp = "^\\+?[0-9 ()-]{10,20}$",
        message = "Введите корректный номер телефона"
    )
    var directorPhone: String = "",

    @field:NotBlank(
        message = "Укажите email"
    )
    @field:Email(
        message = "Введите корректный email"
    )
    @field:Size(
        max = 255,
        message = "Email не должен превышать 255 символов"
    )
    var directorEmail: String = ""
)