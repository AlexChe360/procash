class OnboardingMailer < ApplicationMailer
  def connection_request(row)
    @request = row.connection_request
    @url = "#{ENV.fetch('APP_ORIGIN').delete_suffix('/')}/demo/requests/#{@request.id}"
    mail(from: ENV.fetch("SMTP_FROM"), to: ENV.fetch("SMTP_TO"), subject: "ProCash — новая заявка на подключение", message_id: "<#{row.id}@procash.kz>")
  end

  def invitation(row)
    @invitation = row.merchant_invitation
    @url = "#{ENV.fetch('APP_ORIGIN').delete_suffix('/')}/invite/#{MerchantInvitation.token_for(@invitation.id)}"
    mail(from: ENV.fetch("SMTP_FROM"), to: @invitation.email, subject: "ProCash — приглашение в личный кабинет", message_id: "<#{row.id}@procash.kz>")
  end
end
