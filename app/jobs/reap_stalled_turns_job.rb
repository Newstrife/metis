# Recover turns abandoned by a dead agent process. When the process
# running a turn is killed mid-stream — a worker restart, an OOM, or a dev
# code-reload on the in-process :async adapter — ChatJob's rescue/ensure
# never runs, so the assistant message is left stuck in pending/streaming
# forever: the UI shows "Working…" indefinitely (turn_in_progress? stays
# true) and the composer stays disabled.
#
# This marks any assistant message still pending/streaming past
# config.x.agent.stalled_turn_window as errored and clears the live UI,
# the same shape as ChatJob#fail_message on a caught crash.
#
# Wired in config/recurring.yml (production). Best-effort per row — a
# single failure is logged and the sweep continues. Mirrors
# EvictPausedSandboxesJob.
class ReapStalledTurnsJob < ApplicationJob
  queue_as :default

  def perform
    cutoff = Time.current - Rails.application.config.x.agent.stalled_turn_window
    stalled = Message.where(role: :assistant, streaming_status: %i[pending streaming])
                     .where(started_at: ..cutoff)
                     .includes(:conversation)

    stalled.find_each { |message| reap(message) }
  end

  private

  def reap(message)
    message.update!(streaming_status: :errored, finished_at: Time.current)

    broadcaster = ChatBroadcaster.new(message.conversation, message)
    broadcaster.fail("The agent run was interrupted before it finished.")
    broadcaster.stop_sidebar_indicator
    broadcaster.refresh_composer
  rescue StandardError => e
    Rails.logger.warn(
      "ReapStalledTurnsJob: failed for message=#{message.id}: #{e.class}: #{e.message}"
    )
  end
end
