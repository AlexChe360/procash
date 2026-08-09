package kz.procash.models.order.entity

import kz.procash.models.order.RestaurantOrderStatus
import kz.procash.models.restaurant.Restaurant
import kz.procash.models.restaurant.RestaurantTable
import java.math.BigDecimal
import java.time.OffsetDateTime
import java.time.ZoneOffset
import java.util.UUID
import jakarta.persistence.*

@Entity
@Table(name = "restaurant_orders")
class RestaurantOrderEntity(
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
        name = "restaurant_id",
        nullable = false
    )
    var restaurant: Restaurant? = null,

    @ManyToOne(
        fetch = FetchType.LAZY,
        optional = false
    )
    @JoinColumn(
        name = "restaurant_table_id",
        nullable = false
    )
    var table: RestaurantTable? = null,

    @Column(name = "external_order_id")
    var externalOrderId: String? = null,

    @Column(
        name = "order_number",
        nullable = false,
        length = 100
    )
    var orderNumber: String = "",

    @Enumerated(EnumType.STRING)
    @Column(
        name = "status",
        nullable = false,
        length = 30
    )
    var status: RestaurantOrderStatus =
        RestaurantOrderStatus.OPEN,

    @Column(
        name = "total_amount",
        nullable = false,
        precision = 19,
        scale = 2
    )
    var totalAmount: BigDecimal = BigDecimal.ZERO,

    @Column(
        name = "opened_at",
        nullable = false
    )
    var openedAt: OffsetDateTime =
        OffsetDateTime.now(ZoneOffset.UTC),

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

    @OneToMany(
        mappedBy = "order",
        cascade = [CascadeType.ALL],
        orphanRemoval = true
    )
    var items: MutableList<OrderItemEntity> = mutableListOf()
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