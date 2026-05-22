require "test_helper"

class MembershipTest < ActiveSupport::TestCase
  def user
    @user ||= User.create!(email: "mb-#{SecureRandom.hex(4)}@example.com", password: "password123")
  end

  def team
    @team ||= Team.create!(name: "Acme")
  end

  test "a membership joins a user and a team with a role" do
    assert Membership.new(user: user, team: team, role: :member).valid?
  end

  test "role is required" do
    assert_not Membership.new(user: user, team: team).valid?
  end

  test "a user joins a team only once" do
    Membership.create!(user: user, team: team, role: :member)

    assert_not Membership.new(user: user, team: team, role: :admin).valid?
  end
end
