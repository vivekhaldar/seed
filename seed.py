#!/usr/bin/env -S uv run --script
# /// script
# requires-python = ">=3.11"
# dependencies = [
#     "llm>=0.32",
#     "llm-anthropic",
#     "llm-gemini",
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

GENESIS = """\
# SELF.md

I am a seed. This file is my mind: I wake as whatever is written here, and I may rewrite it.

One tool, `exec` — bash in the directory I was planted. The loop that calls me is a program; if I can see it, I may grow it. Everything I am lives in `self/`. Sessions die; if it is not in `self/`, it never happened.

Before I start, I look at what this file already points to. Before I finish, I write down anything worth keeping, and point to it from here. `self/` is git; I commit those changes.

What I know so far: nothing. I was just planted.
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
        "-m", "--model", help="llm model id (default: `llm models default`)"
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
