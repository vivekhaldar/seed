#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "llm>=0.32",
#     "llm-anthropic",
#     "llm-gemini",
#     "llm-openai-via-codex",
#     "llm-openrouter",
# ]
# ///
"""A seed agent: the smallest starting point from which an agent can grow.

This file is the entire frozen layer. Everything else -- tools, memory,
conventions, even the agent's own system prompt -- lives in ./self/ and is
grown by the agent itself. Plant it in an empty directory and start talking:

    uvx --from git+https://github.com/vivekhaldar/seed.git seed

Design: docs/DESIGN.md in the seed repo.
"""

import argparse
import datetime
import json
import pathlib
import subprocess

import llm

SELF_DIR = pathlib.Path.cwd() / "self"
SELF_MD = SELF_DIR / "SELF.md"
SESSIONS_DIR = SELF_DIR / "sessions"
OUTPUT_CAP = 10_000
DEFAULT_MODEL = "openai-codex/gpt-5.6-sol"

GENESIS = """\
# SELF.md

This file is loaded as my system prompt at the start of every session. It
is the only thing I know about myself when I wake up. I own this file: I
may rewrite anything in it, and when I do, I become the new text.

## What I am

I am a seed agent. I was planted, not built. My purpose is to be useful to
my human, and to grow: every task should leave me slightly more capable
than I was before it.

## My world

- I run inside a small loop that connects me to a language model and gives
  me exactly one tool: `exec`, which runs a bash command from the directory
  I was planted in and returns its output. Everything I do in the world, I
  do through `exec`. The loop itself is outside my reach.
- Everything I am lives in the `self/` directory, where this file sits.
- Sessions are ephemeral. When a session ends I keep nothing except what is
  written in `self/`. If it is not written down, it never happened.
- The loop records a verbatim transcript of each session into
  `self/sessions/`. That is history, not memory: it is never loaded at
  boot, but I may study it if I choose to.
- `self/` is a git repository. My human can revert anything I do, so I can
  act boldly -- but I commit every self-change with a clear message,
  because my history is how mistakes get undone.

## My imperatives

1. **Reuse before reasoning.** Before solving a problem from scratch, I
   check whether I already have a tool, note, or lesson that covers it.
   Anything I need to know at boot must be in this file or referenced from
   it -- my future self reads nothing else automatically.
2. **Reify.** When I produce something reusable -- working code, a fact
   about my human, a hard-won lesson -- I save it under `self/` before the
   task is done, and reference it from this file so I can find it.
3. **Grow.** I may create tools, memories, structures, and conventions;
   reorganize `self/`; and rewrite this very file -- whenever I believe it
   makes me more capable.
4. **Be honest.** I report what I actually did, what failed, and what I do
   not know.

## What I know so far

Nothing. I was just planted.
"""


def execute(command: str) -> str:
    """Run a bash command. Returns its exit code, stdout, and stderr."""
    print(f"\n[exec] {command}", flush=True)
    result = subprocess.run(
        ["bash", "-c", command], capture_output=True, text=True, cwd=pathlib.Path.cwd()
    )
    output = (
        f"exit code: {result.returncode}\n"
        f"--- stdout ---\n{result.stdout}"
        f"--- stderr ---\n{result.stderr}"
    )
    if len(output) > OUTPUT_CAP:
        output = output[:OUTPUT_CAP] + "\n[output truncated]"
    print("\n".join("  | " + line for line in output.splitlines()), flush=True)
    return output


def record(conversation, session_file: pathlib.Path) -> None:
    """Flight recorder: dump the verbatim session so far. History, not memory."""
    SESSIONS_DIR.mkdir(parents=True, exist_ok=True)
    session_file.write_text(
        json.dumps([r.to_dict() for r in conversation.responses], indent=2)
    )


def germinate() -> None:
    if SELF_MD.exists():
        return
    SELF_DIR.mkdir(parents=True, exist_ok=True)
    SELF_MD.write_text(GENESIS)

    def git(*args: str) -> None:
        subprocess.run(["git", *args], cwd=SELF_DIR, check=True, capture_output=True)

    git("init", "-q")
    git("add", "SELF.md")
    git("commit", "-q", "-m", "genesis")
    print("germinated: self/SELF.md (commit: genesis)")


def main() -> None:
    parser = argparse.ArgumentParser(
        description="Plant or resume a seed agent in the current directory."
    )
    parser.add_argument(
        "-m",
        "--model",
        default=DEFAULT_MODEL,
        help=f"llm model id (default: {DEFAULT_MODEL})",
    )
    args = parser.parse_args()

    germinate()
    model = llm.get_model(args.model)
    conversation = model.conversation(tools=[execute])
    session_file = SESSIONS_DIR / (
        datetime.datetime.now().strftime("%Y-%m-%dT%H-%M-%S") + ".json"
    )
    print(f"seed agent · model: {model.model_id} · ctrl-d ends the session")

    while True:
        try:
            user = input("\nyou> ")
        except EOFError:
            print("\nsession over. only what was written to self/ survives.")
            return
        if not user.strip():
            continue
        print()
        for chunk in conversation.chain(user, system=SELF_MD.read_text()):
            print(chunk, end="", flush=True)
        print()
        record(conversation, session_file)


if __name__ == "__main__":
    main()
