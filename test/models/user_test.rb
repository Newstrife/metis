require "test_helper"

class UserTest < ActiveSupport::TestCase
  def create_user
    User.create!(email: "u-#{SecureRandom.hex(4)}@example.com", password: "password123")
  end

  test "a new user gets a personal team owned by them" do
    user = create_user

    assert user.personal_team, "personal team created at signup"
    assert user.personal_team.personal?
    assert_equal "owner", user.memberships.find_by(team: user.personal_team).role
  end

  test "personal_team is the user's team-of-one" do
    user = create_user

    assert_equal [ user ], user.personal_team.members
  end

  test "api_key_for returns the stored key for a provider" do
    user = create_user
    user.api_keys.create!(provider: "anthropic", key: "sk-test")

    assert_equal "sk-test", user.api_key_for("anthropic")
  end

  test "destroying a user destroys its memberships" do
    user = create_user

    assert_difference("Membership.count", -1) { user.destroy }
  end
end
