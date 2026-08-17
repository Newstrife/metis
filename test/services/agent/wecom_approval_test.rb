require "test_helper"

class Agent::WecomApprovalTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "wa-#{SecureRandom.hex(4)}@example.com", password: "password123",
                         wecom_userid: "boss")
    @conversation = @user.conversations.create!(team: @user.personal_team,
      title: "企业微信群 · abc", settings: { "wecom_chatid" => "wrGroupX" })
    @prev_token = ENV["WECOM_BRIDGE_TOKEN"]
    ENV["WECOM_BRIDGE_TOKEN"] = "test-token"
  end

  teardown do
    ENV["WECOM_BRIDGE_TOKEN"] = @prev_token
  end

  test "pushes the approval card to the group and the operator's DM" do
    posted = []
    poster = ->(payload) { posted << payload and true }
    result = Agent::WecomApproval.notify(@conversation,
      { "summary" => "删除旧备份目录", "requester" => "gaoyuming" }, poster: poster)

    assert result[:ok]
    assert_equal %w[group operator_dm], result[:delivered_to]
    assert_equal "wrGroupX", posted[0][:chatid]
    assert_equal "boss", posted[1][:to_userid]
    assert_includes posted[0][:content], "删除旧备份目录"
    assert_includes posted[0][:content], "gaoyuming"
  end

  test "dm-only conversation (no chatid) only pings the operator" do
    dm = @user.conversations.create!(team: @user.personal_team, settings: { "wecom_userid" => "boss" })
    posted = []
    result = Agent::WecomApproval.notify(dm, { "summary" => "装一个软件" },
      poster: ->(payload) { posted << payload and true })

    assert result[:ok]
    assert_equal %w[operator_dm], result[:delivered_to]
    assert_equal 1, posted.size
  end

  test "refuses cleanly when the bridge isn't configured" do
    ENV["WECOM_BRIDGE_TOKEN"] = nil
    result = Agent::WecomApproval.notify(@conversation, { "summary" => "删东西" },
      poster: ->(*) { flunk "不应发出请求" })
    assert_not result[:ok]
  end

  test "requires a summary" do
    result = Agent::WecomApproval.notify(@conversation, { "summary" => "  " })
    assert_not result[:ok]
  end

  test "no wecom linkage means nowhere to deliver" do
    web_user = User.create!(email: "web-#{SecureRandom.hex(4)}@example.com", password: "password123")
    web = web_user.conversations.create!(team: web_user.personal_team)
    result = Agent::WecomApproval.notify(web, { "summary" => "删东西" },
      poster: ->(*) { flunk "不应发出请求" })
    assert_not result[:ok]
  end

  test "a failed push is not reported as delivered" do
    result = Agent::WecomApproval.notify(@conversation, { "summary" => "删东西" },
      poster: ->(_payload) { false })
    assert_not result[:ok]
  end
end
