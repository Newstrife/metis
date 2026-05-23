require "test_helper"

class OauthBrokerTest < ActiveSupport::TestCase
  def credential(catalog_key: "github")
    team = Team.create!(name: "Acme")
    connector = team.connectors.create!(
      name: catalog_key, transport: :http, definition: { "url" => "https://mcp.example/" },
      catalog_key: catalog_key
    )
    connector.connector_credentials.create!(user: nil)
  end

  test "returns the stored access token when not near expiry" do
    cred = credential
    cred.assign_oauth_token!({
      "access_token" => "live", "refresh_token" => "rt",
      "expires_in" => 3600, "scope" => "repo"
    })

    assert_equal "live", OauthBroker.access_token_for(cred, provider: "github")
  end

  test "refreshes through the github client when past expiry" do
    cred = credential
    cred.assign_oauth_token!({ "access_token" => "old", "refresh_token" => "rt0", "expires_in" => -10 })

    token = with_stub(GithubApp::OauthClient, :refresh, lambda { |_rt|
      { "access_token" => "fresh", "refresh_token" => "rt1", "expires_in" => 3600 }
    }) { OauthBroker.access_token_for(cred, provider: "github") }

    assert_equal "fresh", token
    assert_equal "fresh", cred.reload.oauth_token["access_token"]
    assert_equal "rt1", cred.oauth_token["refresh_token"]
  end

  test "refreshes through the google client and preserves the prior refresh token" do
    cred = credential(catalog_key: "gmail")
    cred.assign_oauth_token!({ "access_token" => "old", "refresh_token" => "rt-google", "expires_in" => -10 })

    # Google's refresh response omits refresh_token entirely.
    token = with_stub(OauthBroker::Clients::Google, :refresh, lambda { |_rt|
      { "access_token" => "fresh", "expires_in" => 3600, "scope" => "gmail.readonly" }
    }) { OauthBroker.access_token_for(cred, provider: "google") }

    assert_equal "fresh", token
    assert_equal "rt-google", cred.reload.oauth_token["refresh_token"]
  end

  test "raises on an unknown provider" do
    cred = credential
    cred.assign_oauth_token!({ "access_token" => "x", "refresh_token" => "y", "expires_in" => -10 })

    assert_raises(OauthBroker::Error) do
      OauthBroker.access_token_for(cred, provider: "bogus")
    end
  end

  test "raises when the credential has no oauth bundle" do
    assert_raises(OauthBroker::Error) do
      OauthBroker.access_token_for(credential, provider: "github")
    end
  end

  test "raises when expired and there is no refresh token to use" do
    cred = credential
    cred.assign_oauth_token!({ "access_token" => "expired", "expires_in" => -10 })

    assert_raises(OauthBroker::Error) do
      OauthBroker.access_token_for(cred, provider: "github")
    end
  end
end
