require "test_helper"

class OauthGrantTest < ActiveSupport::TestCase
  # A fresh user per call — tests that build several grants don't
  # want to share a user across calls (uniqueness: {scope: :user_id}).
  def grant(attrs = {})
    user = User.create!(email: "g-#{SecureRandom.hex(4)}@example.com", password: "password123")
    user.oauth_grants.create!({
      provider: "google", access_token: "at", refresh_token: "rt",
      expires_at: 1.hour.from_now, scopes: "email profile"
    }.merge(attrs))
  end

  test "tokens are encrypted at rest" do
    g = grant(access_token: "super-secret-access", refresh_token: "super-secret-refresh")
    row = OauthGrant.connection.select_one(
      OauthGrant.where(id: g.id).select(:access_token, :refresh_token).to_sql
    )

    assert_not_includes row["access_token"].to_s, "super-secret-access"
    assert_not_includes row["refresh_token"].to_s, "super-secret-refresh"
  end

  test "one grant per (user, provider)" do
    g = grant
    dup = g.user.oauth_grants.build(provider: "google", access_token: "at2")

    assert_not dup.valid?, "second google grant for same user must fail uniqueness"
  end

  test "fresh? is true while expires_at is more than the leeway away" do
    assert grant(expires_at: 1.hour.from_now).fresh?
    refute grant(expires_at: 30.seconds.from_now).fresh?, "within 60s leeway is stale"
    refute grant(expires_at: 1.hour.ago).fresh?
    refute grant(expires_at: nil).fresh?
  end

  test "scope_set splits on commas or whitespace" do
    assert_equal %w[a b c], grant(scopes: "a b c").scope_set
    assert_equal %w[a b c], grant(scopes: "a,b,c").scope_set
    assert_equal %w[a b c], grant(scopes: " a , b   c ").scope_set
  end

  test "covers? checks every required scope is present" do
    g = grant(scopes: "email profile gmail.readonly")

    assert g.covers?([ "email" ])
    assert g.covers?([ "email", "gmail.readonly" ])
    refute g.covers?([ "gmail.compose" ])
    refute g.covers?([ "email", "gmail.compose" ])
    assert g.covers?([])
  end

  test "absorb! adopts the response's scope set authoritatively and refreshes tokens + expiry" do
    g = grant(scopes: "email profile", access_token: "old", expires_at: 1.hour.from_now)
    response = {
      "access_token" => "new", "refresh_token" => "new-rt",
      "expires_in" => 3600, "scope" => "profile gmail.readonly"
    }

    g.absorb!(response, at: Time.utc(2026, 5, 23, 12))

    g.reload
    assert_equal "new", g.access_token
    assert_equal "new-rt", g.refresh_token
    assert_equal Time.utc(2026, 5, 23, 13), g.expires_at
    assert_equal %w[profile gmail.readonly], g.scope_set,
                 "response scope replaces the prior set, not unions with it"
  end

  test "absorb! preserves prior refresh_token when the response omits it" do
    g = grant(refresh_token: "long-lived-rt")
    g.absorb!({ "access_token" => "new", "expires_in" => 3600 })

    assert_equal "long-lived-rt", g.reload.refresh_token
  end

  test "absorb! preserves prior scope set when the response omits scope" do
    # Google's refresh response carries no `scope` when unchanged.
    g = grant(scopes: "email profile gmail.readonly")
    g.absorb!({ "access_token" => "new", "expires_in" => 3600 })

    assert_equal %w[email profile gmail.readonly], g.reload.scope_set
  end

  test "absorb! narrows scope_set when the user reduces consent — covers? must reflect Google's truth" do
    g = grant(scopes: "email profile gmail.readonly gmail.compose")
    g.absorb!({ "access_token" => "new", "expires_in" => 3600,
                "scope" => "email profile gmail.readonly" })

    g.reload
    refute g.covers?([ "gmail.compose" ])
    assert g.covers?([ "gmail.readonly" ])
  end

  test "absorb! defaults expires_at to ~1h from `at` when neither prior nor response carry one" do
    # Backfilled grant whose original ConnectorCredential bundle had a
    # bad/missing expires_at, and a refresh response that omits expires_in.
    # Without the default, expires_at stays nil → fresh? always false →
    # OauthBroker refreshes on every chat turn (refresh storm).
    g = grant(expires_at: nil)
    g.absorb!({ "access_token" => "new" }, at: Time.utc(2026, 5, 23, 12))

    assert_equal Time.utc(2026, 5, 23, 13), g.reload.expires_at,
                 "absorb! must fill in a sane default expiry so fresh? doesn't lie forever"
  end

  test "remove_scopes! deletes scopes from the grant" do
    g = grant(scopes: "email profile gmail.readonly gmail.compose")

    g.remove_scopes!([ "gmail.readonly", "gmail.compose" ])

    assert_equal %w[email profile], g.reload.scope_set
  end
end
