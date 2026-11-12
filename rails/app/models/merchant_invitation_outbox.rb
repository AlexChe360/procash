class MerchantInvitationOutbox < ApplicationRecord
  self.table_name = "merchant_invitation_outbox"
  belongs_to :merchant_invitation
end
