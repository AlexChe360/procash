require "test_helper"
require "base64"
class AcquiringSettingsTest < ActionDispatch::IntegrationTest
  setup do
    @old_key = ENV["PROCASH_ENCRYPTION_KEY_V1"]
    ENV["PROCASH_ENCRYPTION_KEY_V1"] = Base64.strict_encode64("k" * 32)
    @user = User.create!(email: "acquiring@example.test", password_hash: Auth::Password.hash("acquiring-password-123"), email_verified_at: Time.current)
    @admin = User.create!(email: "acquiring-admin@example.test", password_hash: Auth::Password.hash("acquiring-password-123"), email_verified_at: Time.current, platform_role: "admin")
    @merchant = Merchant.create!(legal_name: "Company", bin_iin: "123456789012")
    @membership = MerchantMembership.create!(user: @user, merchant: @merchant, role: "owner")
    @outlet = @merchant.merchant_outlets.create!(name: "My outlet", city: "Almaty", address: "Abay 10")
    @base = "/dashboard/merchants/#{@merchant.id}/outlets/#{@outlet.id}"
    post "/login", params: { email: @user.email, password: "acquiring-password-123" }
  end
  teardown { ENV["PROCASH_ENCRYPTION_KEY_V1"] = @old_key }
  def submit_request
    post "#{@base}/acquiring/requests", params: { providers: ["freedom_pay"] }
    @outlet.acquiring_requests.order(:created_at).last
  end
  def admin_login
    post "/admin/login", params: { email: @admin.email, password: "acquiring-password-123" }
  end
  def credentials
    { name: "Freedom Pay", provider_merchant_id: "001234", environment: "live", payment_secret: "synthetic-secret-not-real" }
  end

  test "merchant submits request without credentials and cannot approve or configure" do
    assert_difference "AcquiringRequest.count", 1 do
      assert_no_difference "AcquiringConnection.count" do
        post "#{@base}/acquiring/requests", params: { providers: ["freedom_pay"], status: "approved", provider_merchant_id: "injected", payment_secret: "ignored" }
      end
    end
    item = @outlet.acquiring_requests.sole
    assert_equal "pending", item.status
    assert_equal @user.id, item.requested_by
    assert_no_difference "AcquiringRequest.count" do
      post "#{@base}/acquiring/requests", params: { providers: ["freedom_pay"] }
    end
    get @base, params: { tab: "acquiring" }
    assert_response :success
    assert_includes response.body, "Заявка отправлена"
    assert_select 'input[name="payment_secret"], input[name="provider_merchant_id"]', count: 0
    post "/admin/acquiring/requests/#{item.id}/configure", params: credentials
    assert_redirected_to "/admin/login"
    post "/admin/acquiring/requests/#{item.id}/decision", params: { decision: "approve" }
    assert_redirected_to "/admin/login"
    post "#{@base}/acquiring/connections", params: credentials
    assert_response :not_found
    assert_nil item.reload.acquiring_connection_id
  end

  test "admin reviews configures and approves before merchant selects primary" do
    item = submit_request
    admin_login
    path = "/admin/acquiring/requests/#{item.id}"
    get "/admin/acquiring"
    assert_response :success
    get path
    assert_response :success
    post "#{path}/review"
    assert_equal "in_review", item.reload.status
    post "#{path}/decision", params: { decision: "approve" }
    assert_equal "in_review", item.reload.status
    post "#{path}/configure", params: credentials.merge(environment: "test")
    connection = item.reload.acquiring_connection
    assert connection.secret_saved?
    assert_equal credentials[:payment_secret], PaymentProviders::SecretCipher.new.decrypt(connection)
    assert_not_includes connection.secret_ciphertext, credentials[:payment_secret]
    post "#{path}/decision", params: { decision: "approve" }
    assert_equal "in_review", item.reload.status
    post "#{path}/configure", params: credentials
    post "#{path}/decision", params: { decision: "approve", review_note: "Проверено" }
    assert_equal "approved", item.reload.status
    assert_equal @admin.id, item.reviewed_by
    post "#{@base}/acquiring/requests/#{item.id}/primary"
    assert connection.reload.is_default
    get @base, params: { tab: "acquiring" }
    assert_includes response.body, "Одобрено ProCash"
    assert_not_includes response.body, credentials[:payment_secret]
    assert_not_includes response.body, credentials[:provider_merchant_id]
    assert_select 'input[name="payment_secret"]', count: 0
    post "#{path}/configure", params: credentials.merge(payment_secret: "rotated-test-secret")
    assert_equal "in_review", item.reload.status
    assert_not connection.reload.is_default
    post "#{@base}/acquiring/requests/#{item.id}/primary"
    assert_response :not_found
    get "/dashboard/payments", params: { outlet_id: @outlet.id }
    assert_includes response.body, "Приём платежей ещё не подключён"
  end

  test "rejection includes merchant visible reason and allows a new request" do
    item = submit_request
    admin_login
    path = "/admin/acquiring/requests/#{item.id}"
    post "#{path}/decision", params: { decision: "reject" }
    assert_equal "pending", item.reload.status
    post "#{path}/decision", params: { decision: "reject", review_note: "Уточните реквизиты компании" }
    assert_equal "rejected", item.reload.status
    get @base, params: { tab: "acquiring" }
    assert_includes response.body, "Уточните реквизиты компании"
    assert_difference "AcquiringRequest.count", 1 do
      submit_request
    end
    post "#{path}/decision", params: { decision: "approve" }
    assert_equal "rejected", item.reload.status
  end

  test "foreign outlets staff and unsupported providers cannot submit requests" do
    other = Merchant.create!(legal_name: "Other", bin_iin: "999999999999")
    outlet = other.merchant_outlets.create!(name: "Other outlet", city: "Almaty", address: "Abay 10")
    assert_no_difference "AcquiringRequest.count" do
      post "/dashboard/merchants/#{@merchant.id}/outlets/#{outlet.id}/acquiring/requests", params: { providers: ["freedom_pay"] }
      assert_response :not_found
      post "#{@base}/acquiring/requests", params: { providers: ["unknown"] }
      @membership.update!(role: "staff")
      post "#{@base}/acquiring/requests", params: { providers: ["freedom_pay"] }
      assert_response :forbidden
    end
  end

  test "legacy saved connections are admin only and can be linked to a request" do
    connection = @outlet.acquiring_connections.create!(merchant: @merchant, provider: "freedom_pay", name: "Legacy", provider_merchant_id: "001234", environment: "live")
    item = submit_request
    get "/admin/acquiring/outlets/#{@outlet.id}"
    assert_redirected_to "/admin/login"
    admin_login
    get "/admin/acquiring/outlets/#{@outlet.id}"
    assert_response :success
    assert_includes response.body, "Legacy"
    post "/admin/acquiring/requests/#{item.id}/configure", params: credentials.merge(existing_connection_id: connection.id)
    assert_equal connection.id, item.reload.acquiring_connection_id
    assert_equal 1, @outlet.acquiring_connections.count
    post "/admin/acquiring/requests/#{item.id}/decision", params: { decision: "approve" }
    post "#{@base}/acquiring/requests/#{item.id}/primary"
    assert connection.reload.is_default
    post "/admin/acquiring/outlets/#{@outlet.id}/connections/#{connection.id}", params: credentials.merge(provider: "freedom_pay", name: "Updated")
    assert_equal "in_review", item.reload.status
    assert_not connection.reload.is_default
  end
end
