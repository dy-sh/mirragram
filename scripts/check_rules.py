#!/usr/bin/env python3
"""Repository hygiene checks, run by git hooks before every commit.

  check_rules.py --staged          check files staged for commit (pre-commit)
  check_rules.py --all             check every tracked file
  check_rules.py --commit-msg F    check a commit message file (commit-msg)
  check_rules.py --install-hooks   install the pre-commit and commit-msg hooks

Rules:
  * no Cyrillic outside the Russian localization;
  * nothing that looks like a credential or private key;
  * no local-only files (credentials, docs);
  * no co-author trailers in commit messages.

Personal deny lists live in .git/info/rules (never committed):

  [words]       case-insensitive words banned in files and commit messages
  [paths]       path prefixes or globs that must not be committed
"""

import fnmatch
import re
import subprocess
import sys
from pathlib import Path

CYRILLIC_ALLOWED = {"lib/l10n/app_ru.arb"}
BANNED_PATHS = [".tg_api_hash", "docs/", ".env", ".env.*", "*.local", "*.local.*",
                "*.pem", "*.p12", "*.jks", "*.keystore", "*.mobileprovision"]
CYRILLIC = re.compile("[\u0400-\u04FF]")
SECRETS = [
    (re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"), "private key"),
    (re.compile(r"(?i)(api_?hash|secret|token|password)\w*\s*[:=]\s*['\"]?[0-9a-f]{32,}"),
     "hex secret"),
    (re.compile(r"(?i)api_?id\w*\s*[:=]\s*['\"]?\d{5,}"), "Telegram api_id"),
    (re.compile(r"\bAKIA[0-9A-Z]{16}\b"), "AWS access key"),
    (re.compile(r"\bgh[pousr]_[A-Za-z0-9]{36,}\b"), "GitHub token"),
]
CO_AUTHOR = re.compile(r"(?im)^\s*co-authored-by:")


def git(*args: str) -> str:
    return subprocess.run(["git", *args], check=True, capture_output=True,
                          text=True).stdout


def root() -> Path:
    return Path(git("rev-parse", "--show-toplevel").strip())


def local_rules() -> tuple[list[str], list[str]]:
    path = Path(git("rev-parse", "--git-path", "info/rules").strip())
    if not path.is_absolute():
        path = root() / path
    words, paths, section = [], [], None
    if path.exists():
        for line in path.read_text(encoding="utf-8").splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if line in ("[words]", "[paths]"):
                section = line
            elif section == "[words]":
                words.append(line.lower())
            elif section == "[paths]":
                paths.append(line)
    return words, paths


def path_banned(path: str, patterns: list[str]) -> bool:
    name = path.rsplit("/", 1)[-1]
    for p in patterns:
        if p.endswith("/") and (path.startswith(p) or f"/{p}" in f"/{path}"):
            return True
        if fnmatch.fnmatch(path, p) or fnmatch.fnmatch(name, p):
            return True
    return False


def read(path: str, staged: bool) -> str | None:
    if staged:
        data = subprocess.run(["git", "show", f":{path}"], capture_output=True).stdout
    else:
        file = root() / path
        if not file.exists():
            return None
        data = file.read_bytes()
    if b"\0" in data[:8000]:
        return None
    return data.decode("utf-8", errors="replace")


def check_files(staged: bool) -> list[str]:
    files = (git("diff", "--cached", "--name-only", "--diff-filter=ACMR") if staged
             else git("ls-files")).splitlines()
    words, extra_paths = local_rules()
    errors = []
    for path in files:
        if path_banned(path, BANNED_PATHS + extra_paths):
            errors.append(f"{path}: local-only file")
            continue
        text = read(path, staged)
        if text is None:
            continue
        lowered = text.lower()
        for no, line in enumerate(text.splitlines(), 1):
            if path not in CYRILLIC_ALLOWED and CYRILLIC.search(line):
                errors.append(f"{path}:{no}: Cyrillic outside localization")
            for pattern, what in SECRETS:
                if pattern.search(line):
                    errors.append(f"{path}:{no}: looks like a {what}")
        for word in words:
            if word in lowered or word in path.lower():
                errors.append(f"{path}: contains a banned word from .git/info/rules")
    return errors


def check_message(path: str) -> list[str]:
    lines = []
    for line in Path(path).read_text(encoding="utf-8").splitlines():
        if line.startswith("# ------------------------ >8"):
            break  # git commit -v: the diff below is not part of the message
        if not line.startswith("#"):
            lines.append(line)
    text = "\n".join(lines)
    words, _ = local_rules()
    errors = []
    if CO_AUTHOR.search(text):
        errors.append("commit message: co-author trailers are not allowed")
    if CYRILLIC.search(text):
        errors.append("commit message: use English")
    for word in words:
        if word in text.lower():
            errors.append("commit message: contains a banned word from .git/info/rules")
    first = text.strip().splitlines()[0] if text.strip() else ""
    if len(first) > 72:
        errors.append("commit message: keep the subject within 72 characters")
    return errors


def install_hooks() -> None:
    hooks = Path(git("rev-parse", "--git-path", "hooks").strip())
    if not hooks.is_absolute():
        hooks = root() / hooks
    hooks.mkdir(parents=True, exist_ok=True)
    for name, args in (("pre-commit", "--staged"), ("commit-msg", '--commit-msg "$1"')):
        hook = hooks / name
        hook.write_text(f'#!/bin/sh\nexec python3 scripts/check_rules.py {args}\n')
        hook.chmod(0o755)
    print(f"Installed hooks in {hooks}")


def main() -> int:
    args = sys.argv[1:]
    if args == ["--install-hooks"]:
        install_hooks()
        return 0
    if args == ["--staged"]:
        errors = check_files(staged=True)
    elif args == ["--all"]:
        errors = check_files(staged=False)
    elif len(args) == 2 and args[0] == "--commit-msg":
        errors = check_message(args[1])
    else:
        print(__doc__)
        return 2
    for e in errors:
        print(e, file=sys.stderr)
    return 1 if errors else 0


if __name__ == "__main__":
    sys.exit(main())
