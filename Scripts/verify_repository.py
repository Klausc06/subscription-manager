#!/usr/bin/env python3
"""Deterministic checks for release-owned repository files."""

from __future__ import annotations

import json
import plistlib
import re
import subprocess
import sys
from collections.abc import Iterator
from pathlib import Path
from typing import Any


ROOT = Path(__file__).resolve().parents[1]
REQUIRED_LOCALIZATIONS = ("en", "zh-Hans")
STRUCTURED_SUFFIXES = {
    ".entitlements",
    ".json",
    ".jsonl",
    ".plist",
    ".xcstrings",
}
MAC_APP_SOURCE = ROOT / "SubscriptionManager/App/SubscriptionManagerApp.swift"
SWIFT_CONDITIONAL_DIRECTIVE = re.compile(
    r"^[ \t]*#(?:if|elseif|else|endif)\b[^\n]*(?:\n|$)",
    re.MULTILINE,
)
SWIFT_CONDITIONAL_DIRECTIVE_LINE = re.compile(
    r"^[ \t]*#(?P<kind>if|elseif|else|endif)\b"
)


class DuplicateJSONKey(ValueError):
    pass


def display_path(path: Path) -> str:
    try:
        return str(path.relative_to(ROOT))
    except ValueError:
        return str(path)


def repository_files() -> list[Path]:
    result = subprocess.run(
        [
            "git",
            "ls-files",
            "-z",
            "--cached",
            "--others",
            "--exclude-standard",
        ],
        cwd=ROOT,
        check=True,
        capture_output=True,
    )
    return [
        ROOT / path.decode("utf-8")
        for path in result.stdout.split(b"\0")
        if path
    ]


def reject_duplicate_keys(pairs: list[tuple[str, Any]]) -> dict[str, Any]:
    value: dict[str, Any] = {}
    for key, item in pairs:
        if key in value:
            raise DuplicateJSONKey(f"duplicate key {key!r}")
        value[key] = item
    return value


def load_json(text: str) -> Any:
    return json.loads(text, object_pairs_hook=reject_duplicate_keys)


def string_units(value: Any) -> Iterator[dict[str, Any]]:
    if isinstance(value, dict):
        if "stringUnit" in value:
            string_unit = value["stringUnit"]
            yield string_unit if isinstance(string_unit, dict) else {}
        for key, item in value.items():
            if key != "stringUnit":
                yield from string_units(item)
    if isinstance(value, list):
        for item in value:
            yield from string_units(item)


def has_complete_translation(value: Any) -> bool:
    units = list(string_units(value))
    return bool(units) and all(
        unit.get("state") == "translated"
        and isinstance(unit.get("value"), str)
        and bool(unit["value"].strip())
        for unit in units
    )


def verify_string_catalog(path: Path, catalog: Any) -> list[str]:
    errors: list[str] = []
    if not isinstance(catalog, dict) or not isinstance(catalog.get("strings"), dict):
        return [f"{path.relative_to(ROOT)}: invalid string-catalog structure"]
    for key, entry in catalog["strings"].items():
        localizations = entry.get("localizations", {}) if isinstance(entry, dict) else {}
        for locale in REQUIRED_LOCALIZATIONS:
            if locale not in localizations or not has_complete_translation(
                localizations[locale]
            ):
                errors.append(
                    f"{path.relative_to(ROOT)}: {key!r} has an incomplete "
                    f"{locale} translation"
                )
    return errors


def verify_structured_file(path: Path) -> list[str]:
    relative = path.relative_to(ROOT)
    try:
        if path.suffix in {".json", ".xcstrings"}:
            value = load_json(path.read_text(encoding="utf-8"))
            return verify_string_catalog(path, value) if path.suffix == ".xcstrings" else []
        if path.suffix == ".jsonl":
            for line_number, line in enumerate(
                path.read_text(encoding="utf-8").splitlines(),
                start=1,
            ):
                if line.strip():
                    try:
                        load_json(line)
                    except (json.JSONDecodeError, DuplicateJSONKey) as error:
                        return [f"{relative}:{line_number}: {error}"]
            return []
        if path.suffix in {".entitlements", ".plist"}:
            with path.open("rb") as source:
                plistlib.load(source)
    except (UnicodeDecodeError, json.JSONDecodeError, DuplicateJSONKey, plistlib.InvalidFileException) as error:
        return [f"{relative}: {error}"]
    return []


