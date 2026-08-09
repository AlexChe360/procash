package kz.procash.data.mock.freedompay.client

import kz.procash.models.freedompay.FreedomPayApplication

interface FreedomPayPartnerClient {
    fun submitApplication(
        application: FreedomPayApplication
    ): FreedomPaySubmissionResult
}