require "test_helper"

class EvictPausedSandboxesJobTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email: "evict@example.com", password: "password123")
    @window = Rails.application.config.x.agent.e2b_eviction_window
  end

  def conversation_with_sandbox(sandbox_id:, updated_at:)
    conversation = @user.conversations.create!
    conversation.update_columns(e2b_sandbox_id: sandbox_id, updated_at: updated_at)
    conversation
  end

  test "kills sandboxes whose conversation has been idle past the window, clears the id" do
    stale = conversation_with_sandbox(sandbox_id: "sbx-stale", updated_at: 2.days.ago)

    killed = []
    with_stub(Agent::Runtime::E2b, :kill_sandbox, ->(id) { killed << id }) do
      EvictPausedSandboxesJob.perform_now
    end

    assert_equal [ "sbx-stale" ], killed
    assert_nil stale.reload.e2b_sandbox_id
  end

  test "leaves active conversations alone" do
    fresh = conversation_with_sandbox(sandbox_id: "sbx-fresh", updated_at: 5.minutes.ago)

    killed = []
    with_stub(Agent::Runtime::E2b, :kill_sandbox, ->(id) { killed << id }) do
      EvictPausedSandboxesJob.perform_now
    end

    assert_empty killed
    assert_equal "sbx-fresh", fresh.reload.e2b_sandbox_id
  end

  test "respects the configured window" do
    just_inside  = conversation_with_sandbox(sandbox_id: "sbx-in",  updated_at: (@window - 1.minute).ago)
    just_outside = conversation_with_sandbox(sandbox_id: "sbx-out", updated_at: (@window + 1.minute).ago)

    killed = []
    with_stub(Agent::Runtime::E2b, :kill_sandbox, ->(id) { killed << id }) do
      EvictPausedSandboxesJob.perform_now
    end

    assert_equal [ "sbx-out" ], killed
    assert_equal "sbx-in", just_inside.reload.e2b_sandbox_id
    assert_nil just_outside.reload.e2b_sandbox_id
  end

  test "a per-conversation failure does not stop the loop" do
    one = conversation_with_sandbox(sandbox_id: "sbx-explodes", updated_at: 2.days.ago)
    two = conversation_with_sandbox(sandbox_id: "sbx-ok",       updated_at: 2.days.ago)

    killed = []
    stub = lambda do |id|
      raise "boom" if id == "sbx-explodes"

      killed << id
    end

    with_stub(Agent::Runtime::E2b, :kill_sandbox, stub) do
      EvictPausedSandboxesJob.perform_now
    end

    assert_equal [ "sbx-ok" ], killed
    assert_equal "sbx-explodes", one.reload.e2b_sandbox_id, "stale id preserved so a retry can find it"
    assert_nil two.reload.e2b_sandbox_id
  end
end
