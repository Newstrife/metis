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

  test "destroying a user destroys its memberships" do
    user = create_user

    assert_difference("Membership.count", -1) { user.destroy }
  end

  test "placeholder_email? matches the metis synth suffix and GitHub's noreply, anchored" do
    assert User.placeholder_email?("90943+chagel@users.noreply.github.com")
    assert User.placeholder_email?("42+mgc@github.users.noreply.metis")

    # Real addresses that happen to contain the legacy substring must
    # NOT be treated as placeholders — they are real emails users
    # registered with and backfill would silently overwrite them.
    refute User.placeholder_email?("alex@users.noreply.corp.com")
    refute User.placeholder_email?("me+users.noreply.test@gmail.com")
    refute User.placeholder_email?("real@example.com")
  end

  test "backfill_real_email swallows uniqueness collisions so sign-in proceeds" do
    User.create!(email: "taken@example.com", password: "password123")
    placeholder = User.create!(
      email: "888+mgc@users.noreply.github.com", password: "password123"
    )
    auth = mock_auth(email: "taken@example.com")

    assert_nothing_raised { User.backfill_real_email(placeholder, auth) }
    assert_equal "888+mgc@users.noreply.github.com", placeholder.reload.email
  end

  test "backfill_real_email swallows a Devise-invalid email so sign-in proceeds" do
    placeholder = User.create!(
      email: "999+mgc@users.noreply.github.com", password: "password123"
    )
    auth = mock_auth(email: "not-an-email")

    assert_nothing_raised { User.backfill_real_email(placeholder, auth) }
    assert_equal "999+mgc@users.noreply.github.com", placeholder.reload.email
  end

  test "create_identity_for returns the winner's user when the unique index races" do
    # The race: two callbacks for the same (provider, uid) both pass
    # Identity.find_by and both reach create!. Simulate by pre-creating
    # the winner's identity, then asking create_identity_for to attach
    # the same (provider, uid) to a different user. The unique index
    # rejects the insert; the rescue must resolve to the winner.
    winner = User.create!(email: "winner-#{SecureRandom.hex(4)}@example.com", password: "password123")
    winner.identities.create!(provider: "github", uid: "race-1")
    loser  = User.create!(email: "loser-#{SecureRandom.hex(4)}@example.com",  password: "password123")
    auth = mock_auth(provider: "github", uid: "race-1")

    result = User.create_identity_for(loser, auth)

    assert_equal winner, result, "race recovery must return the winner's user"
  end

  private

  def mock_auth(provider: "github", uid: "1", email: nil, nickname: "mgc")
    OmniAuth::AuthHash.new(provider: provider, uid: uid.to_s,
                           info: { email: email, nickname: nickname })
  end
end
