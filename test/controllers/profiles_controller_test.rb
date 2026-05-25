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
    patch profile_path, params: { user: {
      display_name: "Mike",
      timezone: "America/Los_Angeles",
      language: "en",
      preferred_model: model_id
    } }
    assert_redirected_to profile_path

    @user.reload
    assert_equal "Mike", @user.display_name
    assert_equal "America/Los_Angeles", @user.timezone
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

  test "detect_timezone sets the user's timezone when blank" do
    assert_nil @user.timezone
    post detect_timezone_profile_path, params: { timezone: "Europe/Berlin" }
    assert_response :no_content
    assert_equal "Europe/Berlin", @user.reload.timezone
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
