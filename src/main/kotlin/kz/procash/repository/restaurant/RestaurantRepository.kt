package kz.procash.repository.restaurant

import kz.procash.models.restaurant.Restaurant
import org.springframework.data.jpa.repository.JpaRepository
import java.util.UUID

interface RestaurantRepository: JpaRepository<Restaurant, UUID> {
    fun findAllByOwnerIdOrderByCreatedAtDesc(
        ownerId: UUID
    ): List<Restaurant>

    fun countByOwnerId(
        ownerId: UUID
    ): Long

    fun existsBySlugIgnoreCase(
        slug: String
    ): Boolean

    fun findByIdAndOwnerId(
        id: UUID,
        ownerId: UUID
    ): Restaurant?
}