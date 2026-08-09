package kz.procash.service.payment

import kz.procash.models.order.RestaurantOrderStatus
import kz.procash.models.payment.PaymentProvider
import kz.procash.models.payment.PaymentStatus
import kz.procash.models.payment.PaymentEntity
import kz.procash.repository.order.RestaurantOrderRepository
import kz.procash.repository.payment.PaymentRepository
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional
import java.time.OffsetDateTime
import java.time.ZoneOffset
import java.util.UUID

@Service
class PaymentService(
    private val paymentRepository: PaymentRepository,
    private val orderRepository: RestaurantOrderRepository
) {

    @Transactional
    fun createPayment(
        orderId: UUID
    ): PaymentEntity {

        val order = orderRepository.findById(orderId)
            .orElseThrow {
                IllegalStateException("Заказ не найден")
            }

        check(order.status == RestaurantOrderStatus.OPEN) {
            "Заказ уже закрыт или оплачен"
        }

        val existingPayment =
            paymentRepository
                .findFirstByOrder_IdAndStatusInOrderByCreatedAtDesc(
                    orderId = orderId,
                    statuses = listOf(
                        PaymentStatus.CREATED,
                        PaymentStatus.PENDING
                    )
                )

        if (existingPayment != null) {
            return existingPayment
        }

        val restaurant = order.restaurant
            ?: throw IllegalStateException(
                "У заказа отсутствует ресторан"
            )

        return paymentRepository.save(
            PaymentEntity(
                order = order,
                restaurant = restaurant,
                amount = order.totalAmount,
                status = PaymentStatus.CREATED,
                provider = PaymentProvider.FREEDOM_PAY
            )
        )
    }

    @Transactional(readOnly = true)
    fun findAllForRestaurant(
        restaurantId: UUID
    ): List<PaymentEntity> {
        return paymentRepository
            .findAllByRestaurant_IdOrderByCreatedAtDesc(
                restaurantId
            )
    }

    @Transactional
    fun markPending(
        paymentId: UUID
    ): PaymentEntity {

        val payment = findPayment(paymentId)

        if (payment.status == PaymentStatus.PENDING) {
            return payment
        }

        check(payment.status == PaymentStatus.CREATED) {
            "Платёж нельзя перевести в ожидание"
        }

        payment.status = PaymentStatus.PENDING

        return paymentRepository.save(payment)
    }

    @Transactional
    fun markPaid(
        paymentId: UUID
    ): PaymentEntity {

        val payment = findPayment(paymentId)

        if (payment.status == PaymentStatus.PAID) {
            return payment
        }

        check(
            payment.status == PaymentStatus.CREATED ||
                    payment.status == PaymentStatus.PENDING
        ) {
            "Платёж нельзя подтвердить. Текущий статус: ${payment.status}"
        }

        payment.status = PaymentStatus.PAID
        payment.paidAt = OffsetDateTime.now(ZoneOffset.UTC)

        val order = payment.order
            ?: throw IllegalStateException(
                "У платежа отсутствует заказ"
            )

        order.status = RestaurantOrderStatus.PAID

        orderRepository.save(order)

        return paymentRepository.save(payment)
    }

    @Transactional
    fun markFailed(
        paymentId: UUID
    ): PaymentEntity {

        val payment = findPayment(paymentId)

        if (payment.status == PaymentStatus.FAILED) {
            return payment
        }

        check(
            payment.status == PaymentStatus.CREATED ||
                    payment.status == PaymentStatus.PENDING
        ) {
            "Платёж нельзя завершить с ошибкой. Текущий статус: ${payment.status}"
        }

        payment.status = PaymentStatus.FAILED

        return paymentRepository.save(payment)
    }

    @Transactional(readOnly = true)
    fun findById(
        paymentId: UUID
    ): PaymentEntity {
        return findPayment(paymentId)
    }

    private fun findPayment(
        paymentId: UUID
    ): PaymentEntity {

        return paymentRepository.findWithOrderById(paymentId)
            ?: throw IllegalStateException(
                "Платёж не найден"
            )
    }
}