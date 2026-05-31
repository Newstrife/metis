# Seed data. Idempotent — safe to re-run with `bin/rails db:seed`.

# Local login accounts for development. Skipped in production so a
# known-password account never lands on a live database.
if Rails.env.local?
  accounts = [
    { email: "admin@metis.local", password: "password" }
  ]

  accounts.each do |attrs|
    user = User.find_or_initialize_by(email: attrs[:email])
    if user.new_record?
      user.password = attrs[:password]
      user.save!
      puts "Created login: #{user.email} (password: #{attrs[:password]})"
    else
      puts "Login already exists: #{user.email}"
    end
  end
else
  puts "Skipping development login seeds in #{Rails.env}."
end

# Populate the LLM catalog from pi. Idempotent and curation-preserving;
# a no-op when pi is unreachable — an admin can Refresh from
# /settings/models.
result = Agent::ModelCatalogSync.call
puts result[:ok] ? "Synced #{result[:models]} models from pi." : "pi unreachable — model catalog left as-is."
