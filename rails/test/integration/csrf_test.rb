require "test_helper"
class CsrfTest < ActionDispatch::IntegrationTest
  setup { AssistantController::RATE_STORE.clear }
  test "public assistant accepts same origin with CSRF even when configured origin differs" do
    previous = ActionController::Base.allow_forgery_protection
    previous_origin = ENV["APP_ORIGIN"]
    previous_enabled = ENV["AI_ASSISTANT_ENABLED"]
    ActionController::Base.allow_forgery_protection = true
    ENV["APP_ORIGIN"] = "http://localhost:3101"
    ENV["AI_ASSISTANT_ENABLED"] = "1"
    get "/"
    token = Nokogiri::HTML(response.body).at_css('meta[name="csrf-token"]')["content"]
    post "/assistant/messages", params: { question: "Погода завтра" }, as: :json, headers: { "Origin" => "http://www.example.com", "X-CSRF-Token" => token }
    assert_response :success
    post "/assistant/messages", params: { question: "Погода завтра" }, as: :json, headers: { "Origin" => "https://foreign.example", "X-CSRF-Token" => token }
    assert_response :unprocessable_entity
  ensure
    ActionController::Base.allow_forgery_protection = previous
    ENV["APP_ORIGIN"] = previous_origin
    ENV["AI_ASSISTANT_ENABLED"] = previous_enabled
  end

  test "assistant endpoint rejects oversized bodies and requests without CSRF" do
    post "/assistant/messages", params: "x" * (4 * 1024 + 1), headers: { "CONTENT_TYPE" => "application/json" }
    assert_response :content_too_large
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    post "/assistant/messages", params: { question: "Как подключить iiko?" }, as: :json
    assert_response :unprocessable_entity
  ensure
    ActionController::Base.allow_forgery_protection = previous unless previous.nil?
  end
  test "body size limits run before parameter parsing" do
    post "/connect", params: "x" * (16 * 1024 + 1), headers: { "CONTENT_TYPE" => "application/x-www-form-urlencoded" }
    assert_response :content_too_large
  end
  test "valid CSRF token still requires exact origin" do
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    get "/login"
    token = Nokogiri::HTML(response.body).at_css('input[name="authenticity_token"]')["value"]
    post "/login", params: { authenticity_token: token, email: "missing@example.test", password: "wrong-password" }
    assert_response :forbidden
    post "/login", params: { authenticity_token: token, email: "missing@example.test", password: "wrong-password" }, headers: { "Origin" => "http://www.example.com" }
    assert_response :unprocessable_entity
  ensure
    ActionController::Base.allow_forgery_protection = previous
  end
  test "login and connection requests reject missing CSRF tokens" do
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    get "/login"
    assert_response :success
    post "/login", params: { email: "nobody@example.test", password: "wrong-password" }
    assert_response :unprocessable_entity
    assert_no_difference "ConnectionRequest.count" do
      post "/connect", params: { contact_name: "Test" }
    end
    assert_response :unprocessable_entity
  ensure
    ActionController::Base.allow_forgery_protection = previous
  end
end
