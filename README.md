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

First run copies `seed.py` and `run_seed.sh` into this directory (never
overwriting a file that already exists), germinates `self/SELF.md` (the
genesis self-description, committed to a fresh git repo), and drops you into
a REPL. Start talking. Everything the agent wants to keep must be written
into `self/` — sessions are ephemeral and nothing else survives.

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
(Simon Willison's library), which stores keys machine-wide:

```bash
uvx llm keys set openai        # one-time, per machine
uvx llm models default gpt-5.2 # optional: set a default model
./run_seed.sh -m gemini-2.5-pro  # or pick a model per session
```

Bundled providers: OpenAI, Anthropic, Gemini, OpenRouter (one OpenRouter key
unlocks hundreds of models).

## Design

Why it's shaped this way — McCarthy's metacircular eval, homoiconicity, the
prior art, and the risks we consciously accepted: [docs/DESIGN.md](docs/DESIGN.md).
