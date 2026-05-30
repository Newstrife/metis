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

  PEM = "-----BEGIN RSA PRIVATE KEY-----\nMIIE\n-----END RSA PRIVATE KEY-----\n".freeze

  test "private_key decodes a base64-encoded PEM (the canonical form)" do
    with_env("GITHUB_APP_PRIVATE_KEY" => Base64.strict_encode64(PEM)) do
      assert_equal PEM, GithubApp::Config.private_key
    end
  end

  test "private_key accepts a raw PEM unchanged" do
    with_env("GITHUB_APP_PRIVATE_KEY" => PEM) do
      assert_equal PEM, GithubApp::Config.private_key
    end
  end

  test "private_key unescapes a \\n-escaped PEM" do
    with_env("GITHUB_APP_PRIVATE_KEY" => PEM.gsub("\n", '\n')) do
      assert_equal PEM, GithubApp::Config.private_key
    end
  end

  test "app_auth_configured? is true only with both id and private key" do
    with_env("GITHUB_APP_ID" => "123", "GITHUB_APP_PRIVATE_KEY" => "pem") do
      assert_predicate GithubApp::Config, :app_auth_configured?
    end
    with_env("GITHUB_APP_ID" => "123", "GITHUB_APP_PRIVATE_KEY" => "") do
      assert_not_predicate GithubApp::Config, :app_auth_configured?
    end
    with_env("GITHUB_APP_ID" => "", "GITHUB_APP_PRIVATE_KEY" => "pem") do
      assert_not_predicate GithubApp::Config, :app_auth_configured?
    end
  end
end
