#!/usr/bin/env python3
"""Add the HUD frame-timing files to both native targets of Moonlight.xcodeproj.

New files:
  Limelight/Stream/FrameStatsRecorder.h/.m            -> "Stream" group
  Limelight/ViewControllers/FrameTimeGraphView.h/.m   -> "ViewControllers" group

Both .m files must be compiled by the iOS target ("Moonlight") and the tvOS
target ("Moonlight TV"), which have separate PBXSourcesBuildPhase sections.

The script is idempotent-safe in the sense that it aborts if an anchor is
missing, and it is only meant to run once on a pristine project file.
"""
import sys

PBX = "Moonlight.xcodeproj/project.pbxproj"

# target name -> its PBXSourcesBuildPhase uuid
SOURCES_PHASES = {
    "moonlight-ios": "FB290CEA19B2C406004C83CF",   # target "Moonlight"
    "moonlight-tv": "FB1A674F2132419700507771",   # target "Moonlight TV"
}

FSR_H = "C0FFEE000000000000000001"
FSR_M = "C0FFEE000000000000000002"
FTG_H = "C0FFEE000000000000000003"
FTG_M = "C0FFEE000000000000000004"

# build file uuid -> (file ref uuid, filename, target key)
BUILD_FILES = {
    "C0FFEE0000000000000000B1": (FSR_M, "FrameStatsRecorder.m", "moonlight-ios"),
    "C0FFEE0000000000000000B2": (FSR_M, "FrameStatsRecorder.m", "moonlight-tv"),
    "C0FFEE0000000000000000B3": (FTG_M, "FrameTimeGraphView.m", "moonlight-ios"),
    "C0FFEE0000000000000000B4": (FTG_M, "FrameTimeGraphView.m", "moonlight-tv"),
}


def die(msg):
    sys.exit("ERROR: " + msg)


def insert_after_line(text, needle, payload, count=1):
    """Insert payload right after every matching line (exactly `count` of them)."""
    lines = text.split("\n")
    out = []
    hits = 0
    for line in lines:
        out.append(line)
        if hits < count and needle in line:
            out.append(payload)
            hits += 1
    if hits < count:
        die("anchor not found: %r" % needle)
    return "\n".join(out)


def insert_at_top_of_build_file_section(text, payload):
    marker = "/* Begin PBXBuildFile section */\n"
    if marker not in text:
        die("PBXBuildFile section not found")
    return text.replace(marker, marker + payload, 1)


def add_to_sources_phase(text, phase_uuid, payload):
    lines = text.split("\n")
    for i, line in enumerate(lines):
        if line.strip().startswith(phase_uuid + " /* Sources */ = {"):
            for j in range(i, len(lines)):
                if lines[j].strip() == "files = (":
                    for k in range(j + 1, len(lines)):
                        if lines[k].strip() == ");":
                            lines.insert(k, payload)
                            return "\n".join(lines)
                    die("end of files list not found in phase " + phase_uuid)
            die("'files = (' not found in phase " + phase_uuid)
    die("sources phase not found: " + phase_uuid)


def file_ref(uuid, name, kind):
    return ("\t\t{uuid} /* {name} */ = {{isa = PBXFileReference; fileEncoding = 4; "
            "lastKnownFileType = sourcecode.c.{kind}; path = {name}; "
            "sourceTree = \"<group>\"; }};").format(uuid=uuid, name=name, kind=kind)


def main():
    with open(PBX, "r", encoding="utf-8") as fh:
        text = fh.read()

    for uuid in (FSR_H, FSR_M, FTG_H, FTG_M) + tuple(BUILD_FILES):
        if uuid in text:
            die("uuid already present, refusing to run twice: " + uuid)

    # ------------------------------------------------------------- file refs
    text = insert_after_line(
        text,
        "FB89461D19F646E200339C8A /* VideoDecoderRenderer.m */ = {isa = PBXFileReference;",
        file_ref(FSR_H, "FrameStatsRecorder.h", "h") + "\n"
        + file_ref(FSR_M, "FrameStatsRecorder.m", "objc"),
    )
    text = insert_after_line(
        text,
        "FB89462719F646E200339C8A /* StreamFrameViewController.m */ = {isa = PBXFileReference;",
        file_ref(FTG_H, "FrameTimeGraphView.h", "h") + "\n"
        + file_ref(FTG_M, "FrameTimeGraphView.m", "objc"),
    )

    # ----------------------------------------------------------- build files
    build_lines = []
    for bf_uuid in sorted(BUILD_FILES):
        ref_uuid, name, _target = BUILD_FILES[bf_uuid]
        build_lines.append(
            "\t\t{uuid} /* {name} in Sources */ = {{isa = PBXBuildFile; "
            "fileRef = {ref} /* {name} */; }};".format(uuid=bf_uuid, ref=ref_uuid, name=name)
        )
    text = insert_at_top_of_build_file_section(text, "\n".join(build_lines) + "\n")

    # ---------------------------------------------------------------- groups
    text = insert_after_line(
        text,
        "FB89461D19F646E200339C8A /* VideoDecoderRenderer.m */,",
        "\t\t\t\t%s /* FrameStatsRecorder.h */,\n"
        "\t\t\t\t%s /* FrameStatsRecorder.m */," % (FSR_H, FSR_M),
    )
    text = insert_after_line(
        text,
        "FB89462719F646E200339C8A /* StreamFrameViewController.m */,",
        "\t\t\t\t%s /* FrameTimeGraphView.h */,\n"
        "\t\t\t\t%s /* FrameTimeGraphView.m */," % (FTG_H, FTG_M),
    )

    # -------------------------------------------------------- sources phases
    for bf_uuid in sorted(BUILD_FILES):
        _ref_uuid, name, target = BUILD_FILES[bf_uuid]
        text = add_to_sources_phase(
            text,
            SOURCES_PHASES[target],
            "\t\t\t\t%s /* %s in Sources */," % (bf_uuid, name),
        )

    with open(PBX, "w", encoding="utf-8") as fh:
        fh.write(text)
    print("pbxproj updated")


main()
