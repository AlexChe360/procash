package kz.procash.service.order

import kz.procash.models.order.dto.RestaurantOrder

interface OrderService {
    fun getOrder(
        restaurantId: String,
        tableNumber: Int
    ): RestaurantOrder
}