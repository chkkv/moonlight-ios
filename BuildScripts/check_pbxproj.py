#!/usr/bin/env python3
"""Sanity check Moonlight.xcodeproj/project.pbxproj after a scripted edit.

Xcode is not available in this environment, so instead of a real parse we check
the structural invariants that a broken hand edit would violate:
  * balanced braces / parentheses and an even number of double quotes
  * every object reference resolves, and object ids are defined exactly once
  * the new HUD files are wired into exactly the expected objects

Usage: check_pbxproj.py [path/to/project.pbxproj] [--baseline]
`--baseline` skips the checks that are specific to the new HUD files.
"""
import re
import sys
from collections import Counter

UUID_RE = re.compile(r"\b([0-9A-F]{24})\b")
# An object definition: "<uuid> /* comment */ = {" followed by "isa = <Type>;"
# on the same line or on the next one (Xcode wraps long build file entries).
DEF_RE = re.compile(r"\b([0-9A-F]{24})\b[^\n=]*=\s*\{\s*(?:\n\s*)?isa = (\w+);")
# remoteGlobalIDString points at targets that live in a subproject.
REMOTE_RE = re.compile(r"remoteGlobalIDString = ([0-9A-F]{24});")

NEW = {
    "C0FFEE000000000000000001": "FrameStatsRecorder.h",
    "C0FFEE000000000000000002": "FrameStatsRecorder.m",
    "C0FFEE000000000000000003": "FrameTimeGraphView.h",
    "C0FFEE000000000000000004": "FrameTimeGraphView.m",
    "C0FFEE0000000000000000B1": "FrameStatsRecorder.m build (iOS)",
    "C0FFEE0000000000000000B2": "FrameStatsRecorder.m build (tvOS)",
    "C0FFEE0000000000000000B3": "FrameTimeGraphView.m build (iOS)",
    "C0FFEE0000000000000000B4": "FrameTimeGraphView.m build (tvOS)",
}

args = [a for a in sys.argv[1:] if not a.startswith("--")]
baseline = "--baseline" in sys.argv
PBX = args[0] if args else "Moonlight.xcodeproj/project.pbxproj"

problems = []
text = open(PBX, encoding="utf-8").read()

# --- 1. balance -------------------------------------------------------------
if text.count("{") != text.count("}"):
    problems.append("brace mismatch: %d { vs %d }" % (text.count("{"), text.count("}")))
if text.count("(") != text.count(")"):
    problems.append("paren mismatch: %d ( vs %d )" % (text.count("("), text.count(")")))
if text.count('"') % 2 != 0:
    problems.append("odd number of double quotes")

# --- 2. object graph --------------------------------------------------------
defs = DEF_RE.findall(text)
defined = {u for u, _t in defs}
dupes = sorted(u for u, c in Counter(u for u, _t in defs).items() if c > 1)
if dupes:
    problems.append("duplicate object definitions: %s" % dupes)

external = set(REMOTE_RE.findall(text))
undefined = sorted(set(UUID_RE.findall(text)) - defined - external)
if undefined:
    problems.append("referenced but undefined: %s" % undefined)

# --- 3. expected placement of the new .m files -----------------------------
src_phases = {}
for m in re.finditer(
        r"([0-9A-F]{24}) /\* Sources \*/ = \{\s*isa = PBXSourcesBuildPhase;(.*?)\n\t\t\};",
        text, re.S):
    src_phases[m.group(1)] = m.group(2)

if len(src_phases) != 2:
    problems.append("expected 2 PBXSourcesBuildPhase sections, found %d" % len(src_phases))

if not baseline:
    for uuid, label in NEW.items():
        if uuid not in defined:
            problems.append("new object not defined: %s (%s)" % (uuid, label))

    for phase, body in src_phases.items():
        for name in ("FrameStatsRecorder.m", "FrameTimeGraphView.m"):
            if body.count("/* %s in Sources */" % name) != 1:
                problems.append("phase %s: %s referenced %d times" %
                                (phase, name, body.count("/* %s in Sources */" % name)))
        for name in ("FrameStatsRecorder.h", "FrameTimeGraphView.h"):
            if name in body:
                problems.append("phase %s compiles a header: %s" % (phase, name))

    for name in NEW.values():
        pass
    for name in ("FrameStatsRecorder.h", "FrameStatsRecorder.m",
                 "FrameTimeGraphView.h", "FrameTimeGraphView.m"):
        if text.count("path = %s;" % name) != 1:
            problems.append("file reference for %s defined %d times" %
                            (name, text.count("path = %s;" % name)))

if problems:
    print("FAIL (%s)" % PBX)
    for p in problems:
        print("  - " + p)
    sys.exit(1)

print("OK (%s): %d objects, %d phases, all references resolve"
      % (PBX, len(defined), len(src_phases)))
