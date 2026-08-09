package kz.procash.web.controllers.payment

import kz.procash.models.payment.PaymentStatus
import kz.procash.service.payment.PaymentService
import org.springframework.stereotype.Controller
import org.springframework.ui.Model
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RequestParam
import java.util.UUID

@Controller
@RequestMapping("/payments")
class PaymentController(
    private val paymentService: PaymentService,
) {
    @PostMapping("/create")
    fun createPayment(
        @RequestParam orderId: UUID
    ): String {

        val payment = paymentService.createPayment(orderId)

        if (payment.status == PaymentStatus.CREATED) {
            paymentService.markPending(payment.id)
        }

        return "redirect:/payments/${payment.id}/mock"
    }


    @GetMapping("/{paymentId}/mock")
    fun mockPaymentPage(
        @PathVariable paymentId: UUID,
        model: Model
    ): String {

        val payment = paymentService.findById(paymentId)

        model.addAttribute("payment", payment)

        return "payments/mock"
    }
    

    @PostMapping("/{paymentId}/mock/success")
    fun success(
        @PathVariable paymentId: UUID
    ): String {

        val payment = paymentService.markPaid(paymentId)

        return "redirect:/payments/${payment.id}/success"
    }

    @GetMapping("/{paymentId}/success")
    fun successPage(
        @PathVariable paymentId: UUID,
        model: Model
    ): String {

        val payment = paymentService.findById(paymentId)

        model.addAttribute("payment", payment)

        return "payments/success"
    }

    @PostMapping("/{paymentId}/mock/fail")
    fun fail(
        @PathVariable paymentId: UUID
    ): String {

        val payment = paymentService.markFailed(paymentId)

        val order = payment.order
            ?: throw IllegalStateException(
                "У платежа отсутствует заказ"
            )

        val table = order.table
            ?: throw IllegalStateException(
                "У заказа отсутствует стол"
            )

        val restaurant = order.restaurant
            ?: throw IllegalStateException(
                "У заказа отсутствует ресторан"
            )

        return "redirect:/r/${restaurant.slug}/q/${table.qrToken}?payment=failed"
    }

}