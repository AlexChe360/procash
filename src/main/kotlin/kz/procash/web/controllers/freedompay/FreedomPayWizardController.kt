package kz.procash.web.controllers.freedompay

import jakarta.validation.Valid
import kz.procash.models.freedompay.FreedomPayApplication
import kz.procash.models.freedompay.FreedomPayApplicationStatus
import kz.procash.models.freedompay.FreedomPayStep
import kz.procash.service.freedompay.FreedomPayApplicationService
import org.springframework.stereotype.Controller
import org.springframework.ui.Model
import org.springframework.validation.BindingResult
import org.springframework.web.bind.annotation.GetMapping
import org.springframework.web.bind.annotation.ModelAttribute
import org.springframework.web.bind.annotation.PathVariable
import org.springframework.web.bind.annotation.PostMapping
import org.springframework.web.bind.annotation.RequestMapping
import java.security.Principal
import java.util.UUID

@Controller
@RequestMapping(
    "/restaurants/{restaurantId}/payments/freedom-pay"
)
class FreedomPayWizardController(
    private val applicationService: FreedomPayApplicationService
) {

    @GetMapping
    fun start(
        @PathVariable restaurantId: UUID,
        principal: Principal
    ): String {
        val application =
            applicationService.getOrCreate(
                restaurantId = restaurantId,
                email = principal.name
            )

        return when (application.status) {

            FreedomPayApplicationStatus.DRAFT -> {
                redirectToStep(
                    restaurantId,
                    application.currentStep
                )
            }

            FreedomPayApplicationStatus.NEEDS_CHANGES -> {
                redirectToStep(
                    restaurantId,
                    application.currentStep
                )
            }

            else -> {
                "redirect:/restaurants/$restaurantId" +
                        "/payments/freedom-pay/status"
            }
        }
    }

    @GetMapping("/company")
    fun companyPage(
        @PathVariable restaurantId: UUID,
        principal: Principal,
        model: Model
    ): String {
        val application = applicationService.getOrCreate(
            restaurantId = restaurantId,
            email = principal.name
        )

        submittedRedirect(
            restaurantId = restaurantId,
            application = application
        )?.let {
            return it
        }

        if (!model.containsAttribute("companyForm")) {
            model.addAttribute(
                "companyForm",
                FreedomPayCompanyForm(
                    organizationType =
                        application.organizationType.orEmpty(),
                    companyName =
                        application.companyName.orEmpty(),
                    bin =
                        application.bin.orEmpty()
                )
            )
        }

        model.addAttribute("email", principal.name)
        model.addAttribute("restaurant", application.restaurant)
        model.addAttribute("application", application)
        model.addAttribute("currentStep", "COMPANY")

        return "freedompay/company"
    }

    @PostMapping("/company")
    fun saveCompany(
        @PathVariable restaurantId: UUID,
        principal: Principal,
        @Valid
        @ModelAttribute("companyForm")
        form: FreedomPayCompanyForm,
        bindingResult: BindingResult,
        model: Model
    ): String {
        if (bindingResult.hasErrors()) {
            val application = applicationService.getOrCreate(
                restaurantId = restaurantId,
                email = principal.name
            )

            model.addAttribute("email", principal.name)
            model.addAttribute(
                "restaurant",
                application.restaurant
            )
            model.addAttribute("application", application)
            model.addAttribute("currentStep", "COMPANY")

            return "freedompay/company"
        }

        applicationService.saveCompany(
            restaurantId = restaurantId,
            email = principal.name,
            form = form
        )

        return "redirect:/restaurants/$restaurantId" +
                "/payments/freedom-pay/director"
    }

    @GetMapping("/director")
    fun directorPage(
        @PathVariable restaurantId: UUID,
        principal: Principal,
        model: Model
    ): String {
        val application = applicationService.getOrCreate(
            restaurantId = restaurantId,
            email = principal.name
        )

        submittedRedirect(
            restaurantId = restaurantId,
            application = application
        )?.let {
            return it
        }

        if (!model.containsAttribute("directorForm")) {
            model.addAttribute(
                "directorForm",
                FreedomPayDirectorForm(
                    directorName =
                        application.directorName.orEmpty(),
                    directorIin =
                        application.directorIin.orEmpty(),
                    directorPhone =
                        application.directorPhone.orEmpty(),
                    directorEmail =
                        application.directorEmail.orEmpty()
                )
            )
        }

        addCommonAttributes(
            model = model,
            principal = principal,
            application = application,
            currentStep = "DIRECTOR"
        )

        return "freedompay/director"
    }

    @PostMapping("/director")
    fun saveDirector(
        @PathVariable restaurantId: UUID,
        principal: Principal,
        @Valid
        @ModelAttribute("directorForm")
        form: FreedomPayDirectorForm,
        bindingResult: BindingResult,
        model: Model
    ): String {
        if (bindingResult.hasErrors()) {
            val application = applicationService.getOrCreate(
                restaurantId = restaurantId,
                email = principal.name
            )

            addCommonAttributes(
                model = model,
                principal = principal,
                application = application,
                currentStep = "DIRECTOR"
            )

            return "freedompay/director"
        }

        applicationService.saveDirector(
            restaurantId = restaurantId,
            email = principal.name,
            form = form
        )

        return "redirect:/restaurants/$restaurantId" +
                "/payments/freedom-pay/address"
    }

    @GetMapping("/address")
    fun addressPage(
        @PathVariable restaurantId: UUID,
        principal: Principal,
        model: Model
    ): String {
        val application = applicationService.getOrCreate(
            restaurantId = restaurantId,
            email = principal.name
        )

        submittedRedirect(
            restaurantId = restaurantId,
            application = application
        )?.let {
            return it
        }

        if (!model.containsAttribute("addressForm")) {
            model.addAttribute(
                "addressForm",
                FreedomPayAddressForm(
                    legalAddress =
                        application.legalAddress.orEmpty(),
                    city =
                        application.city.orEmpty(),
                    postalCode =
                        application.postalCode.orEmpty()
                )
            )
        }

        addCommonAttributes(
            model = model,
            principal = principal,
            application = application,
            currentStep = "ADDRESS"
        )

        return "freedompay/address"
    }

    @PostMapping("/address")
    fun saveAddress(
        @PathVariable restaurantId: UUID,
        principal: Principal,
        @Valid
        @ModelAttribute("addressForm")
        form: FreedomPayAddressForm,
        bindingResult: BindingResult,
        model: Model
    ): String {
        if (bindingResult.hasErrors()) {
            val application = applicationService.getOrCreate(
                restaurantId = restaurantId,
                email = principal.name
            )

            addCommonAttributes(
                model = model,
                principal = principal,
                application = application,
                currentStep = "ADDRESS"
            )

            return "freedompay/address"
        }

        applicationService.saveAddress(
            restaurantId = restaurantId,
            email = principal.name,
            form = form
        )

        return "redirect:/restaurants/$restaurantId" +
                "/payments/freedom-pay/bank"
    }

    @GetMapping("/bank")
    fun bankPage(
        @PathVariable restaurantId: UUID,
        principal: Principal,
        model: Model
    ): String {
        val application = applicationService.getOrCreate(
            restaurantId = restaurantId,
            email = principal.name
        )

        submittedRedirect(
            restaurantId = restaurantId,
            application = application
        )?.let {
            return it
        }

        if (!model.containsAttribute("bankForm")) {
            model.addAttribute(
                "bankForm",
                FreedomPayBankForm(
                    iban = application.iban.orEmpty(),
                    bankName = application.bankName.orEmpty(),
                    bankBic = application.bankBic.orEmpty()
                )
            )
        }

        addCommonAttributes(
            model = model,
            principal = principal,
            application = application,
            currentStep = "BANK"
        )

        return "freedompay/bank"
    }

    @PostMapping("/bank")
    fun saveBank(
        @PathVariable restaurantId: UUID,
        principal: Principal,
        @Valid
        @ModelAttribute("bankForm")
        form: FreedomPayBankForm,
        bindingResult: BindingResult,
        model: Model
    ): String {
        normalizeBankForm(form)

        if (bindingResult.hasErrors()) {
            val application = applicationService.getOrCreate(
                restaurantId = restaurantId,
                email = principal.name
            )

            addCommonAttributes(
                model = model,
                principal = principal,
                application = application,
                currentStep = "BANK"
            )

            return "freedompay/bank"
        }

        applicationService.saveBank(
            restaurantId = restaurantId,
            email = principal.name,
            form = form
        )

        return "redirect:/restaurants/$restaurantId" +
                "/payments/freedom-pay/restaurant"
    }

    @GetMapping("/restaurant")
    fun restaurantPage(
        @PathVariable restaurantId: UUID,
        principal: Principal,
        model: Model
    ): String {
        val application = applicationService.getOrCreate(
            restaurantId = restaurantId,
            email = principal.name
        )

        submittedRedirect(
            restaurantId = restaurantId,
            application = application
        )?.let {
            return it
        }

        val restaurant = application.restaurant
            ?: throw IllegalStateException("Ресторан заявки не найден")

        if (!model.containsAttribute("restaurantForm")) {
            model.addAttribute(
                "restaurantForm",
                FreedomPayRestaurantForm(
                    websiteUrl = application.websiteUrl
                        ?: "https://procash.kz/r/${restaurant.slug}",
                    businessCategory =
                        application.businessCategory.orEmpty(),
                    businessDescription =
                        application.businessDescription
                            ?: restaurant.description.orEmpty(),
                    averageCheck =
                        application.averageCheck,
                    expectedMonthlyTurnover =
                        application.expectedMonthlyTurnover
                )
            )
        }

        addCommonAttributes(
            model = model,
            principal = principal,
            application = application,
            currentStep = "RESTAURANT"
        )

        return "freedompay/restaurant"
    }

    @PostMapping("/restaurant")
    fun saveRestaurant(
        @PathVariable restaurantId: UUID,
        principal: Principal,
        @Valid
        @ModelAttribute("restaurantForm")
        form: FreedomPayRestaurantForm,
        bindingResult: BindingResult,
        model: Model
    ): String {
        if (bindingResult.hasErrors()) {
            val application = applicationService.getOrCreate(
                restaurantId = restaurantId,
                email = principal.name
            )

            addCommonAttributes(
                model = model,
                principal = principal,
                application = application,
                currentStep = "RESTAURANT"
            )

            return "freedompay/restaurant"
        }

        applicationService.saveRestaurantDetails(
            restaurantId = restaurantId,
            email = principal.name,
            form = form
        )

        return "redirect:/restaurants/$restaurantId" +
                "/payments/freedom-pay/review"
    }

    @GetMapping("/review")
    fun reviewPage(
        @PathVariable restaurantId: UUID,
        principal: Principal,
        model: Model
    ): String {
        val application = applicationService.findForUser(
            restaurantId = restaurantId,
            email = principal.name
        )

        submittedRedirect(
            restaurantId = restaurantId,
            application = application
        )?.let {
            return it
        }

        val restaurant = application.restaurant
            ?: throw IllegalStateException(
                "У заявки отсутствует ресторан"
            )

        model.addAttribute("email", principal.name)
        model.addAttribute("restaurant", restaurant)
        model.addAttribute("freedomPayApplication", application)
        model.addAttribute("currentStep", FreedomPayStep.REVIEW)

        model.addAttribute(
            "readyToSubmit",
            applicationService.isReadyToSubmit(application)
        )

        return "freedompay/review"
    }

    @PostMapping("/submit")
    fun submit(
        @PathVariable restaurantId: UUID,
        principal: Principal
    ): String {
        applicationService.submitForReview(
            restaurantId = restaurantId,
            email = principal.name
        )

        return "redirect:/restaurants/$restaurantId/payments/freedom-pay/status"
    }

    @GetMapping("/success")
    fun successPage(
        @PathVariable restaurantId: UUID,
        principal: Principal,
        model: Model
    ): String {
        val application = applicationService.findForUser(
            restaurantId = restaurantId,
            email = principal.name
        )

        addCommonAttributes(
            model = model,
            principal = principal,
            application = application,
            currentStep = "SUBMIT"
        )

        return "freedompay/success"
    }

    @GetMapping("/status")
    fun statusPage(
        @PathVariable restaurantId: UUID,
        principal: Principal,
        model: Model
    ): String {
        val application = applicationService.findForUser(
            restaurantId = restaurantId,
            email = principal.name
        )

        val restaurant = application.restaurant
            ?: throw IllegalStateException(
                "У заявки отсутствует ресторан"
            )

        model.addAttribute("email", principal.name)
        model.addAttribute("restaurant", restaurant)
        model.addAttribute(
            "freedomPayApplication",
            application
        )

        return "freedompay/status"
    }

    private fun addCommonAttributes(
        model: Model,
        principal: Principal,
        application: FreedomPayApplication,
        currentStep: String
    ) {
        model.addAttribute("email", principal.name)
        model.addAttribute("restaurant", application.restaurant)

        model.addAttribute(
            "freedomPayApplication",
            application
        )

        model.addAttribute("currentStep", currentStep)
    }

    private fun normalizeBankForm(
        form: FreedomPayBankForm
    ) {
        form.iban = form.iban
            .filterNot(Char::isWhitespace)
            .uppercase()

        form.bankBic = form.bankBic
            .filterNot(Char::isWhitespace)
            .uppercase()

        form.bankName = form.bankName.trim()
    }

    private fun submittedRedirect(
        restaurantId: UUID,
        application: FreedomPayApplication
    ): String? {
        val editable = applicationService.canEdit(application)

        return if (!editable) {
            "redirect:/restaurants/$restaurantId" +
                    "/payments/freedom-pay/status"
        } else {
            null
        }
    }

    private fun redirectToStep(
        restaurantId: UUID,
        step: FreedomPayStep
    ): String {
        val path = when (step) {
            FreedomPayStep.COMPANY -> "company"
            FreedomPayStep.DIRECTOR -> "director"
            FreedomPayStep.ADDRESS -> "address"
            FreedomPayStep.BANK -> "bank"
            FreedomPayStep.RESTAURANT -> "restaurant"
            FreedomPayStep.REVIEW -> "review"
            FreedomPayStep.SUBMIT -> "review"
        }

        return "redirect:/restaurants/$restaurantId" +
                "/payments/freedom-pay/$path"
    }
}