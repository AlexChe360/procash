# Password comes only through stdin, not process arguments or log output.
password = STDIN.read.delete_suffix("\n")
abort "Configure ADMIN_BOOTSTRAP_PASSWORD repository secret (12–128 bytes)" unless (12..128).cover?(password.bytesize) && !password.match?(/[\r\n]/)
email = "info@procash.kz"
User.transaction do
  User.connection.execute("LOCK TABLE users IN SHARE ROW EXCLUSIVE MODE")
  if User.exists?
    abort "Existing database has no administrator; manual review required" unless User.where(platform_role: "admin").exists?
    puts "Existing administrator preserved"
  else
    User.create!(email: email, password_hash: Auth::Password.hash(password), platform_role: "admin", email_verified_at: Time.current, display_name: "Администратор")
    puts "Initial administrator created (password not displayed)"
  end
end
