require "test_helper"

class Api::Wecom::MessagesControllerTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email: "wecom-admin@example.com", password: "password123")
    @token = "test-wecom-token-#{SecureRandom.hex(8)}"
    @prev_token = ENV["WECOM_BRIDGE_TOKEN"]
    @prev_email = ENV["WECOM_BRIDGE_USER_EMAIL"]
    ENV["WECOM_BRIDGE_TOKEN"] = @token
    ENV["WECOM_BRIDGE_USER_EMAIL"] = @user.email
  end

  teardown do
    ENV["WECOM_BRIDGE_TOKEN"] = @prev_token
    ENV["WECOM_BRIDGE_USER_EMAIL"] = @prev_email
  end

  def auth = { "Authorization" => "Bearer #{@token}" }

  test "create starts a turn on a per-sender conversation" do
    assert_difference "Conversation.count", 1 do
      assert_difference "Message.count", 2 do
        post "/api/wecom/messages", params: { from_userid: "zhangsan", content: "查一下仪器台账" },
             headers: auth, as: :json
      end
    end
    assert_response :created

    body = JSON.parse(response.body)
    conversation = Conversation.find(body["conversation_id"])
    assert_equal @user, conversation.user
    assert_equal @user.personal_team, conversation.team
    assert conversation.visibility_personal?
    assert_equal "zhangsan", conversation.settings["wecom_userid"]

    assistant = Message.find(body["message_id"])
    assert assistant.assistant?
    assert assistant.pending?
  end

  test "create reuses the conversation for a repeat sender" do
    post "/api/wecom/messages", params: { from_userid: "zhangsan", content: "第一条" }, headers: auth, as: :json
    first = JSON.parse(response.body)["conversation_id"]
    Message.find(JSON.parse(response.body)["message_id"]).update!(streaming_status: :done)

    assert_no_difference "Conversation.count" do
      post "/api/wecom/messages", params: { from_userid: "zhangsan", content: "第二条" }, headers: auth, as: :json
    end
    assert_equal first, JSON.parse(response.body)["conversation_id"]
  end

  test "create answers 409 while the previous turn is still running" do
    post "/api/wecom/messages", params: { from_userid: "zhangsan", content: "第一条" }, headers: auth, as: :json
    assert_response :created

    assert_no_difference "Message.count" do
      post "/api/wecom/messages", params: { from_userid: "zhangsan", content: "催一下" }, headers: auth, as: :json
    end
    assert_response :conflict
  end

  test "create gives each group chat its own conversation" do
    post "/api/wecom/messages", params: { from_userid: "zhangsan", content: "群A第一条", chatid: "wrGroupA" }, headers: auth, as: :json
    group_a = JSON.parse(response.body)["conversation_id"]
    Message.find(JSON.parse(response.body)["message_id"]).update!(streaming_status: :done)

    post "/api/wecom/messages", params: { from_userid: "zhangsan", content: "群B第一条", chatid: "wrGroupB" }, headers: auth, as: :json
    group_b = JSON.parse(response.body)["conversation_id"]
    assert_not_equal group_a, group_b
    assert_equal "wrGroupB", Conversation.find(group_b).settings["wecom_chatid"]
  end

  test "create reuses the group conversation across senders" do
    post "/api/wecom/messages", params: { from_userid: "zhangsan", content: "第一条", chatid: "wrGroupA" }, headers: auth, as: :json
    first = JSON.parse(response.body)["conversation_id"]
    Message.find(JSON.parse(response.body)["message_id"]).update!(streaming_status: :done)

    assert_no_difference "Conversation.count" do
      post "/api/wecom/messages", params: { from_userid: "lisi", content: "另一个人在同群", chatid: "wrGroupA" }, headers: auth, as: :json
    end
    assert_equal first, JSON.parse(response.body)["conversation_id"]
  end

  test "a busy group does not block another group or a DM" do
    post "/api/wecom/messages", params: { from_userid: "zhangsan", content: "群A处理中", chatid: "wrGroupA" }, headers: auth, as: :json
    assert_response :created

    post "/api/wecom/messages", params: { from_userid: "zhangsan", content: "群B不受限", chatid: "wrGroupB" }, headers: auth, as: :json
    assert_response :created

    post "/api/wecom/messages", params: { from_userid: "zhangsan", content: "私聊不受限" }, headers: auth, as: :json
    assert_response :created

    post "/api/wecom/messages", params: { from_userid: "lisi", content: "群A催办", chatid: "wrGroupA" }, headers: auth, as: :json
    assert_response :conflict
  end

  test "create rejects blank content and missing sender" do
    post "/api/wecom/messages", params: { from_userid: "zhangsan", content: "  " }, headers: auth, as: :json
    assert_response :unprocessable_entity
    post "/api/wecom/messages", params: { content: "没人发的" }, headers: auth, as: :json
    assert_response :unprocessable_entity
  end

  test "requests without a valid bearer are rejected" do
    post "/api/wecom/messages", params: { from_userid: "zhangsan", content: "hi" }, as: :json
    assert_response :unauthorized
    post "/api/wecom/messages", params: { from_userid: "zhangsan", content: "hi" },
         headers: { "Authorization" => "Bearer wrong" }, as: :json
    assert_response :unauthorized
  end

  test "show reports pending while the turn runs and content once done" do
    post "/api/wecom/messages", params: { from_userid: "lisi", content: "在吗" }, headers: auth, as: :json
    message_id = JSON.parse(response.body)["message_id"]

    get "/api/wecom/messages/#{message_id}", headers: auth
    assert_response :success
    body = JSON.parse(response.body)
    assert_equal "pending", body["status"]
    assert_nil body["content"]

    message = Message.find(message_id)
    message.update!(content: "在的，有什么可以帮你？", streaming_status: :done)
    get "/api/wecom/messages/#{message_id}", headers: auth
    body = JSON.parse(response.body)
    assert_equal "done", body["status"]
    assert_equal "在的，有什么可以帮你？", body["content"]
  end

  test "show 404s for unknown messages" do
    get "/api/wecom/messages/0", headers: auth
    assert_response :not_found
  end
end
