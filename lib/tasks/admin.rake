namespace :admin do
  desc "Grant admin to a user: rake 'admin:grant[user@example.com]'"
  task :grant, [ :email ] => :environment do |_task, args|
    user = User.find_by!(email: args.fetch(:email))
    user.update!(admin: true)
    puts "#{user.email} is now an admin."
  end

  desc "Revoke admin from a user: rake 'admin:revoke[user@example.com]'"
  task :revoke, [ :email ] => :environment do |_task, args|
    user = User.find_by!(email: args.fetch(:email))
    user.update!(admin: false)
    puts "#{user.email} is no longer an admin."
  end
end
