require "test_helper"

class Connectors::GithubControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(email: "gh-#{SecureRandom.hex(4)}@example.com", password: "password123")
    sign_in @user
  end

  def with_config(client_id: "client-abc", client_secret: "secret-xyz")
    prev = ENV.to_hash.slice("GITHUB_APP_CLIENT_ID", "GITHUB_APP_CLIENT_SECRET")
    ENV["GITHUB_APP_CLIENT_ID"] = client_id
    ENV["GITHUB_APP_CLIENT_SECRET"] = client_secret
    yield
  ensure
    %w[GITHUB_APP_CLIENT_ID GITHUB_APP_CLIENT_SECRET].each do |k|
      prev.key?(k) ? ENV[k] = prev[k] : ENV.delete(k)
    end
  end

  test "start redirects to GitHub's authorize URL with a signed state" do
    with_config do
      get connector_github_start_path
    end

    assert_response :redirect
    location = URI(@response.headers["Location"])
    assert_equal "github.com", location.host
    assert_equal "/login/oauth/authorize", location.path

    params = URI.decode_www_form(location.query).to_h
    assert_equal "client-abc", params["client_id"]
    assert_equal connector_github_callback_url, params["redirect_uri"]
    assert_equal @user.id, GithubApp::StateToken.verify(params["state"])
  end

  test "start refuses without GitHub OAuth env vars" do
    get connector_github_start_path

    assert_redirected_to connectors_path
    assert_match(/not configured/i, flash[:alert])
  end

  test "callback exchanges the code and stores a per-user oauth credential" do
    state = GithubApp::StateToken.generate(user_id: @user.id)
    response_body = {
      "access_token" => "live-token", "refresh_token" => "rt-1",
      "expires_in" => 28_800, "scope" => "repo"
    }

    with_config do
      with_stub(GithubApp::OauthClient, :exchange_code, ->(_code, redirect_uri:) { response_body }) do
        with_stub(GithubApp::UserInfo, :fetch, ->(_token) { { "login" => "mgc", "id" => 42 } }) do
          assert_difference([ "Connector.count", "ConnectorCredential.count" ], 1) do
            get connector_github_callback_path, params: { code: "abc", state: state }
          end
        end
      end
    end

    connector = @user.personal_team.connectors.find_by(catalog_key: "github")
    credential = connector.credential_for(@user)
    assert_equal @user, credential.user
    assert_equal "live-token", credential.oauth_token["access_token"]
    assert_equal "mgc", credential.external_login
    assert_redirected_to edit_connector_path(connector)
  end

  test "callback still succeeds when the /user fetch fails" do
    state = GithubApp::StateToken.generate(user_id: @user.id)
    response_body = {
      "access_token" => "live-token", "refresh_token" => "rt-1", "expires_in" => 28_800
    }

    with_config do
      with_stub(GithubApp::OauthClient, :exchange_code, ->(_code, redirect_uri:) { response_body }) do
        with_stub(GithubApp::UserInfo, :fetch,
                  ->(_token) { raise GithubApp::TokenService::Error, "boom" }) do
          assert_difference("ConnectorCredential.count", 1) do
            get connector_github_callback_path, params: { code: "abc", state: state }
          end
        end
      end
    end

    credential = @user.personal_team.connectors.find_by(catalog_key: "github").credential_for(@user)
    assert_equal "live-token", credential.oauth_token["access_token"]
    assert_nil credential.external_login
  end

  test "callback rejects a tampered state" do
    get connector_github_callback_path, params: { code: "abc", state: "garbage" }

    assert_redirected_to connectors_path
    assert_match(/verify/i, flash[:alert])
    assert_equal 0, Connector.count
  end

  test "callback rejects a state signed for a different user" do
    other = User.create!(email: "other-#{SecureRandom.hex(4)}@example.com", password: "password123")
    state = GithubApp::StateToken.generate(user_id: other.id)

    get connector_github_callback_path, params: { code: "abc", state: state }

    assert_redirected_to connectors_path
    assert_equal 0, ConnectorCredential.count
  end

  test "callback rejects a missing code" do
    state = GithubApp::StateToken.generate(user_id: @user.id)

    get connector_github_callback_path, params: { state: state }

    assert_redirected_to connectors_path
    assert_match(/not completed/i, flash[:alert])
  end

  test "callback redirects with an alert when the token exchange fails" do
    state = GithubApp::StateToken.generate(user_id: @user.id)

    with_config do
      with_stub(GithubApp::OauthClient, :exchange_code,
                ->(_code, **_) { raise GithubApp::TokenService::Error, "boom" }) do
        get connector_github_callback_path, params: { code: "abc", state: state }
      end
    end

    assert_redirected_to connectors_path
    assert_match(/failed/i, flash[:alert])
  end
end
