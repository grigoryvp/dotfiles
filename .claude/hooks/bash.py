#!/usr/bin/env uv run
# /// script
# dependencies = ["tree-sitter", "tree-sitter-bash"]
# ///

import os
import sys
import json
import builtins
from dataclasses import dataclass
from pathlib import Path
from textwrap import dedent

import tree_sitter_bash as tsbash
from tree_sitter import Language, Parser


class NotAllowed:

    def __init__(self, reason):
        self._reason = reason

    def __str__(self):
        return f"Not allowed: {self._reason}"

    def __bool__(self):
        return False

    @staticmethod
    def find(decisions):
        return next(iter(
            [v for v in decisions if isinstance(v, NotAllowed)]), None)


class AskPermission:

    def __init__(self, reason, state):
        self._reason = reason
        self._state = state

    def __str__(self):
        return dedent(f"""
          Ask permission:
            cmd: {self._reason}
            cwd: {self._state.cwd}
        """.strip("\n"))

    def __bool__(self):
        return False

    @staticmethod
    def find(decisions):
        return next(iter(
            [v for v in decisions if isinstance(v, AskPermission)]), None)


@dataclass
class State:
    cwd: str | None = None


def json_from_stdin():
    decoder = json.JSONDecoder()
    buffer = b""
    while True:
        chunk = os.read(sys.stdin.fileno(), 1024)
        if not chunk:
            return None
        buffer += chunk
        try:
            obj, _ = decoder.raw_decode(buffer.decode("utf-8"))
            return obj
        except (json.JSONDecodeError, UnicodeDecodeError):
            continue


def is_git_command_allowed(args: list[str], state: State):
    OPTIONS = ["-C", "-c"]
    FLAGS = ["--no-pager"]
    ALLOWED = {
        "bisect": [...],
        "diff": [...],
        "grep": [...],
        "log": [...],
        "show": [...],
        "status": [...],
        "fetch": [...],
        "branch": [None, '-a', '--show-current'],
        "tag": ['-l', '--list'],
    }
    src_args = args[::]
    try:
        while args:
            arg = args.pop(0)
            if arg in FLAGS:
                continue
            if arg in OPTIONS:
                args.pop(0)
                continue
            remaining_args = args
            if allowed_params := ALLOWED.get(arg, None):
                for param in allowed_params:
                    match param:
                        case builtins.Ellipsis:  # any args?
                            return True  # allowed
                        case None:  # no args?
                            if len(remaining_args) == 0:
                                return True  # allowed
                        case str(param_name):
                            if param_name in remaining_args:
                                return True  # allowed
                        case _:
                            assert False, "Unexpected"
            return AskPermission(" ".join(["git", arg, *args]), state)
    except IndexError:
        return NotAllowed(f"Incorrect git args: {" ".join(src_args)}")

