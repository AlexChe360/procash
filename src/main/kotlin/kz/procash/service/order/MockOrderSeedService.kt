package kz.procash.service.order

import jakarta.transaction.Transactional
import kz.procash.models.order.RestaurantOrderStatus
import kz.procash.models.order.entity.OrderItemEntity
import kz.procash.models.order.entity.RestaurantOrderEntity
import kz.procash.repository.order.RestaurantOrderRepository
import kz.procash.repository.restaurant.RestaurantTableRepository
import org.springframework.stereotype.Service
import java.math.BigDecimal
import java.util.UUID

@Service
class MockOrderSeedService(
    private val tableRepository: RestaurantTableRepository,
    private val orderRepository: RestaurantOrderRepository
) {

    @Transactional
    fun createMockOrder(
        tableId: UUID
    ): RestaurantOrderEntity {
        val table = tableRepository.findById(tableId)
            .orElseThrow {
                IllegalStateException("Стол не найден")
            }

        val existsOrder =
            orderRepository
                .findFirstByTable_IdAndStatusOrderByOpenedAtDesc(
                    tableId = tableId,
                    status = RestaurantOrderStatus.OPEN
                )

        if (existsOrder != null) {
            return existsOrder
        }

        val restaurant = table.restaurant
            ?: throw IllegalStateException("Ресторан не найден")

        val order = RestaurantOrderEntity(
            restaurant = restaurant,
            table = table,
            orderNumber = "TEST-001",
            status = RestaurantOrderStatus.OPEN
        )

        addItem(
            order = order,
            name = "Цезарь с курицей",
            quantity = "1",
            unitPrice = "3200"
        )

        addItem(
            order = order,
            name = "Капучино",
            quantity = "2",
            unitPrice = "1500"
        )

        addItem(
            order = order,
            name = "Стейк",
            quantity = "1",
            unitPrice = "8500"
        )

        order.totalAmount = order.items
            .fold(BigDecimal.ZERO) { total, item ->
                total.add(item.totalPrice)
            }

        return orderRepository.save(order)
    }

    private fun addItem(
        order: RestaurantOrderEntity,
        name: String,
        quantity: String,
        unitPrice: String
    ) {
        val qty = BigDecimal(quantity)
        val price = BigDecimal(unitPrice)

        val item = OrderItemEntity(
            order = order,
            name = name,
            quantity = qty,
            unitPrice = price,
            totalPrice = price.multiply(qty)
        )

        order.items.add(item)
    }
}