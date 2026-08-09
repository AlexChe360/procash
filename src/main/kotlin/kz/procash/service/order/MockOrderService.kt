package kz.procash.service.order

import kz.procash.exception.order.OrderNotFoundException
import kz.procash.models.order.dto.OrderItem
import kz.procash.models.order.dto.RestaurantOrder
import org.springframework.stereotype.Service
import java.math.BigDecimal

@Service
class MockOrderService : OrderService {
    override fun getOrder(restaurantId: String, tableNumber: Int): RestaurantOrder {
        if (tableNumber == 99) {
            throw OrderNotFoundException(
                restaurantId = restaurantId,
                tableNumber = tableNumber
            )
        }
        return RestaurantOrder(
            restaurantId = restaurantId,
            restaurantName = "ProCash Caffe",
            tableNumber = tableNumber,
            waiterName = "Айгерим",
            items = listOf(
                OrderItem(
                    name = "Капучино",
                    quantity = 2,
                    unitPrice = BigDecimal("1200")
                ),
                OrderItem(
                    name = "Круассан",
                    quantity = 1,
                    unitPrice = BigDecimal("900")
                )
            )
        )
    }
}