# seed

A seed agent: the smallest starting point from which an agent can grow.

[`seed.py`](seed.py) calls a language model with one tool: `exec`, which runs
shell commands. It loads the system prompt from `self/SELF.md`. The agent can
edit `self/` to retain tools, notes, and behavior between sessions.

Everything an agent normally gets from a framework — tools, memory, skills,
conventions — must instead be *grown* by the agent, session by session, into
its `self/` directory.

## Plant one

```bash
mkdir my-agent && cd my-agent
uvx --from git+https://github.com/vivekhaldar/seed.git seed
```

First run copies `seed.py` and `run_seed.sh` into this directory (never
overwriting a file that already exists), germinates `self/SELF.md`, and
commits those files together in a fresh git repo here — the loop is part of
this individual's history, not only `self/`. Then it drops you into a REPL.
Start talking. Everything the agent wants to keep must be written into
`self/` — sessions are ephemeral and nothing else survives.

Come back to the same agent with the local runner — no need to `uvx` again:

```bash
./run_seed.sh
./run_seed.sh -m gemini-2.5-pro
```

A verbatim transcript of every session is recorded to `self/sessions/*.json`
(updated after each turn). This is a flight recorder, not memory: the agent
never loads it at boot, but you can read it — and the agent may grow tools to
study its own past.

One seed, many individuals: each directory you plant in grows a different
agent, diverging based on what it experiences.

## Configuration

Models and keys are handled entirely by [llm](https://llm.datasette.io/)
(Simon Willison's library). The default model is `openai-codex/gpt-5.6-sol`,
which uses the ChatGPT login from the Codex CLI:

```bash
codex login                      # one-time, per machine
./run_seed.sh                    # uses openai-codex/gpt-5.6-sol
./run_seed.sh -m gemini-2.5-pro  # or override it for one session
```

Bundled providers: OpenAI via a Codex subscription or API key, Anthropic,
Gemini, and OpenRouter (one OpenRouter key unlocks hundreds of models).

## Run in a container

The `exec` tool runs arbitrary shell commands, so a container is a natural
pot to plant in. Build the image straight from the repo:

```bash
docker build -t seed https://github.com/vivekhaldar/seed.git
```

Mount a directory at `/agent` — that is where everything the agent is
(`seed.py`, `run_seed.sh`, `self/`) lives, so the individual survives the
container. Mounting `~/.codex` reuses your Codex CLI login for the default
model:

```bash
mkdir my-agent
docker run -it --rm \
  -v "$PWD/my-agent:/agent" \
  -v ~/.codex:/root/.codex \
  seed
```

For other providers, pass an API key as an environment variable and pick a
model:

```bash
docker run -it --rm \
  -v "$PWD/my-agent:/agent" \
  -e OPENROUTER_API_KEY \
  seed -m openrouter/moonshotai/kimi-k2
```

or mount keys you already set with `llm keys set`:
`-v ~/.config/io.datasette.llm:/root/.config/io.datasette.llm`.

Come back to the same agent by mounting the same directory again.

## Design

Why it's shaped this way — McCarthy's metacircular eval, homoiconicity, the
prior art, and the risks we consciously accepted: [docs/DESIGN.md](docs/DESIGN.md).

## License

Seed is licensed under the [Sovereign Source License (SSL) v0.3](SovereignLicense.md).
The canonical license project is maintained by
[Smart Assets](https://gitlab.com/smart-assets.io/SovereignLicense).

## Video walkthrough

[![Watch the video](https://img.youtube.com/vi/3xwpkR5vgBo/maxresdefault.jpg)](https://www.youtube.com/watch?v=3xwpkR5vgBo)
