require "test_helper"
class OutboxTest < ActiveSupport::TestCase
  setup do
    @before_env = ENV.to_h.slice("APP_ORIGIN", "SMTP_FROM", "SMTP_TO")
    ENV["APP_ORIGIN"] = "https://test.example"
    ENV["SMTP_FROM"] = "mail@example.test"
    ENV["SMTP_TO"] = "admin@example.test"
    @request = ConnectionRequest.create!(contact_name: "Test", contact_email: "test@example.test", contact_phone: "+77001234567", establishment_name: "Test Cafe", city: "Almaty", consent: "yes")
  end
  teardown do
    %w[APP_ORIGIN SMTP_FROM SMTP_TO].each { |key| ENV[key] = @before_env[key] }
  end
  test "outbox sends multipart notification once and marks it sent" do
    assert_difference "ActionMailer::Base.deliveries.size", 1 do
      assert DeliverOutboxJob.perform_now("requests")
    end
    row = @request.email_outbox.reload
    assert row.sent_at
    assert_equal 1, row.attempts
    assert_nil row.locked_until
    message = ActionMailer::Base.deliveries.last
    assert message.multipart?
    assert_includes message.html_part.body.decoded, "/demo/requests/#{@request.id}"
    assert_no_difference "ActionMailer::Base.deliveries.size" do
      assert_not DeliverOutboxJob.perform_now("requests")
    end
  end
  test "claimed or exhausted messages are not picked up" do
    row = @request.email_outbox
    row.update!(locked_until: 5.minutes.from_now)
    assert_not DeliverOutboxJob.perform_now("requests")
    row.update!(locked_until: nil, attempts: 8)
    assert_not DeliverOutboxJob.perform_now("requests")
  end
end

class OutboxRetryTest < ActiveSupport::TestCase
  test "failed delivery releases lease and retries without leaking error details" do
    previous = ENV.delete("SMTP_FROM")
    request = ConnectionRequest.create!(contact_name: "Test", contact_email: "test@example.test", contact_phone: "+77001234567", establishment_name: "Test Cafe", city: "Almaty", consent: "yes")
    assert DeliverOutboxJob.perform_now("requests")
    row = request.email_outbox.reload
    assert_nil row.sent_at
    assert_nil row.locked_until
    assert_equal "SMTP delivery failed", row.last_error
    assert_equal 1, row.attempts
    assert_operator row.next_attempt_at, :>, 50.seconds.from_now
    assert_not DeliverOutboxJob.perform_now("requests")
  ensure
    ENV["SMTP_FROM"] = previous
  end
end