def line_number(text: str, offset: int) -> int:
    return text.count("\n", 0, offset) + 1


def expose_all_swift_conditional_branches(source: str) -> str:
    """Make every conditional branch visible to the compiler parser.

    Parse-only compiler AST output omits all conditional-compilation bodies,
    even when a build flag selects one. Prefixing directive-shaped lines with
    a comment marker preserves the complete source while making every branch
    ordinary Swift for one compiler parse. If such a line is actually inside a
    multiline string or block comment, the inserted marker remains in that
    same lexical container, so it cannot expose lookalike code.
    """

    def comment_directive(match: re.Match[str]) -> str:
        line = match.group(0)
        indentation_length = len(line) - len(line.lstrip(" \t"))
        return f"{line[:indentation_length]}//{line[indentation_length:]}"

    return SWIFT_CONDITIONAL_DIRECTIVE.sub(comment_directive, source)


def swift_conditional_directive_lines(source: str) -> dict[int, str]:
    """Return real conditional directives, excluding strings and comments."""
    directives: dict[int, str] = {}
    block_comment_depth = 0
    multiline_literal: tuple[str, int] | None = None

    def delimiter_is_escaped(line: str, offset: int, hash_count: int) -> bool:
        if hash_count:
            escape = f"\\{'#' * hash_count}"
            return line[max(0, offset - len(escape)):offset] == escape
        backslashes = 0
        cursor = offset - 1
        while cursor >= 0 and line[cursor] == "\\":
            backslashes += 1
            cursor -= 1
        return backslashes % 2 == 1

    def literal_end(
        line: str,
        start: int,
        delimiter: str,
        hash_count: int,
    ) -> int | None:
        cursor = start
        while True:
            offset = line.find(delimiter, cursor)
            if offset < 0:
                return None
            if not delimiter_is_escaped(line, offset, hash_count):
                return offset + len(delimiter)
            cursor = offset + 1

    for line_index, line in enumerate(source.splitlines(keepends=True)):
        if block_comment_depth == 0 and multiline_literal is None:
            match = SWIFT_CONDITIONAL_DIRECTIVE_LINE.match(line)
            if match is not None:
                directives[line_index] = match.group("kind")

        cursor = 0
        while cursor < len(line):
            if block_comment_depth:
                if line.startswith("/*", cursor):
                    block_comment_depth += 1
                    cursor += 2
                elif line.startswith("*/", cursor):
                    block_comment_depth -= 1
                    cursor += 2
                else:
                    cursor += 1
                continue

            if multiline_literal is not None:
                literal_kind, hash_count = multiline_literal
                delimiter = (
                    f'"""{"#" * hash_count}'
                    if literal_kind == "string"
                    else f'/{"#" * hash_count}'
                )
                end = literal_end(line, cursor, delimiter, hash_count)
                if end is None:
                    break
                multiline_literal = None
                cursor = end
                continue

            if line.startswith("//", cursor):
                break
            if line.startswith("/*", cursor):
                block_comment_depth = 1
                cursor += 2
                continue

            hash_count = 0
            literal_start = cursor
            while (
                literal_start + hash_count < len(line)
                and line[literal_start + hash_count] == "#"
            ):
                hash_count += 1
            delimiter_start = literal_start + hash_count

            if line.startswith('"""', delimiter_start):
                multiline_literal = ("string", hash_count)
                cursor = delimiter_start + 3
                continue
            if line.startswith('"', delimiter_start):
                delimiter = f'"{"#" * hash_count}'
                end = literal_end(
                    line,
                    delimiter_start + 1,
                    delimiter,
                    hash_count,
                )
                cursor = len(line) if end is None else end
                continue
            if hash_count and line.startswith("/", delimiter_start):
                multiline_literal = ("regex", hash_count)
                cursor = delimiter_start + 1
                continue

            cursor += max(hash_count, 1)

    return directives


