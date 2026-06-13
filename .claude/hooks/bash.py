#!/usr/bin/env uv run
# /// script
# dependencies = ["tree-sitter", "tree-sitter-bash"]
# ///

import os
import sys
import json

import tree_sitter_bash as tsbash
from tree_sitter import Language, Parser

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


def is_git_command_allowed(args: list[str]):
    OPTIONS = ["-C", "-c"]
    ALLOWED = {
        "bisect": [None],
        "diff": [None],
        "grep": [None],
        "log": [None],
        "show": [None],
        "status": [None],
        "branch": [None, '-a'],
        "tag": ['-l', '--list'],
    }
    try:
        while args:
            arg = args.pop(0)
            if arg in OPTIONS:
                args.pop(0)
                continue
            remaining_args = args
            if allowed_params := ALLOWED.get(arg, None):
                for param in allowed_params:
                    match param:
                        case None:
                            if len(remaining_args) == 0:
                                return True  # allowed
                        case str(param_name):
                            if param_name in remaining_args:
                                return True  # allowed
                        case _:
                            assert False, "Unexpected"
            return False  # not allowed
    except IndexError:
        pass

def is_command_allowed(sequence: list[str]):
    if not sequence:
        return
    cmd, *args = sequence
    if cmd == "git":
        return is_git_command_allowed(args)


def node_text(node, source) -> str:
    return source[node.start_byte:node.end_byte].decode("utf-8")


def walk_ast(node, source, decisions):
    if node.type in ("command", "simple_command"):
        # first child is of type "command_name"
        sequence = map(lambda v: node_text(v, source), node.children)
        decision = is_command_allowed(list(sequence))
        decisions.append(decision)
    for child in node.children:
        walk_ast(child, source, decisions)


request = json_from_stdin()
if not request:
    sys.exit(0)

parser = Parser(Language(tsbash.language()))
source = request["tool_input"]["command"].encode("utf-8")
tree = parser.parse(source)
decisions = []
walk_ast(tree.root_node, source, decisions)
if all(decisions):
    print(json.dumps({
        "hookSpecificOutput": {
            "hookEventName": request.hook_event_name,
            "permissionDecision": "allow"
        }
    }))
    sys.exit(0)
if False in decisions:
    sys.stderr.write("Not permitted")
    sys.exit(2)
sys.exit(0)  # ask
