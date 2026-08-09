package kz.procash.models.freedompay

enum class FreedomPayApplicationStatus {
    DRAFT,
    READY_FOR_REVIEW,
    SUBMITTED_TO_FREEDOM,
    UNDER_FREEDOM_REVIEW,
    NEEDS_CHANGES,
    APPROVED,
    REJECTED
}