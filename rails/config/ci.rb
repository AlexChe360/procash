CI.run do
  step "Load application", "bin/rails zeitwerk:check"
  step "Tests", "bin/rails test"
end
