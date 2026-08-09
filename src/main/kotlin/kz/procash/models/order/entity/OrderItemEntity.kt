package kz.procash.models.order.entity

import jakarta.persistence.*
import java.math.BigDecimal
import java.time.OffsetDateTime
import java.time.ZoneOffset
import java.util.UUID

@Entity
@Table(name = "order_items")
class OrderItemEntity(
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

    @Column(
        name = "name",
        nullable = false
    )
    var name: String = "",

    @Column(
        name = "quantity",
        nullable = false,
        precision = 10,
        scale = 3
    )
    var quantity: BigDecimal = BigDecimal.ONE,

    @Column(
        name = "unit_price",
        nullable = false,
        precision = 19,
        scale = 2
    )
    var unitPrice: BigDecimal = BigDecimal.ZERO,

    @Column(
        name = "total_price",
        nullable = false,
        precision = 19,
        scale = 2
    )
    var totalPrice: BigDecimal = BigDecimal.ZERO,

    @Column(
        name = "created_at",
        nullable = false
    )
    var createdAt: OffsetDateTime =
        OffsetDateTime.now(ZoneOffset.UTC)
)