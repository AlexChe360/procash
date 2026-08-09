package kz.procash.common.error

import kz.procash.exception.order.OrderNotFoundException
import org.springframework.http.HttpStatus
import org.springframework.http.ResponseEntity
import org.springframework.web.bind.MissingServletRequestParameterException
import org.springframework.web.bind.annotation.ExceptionHandler
import org.springframework.web.bind.annotation.RestControllerAdvice
import org.springframework.web.method.annotation.HandlerMethodValidationException
import org.springframework.web.method.annotation.MethodArgumentTypeMismatchException

@RestControllerAdvice
class GlobalExceptionHandler {

    @ExceptionHandler(HandlerMethodValidationException::class)
    fun handleValidation(
        exception: HandlerMethodValidationException
    ): ResponseEntity<ApiError> {

        val errors = exception.parameterValidationResults.flatMap { validationResult ->
            val fieldName =
                validationResult.methodParameter.parameterName ?: "parameter"

            validationResult.resolvableErrors.map { error ->
                ApiFieldError(
                    field = fieldName,
                    message = error.defaultMessage ?: "Некорректное значение"
                )
            }
        }

        return ResponseEntity.badRequest().body(
            ApiError(
                code = "VALIDATION_ERROR",
                message = "Параметры запроса заполнены неправильно",
                errors = errors
            )
        )
    }

    @ExceptionHandler(MissingServletRequestParameterException::class)
    fun handleMissingParameter(
        exception: MissingServletRequestParameterException
    ): ResponseEntity<ApiError> {
        return ResponseEntity.badRequest().body(
            ApiError(
                code = "MISSING_PARAMETER",
                message = "Не передан обязательный параметр",
                errors = listOf(
                    ApiFieldError(
                        field = exception.parameterName,
                        message = "Параметр обязателен"
                    )
                )
            )
        )
    }

    @ExceptionHandler(MethodArgumentTypeMismatchException::class)
    fun handleTypeMismatch(
        exception: MethodArgumentTypeMismatchException
    ): ResponseEntity<ApiError> {
        return ResponseEntity.badRequest().body(
            ApiError(
                code = "INVALID_PARAMETER_TYPE",
                message = "Передан параметр неправильного типа",
                errors = listOf(
                    ApiFieldError(
                        field = exception.name,
                        message = "Некорректное значение: ${exception.value}"
                    )
                )
            )
        )
    }

    @ExceptionHandler(OrderNotFoundException::class)
    fun handleOrderNotFound(
        exception: OrderNotFoundException
    ): ResponseEntity<ApiError> {
        return ResponseEntity
            .status(HttpStatus.NOT_FOUND)
            .body(
                ApiError(
                    code = "ORDER_NOT_FOUND",
                    message = exception.message ?: "Активный заказ не найден"
                )
            )
    }
}