class DeliverOutboxJob < ApplicationJob
  queue_as :mailers

  # PostgreSQL outbox is the durable queue. Run this job from the dedicated
  # polling task, or schedule it in an existing Active Job runner.
  def perform(kind)
    model = { "requests" => EmailOutbox, "invitations" => MerchantInvitationOutbox }.fetch(kind)
    row = model.transaction do
      scope = model.where(sent_at: nil)
      if kind == "invitations"
        scope = scope.joins(:merchant_invitation).where(merchant_invitations: { accepted_at: nil, revoked_at: nil }).where("merchant_invitations.expires_at > ?", Time.current)
      end
      item = scope.where("attempts < 8 AND next_attempt_at <= ? AND (locked_until IS NULL OR locked_until < ?)", Time.current, Time.current)
        .order("#{model.table_name}.created_at").lock("FOR UPDATE OF #{model.table_name} SKIP LOCKED").first
      if item
        item.update!(attempts: item.attempts + 1, locked_until: (kind == "invitations" ? 2 : 5).minutes.from_now)
      end
      item
    end
    return false unless row
    attempt = row.attempts
    owned = model.where(id: row.id, attempts: attempt, sent_at: nil)
    begin
      if kind == "invitations"
        invitation = row.merchant_invitation
        if invitation.accepted_at || invitation.revoked_at || invitation.expires_at <= Time.current
          owned.update_all(sent_at: Time.current, locked_until: nil, last_error: nil)
          return true
        end
        OnboardingMailer.invitation(row).deliver_now
      else
        OnboardingMailer.connection_request(row).deliver_now
      end
      owned.update_all(sent_at: Time.current, locked_until: nil, last_error: nil)
    rescue StandardError
      # Do not persist SMTP exception strings, which can contain credentials.
      owned.update_all(locked_until: nil, last_error: "SMTP delivery failed", next_attempt_at: [60, attempt * attempt].min.minutes.from_now)
    end
    true
  end
end
