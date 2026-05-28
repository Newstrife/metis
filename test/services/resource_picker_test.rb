require "test_helper"

class ResourcePickerTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "rp-#{SecureRandom.hex(4)}@example.com", password: "password123")
  end

  test "returns nil for an unknown connector type" do
    assert_nil ResourcePicker.for("notion")
    assert_nil ResourcePicker.for(nil)
  end

  test "github picker returns [{value:, label:}] from /user/repos" do
    @user.oauth_grants.create!(provider: "github",
                                access_token: "ghu_live", refresh_token: "rt",
                                expires_at: 1.hour.from_now, scopes: "repo read:user")

    with_http_routes("https://api.github.com/user/repos?per_page=100&sort=updated" =>
                       [ { "full_name" => "chagel/metis" }, { "full_name" => "chagel/themis" } ]) do
      result = ResourcePicker::Github.list(user: @user)
      assert_equal [ { value: "chagel/metis", label: "chagel/metis" },
                     { value: "chagel/themis", label: "chagel/themis" } ], result
    end
  end

  test "github picker returns [] when the user has no grant" do
    assert_equal [], ResourcePicker::Github.list(user: @user)
  end

  test "github picker swallows HTTP errors and returns []" do
    @user.oauth_grants.create!(provider: "github",
                                access_token: "ghu_live", refresh_token: "rt",
                                expires_at: 1.hour.from_now, scopes: "repo")

    with_raising_http do
      assert_equal [], ResourcePicker::Github.list(user: @user)
    end
  end

  test "linear picker returns [{value: id, label: name}] from the GraphQL projects query" do
    @user.oauth_grants.create!(provider: "linear",
                                access_token: "lin_live", refresh_token: "rt",
                                expires_at: 1.hour.from_now, scopes: "read write issues:create")

    body = { "data" => { "projects" => { "nodes" => [
      { "id" => "p1", "name" => "Metis" },
      { "id" => "p2", "name" => "Themis" }
    ] } } }
    with_http_routes("https://api.linear.app/graphql" => body) do
      result = ResourcePicker::Linear.list(user: @user)
      assert_equal [ { value: "p1", label: "Metis" }, { value: "p2", label: "Themis" } ], result
    end
  end

  test "linear picker returns [] when the user lacks the read scope" do
    # Grant has only write/issues:create, missing read — broker.bearer_for must refuse.
    @user.oauth_grants.create!(provider: "linear",
                                access_token: "lin_live", refresh_token: "rt",
                                expires_at: 1.hour.from_now, scopes: "write issues:create")

    assert_equal [], ResourcePicker::Linear.list(user: @user)
  end

  private

  def with_http_routes(routes)
    original = Net::HTTP.instance_method(:request)
    Net::HTTP.define_method(:request) do |req|
      url = "#{use_ssl? ? "https" : "http"}://#{address}#{req.path}"
      payload = routes[url]
      raise "unstubbed URL: #{url}" if payload.nil?

      body = payload.is_a?(String) ? payload : payload.to_json
      response = Net::HTTPOK.new("1.1", "200", "OK")
      response.instance_variable_set(:@body, body)
      response.instance_variable_set(:@read, true)
      response
    end
    yield
  ensure
    Net::HTTP.define_method(:request, original)
  end

  def with_raising_http
    original = Net::HTTP.instance_method(:request)
    Net::HTTP.define_method(:request) { |_| raise SocketError, "blackholed" }
    yield
  ensure
    Net::HTTP.define_method(:request, original)
  end
end
