require "test_helper"

class ReapStalledTurnsJobTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "reap-#{SecureRandom.hex(4)}@example.com", password: "password123")
    @conversation = @user.conversations.create!
    @window = Rails.application.config.x.agent.stalled_turn_window
  end

  def turn(status:, started_at:)
    @conversation.messages.create!(
      role: :assistant, content: "", streaming_status: status, started_at: started_at
    )
  end

  test "marks a stalled streaming turn errored and stamps finished_at" do
    message = turn(status: :streaming, started_at: @window.ago - 1.minute)

    ReapStalledTurnsJob.perform_now

    assert_equal "errored", message.reload.streaming_status
    assert_not_nil message.finished_at
  end

  test "reaps a stalled pending turn too" do
    message = turn(status: :pending, started_at: @window.ago - 1.minute)

    ReapStalledTurnsJob.perform_now

    assert_equal "errored", message.reload.streaming_status
  end

  test "leaves a recently started turn running" do
    message = turn(status: :streaming, started_at: 30.seconds.ago)

    ReapStalledTurnsJob.perform_now

    assert_equal "streaming", message.reload.streaming_status
  end

  test "ignores turns that already finished" do
    [ :done, :errored, :canceled ].each do |status|
      message = turn(status: status, started_at: @window.ago - 1.hour)
      ReapStalledTurnsJob.perform_now
      assert_equal status.to_s, message.reload.streaming_status
    end
  end

  test "never reaps a user message" do
    message = @conversation.messages.create!(
      role: :user, content: "hi", streaming_status: :pending, started_at: @window.ago - 1.hour
    )

    ReapStalledTurnsJob.perform_now

    assert_equal "pending", message.reload.streaming_status
  end
end
