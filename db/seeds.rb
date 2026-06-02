# Seed data. Idempotent — safe to re-run with `bin/rails db:seed`.

# Local login accounts for development. Skipped in production so a
# known-password account never lands on a live database.
if Rails.env.local?
  # A known superuser login for development — the deployment operator.
  # Superuser is granted explicitly here (and via `rake superuser:grant`
  # in production); there is no automatic "first user is superuser" bootstrap.
  user = User.find_or_initialize_by(email: "admin@metis.local")
  user.password = "password" if user.new_record?
  user.superuser = true
  user.save!
  puts "Dev superuser login: #{user.email} / password"
else
  puts "Skipping development login seeds in #{Rails.env}."
end

# Populate the LLM catalog from pi. Idempotent and curation-preserving;
# a no-op when pi is unreachable — a superuser can Refresh from
# /settings/models.
result = Agent::ModelCatalogSync.call
puts result[:ok] ? "Synced #{result[:models]} models from pi." : "pi unreachable — model catalog left as-is."
