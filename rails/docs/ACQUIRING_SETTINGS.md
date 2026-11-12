# Acquiring onboarding — first iteration

## Ownership

Merchant owners/managers select one or several supported providers and submit requests for a specific outlet. They see their request statuses and review comments. They cannot set Merchant ID, supply/change a payment key, approve a request or change acquiring credentials. Staff cannot submit requests. Only an approved, non-disabled live connection can be chosen as primary by the merchant. No live checkout is enabled by this choice.

ProCash administrators use `/admin/acquiring` to review the request queue, take a request into review, save encrypted provider credentials, approve or reject with a reason. Approval requires live credentials, but is an administrative decision, not evidence of successful API verification. A change to credentials clears primary selection and returns approved requests to review. Requests record requester, reviewer and decision time. Rejected requests remain visible; the merchant can submit a new request. Pending, in-review and approved duplicates are blocked per outlet/provider, including by a database constraint.

Existing acquiring connections are preserved and available only in the ProCash admin panel. An administrator can link them to a merchant request. Nothing is automatically approved as part of this migration.

## Provider configuration

The provider registry is extensible; Freedom Pay is the first supported configuration type. ProCash merchant UUID and provider Merchant ID are separate. Test/live environments, AES-256-GCM encrypted payment keys, a single optional primary connection per outlet, and reversible disabling remain supported. Credential encryption uses connection-specific acquiring AAD and the configured encryption master key. Request metadata and connection identifiers are scoped to the company and outlet.

## Limits

No external provider API is called by these screens. Onboarding automation, payment execution, signed callbacks, reconciliation, POS settlement and refunds remain separate work. The Payments page reports administrative approvals, not active payment acceptance or settlement.

Partner API and Merchant API must use separate adapters and credentials. Merchant API is for hosted payment pages; Partner API Products may automate onboarding if Freedom Pay grants partner access. Manual provider onboarding must remain supported. Never infer that partner access or individually negotiated tariffs are available just because an API method exists.

Commercial concept is context only: framework agreement, supplemental agreements, questionnaires, commissions and individual restaurant tariffs have not been implemented.

Sources reviewed 2026-11-12:
- https://docs.freedompay.kz/overview-2505280m0 (Partner API)
- https://docs.freedompay.kz/overview-741636m0 (Merchant API)
- https://docs.freedompay.kz/client-request-status-12076005e0
