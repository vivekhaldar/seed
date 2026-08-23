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

## Design

Why it's shaped this way — McCarthy's metacircular eval, homoiconicity, the
prior art, and the risks we consciously accepted: [docs/DESIGN.md](docs/DESIGN.md).

## License

Seed is licensed under the [Sovereign Source License (SSL) v0.3](SovereignLicense.md).
The canonical license project is maintained by
[Smart Assets](https://gitlab.com/smart-assets.io/SovereignLicense).
