package kz.procash.exception.order

class OrderNotFoundException(
    restaurantId: String, tableNumber: Int
): RuntimeException(
    "Активный заказ не найден для ресторана $restaurantId, стол $tableNumber"
)