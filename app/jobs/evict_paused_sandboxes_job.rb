# Kill E2B sandboxes whose conversation has been idle past the
# eviction window (config.x.agent.e2b_eviction_window). E2B keeps
# paused sandboxes indefinitely (docs/coding-runtime.md), so without
# this job every conversation a user ever opens leaves a paused
# sandbox on E2B's servers forever — paying for storage we don't use.
#
# The next turn against an evicted conversation will see the
# e2b_sandbox_id cleared and provision a fresh sandbox — the working
# tree is gone, the message history is not.
#
# Wired in config/recurring.yml. Best-effort: a per-conversation
# failure (sandbox already killed, transient API hiccup) is logged
# and the loop continues; we never want one bad row to stall the
# whole eviction.
class EvictPausedSandboxesJob < ApplicationJob
  queue_as :default

  def perform
    cutoff = Time.current - Rails.application.config.x.agent.e2b_eviction_window
    candidates = Conversation.where.not(e2b_sandbox_id: nil).where(updated_at: ..cutoff)

    candidates.find_each do |conversation|
      evict(conversation)
    end
  end

  private

  def evict(conversation)
    Agent::Runtime::E2b.kill_sandbox(conversation.e2b_sandbox_id)
    conversation.update_column(:e2b_sandbox_id, nil)
  rescue StandardError => e
    Rails.logger.warn(
      "EvictPausedSandboxesJob: failed for conversation=#{conversation.id} " \
      "sandbox=#{conversation.e2b_sandbox_id}: #{e.class}: #{e.message}"
    )
  end
end
