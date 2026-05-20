# Durable root for agent files — pi session files (the agent's
# conversation memory) and, later, per-conversation working directories.
#
# This MUST be persistent. It is deliberately not under tmp/, which Rails
# treats as disposable (rails tmp:clear, deploys, container restarts wipe
# it). In production, set METIS_AGENT_ROOT to a mounted volume.
#
# Test runs use a disposable tmp/ path — ephemeral is correct there.
default_root =
  if Rails.env.test?
    Rails.root.join("tmp/test_agent")
  else
    Rails.root.join("storage/agent")
  end

Rails.application.config.x.agent.root =
  Pathname.new(ENV.fetch("METIS_AGENT_ROOT", default_root.to_s))
