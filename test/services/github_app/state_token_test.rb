require "test_helper"

class GithubApp::StateTokenTest < ActiveSupport::TestCase
  test "verify round-trips a generated token to the user id" do
    token = GithubApp::StateToken.generate(user_id: 42)

    assert_equal 42, GithubApp::StateToken.verify(token)
  end

  test "verify raises on a blank token" do
    assert_raises(GithubApp::StateToken::InvalidError) do
      GithubApp::StateToken.verify(nil)
    end
  end

  test "verify raises on a tampered token" do
    token = GithubApp::StateToken.generate(user_id: 7)

    assert_raises(GithubApp::StateToken::InvalidError) do
      GithubApp::StateToken.verify(token + "garbage")
    end
  end
end
