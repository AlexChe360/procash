package kz.procash.repository.payment

import kz.procash.models.payment.PaymentStatus
import kz.procash.models.payment.PaymentEntity
import org.springframework.data.jpa.repository.EntityGraph
import org.springframework.data.jpa.repository.JpaRepository
import java.util.UUID

interface PaymentRepository :
    JpaRepository<PaymentEntity, UUID> {

    fun findFirstByOrder_IdAndStatusInOrderByCreatedAtDesc(
        orderId: UUID,
        statuses: Collection<PaymentStatus>
    ): PaymentEntity?

    @EntityGraph(
        attributePaths = [
            "order",
            "order.restaurant",
            "order.table"
        ]
    )
    fun findWithOrderById(
        id: UUID
    ): PaymentEntity?

    @EntityGraph(
        attributePaths = [
            "order"
        ]
    )
    fun findAllByRestaurant_IdOrderByCreatedAtDesc(
        restaurantId: UUID
    ): List<PaymentEntity>
}