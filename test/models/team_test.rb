require "test_helper"

class TeamTest < ActiveSupport::TestCase
  def make_user
    User.create!(email: "tm-#{SecureRandom.hex(4)}@example.com", password: "password123")
  end

  test "a team requires a name" do
    assert_not Team.new.valid?
    assert Team.new(name: "Acme").valid?
  end

  test "members are the users joined through memberships" do
    team = Team.create!(name: "Acme")
    user = make_user
    team.memberships.create!(user: user, role: :member)

    assert_equal [ user ], team.members
  end

  test "destroying a team destroys its memberships" do
    team = Team.create!(name: "Acme")
    team.memberships.create!(user: make_user, role: :member)

    assert_difference("Membership.count", -1) { team.destroy }
  end
end
