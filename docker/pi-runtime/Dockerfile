# pi runtime image for Agent::Runtime::Docker — pi plus a basic toolchain.
#
# Build it with:        bin/rails "docker:image[metis-pi]"
# Point Metis at it:    export METIS_DOCKER_IMAGE=metis-pi
#                       export METIS_AGENT_RUNTIME=docker
FROM node:22-slim

# pi's bash tool expects a basic toolchain on PATH.
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      bash ca-certificates curl git ripgrep \
 && rm -rf /var/lib/apt/lists/*

# pi itself, pinned to the version pi-agent-rb supports. The rake task
# passes PI_VERSION from PiAgent::SUPPORTED_PI_VERSION.
ARG PI_VERSION
RUN npm install --global "@earendil-works/pi-coding-agent@${PI_VERSION}"

# The MCP connector bridge (pi-mcp-adapter). Keep the version in sync
# with bin/setup and lib/tasks/e2b.rake.
RUN pi install npm:pi-mcp-adapter@2.6.1
