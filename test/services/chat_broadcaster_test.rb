require "test_helper"

class ChatBroadcasterTest < ActiveSupport::TestCase
  setup do
    user = User.create!(email: "bc@example.com", password: "password123")
    conversation = user.conversations.create!
    message = conversation.messages.create!(role: :assistant, content: "", streaming_status: :streaming)
    @broadcaster = ChatBroadcaster.new(conversation, message)
  end

  def event(type, **data)
    Agent::UiEvent.new(type, data: data)
  end

  test "a tool call keeps its name and args when a later event updates it" do
    @broadcaster.send(:record_tool,
      event(:tool_call_started, tool_call_id: "t1", name: "bash", args: { "command" => "ls" }),
      status: :running)

    locals = @broadcaster.send(:record_tool,
      event(:tool_call_finished, tool_call_id: "t1", output: "ok", is_error: false),
      status: :done)

    assert_equal "bash", locals[:name]
    assert_equal({ "command" => "ls" }, locals[:args])
    assert_equal "ok", locals[:output]
    assert_equal :done, locals[:status]
  end

  test "record_tool always returns every tool_call partial local" do
    locals = @broadcaster.send(:record_tool,
      event(:tool_call_started, tool_call_id: "t1", name: "bash", args: {}),
      status: :running)

    assert_equal %i[tool_call_id name args output is_error skill_slug status].sort, locals.keys.sort
  end

  test "record_tool carries skill_slug from started through later events" do
    @broadcaster.send(:record_tool,
      event(:tool_call_started, tool_call_id: "t1", name: "bash",
                                args: { "command" => "cat .pi/skills/eli5/SKILL.md" },
                                skill_slug: "eli5"),
      status: :running)

    locals = @broadcaster.send(:record_tool,
      event(:tool_call_finished, tool_call_id: "t1", output: "ok", is_error: false),
      status: :done)

    assert_equal "eli5", locals[:skill_slug]
  end
end
