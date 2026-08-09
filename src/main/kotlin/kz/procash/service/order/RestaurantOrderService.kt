package kz.procash.service.order

import org.springframework.transaction.annotation.Transactional
import kz.procash.models.order.RestaurantOrderStatus
import kz.procash.models.order.entity.RestaurantOrderEntity
import kz.procash.repository.order.RestaurantOrderRepository
import org.springframework.stereotype.Service
import java.util.UUID

@Service
class RestaurantOrderService(
    private val orderRepository: RestaurantOrderRepository
) {
    @Transactional(readOnly = true)
    fun findOpenOrderForTable(
        tableId: UUID
    ): RestaurantOrderEntity? {
        return orderRepository
            .findFirstByTable_IdAndStatusOrderByOpenedAtDesc(
                tableId = tableId,
                status = RestaurantOrderStatus.OPEN
            )
    }

    @Transactional(readOnly = true)
    fun findLatestOrderForTable(
        tableId: UUID
    ): RestaurantOrderEntity? {
        return orderRepository
            .findFirstByTable_IdOrderByOpenedAtDesc(tableId)
    }

    @Transactional(readOnly = true)
    fun findAllForRestaurant(
        restaurantId: UUID
    ): List<RestaurantOrderEntity> {
        return orderRepository
            .findAllByRestaurant_IdOrderByOpenedAtDesc(restaurantId)
    }
}