def swift_conditional_branch_layout(
    source: str,
) -> tuple[
    list[str],
    list[tuple[int, ...]],
    list[int | None],
    list[tuple[int, ...]],
    dict[int, int],
]:
    """Map each source line to its nested conditional branch path."""
    lines = source.splitlines(keepends=True)
    directives = swift_conditional_directive_lines(source)
    current_path: list[int] = []
    block_stack: list[int] = []
    line_paths: list[tuple[int, ...]] = []
    directive_blocks: list[int | None] = []
    branch_paths: list[tuple[int, ...]] = []
    branch_blocks: dict[int, int] = {}
    next_block_id = 0
    next_branch_id = 0

    for line_index in range(len(lines)):
        directive = directives.get(line_index)
        line_paths.append(tuple(current_path))
        if directive == "if":
            block_id = next_block_id
            next_block_id += 1
            block_stack.append(block_id)
            directive_blocks.append(block_id)
            branch_blocks[next_branch_id] = block_id
            current_path.append(next_branch_id)
            next_branch_id += 1
            branch_paths.append(tuple(current_path))
            continue
        if directive in {"elseif", "else"}:
            if not current_path or not block_stack:
                raise ValueError(f"unexpected #{directive} on line {line_index + 1}")
            block_id = block_stack[-1]
            directive_blocks.append(block_id)
            branch_blocks[next_branch_id] = block_id
            current_path[-1] = next_branch_id
            next_branch_id += 1
            branch_paths.append(tuple(current_path))
            continue
        if directive == "endif":
            if not current_path or not block_stack:
                raise ValueError(f"unexpected #endif on line {line_index + 1}")
            directive_blocks.append(block_stack.pop())
            current_path.pop()
            continue
        directive_blocks.append(None)

    if current_path or block_stack:
        raise ValueError("unterminated conditional compilation block")
    return (
        lines,
        line_paths,
        directive_blocks,
        branch_paths,
        branch_blocks,
    )


def comment_swift_line(line: str) -> str:
    indentation_length = len(line) - len(line.lstrip(" \t"))
    return f"{line[:indentation_length]}//{line[indentation_length:]}"


def swift_conditional_selection(
    branch_paths: list[tuple[int, ...]],
    branch_blocks: dict[int, int],
    target_path: tuple[int, ...],
) -> dict[int, int]:
    """Select a canonical clause for every block reachable from a target."""
    branches_by_block: dict[int, list[int]] = {}
    parent_branch_by_block: dict[int, int | None] = {}
    block_order: list[int] = []
    for branch_path in branch_paths:
        branch_id = branch_path[-1]
        block_id = branch_blocks[branch_id]
        if block_id not in branches_by_block:
            branches_by_block[block_id] = []
            parent_branch_by_block[block_id] = (
                branch_path[-2] if len(branch_path) > 1 else None
            )
            block_order.append(block_id)
        branches_by_block[block_id].append(branch_id)

    target_by_block = {
        branch_blocks[branch_id]: branch_id
        for branch_id in target_path
    }
    child_blocks_by_branch: dict[int, list[int]] = {}
    for block_id in block_order:
        parent_branch = parent_branch_by_block[block_id]
        if parent_branch is not None:
            child_blocks_by_branch.setdefault(parent_branch, []).append(block_id)

    selected_by_block: dict[int, int] = {}

    def select_block(block_id: int) -> None:
        selected_branch = target_by_block.get(
            block_id,
            branches_by_block[block_id][0],
        )
        selected_by_block[block_id] = selected_branch
        for child_block in child_blocks_by_branch.get(selected_branch, []):
            select_block(child_block)

    for block_id in block_order:
        if parent_branch_by_block[block_id] is None:
            select_block(block_id)

    return selected_by_block


def swift_conditional_variant(
    lines: list[str],
    line_paths: list[tuple[int, ...]],
    directive_blocks: list[int | None],
    branch_paths: list[tuple[int, ...]],
    branch_blocks: dict[int, int],
    target_path: tuple[int, ...],
) -> str:
    """Build one complete, parseable conditional-compilation configuration."""
    selected_by_block = swift_conditional_selection(
        branch_paths,
        branch_blocks,
        target_path,
    )
    result: list[str] = []
    for line, line_path, directive_block in zip(
        lines,
        line_paths,
        directive_blocks,
        strict=True,
    ):
        is_selected = all(
            selected_by_block.get(branch_blocks[branch_id]) == branch_id
            for branch_id in line_path
        )
        should_comment = directive_block is not None or not is_selected
        result.append(comment_swift_line(line) if should_comment else line)
    return "".join(result)


