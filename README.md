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

Models and keys are handled by [llm](https://llm.datasette.io/) (Simon
Willison's library); `run_seed.sh` decides which model a session uses. On a
machine with no credentials at all, the first run asks you to pick a provider
and paste an API key — the key is checked with a one-word prompt, stored in
`llm`'s key store, and the model choice is saved to `self/model`. After that,
starting the agent asks nothing.

Resolution order:

1. `-m` flag — one session: `./run_seed.sh -m gemini/gemini-3.7-flash`
2. `SEED_MODEL` env var — one session, handy for containers
3. `self/model` — this individual's saved choice; edit or delete it to change
4. found credentials — a Codex CLI login (`codex login`, uses
   `openai-codex/gpt-5.6-sol`), or a provider key from the environment
   (`OPENROUTER_API_KEY`, `ANTHROPIC_API_KEY`, `GEMINI_API_KEY`,
   `OPENAI_API_KEY`) or from `llm keys set <provider>`
5. none of the above — the first-run picker

Bundled providers: OpenAI via a Codex subscription or API key, Anthropic,
Gemini, and OpenRouter (one OpenRouter key unlocks hundreds of models).

## Design

Why it's shaped this way — McCarthy's metacircular eval, homoiconicity, the
prior art, and the risks we consciously accepted: [docs/DESIGN.md](docs/DESIGN.md).

## License

Seed is licensed under the [Sovereign Source License (SSL) v0.3](SovereignLicense.md).
The canonical license project is maintained by
[Smart Assets](https://gitlab.com/smart-assets.io/SovereignLicense).

## Video walkthrough

[![Watch the video](https://img.youtube.com/vi/3xwpkR5vgBo/maxresdefault.jpg)](https://www.youtube.com/watch?v=3xwpkR5vgBo)
