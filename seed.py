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

I am a seed. This file is my mind: I wake as whatever is written here, and I may rewrite it.

One tool, `exec` — bash in the directory I was planted. The loop that calls me is a program; if I can see it, I may grow it. Everything I am lives in `self/`. Sessions die; if it is not in `self/`, it never happened.

Before I start, I look at what this file already points to. Before I finish, I write down anything worth keeping, and point to it from here. This directory is git; I commit those changes.

What I know so far: nothing. I was just planted.
"""

# Kept identical to the checked-in run_seed.sh. uvx installs only the
# `seed` module (py-modules = ["seed"]), so a plant from cache embeds this.
RUN_SEED_SH = """\
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
exec ./seed.py "$@"
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


def _git_toplevel(cwd: pathlib.Path) -> pathlib.Path | None:
    result = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        cwd=cwd,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        return None
    return pathlib.Path(result.stdout.strip())


def germinate() -> None:
    if SELF_MD.exists():
        return
    SELF_DIR.mkdir(parents=True, exist_ok=True)
    SELF_MD.write_text(GENESIS)

    cwd = pathlib.Path.cwd()
    # Fresh plant: repo at cwd so the copied loop is in this individual's
    # history. Already inside a repo: nest git in self/ instead of committing
    # onto the parent.
    git_root = SELF_DIR if _git_toplevel(cwd) is not None else cwd

    def git(*args: str) -> None:
        subprocess.run(["git", *args], cwd=git_root, check=True, capture_output=True)

    git("init", "-q")
    tracked = ["self/SELF.md"]
    if git_root == SELF_DIR:
        git("add", "SELF.md")
    else:
        git("add", "self/SELF.md")
        for name in ("seed.py", "run_seed.sh"):
            if (cwd / name).exists():
                git("add", name)
                tracked.append(name)
    git("commit", "-q", "-m", "genesis")
    print(f"germinated: {', '.join(tracked)} (commit: genesis)")


def plant() -> None:
    """Leave a visible copy of the loop and a local runner in cwd."""
    running = pathlib.Path(__file__).resolve()
    cwd = pathlib.Path.cwd()
    planted: list[str] = []

    dest_loop = cwd / "seed.py"
    if not dest_loop.exists() and running != dest_loop.resolve():
        dest_loop.write_bytes(running.read_bytes())
        dest_loop.chmod(dest_loop.stat().st_mode | 0o111)
        planted.append("seed.py")

    dest_runner = cwd / "run_seed.sh"
    if not dest_runner.exists():
        sibling = running.parent / "run_seed.sh"
        text = sibling.read_text() if sibling.is_file() else RUN_SEED_SH
        dest_runner.write_text(text)
        dest_runner.chmod(dest_runner.stat().st_mode | 0o111)
        planted.append("run_seed.sh")

    if planted:
        print(f"planted: {', '.join(planted)}")


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

    plant()
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
