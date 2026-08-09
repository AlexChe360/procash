package kz.procash.web.controllers.admin

import kz.procash.repository.freedompay.FreedomPayApplicationRepository
import kz.procash.service.freedompay.FreedomPayApplicationService
import org.springframework.stereotype.Controller
import org.springframework.ui.Model
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.RequestMapping
import org.springframework.web.bind.annotation.RequestParam
import java.security.Principal
import java.util.UUID

@Controller
@RequestMapping("/admin/freedom-pay")
class FreedomPayController(
    private val applicationRepository: FreedomPayApplicationRepository,
    private val freedomPayApplicationService: FreedomPayApplicationService
) {

    @GetMapping("/applications")
    fun applications(
        principal: Principal,
        model: Model
    ): String {
        val applications =
            applicationRepository.findAllByOrderByCreatedAtDesc()

        model.addAttribute("email", principal.name)
        model.addAttribute("freedomApp", applications)

        model.addAttribute(
            "readyForReviewCount",
            applications.count {
                it.status.name == "READY_FOR_REVIEW"
            }
        )

        model.addAttribute(
            "underFreedomReviewCount",
            applications.count {
                it.status.name == "UNDER_FREEDOM_REVIEW"
            }
        )

        model.addAttribute(
            "approvedCount",
            applications.count {
                it.status.name == "APPROVED"
            }
        )

        return "admin/freedompay/applications"
    }

    @GetMapping("/applications/{id}")
    fun applicationDetails(
        @PathVariable id: UUID,
        principal: Principal,
        model: Model
    ): String {
        val freedomApp = applicationRepository.findWithRestaurantById(id)
            ?: throw IllegalStateException("Заявка не найдена")

        model.addAttribute("email", principal.name)
        model.addAttribute("freedomApp", freedomApp)

        return "admin/freedompay/application-details"
    }

    @PostMapping("/applications/{id}/return")
    fun returnForChanges(
        @PathVariable id: UUID
    ): String {
        freedomPayApplicationService.returnForChanges(id)

        return "redirect:/admin/freedom-pay/applications/$id"
    }

    @PostMapping("/applications/{id}/submit")
    fun submitToFreedomPay(
        @PathVariable id: UUID
    ): String {
        freedomPayApplicationService.submitToFreedomPay(id)

        return "redirect:/admin/freedom-pay/applications/$id"
    }

    @PostMapping("/applications/{id}/approve")
    fun approve(
        @PathVariable id: UUID
    ): String {
        freedomPayApplicationService.approve(id)

        return "redirect:/admin/freedom-pay/applications/$id"
    }

    @PostMapping("/applications/{id}/reject")
    fun reject(
        @PathVariable id: UUID,
        @RequestParam comment: String
    ): String {
        freedomPayApplicationService.reject(id, comment = comment)

        return "redirect:/admin/freedom-pay/applications/$id"
    }

    @PostMapping("/applications/{id}/changes")
    fun changes(
        @PathVariable id: UUID,
        @RequestParam comment: String
    ): String {
        freedomPayApplicationService.requestChanges(id, comment = comment)

        return "redirect:/admin/freedom-pay/applications/$id"
    }
}