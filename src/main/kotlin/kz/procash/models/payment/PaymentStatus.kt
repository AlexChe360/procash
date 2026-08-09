package kz.procash.models.payment

enum class PaymentStatus {
    CREATED,
    PENDING,
    PAID,
    FAILED,
    CANCELLED
}