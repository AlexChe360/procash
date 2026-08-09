package kz.procash.models.user

import jakarta.persistence.Column
import jakarta.persistence.Entity
import jakarta.persistence.EnumType
import jakarta.persistence.Enumerated
import jakarta.persistence.Id
import jakarta.persistence.PrePersist
import jakarta.persistence.PreUpdate
import jakarta.persistence.Table
import java.time.OffsetDateTime
import java.time.ZoneOffset
import java.util.UUID

@Entity
@Table(name = "users")
class User(
    @Id
    var id: UUID = UUID.randomUUID(),

    @Column(
        name = "email",
        nullable = false,
        unique = true,
        length = 255
    )
    var email: String,

    @Column(
        name = "password_hash",
        nullable = false,
        length = 255
    )
    var passwordHash: String?,

    @Enumerated(EnumType.STRING)
    @Column(
        name = "role",
        nullable = false,
        length = 30
    )
    var role: UserRole = UserRole.USER,

    @Column(
        name = "enabled",
        nullable = false
    )
    var enabled: Boolean = true,

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

    protected constructor() : this(
        email = "",
        passwordHash = ""
    )

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


