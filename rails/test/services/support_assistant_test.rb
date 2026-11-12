require "test_helper"
require "net/http"
require_relative "../support/method_override"
class SupportAssistantTest < ActiveSupport::TestCase
  include MethodOverride
  setup do
    @settings = %w[AI_ASSISTANT_ENABLED AI_ASSISTANT_BASE_URL AI_ASSISTANT_MODEL].to_h { |key| [key, ENV[key]] }
    ENV["AI_ASSISTANT_ENABLED"] = "1"
    ENV["AI_ASSISTANT_BASE_URL"] = "http://model.example.test:8081/v1"
    ENV["AI_ASSISTANT_MODEL"] = "test-model"
  end
  teardown { @settings.each { |key, value| ENV[key] = value } }
  test "retrieval finds relevant guides without using account records" do
    results = SupportAssistant::KnowledgeBase.find("Как подключить iiko?")
    assert_equal "/documentation#iiko", results.first[:url]
    assert results.size <= 2
    assert results.all? { |item| item[:text].size <= 2100 }
    assert_empty SupportAssistant::KnowledgeBase.find("Погода завтра")
    assert_includes SupportAssistant::KnowledgeBase.find("Нет заказа по QR").map { |item| item[:url] }, "/documentation#troubleshooting"
    assert_equal ["/documentation#acquiring"], SupportAssistant::KnowledgeBase.find("Как подключить эквайринг?").map { |item| item[:url] }
  end
  test "client uses bounded non-thinking chat request and removes model reasoning" do
    captured = nil
    response = Net::HTTPOK.new("1.1", "200", "OK")
    response.define_singleton_method(:read_body) { |&block| block.call({choices: [{message: {content: "<think>internal</think>Откройте POS-интеграцию."}}]}.to_json) }
    http = Object.new
    http.define_singleton_method(:request) { |request, &block| captured = request; block.call(response) }
    start = ->(*, **, &block) { block.call(http) }
    override(Net::HTTP, :start, start) do
      answer = SupportAssistant::Client.new.call(question: "iiko", sources: SupportAssistant::KnowledgeBase.find("iiko"))
      assert_equal "Откройте POS-интеграцию.", answer
    end
    payload = JSON.parse(captured.body)
    assert_equal "/v1/chat/completions", captured.path
    assert_equal false, payload.dig("chat_template_kwargs", "enable_thinking")
    assert_equal 220, payload["max_tokens"]
    assert_equal ["system", "user"], payload["messages"].map { |message| message["role"] }
    assert_not payload.key?("tools")
  end
  test "only one model call per process runs and lock is released after errors" do
    SupportAssistant::Client::LOCK.lock
    assert_raises(SupportAssistant::Client::Busy) { SupportAssistant::Client.new.call(question: "iiko", sources: []) }
    SupportAssistant::Client::LOCK.unlock
    ENV["AI_ASSISTANT_BASE_URL"] = "file:///tmp/not-an-http-service"
    assert_raises(SupportAssistant::Client::Unavailable) { SupportAssistant::Client.new.call(question: "iiko", sources: []) }
    assert_not SupportAssistant::Client::LOCK.locked?
  ensure
    SupportAssistant::Client::LOCK.unlock if SupportAssistant::Client::LOCK.owned?
  end
end
