require "test_helper"

class GithubApp::TokenServiceTest < ActiveSupport::TestCase
  def credential
    @credential ||= begin
      team = Team.create!(name: "Acme")
      connector = team.connectors.create!(
        name: "github", transport: :http, definition: { "url" => "https://mcp.example/" },
        catalog_key: "github"
      )
      connector.connector_credentials.create!(user: nil)
    end
  end

  def stub_refresh(response, &block)
    with_stub(GithubApp::OauthClient, :refresh, ->(_token) { response }, &block)
  end

  test "returns the stored access token when not near expiry" do
    credential.assign_oauth_token!({
      "access_token" => "live", "refresh_token" => "rt",
      "expires_in" => 3600, "scope" => "repo"
    })

    assert_equal "live", GithubApp::TokenService.access_token_for(credential)
  end

  test "refreshes when the access token is past expiry" do
    credential.assign_oauth_token!({
      "access_token" => "expired", "refresh_token" => "rt0", "expires_in" => -10
    })

    new_token = stub_refresh({
      "access_token" => "fresh", "refresh_token" => "rt1", "expires_in" => 3600
    }) do
      GithubApp::TokenService.access_token_for(credential)
    end

    assert_equal "fresh", new_token
    assert_equal "fresh", credential.reload.oauth_token["access_token"]
    assert_equal "rt1", credential.oauth_token["refresh_token"]
  end

  test "raises when the credential has no oauth bundle" do
    assert_raises(GithubApp::TokenService::Error) do
      GithubApp::TokenService.access_token_for(credential)
    end
  end

  test "raises when there is no refresh token to use" do
    credential.assign_oauth_token!({ "access_token" => "expired", "expires_in" => -10 })

    assert_raises(GithubApp::TokenService::Error) do
      GithubApp::TokenService.access_token_for(credential)
    end
  end
end
