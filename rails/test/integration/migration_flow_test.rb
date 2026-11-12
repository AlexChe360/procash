require "test_helper"

class MigrationFlowTest < ActionDispatch::IntegrationTest
  setup do
    @admin = User.create!(email: "admin@example.test", password_hash: Auth::Password.hash("admin-password-123"), platform_role: "admin", email_verified_at: Time.current)
    @user = User.create!(email: "owner@example.test", password_hash: Auth::Password.hash("owner-password-123"), email_verified_at: Time.current)
    @merchant = Merchant.create!(legal_name: "Test restaurant", bin_iin: "123456789012")
    @membership = MerchantMembership.create!(merchant: @merchant, user: @user, role: "owner")
    @outlet = @merchant.merchant_outlets.create!(name: "Алма", city: "Алматы", address: "Абая 10", pos_system: "iiko")
  end

  test "public pages render and protected routes require correct role" do
    get "/"
    assert_response :success
    assert_includes response.body, "/assets/home.css"
    get "/login"
    assert_response :success
    get "/connect"
    assert_response :success
    get "/dashboard"
    assert_redirected_to "/login"
    get "/demo/requests"
    assert_redirected_to "/admin/login"
    post "/login", params: { email: @user.email, password: "owner-password-123" }
    assert_redirected_to "/dashboard"
    follow_redirect!
    assert_response :success
    get "/demo/requests"
    assert_redirected_to "/admin/login"
    get "/dashboard/merchants/#{@merchant.id}"
    assert_response :success
    get "/dashboard/merchants/#{SecureRandom.uuid}"
    assert_response :not_found
    post "/dashboard/logout"
    get "/dashboard"
    assert_redirected_to "/login"
  end

  test "admin navigation opens separate sections and both workspaces show signed in email" do
    post "/admin/login", params: { email: @admin.email, password: "admin-password-123" }
    get "/demo/dashboard"
    assert_response :success
    assert_select "h1", "Обзор ProCash"
    assert_select "table", count: 0
    assert_select 'nav a[href="/demo/dashboard"][aria-current="page"]'
    assert_select ".topbar-email", @admin.email
    get "/demo/requests"
    assert_response :success
    assert_select "h1", "Заявки"
    assert_select 'nav a[href="/demo/requests"][aria-current="page"]'
    get "/demo/merchants"
    assert_response :success
    assert_select "h1", "Компании"
    assert_select 'nav a[href="/demo/merchants"][aria-current="page"]'
    assert_includes response.body, @merchant.legal_name
    post "/admin/logout"
    get "/demo/merchants"
    assert_redirected_to "/admin/login"
    post "/login", params: { email: @user.email, password: "owner-password-123" }
    get "/dashboard"
    assert_select ".topbar-email", @user.email
    get "/demo/merchants"
    assert_redirected_to "/admin/login"
  end

  test "merchant and admin logins and logouts are independent in the same browser" do
    post "/login", params: { email: @user.email, password: "owner-password-123" }
    merchant_session = @user.user_sessions.order(:created_at).last
    post "/admin/login", params: { email: @admin.email, password: "admin-password-123" }
    assert_nil merchant_session.reload.revoked_at
    get "/dashboard"
    assert_response :success
    assert_select ".topbar-email", @user.email
    get "/demo/dashboard"
    assert_response :success
    assert_select ".topbar-email", @admin.email
    post "/admin/logout"
    get "/dashboard"
    assert_response :success
    get "/demo/dashboard"
    assert_redirected_to "/admin/login"
    post "/admin/login", params: { email: @admin.email, password: "admin-password-123" }
    post "/dashboard/logout"
    get "/demo/dashboard"
    assert_response :success
    get "/dashboard"
    assert_redirected_to "/login"
  end

  test "invitation status distinguishes queued sent and activated and prevents duplicate mail" do
    previous = ENV["INVITATION_TOKEN_SECRET"]
    ENV["INVITATION_TOKEN_SECRET"] = "2a" * 32
    @membership.update!(role: "manager")
    item = ConnectionRequest.create!(contact_name: "Тест", contact_email: "invite@example.test", contact_phone: "+77001234567", establishment_name: "Кафе", city: "Алматы", consent: "yes")
    item.transition!("in_review", @admin)
    item.transition!("approved", @admin)
    item.update!(merchant: @merchant)
    post "/admin/login", params: { email: @admin.email, password: "admin-password-123" }
    path = "/demo/requests/#{item.id}"
    assert_difference ["MerchantInvitation.count", "MerchantInvitationOutbox.count"], 1 do
      post "#{path}/invitation"
    end
    follow_redirect!
    assert_includes response.body, "Приглашение в очереди отправки"
    assert_no_difference ["MerchantInvitation.count", "MerchantInvitationOutbox.count"] do
      post "#{path}/invitation"
    end
    follow_redirect!
    assert_select '[role="alert"]', text: /уже создано/
    invitation = MerchantInvitation.find_by!(connection_request: item)
    invitation.merchant_invitation_outbox.update!(sent_at: Time.current)
    assert_no_difference ["MerchantInvitation.count", "MerchantInvitationOutbox.count"] do
      post "#{path}/invitation"
    end
    follow_redirect!
    assert_select '[role="alert"]', text: /уже отправлено/
    @membership.update!(role: "owner")
    get path
    assert_includes response.body, "Кабинет уже активирован"
    assert_select 'form[action$="/invitation"]', count: 0
  ensure
    ENV["INVITATION_TOKEN_SECRET"] = previous
  end

  test "connection request stores a twelve digit BIN and prefills company creation" do
    get "/connect"
    assert_select 'input[name="bin_iin"][inputmode="numeric"][maxlength="12"]'
    fields = { contact_name: "Тест", contact_email: "bin@example.test", contact_phone: "+77001234567", establishment_name: "Кафе", city: "Алматы", consent: "yes", bin_iin: "012345678901" }
    assert_no_difference "ConnectionRequest.count" do
      post "/connect", params: fields.merge(bin_iin: "123abc")
    end
    assert_response :unprocessable_entity
    post "/connect", params: fields
    assert_redirected_to "/connect/success"
    item = ConnectionRequest.find_by!(contact_email: "bin@example.test")
    assert_equal "012345678901", item.bin_iin
    item.transition!("in_review", @admin)
    item.transition!("approved", @admin)
    post "/admin/login", params: { email: @admin.email, password: "admin-password-123" }
    get "/demo/requests/#{item.id}"
    assert_includes response.body, "БИН/ИИН: 012345678901"
    assert_select 'input[name="bin_iin"][value="012345678901"]'
  end

  test "legacy request displays BIN from its linked company" do
    item = ConnectionRequest.create!(contact_name: "Тест", contact_email: "legacy@example.test", contact_phone: "+77001234567", establishment_name: "Кафе", city: "Алматы", consent: "yes", merchant: @merchant)
    post "/admin/login", params: { email: @admin.email, password: "admin-password-123" }
    get "/demo/requests/#{item.id}"
    assert_response :success
    assert_includes response.body, "БИН/ИИН: #{@merchant.bin_iin}"
    assert_nil item.reload.bin_iin
  end

  test "outlet creation stays collapsed until needed and preserves invalid input" do
    post "/login", params: { email: @user.email, password: "owner-password-123" }
    get "/dashboard/merchants/#{@merchant.id}"
    assert_select "details.company-create:not([open])"
    assert_no_difference "MerchantOutlet.count" do
      post "/dashboard/merchants/#{@merchant.id}/outlets", params: { name: "Новый филиал", city: "", address: "Абая 10", pos_system: "iiko" }
    end
    assert_response :unprocessable_entity
    assert_select "details.company-create[open]"
    assert_select 'input[name="name"][value="Новый филиал"]'
    assert_select 'option[value="iiko"][selected]'
  end

  test "staff cannot create outlets or tables" do
    @membership.update!(role: "staff")
    post "/login", params: { email: @user.email, password: "owner-password-123" }
    assert_no_difference "MerchantOutlet.count" do
      post "/dashboard/merchants/#{@merchant.id}/outlets", params: { name: "Other", city: "Алматы", address: "Test 10" }
    end
    assert_response :forbidden
    assert_no_difference "OutletTable.count" do
      post "/dashboard/merchants/#{@merchant.id}/outlets/#{@outlet.id}/tables", params: { code: "1", name: "Стол 1" }
    end
    assert_response :forbidden
  end

  test "request and notification outbox are created together" do
    assert_difference ["ConnectionRequest.count", "EmailOutbox.count"], 1 do
      post "/connect", params: { contact_name: "Тест", contact_email: "TEST@example.test", contact_phone: "+7 700 123 45 67", establishment_name: "Алма", city: "Алматы", consent: "yes" }
    end
    assert_redirected_to "/connect/success"
    assert_equal "test@example.test", ConnectionRequest.last.contact_email
  end

  test "invalid request and spam do not persist" do
    assert_no_difference "ConnectionRequest.count" do
      post "/connect", params: { contact_name: "a" }
    end
    assert_response :unprocessable_entity
    assert_no_difference "ConnectionRequest.count" do
      post "/connect", params: { website: "spam" }
    end
  end

  test "session expiry revocation and account eligibility are checked" do
    token = UserSession.issue!(@user)
    session = UserSession.for_token(token)
    assert_equal 32, session.token_hash.bytesize
    assert_not_equal token, session.token_hash
    travel 13.hours do
      assert_nil UserSession.for_token(token)
    end
    session.update!(revoked_at: Time.current)
    assert_nil UserSession.for_token(token)
    assert_nil UserSession.for_token("invalid")
    @user.update!(is_active: false)
    assert_nil User.authenticate(@user.email, "owner-password-123", role: "user")
    assert_nil User.authenticate(@admin.email, "admin-password-123", role: "user")
  end

  test "one time invitations preserve existing accounts" do
    previous = ENV["INVITATION_TOKEN_SECRET"]
    ENV["INVITATION_TOKEN_SECRET"] = "2a" * 32
    request = ConnectionRequest.create!(contact_name: "Тест", contact_email: "invite@example.test", contact_phone: "+77001234567", establishment_name: "Алма", city: "Алматы", consent: "yes")
    request.transition!("in_review", @admin)
    request.transition!("approved", @admin)
    request.update!(merchant: @merchant)
    @membership.update!(role: "manager")
    invitation = MerchantInvitation.issue!(request, @admin)
    token = MerchantInvitation.token_for(invitation.id)
    assert MerchantInvitation.for_token(token)
    get "/invite/#{token}"
    assert_response :success
    assert_equal token, Nokogiri::HTML(response.body).at_css('input[name="token"]')["value"]
    assert_nil MerchantInvitation.for_token(token.sub(/.$/, token.end_with?("0") ? "1" : "0"))
    user = MerchantInvitation.activate!(token, "invited-password-123")
    assert_equal "invite@example.test", user.email
    assert_nil MerchantInvitation.for_token(token)
    assert_raises(ArgumentError) { MerchantInvitation.activate!(token, "invited-password-123") }
    assert user.merchant_memberships.find_by!(merchant: @merchant).manages?
  ensure
    ENV["INVITATION_TOKEN_SECRET"] = previous
  end

  test "QR keeps old UUID token and safely shows unavailable integration" do
    table = @outlet.outlet_tables.create!(code: "1", name: "Стол 1")
    get "/t/#{table.qr_token}"
    assert_response :success
    assert_includes response.body, "Оплата пока недоступна"
    table.update!(is_active: false)
    get "/t/#{table.qr_token}"
    assert_response :not_found
  end
  test "outlet tabs separate settings and retain the tab after saving" do
    post "/login", params: { email: @user.email, password: "owner-password-123" }
    base = "/dashboard/merchants/#{@merchant.id}/outlets/#{@outlet.id}"
    get base
    assert_response :success
    assert_select '.outlet-tabs a[aria-current="page"]', text: "Обзор"
    assert_select 'form[action$="/tables"]', count: 0
    get base, params: { tab: "tables" }
    assert_select 'form[action$="/tables"]', count: 1
    assert_select 'form[action$="/tip-settings"]', count: 0
    get base, params: { tab: "tips" }
    assert_select 'form[action$="/tip-settings"]', count: 1
    assert_select 'form[action$="/tables"]', count: 0
    get base, params: { tab: "pos" }
    assert_select 'input[name="api_key"]', count: 1
    assert_select 'form[action$="/tip-settings"]', count: 0
    get base, params: { tab: "../../anything" }
    assert_select '.outlet-tabs a[aria-current="page"]', text: "Обзор"
    post "#{base}/tables", params: { code: "01", name: "Стол у окна" }
    assert_redirected_to "#{base}?tab=tables"
    post "#{base}/tip-settings", params: { is_enabled: "1", tip_10: "1" }
    assert_redirected_to "#{base}?tab=tips"
    @membership.update!(role: "staff")
    get base, params: { tab: "pos" }
    assert_select '.outlet-tabs a', count: 2
    assert_select 'input[name="api_key"]', count: 0
  end

  test "iiko setup guides verified key to organization tables and activation" do
    connection = @merchant.iiko_connections.create!(name: "iiko", api_key_ciphertext: "a" * 32, api_key_nonce: "b" * 12)
    organization, group, external_table = SecureRandom.uuid, SecureRandom.uuid, SecureRandom.uuid
    fake = Object.new
    fake.define_singleton_method(:organizations) { [{ "id" => organization, "name" => "Алма iiko" }] }
    fake.define_singleton_method(:terminal_groups) { |_| [{ "organizationId" => organization, "items" => [{ "organizationId" => organization, "id" => group, "name" => "Основная касса" }] }] }
    fake.define_singleton_method(:restaurant_sections) { |_, **| { "restaurantSections" => [{ "id" => SecureRandom.uuid, "name" => "Зал", "terminalGroupId" => group, "tables" => [{ "id" => external_table, "name" => "Стол iiko 1", "isDeleted" => false }] }] } }
    klass = Pos::Adapters::Iiko::Configuration
    original = klass.instance_method(:build_client)
    klass.send(:define_method, :build_client) { |_| fake }
    klass.send(:private, :build_client)
    post "/login", params: { email: @user.email, password: "owner-password-123" }
    base = "/dashboard/merchants/#{@merchant.id}/outlets/#{@outlet.id}"
    pos = "#{base}/pos"
    post "#{pos}/connections/#{connection.id}/check"
    assert_redirected_to "#{pos}/connections/#{connection.id}/setup"
    get "#{pos}/connections/#{connection.id}/setup", params: { organization_id: organization }
    assert_response :success
    assert_includes response.body, "Основная касса"
    post "#{pos}/connections/#{connection.id}/binding", params: { organization_id: organization, terminal_group_id: group }
    assert_redirected_to "#{base}?tab=pos#iiko-step-3"
    get base, params: { tab: "pos" }
    assert_includes response.body, "Организация и терминальная группа сохранены"
    assert_select 'form[action$="/activation/enable"] button[disabled]', count: 1
    table = @outlet.outlet_tables.create!(code: "1", name: "Стол 1")
    get "#{pos}/tables"
    assert_response :success
    post "#{pos}/tables/#{table.id}/link", params: { iiko_table_id: external_table }
    assert_redirected_to "#{pos}/tables"
    assert_equal external_table, table.reload.pos_table_id
    assert_includes flash[:alert], "заказы по QR пока не загружаются"
    get "#{pos}/tables"
    assert_select ".iiko-activation-warning", text: /Интеграция iiko не активна/
    assert_select ".iiko-activation-warning a[href='#{base}?tab=pos#iiko-step-4']"
    get "#{pos}/connections/#{connection.id}/setup"
    assert_select "option[value='#{organization}'][selected]"
    assert_select "option[value='#{group}'][selected]"
    post "#{pos}/activation/check"
    assert_redirected_to "#{base}?tab=pos#iiko-step-4"
    post "#{pos}/activation/enable"
    assert_redirected_to "#{base}?tab=pos#iiko-step-4"
    assert @outlet.reload.outlet_iiko_setting.is_enabled
    get "#{pos}/tables"
    assert_select ".iiko-activation-warning", count: 0
  ensure
    if original
      klass.send(:define_method, :build_client, original)
      klass.send(:private, :build_client)
    end
  end

end
