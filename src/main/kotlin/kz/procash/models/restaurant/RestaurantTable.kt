package kz.procash.models.restaurant

import jakarta.persistence.Column
import jakarta.persistence.Entity
import jakarta.persistence.FetchType
import jakarta.persistence.JoinColumn
import jakarta.persistence.ManyToOne
import jakarta.persistence.PrePersist
import jakarta.persistence.PreUpdate
import jakarta.persistence.Table
import jakarta.persistence.Id
import java.time.OffsetDateTime
import java.time.ZoneOffset
import java.util.UUID

@Entity
@Table(name = "restaurant_tables")
class RestaurantTable(
    @Id
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

    @Column(
        name = "table_number",
        nullable = false,
        length = 50
    )
    var tableNumber: String = "",

    @Column(
        name = "display_name",
        length = 150
    )
    var displayName: String? = null,

    @Column(
        name = "qr_token",
        nullable = false,
        unique = true
    )
    var qrToken: UUID = UUID.randomUUID(),

    @Column(
        name = "active",
        nullable = false
    )
    var active: Boolean = true,

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
        OffsetDateTime.now(ZoneOffset.UTC)
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