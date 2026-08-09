package kz.procash.models.payment

import jakarta.persistence.*
import kz.procash.models.order.entity.RestaurantOrderEntity
import kz.procash.models.restaurant.Restaurant
import java.math.BigDecimal
import java.time.OffsetDateTime
import java.time.ZoneOffset
import java.util.UUID

@Entity
@Table(name = "payments")
class PaymentEntity(
    @Id
    @Column(
        name = "id",
        nullable = false,
        updatable = false
    )
    var id: UUID = UUID.randomUUID(),

    @ManyToOne(
        fetch = FetchType.LAZY,
        optional = false
    )
    @JoinColumn(
        name = "order_id",
        nullable = false
    )
    var order: RestaurantOrderEntity? = null,

    @ManyToOne(
        fetch = FetchType.LAZY,
        optional = false
    )
    @JoinColumn(
        name = "restaurant_id",
        nullable = false
    )
    var restaurant: Restaurant? = null,

    @Column(
        name = "amount",
        nullable = false,
        precision = 19,
        scale = 2
    )
    var amount: BigDecimal = BigDecimal.ZERO,

    @Enumerated(EnumType.STRING)
    @Column(
        name = "status",
        nullable = false,
        length = 30
    )
    var status: PaymentStatus = PaymentStatus.CREATED,

    @Enumerated(EnumType.STRING)
    @Column(
        name = "provider",
        nullable = false,
        length = 30
    )
    var provider: PaymentProvider =
        PaymentProvider.FREEDOM_PAY,

    @Column(name = "external_payment_id")
    var externalPaymentId: String? = null,

    @Column(
        name = "created_at",
        nullable = false
    )
    var createdAt: OffsetDateTime =
        OffsetDateTime.now(ZoneOffset.UTC),

    @Column(
        name = "updated_at",
        nullable = false
    )
    var updatedAt: OffsetDateTime =
        OffsetDateTime.now(ZoneOffset.UTC),

    @Column(name = "paid_at")
    var paidAt: OffsetDateTime? = null
) {
    @PrePersist
    fun beforeInsert() {
        val now = OffsetDateTime.now(ZoneOffset.UTC)
        createdAt = now
        updatedAt = now
    }

    @PreUpdate
    fun beforeUpdate() {
        updatedAt = OffsetDateTime.now(ZoneOffset.UTC)
    }
}