package kz.procash.models.freedompay

import jakarta.persistence.Column
import jakarta.persistence.Entity
import jakarta.persistence.EnumType
import jakarta.persistence.Enumerated
import jakarta.persistence.FetchType
import jakarta.persistence.Id
import jakarta.persistence.JoinColumn
import jakarta.persistence.OneToOne
import jakarta.persistence.PrePersist
import jakarta.persistence.PreUpdate
import jakarta.persistence.Table
import kz.procash.models.restaurant.Restaurant
import java.math.BigDecimal
import java.time.OffsetDateTime
import java.time.ZoneOffset
import java.util.UUID

@Entity
@Table(name = "freedom_pay_applications")
class FreedomPayApplication(
    @Id
    var id: UUID = UUID.randomUUID(),

    @OneToOne(
        fetch = FetchType.LAZY,
        optional = false
    )
    @JoinColumn(
        name = "restaurant_id",
        nullable = false,
        unique = true
    )
    var restaurant: Restaurant? = null,

    @Enumerated(EnumType.STRING)
    @Column(
        name = "status",
        nullable = false,
        length = 30
    )
    var status: FreedomPayApplicationStatus =
        FreedomPayApplicationStatus.DRAFT,

    @Enumerated(EnumType.STRING)
    @Column(
        name = "current_step",
        nullable = false,
        length = 30
    )
    var currentStep: FreedomPayStep =
        FreedomPayStep.COMPANY,

    @Column(name = "organization_type", length = 50)
    var organizationType: String? = null,

    @Column(name = "company_name", length = 255)
    var companyName: String? = null,

    @Column(name = "bin", length = 20)
    var bin: String? = null,

    @Column(name = "director_name", length = 255)
    var directorName: String? = null,

    @Column(name = "director_iin", length = 20)
    var directorIin: String? = null,

    @Column(name = "director_phone", length = 30)
    var directorPhone: String? = null,

    @Column(name = "director_email", length = 255)
    var directorEmail: String? = null,

    @Column(name = "legal_address", length = 500)
    var legalAddress: String? = null,

    @Column(name = "city", length = 100)
    var city: String? = null,

    @Column(name = "postal_code", length = 20)
    var postalCode: String? = null,

    @Column(name = "iban", length = 50)
    var iban: String? = null,

    @Column(name = "bank_name", length = 255)
    var bankName: String? = null,

    @Column(name = "bank_bic", length = 30)
    var bankBic: String? = null,

    @Column(name = "website_url", length = 500)
    var websiteUrl: String? = null,

    @Column(name = "business_category", length = 150)
    var businessCategory: String? = null,

    @Column(name = "business_description", length = 1500)
    var businessDescription: String? = null,

    @Column(
        name = "average_check",
        precision = 19,
        scale = 2
    )
    var averageCheck: BigDecimal? = null,

    @Column(
        name = "expected_monthly_turnover",
        precision = 19,
        scale = 2
    )
    var expectedMonthlyTurnover: BigDecimal? = null,

    @Column(name = "partner_application_id", length = 255)
    var partnerApplicationId: String? = null,

    @Column(name = "merchant_id", length = 255)
    var merchantId: String? = null,

    @Column(name = "review_comment")
    var reviewComment: String? = null,

    @Column(name = "created_at", nullable = false)
    var createdAt: OffsetDateTime =
        OffsetDateTime.now(ZoneOffset.UTC),

    @Column(name = "updated_at", nullable = false)
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