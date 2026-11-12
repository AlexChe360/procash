require "test_helper"
class DocumentationTest < ActionDispatch::IntegrationTest
  test "public guide covers the current workflow with valid local illustrations" do
    get "/documentation"
    assert_response :success
    assert_select "title", "Документация — кабинет мерчанта ProCash"
    assert_select "article.guide-article", count: 10
    assert_select 'input[aria-label="Поиск по документации"]'
    assert_select 'nav[aria-label="Содержание документации"] a', count: 10
    assert_includes response.body, "банковский приём платежей пока не включён"
    assert_includes response.body, "Merchant ID и секретный ключ в кабинете мерчанта вводить не нужно"
    assert_includes response.body, "Скачать SVG"
    assert_includes response.body, "повторная проверка и активация"
    assert_select "figure img", count: 8
    css_select("figure img").each do |image|
      file = Rails.root.join("public", image["src"].delete_prefix("/"))
      assert file.file?, image["src"]
      assert image["alt"].present?
      assert_empty Nokogiri::XML(File.read(file)).errors
    end
    get "/"
    assert_select 'nav a[href="/documentation"]', text: "Документация"
  end

  test "documentation stays public and is absent from merchant navigation" do
    user = User.create!(email: "guide@example.test", password_hash: Auth::Password.hash("documentation-password"), email_verified_at: Time.current)
    merchant = Merchant.create!(legal_name: "Guide Company", bin_iin: "123456789012")
    MerchantMembership.create!(merchant: merchant, user: user, role: "owner")
    post "/login", params: { email: user.email, password: "documentation-password" }
    get "/dashboard"
    assert_select 'nav a[href="/documentation"]', count: 0
    assert_select '.pc-assistant', count: 0
    get "/documentation"
    assert_response :success
    assert_select 'nav a[href="/documentation"][aria-current="page"]'
    assert_select 'nav a[href="/dashboard"]', count: 0
    get "/dashboard"
    assert_response :success
  end
end
