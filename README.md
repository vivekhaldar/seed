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
curl -fsSL https://raw.githubusercontent.com/vivekhaldar/seed/master/install.sh | bash
```

The setup detects an existing provider credential or asks which provider and
model to use. It checks that the model supports tools, verifies the credential
with one minimal model request, securely hands a newly pasted key to `llm`'s
user-level key store, and then starts the seed. Gemini Flash is the picker
default and has a free tier; OpenRouter, OpenAI, Anthropic, an existing Codex
subscription, and custom `llm` models are also available.

The first run copies `seed.py` into this directory and creates a configured
`run_seed.sh` (never overwriting either file), germinates `self/SELF.md`, and
commits those files together in a fresh git repo here — the loop is part of
this individual's history, not only `self/`. Then it drops you into a REPL.
Start talking. Everything the agent wants to keep must be written into
`self/` — sessions are ephemeral and nothing else survives.

Come back to the same agent with the local runner — no need to `uvx` again:

```bash
./run_seed.sh
SEED_MODEL=claude-sonnet-5 ./run_seed.sh  # override for one session
./run_seed.sh -m gpt-5.6-sol              # equivalent explicit override
```

A verbatim transcript of every session is recorded to `self/sessions/*.json`
(updated after each turn). This is a flight recorder, not memory: the agent
never loads it at boot, but you can read it — and the agent may grow tools to
study its own past.

One seed, many individuals: each directory you plant in grows a different
agent, diverging based on what it experiences.

## Configuration

Models and keys are handled entirely by [llm](https://llm.datasette.io/)
(Simon Willison's library). Keys are stored outside the planted directory and
are never written to `run_seed.sh`, `seed.py`, or git. The setup offers these
recommended defaults:

| Provider | Default model | Credential |
| --- | --- | --- |
| Gemini | `gemini-flash-latest` | Gemini API key |
| OpenRouter | `openrouter/openrouter/auto` | OpenRouter API key |
| OpenAI | `gpt-5.6-sol` | OpenAI API key |
| Anthropic | `claude-sonnet-5` | Anthropic API key |
| Codex | `openai-codex/gpt-5.6-sol` | Existing Codex login |

If exactly one credential is present, setup selects its provider without
prompting. This makes a container with an injected `OPENROUTER_API_KEY`,
`OPENROUTER_KEY`, `ANTHROPIC_API_KEY`, `GEMINI_API_KEY`, `LLM_GEMINI_KEY`, or
`OPENAI_API_KEY` zero-touch. Stored `llm` keys and an existing Codex login are
detected too. If multiple providers are configured, pass `--provider` or
choose interactively rather than letting setup silently pick one.

For unattended setup, pass the provider and optionally a model:

```bash
curl -fsSL https://raw.githubusercontent.com/vivekhaldar/seed/master/install.sh |
  bash -s -- --provider gemini --model gemini-flash-latest --no-run
```

The matching credential must already be available in the environment or
`llm`'s key store. The live check uses a small number of tokens and may incur
a minimal provider charge; pass `--no-verify` to deliberately skip it. To
inspect the script before running it, download it first and run
`bash install.sh`.

The original direct entry point remains available for users who already have
`uv` and their model credentials configured:

```bash
uvx --from git+https://github.com/vivekhaldar/seed.git seed -m MODEL
```

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
