require "test_helper"

class GithubApp::ConfigTest < ActiveSupport::TestCase
  def with_env(env)
    previous = ENV.to_hash.slice(*env.keys)
    env.each { |k, v| ENV[k] = v }
    yield
  ensure
    env.each_key { |k| previous.key?(k) ? ENV[k] = previous[k] : ENV.delete(k) }
  end

  test "client_id and client_secret read from the environment" do
    with_env("GITHUB_APP_CLIENT_ID" => "client-abc", "GITHUB_APP_CLIENT_SECRET" => "shh") do
      assert_equal "client-abc", GithubApp::Config.client_id
      assert_equal "shh", GithubApp::Config.client_secret
    end
  end

  test "configured? is true when both env vars are set" do
    with_env("GITHUB_APP_CLIENT_ID" => "x", "GITHUB_APP_CLIENT_SECRET" => "y") do
      assert_predicate GithubApp::Config, :configured?
    end
  end

  test "configured? is false when either env var is missing" do
    with_env("GITHUB_APP_CLIENT_ID" => "x", "GITHUB_APP_CLIENT_SECRET" => "") do
      assert_not_predicate GithubApp::Config, :configured?
    end
    with_env("GITHUB_APP_CLIENT_ID" => "", "GITHUB_APP_CLIENT_SECRET" => "y") do
      assert_not_predicate GithubApp::Config, :configured?
    end
  end
end