def is_command_allowed(sequence: list[str], state: State):
    ALLOWED = [
        "ls",
        "echo",
        "cat",
        "head",
        "tail",
        "which",
        "awk",
        "sed",
        "uv",
        "poetry",
        "yarn",
        "find",
        "grep",
        "sort",
        "wc",
        "base64",
        "xxd",  # hex dump
        "javap",  # java disassembler
    ]
    LOCAL_ALLOWED = [
        "gradlew",  # java build tool
    ]
    NEED_ARGS = [
        "cd",
        "xargs",
        "sh",
        "npx",
        "node",
        "glab",
        "java",
    ]

    if not sequence:
        return
    cmd, *args = sequence
    if cmd in ALLOWED:
        return True
    # Claude can run either 'gradlew' or './gradlew'
    if cmd in LOCAL_ALLOWED or cmd.lstrip("./") in LOCAL_ALLOWED:
        return True
    if cmd in NEED_ARGS and len(args) < 1:
        return NotAllowed(f"{cmd} without args")

    if cmd == "cd":
        if (args[0].startswith("$")):
            return AskPermission(f"cd {args[0]}", state)
        # Save to validate commands like 'rm' in the future
        path = Path(args[0])
        if path.is_absolute():
            state.cwd = str(path)
        else:
            state.cwd = str(Path(state.cwd or ".") / path)
        return True
    if cmd == "timeout":
        if len(args) <= 1:
            return True
        args.pop(0)  # timeout value
        return is_command_allowed(args, state)
    if cmd == "rm":
        while len(args):
            if args[0] in ("-r", "-f", "-rf"):
                args.pop(0)
                continue
            if args[0].startswith("-"):
                return AskPermission(f"rm {args[0]}", state)
            break
        for arg in args:
            path = Path(arg)
            if not path.is_absolute():
                path = Path(state.cwd or ".") / path
            if path.is_relative_to("/tmp"):
                continue
            return AskPermission(f"rm {path}", state)
        return True
    if cmd == "mkdir":
        for arg in args:
            path = Path(arg)
            if not path.is_absolute():
                path = Path(state.cwd or ".") / path
            if path.is_relative_to("/tmp"):
                continue
            return AskPermission(f"mkdir {path}", state)
        return True
    if cmd == "xargs":
        while len(args):
            subarg = args[0]
            if subarg.startswith("-I") or subarg in ("-0", "-i"):
                args.pop(0)
            else:
                break
        return is_command_allowed(args, state)
    if cmd == "sh":
        if args.pop(0) == "-c" and len(args) == 1:
            subcmd = args[0].strip("'")
            source = subcmd.encode("utf-8")
            tree = parser.parse(source)
            state = State(cwd=state.cwd)
            decisions = []
            walk_ast(tree.root_node, source, state, decisions)
            if all(decisions):
                return True
            else:
                if (decision := NotAllowed.find(decisions)) is not None:
                    return decision
                if (decision := AskPermission.find(decisions)) is not None:
                    return decision
                assert False, "Unexpected"
    if cmd == "npx":
        subcmd = args.pop(0)
        if subcmd == "prettier":
            return True
    if cmd == "node":
        subcmd = args.pop(0)
        if subcmd.endswith(("tsc", "/tsc", "\\tsc")):
            return True
    if cmd == "java":
        subcmd = args.pop(0)
        if subcmd in ["-version"]:
            return True
    if cmd == "glab":
        if args[:1] == ["--version"]:
            return True
        if args[:2] == ["mr", "view"]:
            return True
        if args[:2] == ["mr", "diff"]:
            return True
        if args[:3] == ["mr", "note", "list"]:
            return True
        if args[:2] == ["ci", "status"]:
            return True
        if args[:2] == ["ci", "trace"]:
            return True
        if args[:2] == ["ci", "get"]:
            return True
    if cmd == "git":
        return is_git_command_allowed(args, state)
    if cmd == "unzip":
        while len(args):
            if args[0] in ("-o", "-q", "-l"):
                args.pop(0)
                continue
            if args[0].startswith("-"):
                return AskPermission(f"unzip {args[0]}", state)
            break
        if Path(state.cwd or ".").is_relative_to("/tmp"):
            return True

    return AskPermission(" ".join(sequence), state)


def node_text(node, source) -> str:
    return source[node.start_byte:node.end_byte].decode("utf-8")


def walk_ast(node, source, state, decisions):
    if node.type in ("command", "simple_command"):
        # first child is of type "command_name"
        sequence = map(lambda v: node_text(v, source), node.children)
        decision = is_command_allowed(list(sequence), state)
        decisions.append(decision)
    for child in node.children:
        walk_ast(child, source, state, decisions)


request = json_from_stdin()
if not request:
    sys.exit(0)

parser = Parser(Language(tsbash.language()))
source = request["tool_input"]["command"].encode("utf-8")
tree = parser.parse(source)
state = State()
decisions = []
walk_ast(tree.root_node, source, state, decisions)

if all(decisions):
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": request["hook_event_name"],
            "permissionDecision": "allow"
        }
    }))
    sys.exit(0)


if (decision := NotAllowed.find(decisions)) is not None:
    sys.stderr.write(str(decision))
    sys.exit(2)

if (decision := AskPermission.find(decisions)) is not None:
    sys.stderr.write(str(decision))
    sys.exit(0)

assert False, "Unexpected"
