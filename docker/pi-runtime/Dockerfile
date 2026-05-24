# pi runtime image for Agent::Runtime::Docker — pi plus a basic toolchain.
#
# Build it with:        bin/rails "docker:image[metis-pi]"
# Point Metis at it:    export METIS_DOCKER_IMAGE=metis-pi
#                       export METIS_AGENT_RUNTIME=docker
FROM node:22-slim

# pi's bash tool expects a basic toolchain on PATH. `gh` is here so the
# agent can authenticate as the operator against GitHub via the
# `GH_TOKEN` the runtime injects per turn (see app/services/agent/
# runtime/base.rb). Installed from GitHub's apt source — the
# `gh-cli.list` repo holds the current major.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      bash ca-certificates curl git gnupg ripgrep \
 && install -m 0755 -d /etc/apt/keyrings \
 && curl -fsSL https://cli.github.com/packages/githubcli-archive-keyring.gpg \
      | tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null \
 && chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg \
 && echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
      > /etc/apt/sources.list.d/github-cli.list \
 && apt-get update \
 && apt-get install -y --no-install-recommends gh \
 && rm -rf /var/lib/apt/lists/*

# pi itself, pinned to the version pi-agent-rb supports. The rake task
# passes PI_VERSION from PiAgent::SUPPORTED_PI_VERSION.
ARG PI_VERSION
RUN npm install --global "@earendil-works/pi-coding-agent@${PI_VERSION}"

# The MCP connector bridge (pi-mcp-adapter). Keep the version in sync
# with bin/setup and lib/tasks/e2b.rake.
RUN pi install npm:pi-mcp-adapter@2.6.1