def is_lossy_decoding_use(node: dict[str, Any]) -> bool:
    """Conservatively reject executable uses of the decoding:as: signature.

    The parse AST cannot resolve type aliases or contextual ``.init`` calls.
    Matching the signature's argument labels instead covers direct, qualified,
    explicit-initializer, contextual, and aliased spellings. Compound
    initializer references are represented separately as unresolved dot
    expressions and are rejected as well.
    """
    if node.get("_kind") == "call_expr":
        arguments = node.get("args")
        return (
            isinstance(arguments, dict)
            and arguments.get("_kind") == "argument_list"
            and arguments.get("labels") == "decoding:as:"
        )
    return (
        node.get("_kind") == "unresolved_dot_expr"
        and node.get("field") == "init(decoding:as:)"
    ) or (
        node.get("_kind") == "unresolved_member_expr"
        and node.get("name") == "init(decoding:as:)"
    )


def swift_ast_nodes(value: Any) -> Iterator[dict[str, Any]]:
    if isinstance(value, list):
        for item in value:
            yield from swift_ast_nodes(item)
        return
    if not isinstance(value, dict):
        return

    yield value
    for key, item in value.items():
        if not key.startswith("processed_"):
            yield from swift_ast_nodes(item)


def swift_policy_counts(ast: Any) -> tuple[int, int]:
    force_try_count = 0
    string_decoding_count = 0

    for node in swift_ast_nodes(ast):
        if node.get("_kind") == "force_try_expr":
            force_try_count += 1
        if is_lossy_decoding_use(node):
            string_decoding_count += 1

    return force_try_count, string_decoding_count


def swift_policy_counts_in_all_conditional_branches(
    source: str,
    source_name: str,
) -> tuple[tuple[int, int] | None, list[str]]:
    """Find policy nodes in legal variants covering every conditional clause.

    Every variant selects canonical clauses for all reachable blocks, then
    overrides the target clause and its ancestors. Taking the maximum AST
    count proves presence without pretending mutually exclusive clauses run in
    one physical configuration.
    """
    try:
        (
            lines,
            line_paths,
            directive_blocks,
            branch_paths,
            branch_blocks,
        ) = swift_conditional_branch_layout(source)
    except ValueError as error:
        return None, [
            f"{source_name}: Swift conditional analysis failed: {error}"
        ]

    if not branch_paths:
        return (0, 0), []

    parsed_variants: dict[str, tuple[int, int]] = {}
    variant_counts: list[tuple[int, int]] = []
    for target_path in [(), *branch_paths]:
        variant = swift_conditional_variant(
            lines,
            line_paths,
            directive_blocks,
            branch_paths,
            branch_blocks,
            target_path,
        )
        counts = parsed_variants.get(variant)
        if counts is None:
            ast, errors = parse_swift_source(variant, source_name)
            if ast is None:
                return None, errors
            counts = swift_policy_counts(ast)
            parsed_variants[variant] = counts
        variant_counts.append(counts)

    return (
        max(counts[0] for counts in variant_counts),
        max(counts[1] for counts in variant_counts),
    ), []


def declaration_name(node: dict[str, Any]) -> str | None:
    name = node.get("name")
    if isinstance(name, str):
        return name
    if not isinstance(name, dict):
        return None
    base_name = name.get("base_name")
    if isinstance(base_name, str):
        return base_name
    if isinstance(base_name, dict):
        value = base_name.get("name")
        return value if isinstance(value, str) else None
    return None


def call_name(node: dict[str, Any]) -> str | None:
    if node.get("_kind") != "call_expr":
        return None
    function = node.get("fn")
    if not isinstance(function, dict):
        return None
    value = function.get("name") or function.get("field")
    return value if isinstance(value, str) else None


def call_has_member_argument(
    node: dict[str, Any],
    *,
    label: str,
    member: str,
) -> bool:
    arguments = node.get("args")
    if not isinstance(arguments, dict):
        return False
    values = arguments.get("args")
    if not isinstance(values, list):
        return False
    for argument in values:
        if not isinstance(argument, dict) or argument.get("label") != label:
            continue
        expression = argument.get("expr")
        if not isinstance(expression, dict):
            continue
        value = expression.get("name") or expression.get("field")
        if value == member:
            return True
    return False


