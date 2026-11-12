module Middleware
  class RequestBodyLimit
    def initialize(app) = @app = app
    def call(env)
      return @app.call(env) unless env["REQUEST_METHOD"] == "POST"
      path = env["PATH_INFO"]
      limit = if path == "/assistant/messages"
        4 * 1024
      elsif path == "/connect"
        16 * 1024
      elsif path.start_with?("/admin/acquiring/") || path.match?(%r{\A/dashboard/merchants/[^/]+/outlets/[^/]+/acquiring/})
        16 * 1024
      elsif path.match?(%r{\A/dashboard/merchants/[^/]+/outlets/[^/]+/tables/[^/]+/qr/logo\z})
        520 * 1024
      elsif path == "/dashboard/logout" || path.match?(%r{/pos/(?:connections/[^/]+/(?:check|binding))\z})
        4 * 1024
      elsif path == "/login" || path == "/invite/activate" || path.match?(%r{\A/dashboard/merchants/[^/]+/outlets(?:\z|/[^/]+/(?:tables|pos/connections)\z)})
        8 * 1024
      end
      return @app.call(env) unless limit
      input = env["rack.input"]
      if env["CONTENT_LENGTH"].to_i > limit
        return [413, { "content-type" => "text/plain", "cache-control" => "no-store" }, ["Слишком большой запрос"]]
      end
      if input
        data = input.read(limit + 1)
        input.rewind
        return [413, { "content-type" => "text/plain", "cache-control" => "no-store" }, ["Слишком большой запрос"]] if data && data.bytesize > limit
      end
      @app.call(env)
    end
  end
end
