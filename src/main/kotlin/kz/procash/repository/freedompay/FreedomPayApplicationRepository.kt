package kz.procash.repository.freedompay

import kz.procash.models.freedompay.FreedomPayApplication
import org.springframework.data.jpa.repository.EntityGraph
import org.springframework.data.jpa.repository.JpaRepository
import java.util.UUID

interface FreedomPayApplicationRepository : JpaRepository<FreedomPayApplication, UUID> {

    fun findByRestaurantId(restaurantId: UUID): FreedomPayApplication?

    @EntityGraph(attributePaths = ["restaurant"])
    fun findAllByOrderByCreatedAtDesc(): List<FreedomPayApplication>

    @EntityGraph(attributePaths = ["restaurant"])
    fun findWithRestaurantById(id: UUID): FreedomPayApplication?
    fun id(id: UUID): MutableList<FreedomPayApplication>
}