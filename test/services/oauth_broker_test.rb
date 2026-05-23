require "test_helper"

class OauthBrokerTest < ActiveSupport::TestCase
  def user
    @user ||= User.create!(email: "ob-#{SecureRandom.hex(4)}@example.com", password: "password123")
  end

  def grant(provider: "github", **attrs)
    user.oauth_grants.create!({
      provider: provider, access_token: "at", refresh_token: "rt",
      expires_at: 1.hour.from_now, scopes: "x"
    }.merge(attrs))
  end

  test "returns the stored access token when not near expiry" do
    g = grant(access_token: "live")

    assert_equal "live", OauthBroker.access_token_for(g)
  end

  test "refreshes through the github client when past expiry" do
    g = grant(provider: "github", access_token: "old", refresh_token: "rt0", expires_at: 10.seconds.ago)

    token = with_stub(GithubApp::OauthClient, :refresh, lambda { |_rt|
      { "access_token" => "fresh", "refresh_token" => "rt1", "expires_in" => 3600 }
    }) { OauthBroker.access_token_for(g) }

    assert_equal "fresh", token
    g.reload
    assert_equal "fresh", g.access_token
    assert_equal "rt1", g.refresh_token
  end

  test "refreshes through the google client and preserves the prior refresh token" do
    g = grant(provider: "google", access_token: "old", refresh_token: "rt-google", expires_at: 10.seconds.ago)

    # Google's refresh response omits refresh_token entirely.
    token = with_stub(OauthBroker::Clients::Google, :refresh, lambda { |_rt|
      { "access_token" => "fresh", "expires_in" => 3600, "scope" => "gmail.readonly" }
    }) { OauthBroker.access_token_for(g) }

    assert_equal "fresh", token
    assert_equal "rt-google", g.reload.refresh_token
  end

  test "raises on an unknown provider" do
    g = grant(expires_at: 10.seconds.ago)
    g.update_column(:provider, "bogus") # bypass validation just to exercise the broker

    assert_raises(OauthBroker::Error) { OauthBroker.access_token_for(g) }
  end

  test "raises when expired and there is no refresh token to use" do
    g = grant(access_token: "expired", refresh_token: nil, expires_at: 10.seconds.ago)

    assert_raises(OauthBroker::Error) { OauthBroker.access_token_for(g) }
  end

  test "revoke calls the provider client's revoke method" do
    g = grant(provider: "google")
    called_with = nil

    with_stub(OauthBroker::Clients::Google, :revoke, ->(token) { called_with = token }) do
      OauthBroker.revoke(g)
    end

    assert_equal g.refresh_token, called_with,
                 "revoke should hit the refresh_token (the long-lived one) when available"
  end

  test "revoke swallows provider errors so the local delete can proceed" do
    g = grant(provider: "google")

    with_stub(OauthBroker::Clients::Google, :revoke, ->(_) { raise "network down" }) do
      assert_nothing_raised { OauthBroker.revoke(g) }
    end
  end
end
