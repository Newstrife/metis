require "test_helper"

class Users::OmniauthCallbacksControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  def mock_github(uid: "1", login: "mgc", email: "omni-#{SecureRandom.hex(4)}@example.com")
    OmniAuth.config.mock_auth[:github] = OmniAuth::AuthHash.new(
      provider: "github",
      uid: uid.to_s,
      info: { email: email, nickname: login },
      credentials: {
        token: "live", refresh_token: "rt", expires_at: Time.current.to_i + 3600
      }
    )
    Rails.application.env_config["omniauth.auth"] = OmniAuth.config.mock_auth[:github]
    email
  end

  teardown do
    OmniAuth.config.mock_auth[:github] = nil
    Rails.application.env_config["omniauth.auth"] = nil
  end

  test "first sign-in creates a user, signs them in, and connects GitHub" do
    email = mock_github(uid: "42", login: "mgc")

    assert_difference("User.count", 1) do
      get user_github_omniauth_callback_path
    end

    user = User.find_by(provider: "github", uid: "42")
    assert user
    assert_equal email, user.email

    connector = user.personal_team.connectors.find_by(catalog_key: "github")
    assert connector
    credential = connector.credential_for(user)
    assert_equal "live", credential.oauth_token["access_token"]
    assert_equal "mgc", credential.external_login
  end

  test "subsequent sign-in finds the existing GitHub user" do
    user = User.create!(email: "existing-#{SecureRandom.hex(4)}@example.com",
                        password: "password123", provider: "github", uid: "7")
    mock_github(uid: "7", login: "mgc", email: user.email)

    assert_no_difference("User.count") do
      get user_github_omniauth_callback_path
    end

    credential = user.personal_team.connectors.find_by(catalog_key: "github").credential_for(user)
    assert_equal "live", credential.oauth_token["access_token"]
  end

  test "first sign-in with no email falls back to GitHub's noreply address" do
    OmniAuth.config.mock_auth[:github] = OmniAuth::AuthHash.new(
      provider: "github", uid: "999",
      info: { email: nil, nickname: "mgc" },
      credentials: { token: "live", refresh_token: "rt", expires_at: Time.current.to_i + 3600 }
    )
    Rails.application.env_config["omniauth.auth"] = OmniAuth.config.mock_auth[:github]

    assert_difference("User.count", 1) do
      get user_github_omniauth_callback_path
    end

    user = User.find_by(provider: "github", uid: "999")
    assert_equal "999+mgc@users.noreply.github.com", user.email
  end

  test "a signed-in password user attaches the GitHub identity to their account" do
    user = User.create!(email: "attach-#{SecureRandom.hex(4)}@example.com", password: "password123")
    sign_in user
    mock_github(uid: "13", login: "mgc", email: user.email)

    assert_no_difference("User.count") do
      get user_github_omniauth_callback_path
    end

    assert_equal "github", user.reload.provider
    assert_equal "13", user.uid
  end
end
