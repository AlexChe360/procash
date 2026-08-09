package kz.procash.models.order.dto

import java.math.BigDecimal

data class OrderItem(
    val name: String,
    val quantity: Int,
    val unitPrice: BigDecimal
) {
    val totalPrice: BigDecimal
        get() = unitPrice.multiply(quantity.toBigDecimal())
}

