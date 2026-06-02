namespace :superuser do
  desc "Grant superuser to a user: rake 'superuser:grant[user@example.com]'"
  task :grant, [ :email ] => :environment do |_task, args|
    user = User.find_by!(email: args.fetch(:email))
    user.update!(superuser: true)
    puts "#{user.email} is now a superuser."
  end

  desc "Revoke superuser from a user: rake 'superuser:revoke[user@example.com]'"
  task :revoke, [ :email ] => :environment do |_task, args|
    user = User.find_by!(email: args.fetch(:email))
    user.update!(superuser: false)
    puts "#{user.email} is no longer a superuser."
  end
end
