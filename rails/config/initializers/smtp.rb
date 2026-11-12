if ENV["SMTP_MODE"].present?
  mode = ENV.fetch("SMTP_MODE")
  host = ENV.fetch("SMTP_HOST")
  raise "Local SMTP must use loopback" if mode == "local" && !%w[localhost 127.0.0.1].include?(host)
  raise "Unsupported SMTP_MODE" unless %w[local tls starttls].include?(mode)
  ActionMailer::Base.smtp_settings = {
    address: host, port: mode == "local" ? 1026 : mode == "tls" ? 465 : 587,
    user_name: ENV["SMTP_USERNAME"], password: ENV["SMTP_PASSWORD"],
    authentication: mode == "local" ? nil : :plain,
    ssl: mode == "tls", enable_starttls_auto: mode == "starttls",
    open_timeout: 5, read_timeout: 30
  }
  ActionMailer::Base.delivery_method = :smtp unless Rails.env.test?
end