def direct_getter_body(
    declaration: dict[str, Any],
    *,
    member_name: str,
) -> dict[str, Any] | None:
    members = declaration.get("members")
    if not isinstance(members, list):
        return None
    matching_members = [
        member
        for member in members
        if isinstance(member, dict)
        and member.get("_kind") == "var_decl"
        and declaration_name(member) == member_name
    ]
    if len(matching_members) != 1:
        return None
    accessors = matching_members[0].get("accessors")
    if not isinstance(accessors, list):
        return None
    getter_bodies = [
        accessor.get("body")
        for accessor in accessors
        if isinstance(accessor, dict)
        and accessor.get("get") is True
        and isinstance(accessor.get("body"), dict)
        and accessor["body"].get("_kind") == "brace_stmt"
    ]
    return getter_bodies[0] if len(getter_bodies) == 1 else None


def brace_elements(body: dict[str, Any] | None) -> list[dict[str, Any]]:
    if body is None:
        return []
    elements = body.get("elements")
    if not isinstance(elements, list):
        return []
    return [element for element in elements if isinstance(element, dict)]


def top_level_expression(statement: dict[str, Any]) -> dict[str, Any] | None:
    if statement.get("_kind") != "return_stmt":
        return statement
    for key in ("result", "expr"):
        value = statement.get(key)
        if isinstance(value, dict):
            return value
    return None


def call_chain(expression: dict[str, Any] | None) -> Iterator[dict[str, Any]]:
    current = expression
    while isinstance(current, dict) and current.get("_kind") == "call_expr":
        yield current
        function = current.get("fn")
        if (
            not isinstance(function, dict)
            or function.get("_kind") != "unresolved_dot_expr"
            or not isinstance(function.get("base"), dict)
        ):
            return
        current = function["base"]


def member_call_name(node: dict[str, Any]) -> str | None:
    if node.get("_kind") != "call_expr":
        return None
    function = node.get("fn")
    if not isinstance(function, dict) or function.get("_kind") != "unresolved_dot_expr":
        return None
    field = function.get("field")
    return field if isinstance(field, str) else None


def closure_body_elements(call: dict[str, Any]) -> Iterator[dict[str, Any]]:
    arguments = call.get("args")
    if not isinstance(arguments, dict):
        return
    values = arguments.get("args")
    if not isinstance(values, list):
        return
    for argument in values:
        if not isinstance(argument, dict):
            continue
        expression = argument.get("expr")
        if (
            not isinstance(expression, dict)
            or expression.get("_kind") != "closure_expr"
        ):
            continue
        body = expression.get("body")
        if isinstance(body, dict):
            yield from brace_elements(body)


