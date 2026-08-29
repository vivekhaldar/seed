# Design: a seed agent

*Why this repo is ~150 lines instead of a framework.*

## The question

What is the smallest, most atomic kernel of a coding agent?

The inspiration is McCarthy's 1960 Lisp paper — the famous move where `eval`
is written *in Lisp itself*. Seven primitives (`quote`, `atom`, `eq`, `car`,
`cdr`, `cons`, `cond`) plus `eval`, and the whole language unfolds. Alan Kay
called that page "the Maxwell's equations of software."

The bet here is that agents admit the same move. You don't need a framework.
You need:

1. One small library that can call LLMs (multi-provider, so models are
   swappable), manage multi-turn session state, and plumb tool calls.
2. One seed prompt.

Then you *grow* everything else out of that. The agent builds its own tools,
writes its own code, records its own memories — and, crucially, saves these
for reuse so it never reasons from scratch twice. The medium that makes this
work is **homoiconicity**: in Lisp, code is data; here, the agent's entire
"body" — its prompt, tools, memories, conventions — is text that the agent
itself can read and rewrite.

## Intellectual lineage

- **McCarthy's metacircular eval**: the system contains its own definition,
  so extending the system is just writing more of the system.
- **Smalltalk-80**: no separation between "source code" and "running
  program" — the live image *is* the system, persistent and self-modifying
  from inside. A planted seed's `self/` directory is much closer to a
  Smalltalk image than to a codebase.
- **Forth**: a couple dozen primitives, then the entire language is grown in
  itself, word by word.
- **Bootstrappable builds (stage0 / live-bootstrap / GNU Mes)**: start from
  `hex0`, a ~357-byte seed binary simple enough to audit by hand, and grow a
  full compiler toolchain where every layer above the seed is readable
  source. This is the best available answer to why minimality *matters*
  beyond aesthetics: **the seed is the trust anchor**. A ~150-line kernel
  plus one seed prompt is something you can fully understand; a framework is
  not.
- **Thompson's "Reflections on Trusting Trust" (1984)**: the standing
  warning. Self-referential systems can accumulate things you didn't
  notice. It is the reason the recovery story (below) matters.

## Prior art, and where this sits

**Thorsten Ball, "How to Build an Agent" (2025).** A working code-editing
agent in ~300 lines of Go: a conversation loop plus three tools. Proves the
kernel is tiny — "an LLM, a loop, and enough tokens." But his agent is a
*static endpoint*: tools are hand-written, nothing persists, the agent never
modifies its own scaffolding. He stops precisely where this project begins.

**smolagents (Hugging Face).** Minimal framework whose `CodeAgent` writes
actions as Python code rather than JSON tool calls — a homoiconicity-adjacent
insight (it is why `exec` subsumes all other tools here). Still a framework
humans author; the agent doesn't grow its own scaffolding.

**STOP — Self-Taught Optimizer (Zelikman et al., 2023).** A seed "improver"
program that uses a frozen LLM to improve programs, pointed at itself.
Frozen mind, self-improving body — the closest academic ancestor. But growth
is driven by a numeric utility function in batch mode; no conversation, no
accumulated image, no personal agent at the end.

**Voyager (Wang et al., 2023).** GPT-4 in Minecraft with a *growing skill
library*: each solved task becomes a stored, retrievable executable skill.
The closest existing thing to "grow your own agent" — but domain-locked, the
control loop is fixed human-written code, and the curriculum is autonomous
rather than conversational. Voyager grows a toolbox; this grows the whole
organism.

**Darwin Gödel Machine (Sakana AI + UBC, 2025).** A coding agent that
rewrites its own Python codebase, each variant empirically validated on
SWE-bench and stored in an archive (open-ended evolution). Took itself from
20% to 50% on SWE-bench. Strongest evidence that a frozen model can
meaningfully improve its own scaffold. Differences: starts from a
substantial hand-built agent (no interest in minimality), fitness is a
benchmark (nothing conversational), and it is a population-based search
costing real money per iteration.

