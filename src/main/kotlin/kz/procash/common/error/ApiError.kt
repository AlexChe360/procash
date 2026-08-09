package kz.procash.common.error

data class ApiError(
    val code: String,
    val message: String,
    val errors: List<ApiFieldError> = emptyList()
)

data class ApiFieldError(
    val field: String,
    val message: String
)
