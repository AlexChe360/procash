package kz.procash.data.mock.freedompay.client

import kz.procash.models.freedompay.FreedomPayApplication
import org.springframework.stereotype.Component
import java.util.UUID

@Component
class MockFreedomPayPartnerClient : FreedomPayPartnerClient {
    override fun submitApplication(application: FreedomPayApplication): FreedomPaySubmissionResult {
        val applicationId = UUID.randomUUID()
            .toString()
            .replace("-", "")
            .take(12)
            .uppercase()

        return FreedomPaySubmissionResult(
            partnerApplicationId = "FP-$applicationId"
        )
    }
}