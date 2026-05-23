require "test_helper"

class DeviseOauthButtonsTest < ActionDispatch::IntegrationTest
  test "sign-in hides OAuth buttons when providers are not configured" do
    with_stub(GithubApp::Config, :configured?, -> { false }) do
      with_stub(GoogleApp::Config, :configured?, -> { false }) do
        get new_user_session_path
        assert_response :success

        assert_select "button", text: /Sign in with GitHub/, count: 0
        assert_select "button", text: /Sign in with Google/, count: 0
        assert_select ".auth-or", count: 0
      end
    end
  end

  test "registration hides OAuth buttons when providers are not configured" do
    with_stub(GithubApp::Config, :configured?, -> { false }) do
      with_stub(GoogleApp::Config, :configured?, -> { false }) do
        get new_user_registration_path
        assert_response :success

        assert_select "button", text: /Sign up with GitHub/, count: 0
        assert_select "button", text: /Sign up with Google/, count: 0
        assert_select ".auth-or", count: 0
      end
    end
  end

  test "sign-in renders only configured OAuth providers" do
    with_stub(GithubApp::Config, :configured?, -> { false }) do
      with_stub(GoogleApp::Config, :configured?, -> { true }) do
        get new_user_session_path
        assert_response :success

        assert_select "button", text: /Sign in with GitHub/, count: 0
        assert_select "button", text: /Sign in with Google/, count: 1
      end
    end
  end
end
