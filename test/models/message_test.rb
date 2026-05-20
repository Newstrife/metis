require "test_helper"

class MessageTest < ActiveSupport::TestCase
  setup do
    user = User.create!(email: "msg-model@example.com", password: "password123")
    @conversation = user.conversations.create!(backend: :pi)
  end

  test "attachments? is false for a message with no uploads" do
    message = @conversation.messages.create!(role: :user, content: "hi", streaming_status: :done)
    assert_not message.attachments?
  end

  test "attachments? is true once an image or file is attached" do
    message = @conversation.messages.create!(role: :user, content: "hi", streaming_status: :done)
    message.files.attach(io: StringIO.new("data"), filename: "notes.txt", content_type: "text/plain")
    assert message.attachments?
  end
end
