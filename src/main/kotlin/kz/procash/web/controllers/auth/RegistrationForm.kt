package kz.procash.web.controllers.auth

import jakarta.validation.constraints.Email
import jakarta.validation.constraints.NotBlank
import jakarta.validation.constraints.Size

data class RegistrationForm(

    @field:NotBlank(
        message = "Укажите email"
    )
    @field:Email(
        message = "Введите корректный email"
    )
    var email: String = "",

    @field:NotBlank(
        message = "Укажите пароль"
    )
    @field:Size(
        min = 8,
        max = 72,
        message = "Пароль должен содержать от 8 до 72 символов"
    )
    var password: String = "",

    @field:NotBlank(
        message = "Повторите пароль"
    )
    var passwordConfirmation: String = ""
)
