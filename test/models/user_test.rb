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

  test "display_label falls back to email when display_name is blank" do
    user = create_user
    assert_equal user.email, user.display_label

    user.update!(display_name: "Mike Chen")
    assert_equal "Mike Chen", user.display_label
  end

  test "initials are derived from display name when set, email otherwise" do
    user = User.new(email: "alex.kim@example.com")
    assert_equal "AK", user.initials

    user.display_name = "Mike Chen"
    assert_equal "MC", user.initials

    user.display_name = "q"
    assert_equal "Q", user.initials
  end

  test "profile_update context requires a display name" do
    user = create_user
    user.display_name = ""
    refute user.valid?(:profile_update)
    assert_includes user.errors[:display_name], "can't be blank"
  end

  test "normalizes profile string fields: trims whitespace, blanks become nil" do
    user = User.create!(
      email: "u-#{SecureRandom.hex(4)}@example.com", password: "password123",
      display_name: "  Mike  ", timezone: "  Tokyo  ",
      language: "  en  ", preferred_model: "  "
    )
    assert_equal "Mike", user.display_name
    assert_equal "Tokyo", user.timezone
    assert_equal "en", user.language
    assert_nil user.preferred_model
  end

  test "timezone must be a known Rails-friendly zone name" do
    user = create_user
    user.timezone = "Mars/Olympus"
    refute user.valid?

    # The validator is `inclusion: ActiveSupport::TimeZone.all.map(&:name)`
    # — i.e. the curated Rails-friendly names rendered by
    # `time_zone_select`. IANA names like "America/Los_Angeles" arrive
    # only via ProfilesController#detect_timezone, which canonicalizes
    # before persisting.
    user.timezone = "Pacific Time (US & Canada)"
    assert user.valid?
  end

  test "preferred_model must be in the catalog" do
    user = create_user
    user.preferred_model = "no-such-model"
    refute user.valid?

    user.preferred_model = Agent::Catalog::PROVIDERS.first[:models].first[:id]
    assert user.valid?
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

  test "from_omniauth race-recovers to the winner's user without leaving an orphan User" do
    # Simulate the late half of the concurrent-first-sign-in race: the
    # winner has already committed an Identity for (provider, uid). The
    # loser's from_omniauth call now: misses Identity.find_by (the test
    # forces the timing by pre-creating the identity), enters the
    # transaction, builds a new User with a different email, hits the
    # unique index on identities.uid, rolls back, retries — second
    # pass finds the winner's identity and returns the winner.
    winner = User.create!(email: "winner-#{SecureRandom.hex(4)}@example.com", password: "password123")
    winner.identities.create!(provider: "github", uid: "race-1")
    auth = mock_auth(provider: "github", uid: "race-1", email: "loser-#{SecureRandom.hex(4)}@example.com")

    result = nil
    assert_no_difference("User.count", "the loser's User must not be persisted") do
      assert_no_difference("Team.count", "the loser's personal Team must not be persisted") do
        result = User.from_omniauth(auth)
      end
    end

    assert_equal winner, result, "race recovery must return the winner's user"
  end

  private

  def mock_auth(provider: "github", uid: "1", email: nil, nickname: "mgc")
    OmniAuth::AuthHash.new(provider: provider, uid: uid.to_s,
                           info: { email: email, nickname: nickname })
  end
end