def validate_swift_source(source: str, source_name: str) -> list[str]:
    result = subprocess.run(
        [
            "swiftc",
            "-frontend",
            "-parse",
            "-enable-bare-slash-regex",
            "-",
        ],
        cwd=ROOT,
        input=source,
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode == 0:
        return []
    detail = next(
        (line.strip() for line in result.stderr.splitlines() if line.strip()),
        f"swiftc exited {result.returncode}",
    )
    return [f"{source_name}: Swift parser failed: {detail}"]


def parse_swift_source(source: str, source_name: str) -> tuple[Any | None, list[str]]:
    result = subprocess.run(
        [
            "swiftc",
            "-frontend",
            "-dump-parse",
            "-dump-ast-format",
            "json",
            "-enable-bare-slash-regex",
            "-",
        ],
        cwd=ROOT,
        input=source,
        check=False,
        capture_output=True,
        text=True,
    )
    if result.returncode != 0:
        detail = next(
            (line.strip() for line in result.stderr.splitlines() if line.strip()),
            f"swiftc exited {result.returncode}",
        )
        return None, [f"{source_name}: Swift parser failed: {detail}"]
    try:
        return json.loads(result.stdout), []
    except json.JSONDecodeError as error:
        return None, [f"{source_name}: Swift parser returned invalid JSON: {error}"]


def verify_mac_new_item_command(source: str, source_name: str) -> list[str]:
    """Require the Mac command set to replace, and never append after, New Window.

    The parser omits conditional-compilation bodies in parse-only mode, so the
    directive lines are removed before parsing. The compiler still supplies the
    syntax tree used below; comments and string lookalikes cannot satisfy it.
    """
    expanded_source = expose_all_swift_conditional_branches(source)
    ast, errors = parse_swift_source(expanded_source, source_name)
    if ast is None:
        return errors

    structs = [
        node
        for node in swift_ast_nodes(ast)
        if node.get("_kind") == "struct_decl"
    ]
    app_structs = [
        node for node in structs if declaration_name(node) == "SubscriptionManagerApp"
    ]
    command_structs = [
        node for node in structs if declaration_name(node) == "MacWindowCommands"
    ]

    install_count = 0
    if len(app_structs) == 1:
        app_body = direct_getter_body(app_structs[0], member_name="body")
        for statement in brace_elements(app_body):
            for call in call_chain(top_level_expression(statement)):
                if member_call_name(call) != "commands":
                    continue
                installed_commands = sum(
                    call_name(top_level_expression(element))
                    == "MacWindowCommands"
                    for element in closure_body_elements(call)
                )
                if installed_commands == 1:
                    install_count += 1

    replacement_count = 0
    appended_count = 0
    if len(command_structs) == 1:
        commands_body = direct_getter_body(
            command_structs[0],
            member_name="body",
        )
        for statement in brace_elements(commands_body):
            for call in call_chain(top_level_expression(statement)):
                if call_name(call) != "CommandGroup":
                    continue
                if call_has_member_argument(
                    call,
                    label="replacing",
                    member="newItem",
                ):
                    replacement_count += 1
                if call_has_member_argument(
                    call,
                    label="after",
                    member="newItem",
                ):
                    appended_count += 1

    errors = []
    if install_count != 1:
        errors.append(
            f"{source_name}: SubscriptionManagerApp installs MacWindowCommands "
            f"exactly once; found {install_count}"
        )
    if replacement_count != 1:
        errors.append(
            f"{source_name}: macOS commands require exactly one "
            f"CommandGroup(replacing: .newItem); found {replacement_count}"
        )
    if appended_count:
        errors.append(
            f"{source_name}: CommandGroup(after: .newItem) is forbidden; "
            f"found {appended_count}"
        )
    return errors


def verify_swift_policy(source: str, source_name: str) -> list[str]:
    if swift_conditional_directive_lines(source):
        errors = validate_swift_source(source, source_name)
        if errors:
            return errors
        counts, errors = swift_policy_counts_in_all_conditional_branches(
            source,
            source_name,
        )
        if counts is None:
            return errors
    else:
        ast, errors = parse_swift_source(source, source_name)
        if ast is None:
            return errors
        counts = swift_policy_counts(ast)

    force_try_count, string_decoding_count = counts
    errors = []
    if force_try_count:
        errors.append(
            f"{source_name}: force try expressions: at least "
            f"{force_try_count} in a compiler-parsed variant"
        )
    if string_decoding_count:
        errors.append(
            f"{source_name}: lossy UTF-8 decoding uses: at least "
            f"{string_decoding_count} in a compiler-parsed variant"
        )
    return errors


def verify_source(path: Path) -> list[str]:
    relative = display_path(path)
    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError as error:
        return [f"{relative}: {error}"]

    errors: list[str] = []
    conflict = re.search(r"^(<<<<<<<|=======|>>>>>>>)", text, re.MULTILINE)
    if conflict:
        errors.append(
            f"{relative}:{line_number(text, conflict.start())}: merge-conflict marker"
        )
    if path.suffix == ".swift":
        errors.extend(verify_swift_policy(text, relative))
    if path == MAC_APP_SOURCE:
        errors.extend(verify_mac_new_item_command(text, relative))
    return errors


def main() -> int:
    errors: list[str] = []
    files = repository_files()
    for path in files:
        if path.suffix in STRUCTURED_SUFFIXES:
            errors.extend(verify_structured_file(path))
        if path.suffix in {".swift", ".md", ".yml", ".yaml", ".py"}:
            errors.extend(verify_source(path))

    if errors:
        print("repository verification failed:", file=sys.stderr)
        for error in errors:
            print(f"- {error}", file=sys.stderr)
        return 1

    structured_count = sum(
        path.suffix in STRUCTURED_SUFFIXES
        for path in files
    )
    print(
        "repository verification passed: "
        f"files={len(files)} structured={structured_count}"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