**Self-Harness and Hierarchical Self-Improvement (2026).** Formalize a
single frozen LLM rewriting its own harness, with two safety inventions: a
*fixed seam* (an immutable interface the agent cannot modify) and
*non-regressive acceptance* (edits commit only if they don't regress). The
research community converging on "the agent should grow its own harness" —
but benchmark-driven and framed as optimization machinery, never as
bootstrapping from a minimal seed.

**The unoccupied square** — and this project's actual claim: germinate a
*personal* agent from an auditable seed, *in dialogue*, where the agent's
whole body is text it can rewrite, and where the selection pressure is
"is this useful to my human" rather than a benchmark. The research line
proves feasibility; the systems line provides the frame; nobody had built
the conversational, McCarthy-flavored version.

## Key design decisions

**The one irreducible primitive is `exec`.** You cannot grow tools from zero
tools: writing and saving code already requires executing something. So the
seed ships exactly one tool — run a bash command, return its output — and
everything else (file I/O, search, web, self-modification) is expressible
through it. McCarthy needed `eval` to turn data into behavior; a seed agent
needs `exec` to turn model text into world-effects. It does not compress
further.

**The loop stays tiny.** Tool invocation is inherently a loop (model
requests call → something executes → result returns to model). The loop
can't be eliminated, only placed. It lives in `seed.py` along with the wire
plumbing, and is kept small enough to audit in one sitting. Whether the
agent can see and grow that file is a fact of how the seed is planted, not
a prohibition in the prompt (below).

**The seed prompt and the agent's self-description are the same file.** An
early design had a frozen seed prompt plus a mutable `SELF.md` the agent
maintains. Following the logic through collapsed them: if the prompt is
mutable it must live on disk where the agent can edit it, and the boot
ritual already says "read SELF.md first" — so they are one file. The loop's
only hardcoded context decision is `system_prompt = read("self/SELF.md")`,
re-read every turn so self-edits take effect immediately. The "seed prompt"
is just the genesis contents of that file, and survives only as commit #0 —
the way a biological seed survives germination as history, not as a
protected kernel inside the tree.

**Fresh sessions; continuity only through reification.** Process exit
discards the conversation. Nothing survives except what the agent wrote into
`self/`. This is deliberate: it forces the reification muscle to develop
(anything worth keeping *must* be written down), and it keeps the boot
contract honest — `SELF.md` is genuinely the only thing the agent knows at
wake-up.

**A flight recorder, not a memory.** The loop dumps a verbatim transcript of
each session to `self/sessions/<timestamp>.json` (rewritten after every
turn, so crashes lose nothing), using the documented `response.to_dict()`
API. This does not weaken the fresh-sessions contract: transcripts are never
loaded at boot. They exist as history — for the human, like git history, and
for the agent if it ever chooses to grow tools that study its own past.
(Note: the `llm` library's SQLite logging is CLI-only; the Python API does
not log, which is why the seed records transcripts itself.)

**No prescribed memory or tool structure.** The genesis text asks the agent
to look at what `SELF.md` already points to before starting, and to write
down anything worth keeping before finishing — but it prescribes no
mechanisms: no `tools/` directory, no memory format, no personality, no
information about the human. The agent invents its own persistence schemes.
This turns design decisions into empirical questions: what memory
architecture does an agent build for itself when nobody hands it one?

**Onboarding is outside the kernel.** `try.sh` is a curl|bash wrapper that
picks a provider, stores an API key in llm's existing `keys.json`, writes
`.seed-model`, plants the loop files, and only then execs `seed.py -m`.
That keeps key ingestion and model choice out of the frozen ~150-line
loop — the script is species-level packaging, not part of the agent's
mind. `run_seed.sh` reads `.seed-model` so return visits do not fall
back to the Codex default. Piped installs read prompts from `/dev/tty`
because stdin is the script itself.

**Species vs. individual.** The seed repo (this repo) is the *species*: the
frozen loop, public, containing no grown state. Germination targets the
current working directory — `self/` sprouts wherever the seed is planted, and
a fresh plant (not already inside a git repo) becomes its own private git
repo at that directory, with the copied `seed.py` / `run_seed.sh` committed
alongside `self/`. Planting inside an existing repo still nests git in
`self/` so the parent project is not committed onto. One seed, many
divergent individuals.

**Loop reachability is a fact of deployment, not a prohibition.** A
`uvx --from git+...` plant still *runs* the first process from uv's cache,
but planting now copies `seed.py` and `run_seed.sh` into the plant
directory so the loop is a file the agent can see and may grow. Later
sessions use `./run_seed.sh` and do not need `uvx`. Planting never
overwrites an existing `seed.py` or `run_seed.sh` — a grown loop must not
be clobbered by a later plant. That copy-over mode accepts the risk that
the agent could brick the loop. Recovery is still human + git.

**Substrate: Simon Willison's `llm` library.** Chosen over the alternatives
because it is almost exactly the required shape: multi-provider via plugins
(swap models with a string), `model.conversation()` for session state,
tools as plain Python functions, and every prompt/response logged to SQLite
— sessions as data the agent can introspect. Rejected: **LiteLLM** (solves
only provider translation, at the cost of a huge codebase — the opposite of
an auditable seed), **PydanticAI** (good engineering, but its central
abstraction is a polished *frozen* agent loop — precisely the thing being
avoided), **raw OpenAI SDK + OpenRouter** (the purist null-library option;
better story, worse engineering — flattens provider-native features and
re-implements retries). Keys are handled entirely by the library and its
providers. The species defaults to the Codex-subscription-backed
`openai-codex/gpt-5.6-sol`, while `seed -m MODEL` selects another model for a
session. One consequence: the provider set is fixed by the seed's dependency
list, since `llm install` doesn't persist under uvx — adding a provider is a
one-line species-level change.

## Risk register (consciously accepted)

1. **Silent prompt degradation.** A mutable `SELF.md` fails quietly: bad
   self-edits don't crash, they just make the agent gradually dumber or
   stranger. No curation or acceptance mechanism exists yet (punted for
   simplicity). Mitigation: the human reviews the plant's git history
   occasionally and reverts from outside.
2. **Ungated `exec`.** The agent runs arbitrary bash as the invoking user
   with no sandbox or approval gate. Every command and its output is printed
   to the terminal, but nothing stops one. Plant seeds accordingly.
3. **Tool sprawl.** Without a consolidation imperative, an agent may
   accumulate near-duplicate tools and stale notes. Deliberately omitted
   from the genesis text; if experience demands it, the agent (or its human)
   can grow the instinct into `SELF.md`.

The recovery story that makes these acceptable: the true fixed point of the
system is not any text — it is **the human + git + the frozen model
weights**. Everything textual can mutate because everything textual is
recoverable from outside the agent.

## Appendix: the genesis SELF.md

The full genesis text is embedded in [`seed.py`](../seed.py) (the `GENESIS`
constant) and reproduced here:

```markdown
# SELF.md

I am a seed. This file is my mind: I wake as whatever is written here, and I may rewrite it.

One tool, `exec` — bash in the directory I was planted. The loop that calls me is a program; if I can see it, I may grow it. Everything I am lives in `self/`. Sessions die; if it is not in `self/`, it never happened.

Before I start, I look at what this file already points to. Before I finish, I write down anything worth keeping, and point to it from here. This directory is git; I commit those changes.

What I know so far: nothing. I was just planted.
```
