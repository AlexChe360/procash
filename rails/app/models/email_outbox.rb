class EmailOutbox < ApplicationRecord
  self.table_name = "email_outbox"
  belongs_to :connection_request
end
