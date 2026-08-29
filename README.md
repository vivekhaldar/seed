# seed

A seed agent: the smallest starting point from which an agent can grow.

[`seed.py`](seed.py) calls a language model with one tool: `exec`, which runs
shell commands. It loads the system prompt from `self/SELF.md`. The agent can
edit `self/` to retain tools, notes, and behavior between sessions.

Everything an agent normally gets from a framework — tools, memory, skills,
conventions — must instead be *grown* by the agent, session by session, into
its `self/` directory.

## Try one

Model and API key are collected *before* `seed.py` runs, so the kernel stays
a loop. Pipe this from an empty directory (or pass `--dir`):

```bash
mkdir my-agent && cd my-agent
curl -fsSL https://raw.githubusercontent.com/vivekhaldar/seed/master/try.sh | bash
```

The script asks which provider to use (OpenRouter, Anthropic, OpenAI, Gemini,
or a Codex subscription), stores the key in [llm](https://llm.datasette.io/)'s
existing `keys.json`, writes `.seed-model`, plants `seed.py` / `run_seed.sh`,
and starts the REPL. Later sessions reuse that model:

```bash
./run_seed.sh
./run_seed.sh -m gemini/gemini-2.5-flash
```

Non-interactive, if you already have a key:

```bash
curl -fsSL https://raw.githubusercontent.com/vivekhaldar/seed/master/try.sh \
  | bash -s -- --provider anthropic --key "$ANTHROPIC_API_KEY"
```

`try.sh --help` lists flags. If `cwd` already has files, the script plants
in `./seed` unless you pass `--dir`.

Already on Codex and do not want the wizard? The previous entry still works:

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

A verbatim transcript of every session is recorded to `self/sessions/*.json`
(updated after each turn). This is a flight recorder, not memory: the agent
never loads it at boot, but you can read it — and the agent may grow tools to
study its own past.

One seed, many individuals: each directory you plant in grows a different
agent, diverging based on what it experiences.

## Configuration

Models and keys are handled entirely by [llm](https://llm.datasette.io/)
(Simon Willison's library). `try.sh` writes the key into llm's user
`keys.json` and the chosen model into `.seed-model`; `seed.py` only
receives `-m`. Direct `uvx` / `./seed.py` still default to
`openai-codex/gpt-5.6-sol` (ChatGPT login via the Codex CLI):

```bash
codex login                      # one-time, per machine
./run_seed.sh                    # .seed-model if present, else Codex default
./run_seed.sh -m gemini/gemini-2.5-flash
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

## Video walkthrough

[![Watch the video](https://img.youtube.com/vi/3xwpkR5vgBo/maxresdefault.jpg)](https://www.youtube.com/watch?v=3xwpkR5vgBo)
