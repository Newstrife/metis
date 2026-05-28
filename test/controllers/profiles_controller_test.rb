require "test_helper"

class ProfilesControllerTest < ActionDispatch::IntegrationTest
  include Devise::Test::IntegrationHelpers

  setup do
    @user = User.create!(email: "p-#{SecureRandom.hex(4)}@example.com", password: "password123")
    sign_in @user
  end

  test "show renders the profile page" do
    get profile_path
    assert_response :success
    assert_select "form.profile-form"
  end

  test "update saves valid preferences" do
    model_id = Agent::Catalog::PROVIDERS.first[:models].first[:id]
    # Submit a Rails-friendly zone name — the form's `time_zone_select`
    # only renders Rails-friendly names, so that's what the inclusion
    # validator accepts. (IANA names like "America/Los_Angeles" arrive
    # only via #detect_timezone, which normalizes through TimeZone#name
    # before persisting.)
    patch profile_path, params: { user: {
      display_name: "Mike",
      timezone: "Pacific Time (US & Canada)",
      language: "en",
      preferred_model: model_id
    } }
    assert_redirected_to profile_path

    @user.reload
    assert_equal "Mike", @user.display_name
    assert_equal "Pacific Time (US & Canada)", @user.timezone
    assert_equal "en", @user.language
    assert_equal model_id, @user.preferred_model
  end

  test "update rejects blank display name" do
    patch profile_path, params: { user: { display_name: "" } }
    assert_response :unprocessable_entity
    assert_nil @user.reload.display_name
  end

  test "update rejects an unknown timezone" do
    patch profile_path, params: { user: { display_name: "M", timezone: "Mars/Olympus" } }
    assert_response :unprocessable_entity
  end

  test "update rejects an out-of-catalog model" do
    patch profile_path, params: { user: { display_name: "M", preferred_model: "no-such-model" } }
    assert_response :unprocessable_entity
  end

  test "update via turbo stream re-renders the form" do
    model_id = Agent::Catalog::PROVIDERS.first[:models].first[:id]
    patch profile_path,
      params: { user: { display_name: "Mike", preferred_model: model_id } },
      headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_match "turbo-stream", response.body
    assert_match "profile_form", response.body
  end

  test "update saves personalization fields" do
    patch profile_path, params: { user: {
      display_name: "Mike",
      theme: "dark",
      about_you: "Founder. Hates emoji.",
      custom_instructions: "Be terse. No filler."
    } }
    assert_redirected_to profile_path

    @user.reload
    assert_equal "dark", @user.theme
    assert_equal "Founder. Hates emoji.", @user.about_you
    assert_equal "Be terse. No filler.", @user.custom_instructions
  end

  test "update rejects an unknown theme" do
    patch profile_path, params: { user: { display_name: "M", theme: "neon" } }
    assert_response :unprocessable_entity
  end

  test "update_theme persists a valid theme" do
    patch update_theme_profile_path, params: { theme: "dark" }
    assert_response :no_content
    assert_equal "dark", @user.reload.theme
  end

  test "update_theme silently ignores junk values" do
    @user.update!(theme: "light")
    patch update_theme_profile_path, params: { theme: "neon" }
    assert_response :no_content
    assert_equal "light", @user.reload.theme
  end

  # IANA→Rails-friendly normalization: the browser sends "Europe/Berlin"
  # but the model validation and time_zone_select only know "Berlin".
  # Without normalization the selector silently shows blank after
  # auto-detect AND the next profile save validation-fails on a field
  # the user didn't touch.
  test "detect_timezone canonicalizes IANA names to Rails-friendly names" do
    assert_nil @user.timezone
    post detect_timezone_profile_path, params: { timezone: "Europe/Berlin" }
    assert_response :no_content
    assert_equal "Berlin", @user.reload.timezone
  end

  test "detect_timezone accepts a Rails-friendly name directly" do
    assert_nil @user.timezone
    post detect_timezone_profile_path, params: { timezone: "Tokyo" }
    assert_response :no_content
    assert_equal "Tokyo", @user.reload.timezone
  end

  test "detect_timezone is a no-op once a timezone is set" do
    @user.update!(timezone: "UTC")
    post detect_timezone_profile_path, params: { timezone: "Europe/Berlin" }
    assert_response :no_content
    assert_equal "UTC", @user.reload.timezone
  end

  test "detect_timezone ignores junk values" do
    post detect_timezone_profile_path, params: { timezone: "Mars/Olympus" }
    assert_response :no_content
    assert_nil @user.reload.timezone
  end

  test "new conversation uses the user's preferred model when none picked" do
    model_id = Agent::Catalog::PROVIDERS.first[:models].first[:id]
    @user.update!(preferred_model: model_id)

    assert_difference("Conversation.count", 1) do
      post conversations_path, params: { content: "hello" }
    end

    conversation = Conversation.order(:id).last
    assert_equal model_id, conversation.settings["model"]
  end
end
