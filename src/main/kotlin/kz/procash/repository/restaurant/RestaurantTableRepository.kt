package kz.procash.repository.restaurant

import kz.procash.models.restaurant.RestaurantTable
import org.springframework.data.jpa.repository.EntityGraph
import org.springframework.data.jpa.repository.JpaRepository
import java.util.UUID

interface RestaurantTableRepository : JpaRepository<RestaurantTable, UUID> {
    fun findAllByRestaurantIdOrderByTableNumberAsc(
        restaurantId: UUID
    ): List<RestaurantTable>

    fun countByRestaurantId(
        restaurantId: UUID
    ): Long

    fun existsByRestaurantIdAndTableNumberIgnoreCase(
        restaurantId: UUID,
        tableNumber: String
    ): Boolean

    fun findByIdAndRestaurantId(
        id: UUID,
        restaurantId: UUID
    ): RestaurantTable?

    @EntityGraph(
        attributePaths = ["restaurant"],
    )
    fun findByQrTokenAndActiveTrue(
        qrToken: UUID
    ): RestaurantTable?
}