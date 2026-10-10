#!/usr/bin/env python3
"""Offline XML/engine-boundary checks; never loaded by the live /qt tests."""

import argparse
from pathlib import Path
import re
import subprocess
import xml.etree.ElementTree as ET


ROOT = Path(__file__).resolve().parents[1]
CATEGORY = "BINDING_HEADER_QUESTTOGETHER"
EXPECTED = {
    "QUESTTOGETHER_PARTY_LOG": ("party_log", "Toggle Party Quest Log"),
    "QUESTTOGETHER_MENU": ("menu", "Open QuestTogether menu"),
    "QUESTTOGETHER_QUEST_PARTNERS": ("quest_partners", "Toggle Looking for Questing Partners"),
    "QUESTTOGETHER_STOP_FOLLOW": ("stop_follow", "Stop following quest focus"),
    "QUESTTOGETHER_CHAT": ("chat", "Open QuestTogether chat"),
    "QUESTTOGETHER_SETTINGS": ("settings", "Open QuestTogether settings"),
}


def lua_string(text):
    delimiter = "="
    while "]" + delimiter + "]" in text:
        delimiter += "="
    return "[" + delimiter + "[" + text + "]" + delimiter + "]"


def verify(xml_source, core_source, lua):
    bindings = ET.fromstring(xml_source)
    assert bindings.tag == "Bindings", "expected Bindings XML root"
    rows = list(bindings)
    names = [row.get("name") for row in rows]
    assert len(names) == len(set(names)), "duplicate binding action"
    assert set(names) == set(EXPECTED), "six public binding IDs must remain declared, including the original PQL ID"
    for row in rows:
        assert row.tag == "Binding" and not list(row), "unexpected binding declaration"
        assert row.get("category") == CATEGORY, f"{row.get('name')}: explicit localized category required"
        assert "header" not in row.attrib, "legacy header creates a spurious HEADER action in Forever"
        assert row.get("hidden") not in ("true", "1"), "public action must be visible in Key Bindings"
        if row.get("name") == "QUESTTOGETHER_MENU":
            assert row.get("runOnUp") == "true", "menu must receive key release"
        else:
            assert row.get("runOnUp") in (None, "false"), "ordinary action must not fire on both edges"

    # Evaluate the real display-label declarations, including their L() calls,
    # in the same private environment as the real XML bodies. No Core or native
    # state is bootstrapped, and the production action dispatcher is a spy.
    declarations = re.findall(
        r"^(BINDING_(?:HEADER_QUESTTOGETHER|NAME_QUESTTOGETHER_[A-Z_]+))\s*=([^\r\n]+)$",
        core_source,
        re.MULTILINE,
    )
    declared = [name for name, _ in declarations]
    assert len(declared) == len(set(declared)), "duplicate binding display label"
    assert set(declared) == {CATEGORY, *("BINDING_NAME_" + name for name in EXPECTED)}, "binding labels must match XML IDs"
    labels = "\n".join(name + " = " + value for name, value in declarations)
    program = [
        """
local calls, addon = {}, {}
function addon:HandleKeybinding(action)
    assert(self == addon, 'XML must dispatch on its own addon')
    calls[#calls + 1] = action
end
local env = {QuestTogether = addon, L = function(text) return text end}
local function Compile(source, name)
    if setfenv then
        local body = assert(loadstring(source, name))
        setfenv(body, env)
        return body
    end
    return assert(load(source, name, 't', env))
end
local function CheckCalls(expected, count, name)
    assert(#calls == count, name .. ': wrong number of dispatches')
    for _, action in ipairs(calls) do
        assert(action == expected, name .. ': wrong action dispatched')
    end
end
""",
        "Compile(" + lua_string(labels) + ", '@private-binding-labels')()",
        "assert(env." + CATEGORY + " == 'QuestTogether', 'category label must resolve')",
    ]
    for row in rows:
        name = row.get("name")
        action, label = EXPECTED[name]
        program.extend([
            "assert(env.BINDING_NAME_" + name + " == " + lua_string(label) + ", 'wrong display label: " + name + "')",
            "do local body = Compile(" + lua_string(row.text or "") + ", '@Bindings.xml:" + name + "')",
            "calls = {}",
        ])
        if action == "menu":
            # runOnUp invokes the body on both edges. Repeated down events must
            # not open a menu before the opening controller button is released.
            program.extend([
                "for press = 1, 3 do",
                "    env.keystate = 'down'; body(); body()",
                "    CheckCalls('menu', press - 1, 'menu before release')",
                "    env.keystate = 'up'; body()",
                "    CheckCalls('menu', press, 'menu after release')",
                "end",
            ])
        else:
            program.extend([
                "env.keystate = 'down'; body()",
                "CheckCalls(" + lua_string(action) + ", 1, " + lua_string(name) + ")",
            ])
        program.append("end")
    result = subprocess.run([lua, "-"], input="\n".join(program), text=True, capture_output=True)
    assert result.returncode == 0, result.stderr or result.stdout


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("lua", nargs="?", default="lua", help="Lua 5.1 or 5.2 executable")
    parser.add_argument("--root", type=Path, default=ROOT)
    args = parser.parse_args()
    verify((args.root / "Bindings.xml").read_text(), (args.root / "Core.lua").read_text(), args.lua)
    print("Bindings: six actions, localized category/labels, preserved IDs and release-only menu dispatch passed")


if __name__ == "__main__":
    main()
