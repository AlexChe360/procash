require "test_helper"
class AccountWorkspaceTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "settings@example.test", password_hash: Auth::Password.hash("original-password-123"), email_verified_at: Time.current)
    @merchant = Merchant.create!(legal_name: "Company", bin_iin: "123456789012")
    MerchantMembership.create!(user: @user, merchant: @merchant, role: "owner")
    @outlet = @merchant.merchant_outlets.create!(name: "My outlet", city: "Almaty", address: "Abay 10")
    post "/login", params: { email: @user.email, password: "original-password-123" }
  end
  test "profile password and session changes are scoped to the signed in account" do
    get "/dashboard/settings"
    assert_response :success
    post "/dashboard/settings/profile", params: { display_name: "Алексей", platform_role: "admin" }
    assert_redirected_to "/dashboard/settings"
    assert_equal "Алексей", @user.reload.display_name
    assert_not @user.admin?
    token = UserSession.issue!(@user)
    post "/dashboard/settings/password", params: { current_password: "wrong", new_password: "replacement-password-123", password_confirmation: "replacement-password-123" }
    assert_response :unprocessable_entity
    assert UserSession.for_token(token)
    post "/dashboard/settings/password", params: { current_password: "original-password-123", new_password: "replacement-password-123", password_confirmation: "replacement-password-123" }
    assert_redirected_to "/dashboard/settings"
    assert_nil UserSession.for_token(token)
    assert Auth::Password.verify("replacement-password-123", @user.reload.password_hash)
    get "/dashboard/settings"
    assert_response :success
    assert_select 'input[type="password"][value]', count: 0
  end
  test "payments show configuration state and protect foreign outlets" do
    get "/dashboard/payments", params: { outlet_id: @outlet.id }
    assert_response :success
    assert_includes response.body, "платёжный провайдер"
    assert_not_includes response.body, "Freedom Pay"
    assert_includes response.body, "Приём платежей ещё не подключён"
    get "/dashboard/payments", params: { outlet_id: SecureRandom.uuid }
    assert_response :not_found
    get "/admin/settings"
    assert_redirected_to "/admin/login"
  end
  test "admin settings coexist with merchant settings" do
    admin = User.create!(email: "settings-admin@example.test", password_hash: Auth::Password.hash("admin-password-123"), platform_role: "admin", email_verified_at: Time.current)
    post "/admin/login", params: { email: admin.email, password: "admin-password-123" }
    get "/admin/settings"
    assert_response :success
    post "/admin/settings/profile", params: { display_name: "Администратор" }
    assert_redirected_to "/admin/settings"
    assert_equal "Администратор", admin.reload.display_name
    assert_nil @user.reload.display_name
    get "/dashboard/settings"
    assert_response :success
  end

  test "QR logo persists for the outlet can be reset and is manager only" do
    require "tempfile"
    table = @outlet.outlet_tables.create!(code: "1", name: "Стол 1")
    path = "/dashboard/merchants/#{@merchant.id}/outlets/#{@outlet.id}/tables/#{table.id}"
    Tempfile.create(["logo", ".png"]) do |file|
      file.binmode
      file.write(ChunkyPNG::Image.new(8, 8, ChunkyPNG::Color::BLACK).to_blob)
      file.flush
      upload = Rack::Test::UploadedFile.new(file.path, "image/png")
      post "#{path}/qr/logo", params: { logo: upload, design: "mint" }
      assert_redirected_to "#{path}/qr/design?design=mint"
      assert @outlet.reload.qr_logo.present?
      get "#{path}/qr.svg"
      assert_includes response.body, "data:image/png;base64,"
      assert_not_includes response.body, '>Cash</text>'
      post "#{path}/qr/logo", params: { reset_logo: "1" }
      assert_nil @outlet.reload.qr_logo
      get "#{path}/qr.svg"
      assert_includes response.body, '>Cash</text>'
      @user.merchant_memberships.first.update!(role: "staff")
      post "#{path}/qr/logo", params: { logo: Rack::Test::UploadedFile.new(file.path, "image/png") }
      assert_response :forbidden
      assert_nil @outlet.reload.qr_logo
    end
  end

  test "invalid QR logo leaves existing logo unchanged" do
    table = @outlet.outlet_tables.create!(code: "1", name: "Стол 1")
    path = "/dashboard/merchants/#{@merchant.id}/outlets/#{@outlet.id}/tables/#{table.id}"
    post "#{path}/qr/logo", params: { logo: "not an upload" }
    assert_response :unprocessable_entity
    assert_nil @outlet.reload.qr_logo
  end

  test "print layout embeds vector QR with explicit physical dimensions and palette" do
    table = @outlet.outlet_tables.create!(code: "1", name: "Стол 1")
    path = "/dashboard/merchants/#{@merchant.id}/outlets/#{@outlet.id}/tables/#{table.id}/qr/print"
    get path, params: { size: "small", color: "#8B5CF6" }
    assert_response :success
    assert_select '.print-card[style="width:40mm;height:50mm"] svg path'
    assert_includes response.body, 'fill="#8B5CF6"'
    assert_includes response.body, "Печать / сохранить PDF"
    assert_select 'img', count: 0
    get path, params: { size: "invalid" }
    assert_select '.print-card[style="width:60mm;height:75mm"]'
  end

  test "QR design defaults to classic and keeps the same table link" do
    table = @outlet.outlet_tables.create!(code: "1", name: "Стол 1")
    path = "/dashboard/merchants/#{@merchant.id}/outlets/#{@outlet.id}/tables/#{table.id}"
    get "#{path}/qr/design"
    assert_response :success
    assert_select 'option[value="classic"][selected]'
    assert_select 'a[data-qr-palette-target="svg"]', text: "Скачать SVG"
    assert_select '[data-action="qr-download#download"]', count: 0
    get "#{path}/qr.svg"
    classic = response.body
    assert_includes classic, "#E66353"
    get "#{path}/qr.svg", params: { design: "mint" }
    assert_includes response.body, "#16A365"
    assert_equal classic[/<path d="([^"]+)"/, 1], response.body[/<path d="([^"]+)"/, 1]
    get "#{path}/qr.svg", params: { design: "unknown" }
    assert_equal classic, response.body
    get "#{path}/qr.svg", params: { download: "1", color: "#8B5CF6" }
    assert_response :success
    assert_includes response.headers["Content-Disposition"], "attachment"
    assert_includes response.body, 'fill="#8B5CF6"'
    get "/dashboard/merchants/#{@merchant.id}/outlets/#{@outlet.id}/tables/#{SecureRandom.uuid}/qr/design"
    assert_response :not_found
  end
end
