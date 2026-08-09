package kz.procash.web.controllers.freedompay

import jakarta.validation.constraints.DecimalMin
import jakarta.validation.constraints.NotBlank
import jakarta.validation.constraints.Size
import org.hibernate.validator.constraints.URL
import java.math.BigDecimal

data class FreedomPayRestaurantForm(
    @field:NotBlank(
        message = "Укажите адрес сайта"
    )
    @field:URL(
        message = "Введите корректный адрес сайта"
    )
    @field:Size(
        max = 500,
        message = "Адрес сайта не должен превышать 500 символов"
    )
    var websiteUrl: String = "",

    @field:NotBlank(
        message = "Выберите категорию бизнеса"
    )
    @field:Size(
        max = 150,
        message = "Категория не должна превышать 150 символов"
    )
    var businessCategory: String = "",

    @field:NotBlank(
        message = "Опишите деятельность ресторана"
    )
    @field:Size(
        min = 20,
        max = 1500,
        message = "Описание должно содержать от 20 до 1500 символов"
    )
    var businessDescription: String = "",

    @field:DecimalMin(
        value = "1.00",
        message = "Средний чек должен быть больше нуля"
    )
    var averageCheck: BigDecimal? = null,

    @field:DecimalMin(
        value = "1.00",
        message = "Ожидаемый оборот должен быть больше нуля"
    )
    var expectedMonthlyTurnover: BigDecimal? = null
)
