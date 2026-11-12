require "test_helper"

class CompatibilityTest < ActiveSupport::TestCase
  test "Argon2id PHC hashes round trip and reject wrong passwords" do
    hash = Auth::Password.hash("correct-password-123")
    assert_match(/\A\$argon2id\$v=19\$m=19456,t=2,p=1\$/, hash)
    assert Auth::Password.verify("correct-password-123", hash)
    assert_not Auth::Password.verify("wrong", hash)
    assert_not Auth::Password.verify("password", "invalid")
    assert_not_equal hash, Auth::Password.hash("correct-password-123")
    assert_raises(ArgumentError) { Auth::Password.hash("short") }
  end

  test "iiko authenticated encryption binds keys to connection ID" do
    cipher = Pos::Adapters::Iiko::KeyCipher.new(key: "*" * 32)
    id = SecureRandom.uuid
    encrypted = cipher.encrypt(id, "test-key")
    assert_equal 12, encrypted[:api_key_nonce].bytesize
    args = { ciphertext: encrypted[:api_key_ciphertext], nonce: encrypted[:api_key_nonce], version: 1 }
    assert_equal "test-key", cipher.decrypt(id, **args)
    assert_raises(OpenSSL::Cipher::CipherError) { cipher.decrypt(SecureRandom.uuid, **args) }
    assert_raises(ArgumentError) { cipher.decrypt(id, **args.merge(version: 2)) }
    assert_not_equal encrypted[:api_key_nonce], cipher.encrypt(id, "test-key")[:api_key_nonce]
  end

  test "invitation tokens sign UUID bytes rather than UUID text" do
    id = "11111111-2222-4333-8444-555555555555"
    key = "*" * 32
    expected = OpenSSL::HMAC.hexdigest("SHA256", key, "procash:merchant-invitation:v1:".b + [id.delete("-")].pack("H*"))
    assert_equal "#{id}.#{expected}", MerchantInvitation.token_for(id, key: key)
  end

  test "tips preserve half-up rounding and custom precision rules" do
    calculator = Tips::Calculator.new(enabled: true, custom: true)
    assert_equal BigDecimal("0.51"), calculator.percentage("10.10", 5)[:tip_amount]
    assert_equal BigDecimal("150.50"), calculator.custom("2000", "150,50")[:tip_amount]
    assert_equal BigDecimal("150.50"), calculator.custom("2000", "150.500")[:tip_amount]
    ["-1", "150.567", "1e2", "2001", "NaN", ""].each do |value|
      assert_raises(ArgumentError) { calculator.custom("2000", value) }
    end
    assert_raises(ArgumentError) { calculator.percentage("100", 20) }
    assert_equal 0, Tips::Calculator.new.percentage("100", 0)[:tip_amount]
    assert_raises(ArgumentError) { Tips::Calculator.new.percentage("100", 5) }
  end

  test "client sends exact Rust v2 credentials and by-table payload" do
    calls = []
    transport = ->(endpoint, body, token) do
      calls << [endpoint, body, token]
      endpoint == "/api/v2/access_token" ? { "token" => "access-token" } : { "orders" => [] }
    end
    client = Pos::Adapters::Iiko::Client.new(app_id: "app", client_secret: "secret", api_key: "key", transport: transport)
    assert_equal({ "orders" => [] }, client.orders_by_table("org", "table"))
    assert_equal ["/api/v2/access_token", { appId: "app", clientSecret: "secret", apiKey: "key" }, nil], calls[0]
    assert_equal ["/api/1/order/by_table", { organizationIds: ["org"], tableIds: ["table"], statuses: %w[New Bill] }, "access-token"], calls[1]
  end

  def response
    { "orders" => [{ "id" => "order", "organizationId" => "org", "creationStatus" => "Success", "order" => {
      "status" => "New", "tableIds" => ["table"], "sum" => BigDecimal("12500.75"), "processedPaymentsSum" => BigDecimal("1500.25"),
      "items" => [{ "type" => "Product", "product" => { "id" => "p", "name" => "Бургер" }, "amount" => 2, "price" => 3500, "resultSum" => 7000 }] } }] }
  end

  def map(value) = Pos::Adapters::Iiko::BillMapper.call(value, organization_id: "org", table_id: "table")

  test "bill preserves exact partial payment and unknown balances" do
    value = response
    assert_equal BigDecimal("11000.50"), map(value).order[:remaining]
    value["orders"][0]["order"].delete("processedPaymentsSum")
    assert_nil map(value).order[:remaining]
    assert_nil map(value).order[:processed_payments]
  end

  test "bill states do not conflate no order, syncing, multiple, and closed" do
    assert_equal :no_order, map({ "orders" => [] }).state
    value = response
    value["orders"] *= 2
    assert_equal :multiple_orders, map(value).state
    value = response
    value["orders"][0]["creationStatus"] = "InProgress"
    assert_equal :syncing, map(value).state
    value = response
    value["orders"][0]["order"]["status"] = "Closed"
    assert_equal :closed, map(value).state
  end

  test "bill rejects inconsistent money, table, organization and unsupported items" do
    [->(v) { v["orders"][0]["order"]["sum"] = -1 },
     ->(v) { v["orders"][0]["order"]["processedPaymentsSum"] = 999999 },
     ->(v) { v["orders"][0]["organizationId"] = "other" },
     ->(v) { v["orders"][0]["order"]["tableIds"] = ["other"] },
     ->(v) { v["orders"][0]["order"]["items"][0]["type"] = "Combo" }].each do |mutation|
      value = response
      mutation.call(value)
      assert_equal :unavailable, map(value).state
    end
    assert_equal :unavailable, map({}).state
  end
end
