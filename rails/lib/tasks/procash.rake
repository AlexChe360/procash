namespace :procash do
  desc "Run durable onboarding outbox worker (no Redis required)"
  task mail_worker: :environment do
    loop do
      processed = DeliverOutboxJob.perform_now("requests")
      processed = DeliverOutboxJob.perform_now("invitations") || processed
      sleep 2 unless processed
    end
  end

  desc "Create the first administrator with an interactive password"
  task create_admin: :environment do
    require "io/console"
    abort "Administrator already exists" if User.where(platform_role: "admin").exists?
    print "Email: "
    email = STDIN.gets.to_s.strip.downcase
    abort "Invalid email" unless email.match?(/\A[^\s@]+@[^\s@]+\z/) && email.bytesize <= 254
    password = STDIN.getpass("Password: ")
    abort "Passwords differ" unless password == STDIN.getpass("Confirm password: ")
    hash = Auth::Password.hash(password)
    User.transaction do
      User.connection.execute("LOCK TABLE users IN SHARE ROW EXCLUSIVE MODE")
      abort "Administrator already exists" if User.where(platform_role: "admin").exists?
      User.create!(email: email, password_hash: hash, platform_role: "admin", email_verified_at: Time.current)
    end
    puts "Administrator created"
  end
end
