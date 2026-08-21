# seed

A seed agent: the smallest starting point from which an agent can grow.

There is no framework here. The entire frozen layer is [`seed.py`](seed.py) —
a small loop that connects a language model to exactly one tool (`exec`, which
runs bash) and loads its system prompt from a file the agent itself owns and
may rewrite. Everything an agent normally gets from a framework — tools,
memory, skills, conventions — must instead be *grown* by the agent, session by
session, into its `self/` directory.

## Plant one

```bash
mkdir my-agent && cd my-agent
uvx --from git+https://github.com/vivekhaldar/seed.git seed
```

First run germinates `self/SELF.md` (the genesis self-description, committed
to a fresh git repo) and drops you into a REPL. Start talking. Everything the
agent wants to keep must be written into `self/` — sessions are ephemeral and
nothing else survives.

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
codex login                    # one-time, per machine
seed                           # uses openai-codex/gpt-5.6-sol
seed -m gemini-2.5-pro         # or override it for one session
```

Bundled providers: OpenAI via a Codex subscription or API key, Anthropic,
Gemini, and OpenRouter (one OpenRouter key unlocks hundreds of models).

## Design

Why it's shaped this way — McCarthy's metacircular eval, homoiconicity, the
prior art, and the risks we consciously accepted: [docs/DESIGN.md](docs/DESIGN.md).
