#!/usr/bin/env python3
"""Prevent host-Lua NaN construction from entering WoW-loaded test fixtures."""
from pathlib import Path
import re

ROOT = Path(__file__).resolve().parents[1]
LONG_OPEN = re.compile(r"\[(=*)\[")
ZERO = r"(?:0[xX]0+(?:\.0*)?(?:[pP][+-]?\d+)?|(?:0+(?:\.0*)?|\.0+)(?:[eE][+-]?\d+)?)(?![\w.])"
DENOMINATOR = ZERO
for _ in range(4):
    DENOMINATOR = rf"[+-]?\s*(?:{ZERO}|\(\s*{DENOMINATOR}\s*\))"
ZERO_DIVISION = re.compile(r"(?<!/)/(?!/)\s*" + DENOMINATOR)


def executable_source(source):
    """Blank Lua comments and literals while preserving source line numbers."""
    output = list(source)
    cursor = 0
    while cursor < len(source):
        start = cursor
        comment = source.startswith("--", cursor)
        if comment:
            cursor += 2
        long = LONG_OPEN.match(source, cursor)
        if long:
            close = "]" + long.group(1) + "]"
            end = source.find(close, long.end())
            cursor = len(source) if end < 0 else end + len(close)
        elif comment:
            end = source.find("\n", cursor)
            cursor = len(source) if end < 0 else end
        elif source[cursor] in "\"'":
            quote = source[cursor]
            cursor += 1
            while cursor < len(source):
                character = source[cursor]
                cursor += 1
                if character == "\\":
                    cursor += 1
                elif character == quote:
                    break
        else:
            cursor += 1
            continue
        for index in range(start, min(cursor, len(source))):
            if output[index] not in "\r\n":
                output[index] = " "
    return "".join(output)


def violations(source):
    clean = executable_source(source)
    return [clean.count("\n", 0, match.start()) + 1 for match in ZERO_DIVISION.finditer(clean)]


def check(root=ROOT, source_overrides=None):
    root = Path(root)
    overrides = source_overrides or {}
    errors, count = [], 0
    for line in (root / "QuestTogether.toc").read_text().splitlines():
        name = line.strip().replace("\\", "/")
        if name != "Tests.lua" and not (name.startswith("scripts/") and name.endswith(".lua")):
            continue
        count += 1
        source = overrides.get(name)
        if source is None:
            source = (root / name).read_text()
        for number in violations(source):
            errors.append(f"{name}:{number}: zero-division numeric fixtures must remain offline")
    if errors:
        raise ValueError("\n".join(errors))
    return count


if __name__ == "__main__":
    print(f"Live numeric fixtures verified across {check()} manifest test modules")
