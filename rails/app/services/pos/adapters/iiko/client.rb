require "net/http"
require "json"
require "bigdecimal"

module Pos::Adapters::Iiko
  class Client
    BASE_URL = "https://api-ru.iiko.services"
    class Error < StandardError
      attr_reader :status
      def initialize(message, status: nil)
        @status = status
        super(message)
      end
    end

    def initialize(app_id:, client_secret:, api_key:, transport: nil)
      raise ArgumentError, "Missing credentials" if [app_id, client_secret, api_key].any? { |value| value.to_s.strip.empty? }
      @credentials = { appId: app_id, clientSecret: client_secret, apiKey: api_key }
      @transport = transport
    end

    def organizations
      result = authorized("/api/1/organizations", {})["organizations"]
      raise Error, "Invalid organizations response" unless result.is_a?(Array) && result.all? { |item| item.is_a?(Hash) && item["id"].is_a?(String) && item["name"].is_a?(String) }
      result
    end
    def terminal_groups(organization_id)
      groups = authorized("/api/1/terminal_groups", { organizationIds: [organization_id], includeDisabled: true })["terminalGroups"]
      raise Error, "Invalid terminal groups response" unless groups.is_a?(Array) && groups.all? { |group| group.is_a?(Hash) && group["items"].is_a?(Array) }
      groups
    end
    def restaurant_sections(terminal_group_id, revision: nil)
      body = { terminalGroupIds: [terminal_group_id], returnSchema: false }
      body[:revision] = revision unless revision.nil?
      authorized("/api/1/reserve/available_restaurant_sections", body)
    end
    def orders_by_table(organization_id, table_id)
      authorized("/api/1/order/by_table", { organizationIds: [organization_id], tableIds: [table_id], statuses: %w[New Bill] })
    end
    def init_orders_by_table(organization_id, terminal_group_id, table_id)
      authorized("/api/1/order/init_by_table", { organizationId: organization_id, terminalGroupId: terminal_group_id, tableIds: [table_id] })
    end
    def command_status(organization_id, correlation_id)
      authorized("/api/1/commands/status", { organizationId: organization_id, correlationId: correlation_id })
    end
    def inspect = "#<#{self.class.name} [FILTERED]>"

    private
    def authorized(endpoint, body)
      token = post("/api/v2/access_token", @credentials).fetch("token")
      raise Error, "Empty access token" unless token.is_a?(String) && !token.strip.empty?
      post(endpoint, body, token)
    rescue KeyError, TypeError
      raise Error, "Invalid iiko response"
    end

    def post(endpoint, body, token = nil)
      return @transport.call(endpoint, body, token) if @transport
      uri = URI(BASE_URL + endpoint)
      request = Net::HTTP::Post.new(uri)
      request["Content-Type"] = "application/json"
      request["Authorization"] = "Bearer #{token}" if token
      request.body = JSON.generate(body)
      response = Net::HTTP.start(uri.hostname, uri.port, use_ssl: true, open_timeout: 5, read_timeout: 20, write_timeout: 20) { |http| http.request(request) }
      raise Error.new("iiko #{endpoint} HTTP #{response.code}", status: response.code.to_i) unless response.is_a?(Net::HTTPSuccess)
      result = JSON.parse(response.body, decimal_class: BigDecimal)
      raise Error, "Invalid iiko response" unless result.is_a?(Hash)
      result
    rescue JSON::ParserError, IOError, SystemCallError, Timeout::Error, OpenSSL::SSL::SSLError
      raise Error, "iiko request failed"
    end
  end
end
