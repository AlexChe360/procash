package kz.procash.service.freedompay

import kz.procash.data.mock.freedompay.client.FreedomPayPartnerClient
import kz.procash.models.freedompay.FreedomPayApplication
import kz.procash.models.freedompay.FreedomPayApplicationStatus
import kz.procash.models.freedompay.FreedomPayStep
import kz.procash.repository.freedompay.FreedomPayApplicationRepository
import kz.procash.service.restaurant.RestaurantService
import kz.procash.web.controllers.freedompay.FreedomPayAddressForm
import kz.procash.web.controllers.freedompay.FreedomPayBankForm
import kz.procash.web.controllers.freedompay.FreedomPayCompanyForm
import kz.procash.web.controllers.freedompay.FreedomPayDirectorForm
import kz.procash.web.controllers.freedompay.FreedomPayRestaurantForm
import java.util.UUID
import org.springframework.stereotype.Service
import org.springframework.transaction.annotation.Transactional

@Service
class FreedomPayApplicationService(
    private val applicationRepository: FreedomPayApplicationRepository,
    private val restaurantService: RestaurantService,
    private val freedomPayPartnerClient: FreedomPayPartnerClient
) {
    @Transactional
    fun getOrCreate(
        restaurantId: UUID,
        email: String
    ): FreedomPayApplication {
        val restaurant = restaurantService.findForUser(
            restaurantId = restaurantId,
            email = email
        )

        val existingApplication =
            applicationRepository.findByRestaurantId(restaurantId)

        if (existingApplication != null) {
            return existingApplication
        }

        val application = FreedomPayApplication(
            restaurant = restaurant,
            status = FreedomPayApplicationStatus.DRAFT,
            currentStep = FreedomPayStep.COMPANY
        )

        return applicationRepository.save(application)
    }

    @Transactional(readOnly = true)
    fun findOptionalForUser(
        restaurantId: UUID,
        email: String
    ): FreedomPayApplication? {
        restaurantService.findForUser(
            restaurantId = restaurantId,
            email = email
        )

        return applicationRepository.findByRestaurantId(restaurantId)
    }

    @Transactional
    fun saveCompany(
        restaurantId: UUID,
        email: String,
        form: FreedomPayCompanyForm
    ): FreedomPayApplication {
        val application = getOrCreate(
            restaurantId = restaurantId,
            email = email
        )

        ensureEditable(application)

        application.organizationType =
            form.organizationType.trim().uppercase()

        application.companyName =
            form.companyName.trim()

        application.bin =
            form.bin.filter(Char::isDigit)

        application.currentStep =
            FreedomPayStep.DIRECTOR

        return applicationRepository.save(application)
    }

    @Transactional
    fun saveDirector(
        restaurantId: UUID,
        email: String,
        form: FreedomPayDirectorForm
    ): FreedomPayApplication {
        val application = getOrCreate(
            restaurantId = restaurantId,
            email = email
        )

        ensureEditable(application)

        application.directorName =
            form.directorName.trim()

        application.directorIin =
            form.directorIin.filter(Char::isDigit)

        application.directorPhone =
            form.directorPhone.trim()

        application.directorEmail =
            form.directorEmail
                .trim()
                .lowercase()

        application.currentStep =
            FreedomPayStep.ADDRESS

        return applicationRepository.save(application)
    }

    @Transactional
    fun saveAddress(
        restaurantId: UUID,
        email: String,
        form: FreedomPayAddressForm
    ): FreedomPayApplication {
        val application = getOrCreate(
            restaurantId = restaurantId,
            email = email
        )

        ensureEditable(application)

        application.legalAddress =
            form.legalAddress.trim()

        application.city =
            form.city.trim()

        application.postalCode =
            form.postalCode.filter(Char::isDigit)

        application.currentStep =
            FreedomPayStep.BANK

        return applicationRepository.save(application)
    }

    @Transactional
    fun saveBank(
        restaurantId: UUID,
        email: String,
        form: FreedomPayBankForm
    ): FreedomPayApplication {
        val application = getOrCreate(
            restaurantId = restaurantId,
            email = email
        )

        ensureEditable(application)

        application.iban = normalizeBankValue(form.iban)
        application.bankName = form.bankName.trim()
        application.bankBic = normalizeBankValue(form.bankBic)

        application.currentStep = FreedomPayStep.RESTAURANT

        return applicationRepository.save(application)
    }

    @Transactional
    fun saveRestaurantDetails(
        restaurantId: UUID,
        email: String,
        form: FreedomPayRestaurantForm
    ): FreedomPayApplication {
        val application = getOrCreate(
            restaurantId = restaurantId,
            email = email
        )

        ensureEditable(application)

        application.websiteUrl =
            form.websiteUrl.trim()

        application.businessCategory =
            form.businessCategory.trim()

        application.businessDescription =
            form.businessDescription.trim()

        application.averageCheck =
            form.averageCheck

        application.expectedMonthlyTurnover =
            form.expectedMonthlyTurnover

        application.currentStep =
            FreedomPayStep.REVIEW

        application.status =
            FreedomPayApplicationStatus.DRAFT

        return applicationRepository.save(application)
    }

    @Transactional(readOnly = true)
    fun findForUser(
        restaurantId: UUID,
        email: String
    ): FreedomPayApplication {
        restaurantService.findForUser(
            restaurantId = restaurantId,
            email = email
        )

        return applicationRepository
            .findByRestaurantId(restaurantId)
            ?: throw IllegalStateException(
                "Заявка Freedom Pay не найдена"
            )
    }

    @Transactional
    fun submitForReview(
        restaurantId: UUID,
        email: String
    ): FreedomPayApplication {
        val application = findForUser(
            restaurantId = restaurantId,
            email = email
        )

        check(
            application.status == FreedomPayApplicationStatus.DRAFT ||
                    application.status == FreedomPayApplicationStatus.NEEDS_CHANGES ||
                    application.status == FreedomPayApplicationStatus.READY_FOR_REVIEW
        ) {
            "Заявку нельзя отправить в текущем статусе"
        }

        check(isReadyToSubmit(application)) {
            "Заявка заполнена не полностью"
        }

        application.reviewComment = null

        application.status =
            FreedomPayApplicationStatus.READY_FOR_REVIEW

        application.currentStep =
            FreedomPayStep.SUBMIT

        return applicationRepository.save(application)
    }

    fun canEdit(
        application: FreedomPayApplication
    ): Boolean =
        application.status == FreedomPayApplicationStatus.DRAFT ||
                application.status == FreedomPayApplicationStatus.NEEDS_CHANGES

    fun isReadyToSubmit(
        application: FreedomPayApplication
    ): Boolean {
        return !application.organizationType.isNullOrBlank() &&
                !application.companyName.isNullOrBlank() &&
                !application.bin.isNullOrBlank() &&
                !application.directorName.isNullOrBlank() &&
                !application.directorIin.isNullOrBlank() &&
                !application.directorPhone.isNullOrBlank() &&
                !application.directorEmail.isNullOrBlank() &&
                !application.legalAddress.isNullOrBlank() &&
                !application.city.isNullOrBlank() &&
                !application.postalCode.isNullOrBlank() &&
                !application.iban.isNullOrBlank() &&
                !application.bankName.isNullOrBlank() &&
                !application.bankBic.isNullOrBlank() &&
                !application.websiteUrl.isNullOrBlank() &&
                !application.businessCategory.isNullOrBlank() &&
                !application.businessDescription.isNullOrBlank() &&
                application.averageCheck != null &&
                application.expectedMonthlyTurnover != null
    }

    @Transactional
    fun returnForChanges(
        applicationId: UUID
    ): FreedomPayApplication {
        val application = applicationRepository.findById(applicationId)
            .orElseThrow {
                IllegalStateException("Заявка не найдена")
            }

        check(
            application.status == FreedomPayApplicationStatus.READY_FOR_REVIEW
        ) {
            "Заявку нельзя вернуть на исправление в текущем статусе"
        }

        application.status = FreedomPayApplicationStatus.NEEDS_CHANGES

        return applicationRepository.save(application)
    }

    @Transactional
    fun submitToFreedomPay(
        applicationId: UUID
    ): FreedomPayApplication {
        val application = applicationRepository.findById(applicationId)
            .orElseThrow {
                IllegalStateException("Заявка не найдена")
            }

        check(
            application.status == FreedomPayApplicationStatus.READY_FOR_REVIEW
        ) {
            "Заявку нельзя отправить в Freedom Pay"
        }

        check(isReadyToSubmit(application)) {
            "Заявка заполнена не полностью"
        }

        application.status = FreedomPayApplicationStatus.SUBMITTED_TO_FREEDOM

        val result =
            freedomPayPartnerClient.submitApplication(application)

        application.partnerApplicationId = result.partnerApplicationId

        application.status = FreedomPayApplicationStatus.UNDER_FREEDOM_REVIEW

        return applicationRepository.save(application)
    }

    @Transactional
    fun approve(
        applicationId: UUID
    ): FreedomPayApplication {
        val application = applicationRepository.findById(applicationId)
            .orElseThrow {
                IllegalStateException("Заявка не найдена")
            }

        check(
            application.status == FreedomPayApplicationStatus.UNDER_FREEDOM_REVIEW
        ) {
            "Заявка не находится на рассмотрении Freedom Pay"
        }

        application.merchantId =
            application.merchantId
                ?: ("MERCHANT-" +
                        UUID.randomUUID()
                            .toString()
                            .take(8)
                            .uppercase())

        application.reviewComment = null

        application.status = FreedomPayApplicationStatus.APPROVED

        return applicationRepository.save(application)
    }

    @Transactional
    fun reject(
        applicationId: UUID,
        comment: String
    ): FreedomPayApplication {
        val application = applicationRepository.findById(applicationId)
            .orElseThrow {
                IllegalStateException("Заявка не найдена")
            }

        check(
            application.status == FreedomPayApplicationStatus.UNDER_FREEDOM_REVIEW
        ) {
            "Заявка не находится на рассмотрении Freedom Pay"
        }

        val reviewComment = comment.trim()

        require(reviewComment.isNotBlank()) {
            "Укажите причину оклонения"
        }

        application.status = FreedomPayApplicationStatus.REJECTED

        application.reviewComment = reviewComment

        return applicationRepository.save(application)
    }

    @Transactional
    fun requestChanges(
        applicationId: UUID,
        comment: String
    ): FreedomPayApplication {
        val application = applicationRepository.findById(applicationId)
            .orElseThrow {
                IllegalStateException("Заявка не найдена")
            }

        check(
            application.status == FreedomPayApplicationStatus.READY_FOR_REVIEW ||
                    application.status == FreedomPayApplicationStatus.UNDER_FREEDOM_REVIEW
        ) {
            "Заявка не находится на рассмотрении Freedom Pay"
        }

        val reviewComment = comment.trim()

        require(reviewComment.isNotBlank()) {
            "Укажите причину возврата на исправление"
        }

        application.status = FreedomPayApplicationStatus.NEEDS_CHANGES

        application.currentStep = FreedomPayStep.COMPANY

        application.reviewComment = reviewComment

        return applicationRepository.save(application)
    }

    private fun ensureEditable(
        application: FreedomPayApplication
    ) {
        check(canEdit(application)) {
            "Отправленную заявку нельзя редактировать"
        }
    }

    private fun normalizeBankValue(value: String): String {
        return value
            .filterNot(Char::isWhitespace)
            .uppercase()
    }

}