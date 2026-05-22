class AddTeamToConversations < ActiveRecord::Migration[8.1]
  # Existing conversations predate teams. Backfill: give every user a
  # personal team and assign their conversations to it. New users get a
  # personal team from User's after_create hook; new conversations
  # default their team in a before_validation. Metis is pre-release, so
  # this one-time fixup only ever runs on a dev database with prior data.
  def up
    add_reference :conversations, :team, foreign_key: true

    User.reset_column_information
    User.find_each do |user|
      team = Team.create!(name: user.email, personal: true)
      Membership.create!(user: user, team: team, role: :owner)
      user.conversations.update_all(team_id: team.id)
    end

    change_column_null :conversations, :team_id, false
  end

  def down
    remove_reference :conversations, :team
  end
end
