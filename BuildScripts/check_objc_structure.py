#!/usr/bin/env python3
"""Lightweight structural check for Objective-C sources.

No iOS SDK / clang is available here, so this only catches the mistakes a human
review might miss: unbalanced braces/parens/brackets and @interface /
@implementation / @end mismatches. Strings, chars and comments are stripped first.
"""
import re
import sys

FILES = [
    "Limelight/Stream/FrameStatsRecorder.h",
    "Limelight/Stream/FrameStatsRecorder.m",
    "Limelight/ViewControllers/FrameTimeGraphView.h",
    "Limelight/ViewControllers/FrameTimeGraphView.m",
    "Limelight/Stream/VideoDecoderRenderer.h",
    "Limelight/Stream/VideoDecoderRenderer.m",
    "Limelight/Stream/Connection.m",
    "Limelight/Stream/StreamManager.h",
    "Limelight/Database/TemporarySettings.h",
    "Limelight/Database/TemporarySettings.m",
    "Limelight/Database/DataManager.h",
    "Limelight/Database/DataManager.m",
    "Limelight/ViewControllers/SettingsViewController.h",
    "Limelight/ViewControllers/SettingsViewController.m",
    "Limelight/ViewControllers/MainFrameViewController.m",
    "Limelight/Stream/StreamConfiguration.h",
    "Limelight/Stream/StreamManager.m",
    "Limelight/ViewControllers/StreamFrameViewController.m",
]


def strip_code(text):
    out = []
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        nxt = text[i + 1] if i + 1 < n else ""
        if c == "/" and nxt == "/":
            i = text.find("\n", i)
            if i < 0:
                break
            continue
        if c == "/" and nxt == "*":
            j = text.find("*/", i + 2)
            i = n if j < 0 else j + 2
            continue
        if c == '"':
            i += 1
            while i < n and text[i] != '"':
                i += 2 if text[i] == "\\" else 1
            i += 1
            continue
        if c == "'":
            i += 1
            while i < n and text[i] != "'":
                i += 2 if text[i] == "\\" else 1
            i += 1
            continue
        out.append(c)
        i += 1
    return "".join(out)


problems = []
for path in FILES:
    try:
        raw = open(path, encoding="utf-8").read()
    except FileNotFoundError:
        problems.append("%s: missing" % path)
        continue
    code = strip_code(raw)
    for open_c, close_c in (("{", "}"), ("(", ")"), ("[", "]")):
        if code.count(open_c) != code.count(close_c):
            problems.append("%s: %s/%s mismatch (%d vs %d)"
                            % (path, open_c, close_c, code.count(open_c), code.count(close_c)))
    if_count = len(re.findall(r"^\s*@interface\b", code, re.M))
    impl_count = len(re.findall(r"^\s*@implementation\b", code, re.M))
    end_count = len(re.findall(r"^\s*@end\b", code, re.M))
    if if_count + impl_count != end_count:
        problems.append("%s: @interface+@implementation=%d but @end=%d"
                        % (path, if_count + impl_count, end_count))
    if not raw.endswith("\n"):
        problems.append("%s: no trailing newline" % path)

if problems:
    print("FAIL")
    for p in problems:
        print("  - " + p)
    sys.exit(1)
print("OK: %d Objective-C files balanced" % len(FILES))
