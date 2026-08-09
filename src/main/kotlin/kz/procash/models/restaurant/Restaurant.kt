package kz.procash.models.restaurant

import jakarta.persistence.Column
import jakarta.persistence.Entity
import jakarta.persistence.EnumType
import jakarta.persistence.Enumerated
import jakarta.persistence.FetchType
import jakarta.persistence.Id
import jakarta.persistence.JoinColumn
import jakarta.persistence.ManyToOne
import jakarta.persistence.PrePersist
import jakarta.persistence.PreUpdate
import jakarta.persistence.Table
import kz.procash.models.user.User
import java.time.OffsetDateTime
import java.time.ZoneOffset
import java.util.UUID

@Entity
@Table(name = "restaurants")
class Restaurant(
    @Id
    var id: UUID = UUID.randomUUID(),

    @ManyToOne(
        fetch = FetchType.LAZY,
        optional = false
    )
    @JoinColumn(
        name = "owner_id",
        nullable = false
    )
    var owner: User? =null,

    @Column(
        name = "name",
        nullable = false,
        length = 150
    )
    var name: String,

    @Column(
        name = "slug",
        nullable = false,
        unique = true,
        length = 150
    )
    var slug: String,

    @Column(
        name = "description",
        length = 1000
    )
    var description: String? = null,

    @Column(
        name = "phone",
        length = 30
    )
    var phone: String? = null,

    @Column(
        name = "city",
        length = 100
    )
    var city: String? = null,

    @Enumerated(EnumType.STRING)
    @Column(
        name = "status",
        nullable = false,
        length = 30
    )
    var status: RestaurantStatus = RestaurantStatus.DRAFT,

    @Column(
        name = "active",
        nullable = false
    )
    var active: Boolean = false,

    @Column(
        name = "created_at",
        nullable = false
    )
    var createdAt: OffsetDateTime = OffsetDateTime.now(ZoneOffset.UTC),

    @Column(
        name = "updated_at",
        nullable = false
    )
    var updatedAt: OffsetDateTime = OffsetDateTime.now(ZoneOffset.UTC)
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