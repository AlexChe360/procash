package kz.procash.models.order.dto

import java.math.BigDecimal

data class RestaurantOrder(
    val restaurantId: String,
    val restaurantName: String,
    val tableNumber: Int,
    val waiterName: String?,
    val items: List<OrderItem>
) {
    val totalAmount: BigDecimal
        get() = items.fold(BigDecimal.ZERO) { total, item ->
            total.add(item.totalPrice)
        }
}
