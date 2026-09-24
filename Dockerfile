# A pot to plant a seed in.
#
#   docker build -t seed .
#   mkdir my-agent
#   docker run -it --rm -v "$PWD/my-agent:/agent" -v ~/.codex:/root/.codex seed
#
# Everything the agent is lives in /agent (seed.py, run_seed.sh, self/);
# mount a directory there and the individual survives the container.

FROM ghcr.io/astral-sh/uv:python3.13-bookworm-slim

# The exec tool is bash; germination commits to git.
RUN apt-get update \
    && apt-get install -y --no-install-recommends git ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# Give git an identity for the agent's own commits, and trust /agent even
# when the mounted volume is owned by a different uid than the container.
RUN git config --system user.name "seed" \
    && git config --system user.email "seed@container" \
    && git config --system init.defaultBranch main \
    && git config --system --add safe.directory '*'

COPY seed.py run_seed.sh /opt/seed/

# Resolve and cache the dependencies at build time so the first run is instant.
RUN /opt/seed/seed.py --help > /dev/null

WORKDIR /agent

ENTRYPOINT ["/opt/seed/seed.py"]
