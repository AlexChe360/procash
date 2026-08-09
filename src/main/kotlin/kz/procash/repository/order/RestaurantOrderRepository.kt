package kz.procash.repository.order

import kz.procash.models.order.RestaurantOrderStatus
import kz.procash.models.order.entity.RestaurantOrderEntity
import org.springframework.data.jpa.repository.EntityGraph
import org.springframework.data.jpa.repository.JpaRepository
import java.util.UUID

interface RestaurantOrderRepository : JpaRepository<RestaurantOrderEntity, UUID> {

    @EntityGraph(
        attributePaths = [
            "restaurant",
            "table",
            "items"
        ]
    )
    fun findFirstByTable_IdAndStatusOrderByOpenedAtDesc(
        tableId: UUID,
        status: RestaurantOrderStatus
    ): RestaurantOrderEntity?

    @EntityGraph(
        attributePaths = [
            "restaurant",
            "table",
            "items"
        ]
    )
    fun findFirstByTable_IdOrderByOpenedAtDesc(
        tableId: UUID
    ): RestaurantOrderEntity?

    @EntityGraph(
        attributePaths = [
            "restaurant",
            "table",
            "items"
        ]
    )
    fun findAllByRestaurant_IdOrderByOpenedAtDesc(
        restaurantId: UUID
    ): List<RestaurantOrderEntity>
}