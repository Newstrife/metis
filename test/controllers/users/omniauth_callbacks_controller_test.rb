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

  def mock_google(uid: "g-1", email: "g-#{SecureRandom.hex(4)}@example.com", name: "User")
    OmniAuth.config.mock_auth[:google_oauth2] = OmniAuth::AuthHash.new(
      provider: "google_oauth2",
      uid: uid.to_s,
      info: { email: email, name: name },
      credentials: {
        token: "g-live", refresh_token: "g-rt", expires_at: Time.current.to_i + 3600
      }
    )
    Rails.application.env_config["omniauth.auth"] = OmniAuth.config.mock_auth[:google_oauth2]
    email
  end

  teardown do
    OmniAuth.config.mock_auth[:github] = nil
    OmniAuth.config.mock_auth[:google_oauth2] = nil
    Rails.application.env_config["omniauth.auth"] = nil
  end

  test "first GitHub sign-in creates a user, records the identity, and connects GitHub" do
    email = mock_github(uid: "42", login: "mgc")

    assert_difference("User.count", 1) do
      assert_difference("Identity.count", 1) do
        get user_github_omniauth_callback_path
      end
    end

    identity = Identity.find_by(provider: "github", uid: "42")
    user = identity.user
    assert_equal email, user.email

    connector = user.personal_team.connectors.find_by(catalog_key: "github")
    assert connector
    credential = connector.credential_for(user)
    assert_equal "live", credential.oauth_token["access_token"]
    assert_equal "mgc", credential.external_login
  end

  test "subsequent GitHub sign-in finds the user through the identity" do
    user = User.create!(email: "existing-#{SecureRandom.hex(4)}@example.com", password: "password123")
    user.identities.create!(provider: "github", uid: "7")
    mock_github(uid: "7", login: "mgc", email: "different-#{SecureRandom.hex(4)}@example.com")

    assert_no_difference("User.count") do
      assert_no_difference("Identity.count") do
        get user_github_omniauth_callback_path
      end
    end

    credential = user.personal_team.connectors.find_by(catalog_key: "github").credential_for(user)
    assert_equal "live", credential.oauth_token["access_token"]
  end

  test "first sign-in with no email falls back to a synthetic noreply address" do
    OmniAuth.config.mock_auth[:github] = OmniAuth::AuthHash.new(
      provider: "github", uid: "999",
      info: { email: nil, nickname: "mgc" },
      credentials: { token: "live", refresh_token: "rt", expires_at: Time.current.to_i + 3600 }
    )
    Rails.application.env_config["omniauth.auth"] = OmniAuth.config.mock_auth[:github]

    assert_difference("User.count", 1) do
      get user_github_omniauth_callback_path
    end

    user = Identity.find_by(provider: "github", uid: "999").user
    assert_match(/\A999\+mgc@github\.users\.noreply\.metis\z/, user.email)
  end

  test "next sign-in backfills a real email onto a synthesized-email user" do
    user = User.create!(email: "777+mgc@github.users.noreply.metis",
                        password: "password123")
    user.identities.create!(provider: "github", uid: "777")
    mock_github(uid: "777", login: "mgc", email: "real@example.com")

    get user_github_omniauth_callback_path

    assert_equal "real@example.com", user.reload.email
  end

  test "next sign-in backfills a real email onto GitHub's noreply pseudo-email" do
    user = User.create!(email: "111+mgc@users.noreply.github.com",
                        password: "password123")
    user.identities.create!(provider: "github", uid: "111")
    mock_github(uid: "111", login: "mgc", email: "real@example.com")

    get user_github_omniauth_callback_path

    assert_equal "real@example.com", user.reload.email
  end

  test "backfill refuses to swap one placeholder for another" do
    user = User.create!(email: "222+mgc@users.noreply.github.com",
                        password: "password123")
    user.identities.create!(provider: "github", uid: "222")
    mock_github(uid: "222", login: "mgc", email: "222+other@users.noreply.github.com")

    get user_github_omniauth_callback_path

    assert_equal "222+mgc@users.noreply.github.com", user.reload.email
  end

  test "a missing auth email never downgrades a user who already has a real one" do
    user = User.create!(email: "real-#{SecureRandom.hex(4)}@example.com",
                        password: "password123")
    user.identities.create!(provider: "github", uid: "555")
    original = user.email
    OmniAuth.config.mock_auth[:github] = OmniAuth::AuthHash.new(
      provider: "github", uid: "555",
      info: { email: nil, nickname: "mgc" },
      credentials: { token: "live", refresh_token: "rt", expires_at: Time.current.to_i + 3600 }
    )
    Rails.application.env_config["omniauth.auth"] = OmniAuth.config.mock_auth[:github]

    get user_github_omniauth_callback_path

    assert_equal original, user.reload.email
  end

  test "backfill skips when the real email already belongs to another user" do
    User.create!(email: "taken@example.com", password: "password123")
    synth = User.create!(email: "888+mgc@github.users.noreply.metis", password: "password123")
    synth.identities.create!(provider: "github", uid: "888")
    mock_github(uid: "888", login: "mgc", email: "taken@example.com")

    get user_github_omniauth_callback_path

    assert_equal "888+mgc@github.users.noreply.metis", synth.reload.email
  end

  test "linking a GitHub identity already owned by another user is rejected with a clear alert" do
    other = User.create!(email: "other-#{SecureRandom.hex(4)}@example.com", password: "password123")
    other.identities.create!(provider: "github", uid: "claimed-42")

    me = User.create!(email: "me-#{SecureRandom.hex(4)}@example.com", password: "password123")
    sign_in me
    mock_github(uid: "claimed-42", login: "mgc", email: "me@example.com")

    assert_no_difference("Identity.count") do
      get user_github_omniauth_callback_path
    end

    assert_redirected_to root_path
    assert_match(/already linked/i, flash[:alert])
  end

  test "a connector upsert failure does not block sign-in" do
    OmniauthConnector.singleton_class.send(:alias_method, :__orig_upsert, :upsert)
    OmniauthConnector.define_singleton_method(:upsert) { |*_| raise "boom from connector" }

    begin
      mock_github(uid: "conn-fail-1", login: "mgc", email: "ok@example.com")

      assert_difference("User.count", 1) do
        get user_github_omniauth_callback_path
      end

      user = Identity.find_by(provider: "github", uid: "conn-fail-1").user
      assert_equal "ok@example.com", user.email
      # The connector wasn't created (the upsert raised), but the user
      # got signed in — they can re-trigger the connector flow from the
      # marketplace later.
      assert_nil user.personal_team.connectors.find_by(catalog_key: "github")
      assert_redirected_to root_path
    ensure
      OmniauthConnector.singleton_class.send(:alias_method, :upsert, :__orig_upsert)
    end
  end

  test "a signed-in password user attaches the GitHub identity to their account" do
    user = User.create!(email: "attach-#{SecureRandom.hex(4)}@example.com", password: "password123")
    sign_in user
    mock_github(uid: "13", login: "mgc", email: user.email)

    assert_no_difference("User.count") do
      assert_difference("Identity.count", 1) do
        get user_github_omniauth_callback_path
      end
    end

    assert user.reload.identities.exists?(provider: "github", uid: "13")
  end

  test "first Google sign-in creates the user and connects Gmail" do
    email = mock_google(uid: "g-42")

    assert_difference("User.count", 1) do
      get user_google_oauth2_omniauth_callback_path
    end

    user = Identity.find_by(provider: "google_oauth2", uid: "g-42").user
    assert_equal email, user.email

    gmail = user.personal_team.connectors.find_by(catalog_key: "gmail")
    assert gmail
    credential = gmail.credential_for(user)
    assert_equal "g-live", credential.oauth_token["access_token"]
    assert_equal "g-rt", credential.oauth_token["refresh_token"]
    # Google omniauth has no nickname; external_login must NOT fall
    # back to the user's email — that would leak PII into the connector
    # UI where a handle was expected.
    assert_nil credential.external_login,
               "external_login must not be populated from email for Google"
  end

  test "Google sign-in upserts every catalog connector backed by Google" do
    # Stays true as more google_oauth_provider catalog entries are added:
    # one sign-in covers every Google-backed connector.
    google_apps = ConnectorCatalog.all.select { |a| a.oauth_provider == "google" }
    assert google_apps.any?

    mock_google(uid: "g-7")
    get user_google_oauth2_omniauth_callback_path

    user = Identity.find_by(provider: "google_oauth2", uid: "g-7").user
    keys = user.personal_team.connectors.pluck(:catalog_key)
    google_apps.each { |app| assert_includes keys, app.key }
  end

  test "an existing GitHub user can additionally connect Google" do
    user = User.create!(email: "multi-#{SecureRandom.hex(4)}@example.com", password: "password123")
    user.identities.create!(provider: "github", uid: "100")
    sign_in user

    mock_google(uid: "g-100", email: user.email)
    assert_no_difference("User.count") do
      assert_difference("Identity.count", 1) do
        get user_google_oauth2_omniauth_callback_path
      end
    end

    assert user.reload.identities.exists?(provider: "google_oauth2", uid: "g-100")
    assert user.personal_team.connectors.find_by(catalog_key: "gmail")
  end

  # Strategy-option lock-ins — these guard the operator's
  # config/initializers/devise.rb against silent regressions. Each
  # failed assertion has a concrete user-visible consequence; the
  # message names it so a future refactor can't strip the option by
  # accident. We parse the initializer source rather than introspect
  # Devise.omniauth_configs because the env-gated `config.omniauth`
  # blocks don't register without the OAuth env vars present at boot,
  # which Spring + dotenv-not-loaded-in-test makes unreliable.

  DEVISE_INITIALIZER_SRC = File.read(
    Rails.root.join("config/initializers/devise.rb")
  ).freeze
  private_constant :DEVISE_INITIALIZER_SRC

  def google_omniauth_block
    DEVISE_INITIALIZER_SRC[/config\.omniauth :google_oauth2.*?(?=\n\s*end\n)/m]
  end

  def github_omniauth_block
    DEVISE_INITIALIZER_SRC[/config\.omniauth :github.*?(?=\n\s*end\n)/m]
  end

  test "Google omniauth strategy forces re-consent and offline access" do
    block = google_omniauth_block
    assert block, "no config.omniauth :google_oauth2 block found in devise.rb"

    assert_match(/prompt:\s*["']consent["']/, block,
                 "prompt=consent must stay set. Without it (a) Google won't show the " \
                 "consent screen after a user disconnects and re-connects, so they " \
                 "can't fully re-grant; (b) when this deployment adds new scopes, " \
                 "Google silently no-ops them against the existing grant and the new " \
                 "connector features ship dead.")
    assert_match(/access_type:\s*["']offline["']/, block,
                 "access_type=offline is required to receive a refresh_token; without " \
                 "it Google issues only a 1-hour access token and every refresh fails.")
    assert_match(/userinfo\.email/, block,
                 "userinfo.email is required to populate auth.info.email; without it " \
                 "every Google sign-in falls back to a synthesized noreply address.")
  end

  test "GitHub omniauth strategy requests user:email so the real address comes through" do
    block = github_omniauth_block
    assert block, "no config.omniauth :github block found in devise.rb"

    assert_match(/scope:\s*["']user:email["']/, block,
                 "scope=user:email is what tells omniauth-github to call /user/emails " \
                 "and pick the primary verified address. Drop it and every GitHub user " \
                 "whose profile email is private silently lands as a noreply placeholder.")
  end
end
