#!/usr/bin/env python3
"""Add the custom control overlay files to Moonlight.xcodeproj.

New files:
  Limelight/Input/CustomLayoutDocument.h/.m             -> "Input" group
  Limelight/Input/CustomControlsView.h/.m               -> "Input" group
  Limelight/Database/TemporaryCustomLayout.h/.m         -> "Database" group
  Limelight/ViewControllers/CustomLayoutListViewController.h/.m     -> "ViewControllers"
  Limelight/ViewControllers/CustomControlsEditorViewController.h/.m -> "ViewControllers"

Only the UI is iOS-only: tvOS has no touch screen, so CustomControlsView and the
two view controllers are compiled into the "Moonlight" target only.

The model, codec and CoreData wrapper ARE added to both targets. DataManager.m
is built for both and uses TemporaryCustomLayout, so leaving it out of the tvOS
target would be an undefined symbol at link time. They are platform-neutral and
the tvOS settings bundle never turns the overlay on, so customOverlayEnabled
stays NO there and isCustomOverlayActive short-circuits.

The group anchors matter. The "Input" and "ViewControllers" groups carry a
`path`, so their children use a bare `path = <name>`. The "Database" group has
only a `name`, so its children need `name` plus `path = Database/<name>`.

Aborts if the generated UUIDs are already present, so a double run is detected
instead of corrupting the project file.
"""
import sys

PBX = "Moonlight.xcodeproj/project.pbxproj"

# PBXSourcesBuildPhase of the "Moonlight" (iOS) and "Moonlight TV" targets.
IOS_SOURCES_PHASE = "FB290CEA19B2C406004C83CF"
TVOS_SOURCES_PHASE = "FB1A674F2132419700507771"


def uuid(tag):
    """A stable 24 hex digit id in a private range (CA5E...) for this feature."""
    return "CA5E%020X" % tag


def target_phases(targets, kind):
    """The PBXSourcesBuildPhase ids that compile a file. Headers compile nowhere."""
    if kind == "h":
        return []
    if targets == "shared":
        return [IOS_SOURCES_PHASE, TVOS_SOURCES_PHASE]
    if targets == "ui":
        return [IOS_SOURCES_PHASE]
    return []


# tag, filename, group, lastKnownFileType, targets ("ui" = iOS only,
# "shared" = both targets)
FILES = [
    (0x01, "CustomLayoutDocument.h", "input", "h", "shared"),
    (0x02, "CustomLayoutDocument.m", "input", "objc", "shared"),
    (0x03, "CustomControlsView.h", "input", "h", "ui"),
    (0x04, "CustomControlsView.m", "input", "objc", "ui"),
    (0x05, "TemporaryCustomLayout.h", "database", "h", "shared"),
    (0x06, "TemporaryCustomLayout.m", "database", "objc", "shared"),
    (0x07, "CustomLayoutListViewController.h", "viewcontrollers", "h", "ui"),
    (0x08, "CustomLayoutListViewController.m", "viewcontrollers", "objc", "ui"),
    (0x09, "CustomControlsEditorViewController.h", "viewcontrollers", "h", "ui"),
    (0x0A, "CustomControlsEditorViewController.m", "viewcontrollers", "objc", "ui"),
]

GROUPS = {
    "input": {
        "ref_anchor": "FB4678EC1A50C40900377732 /* OnScreenControls.m */ = {isa = PBXFileReference;",
        "child_anchor": "FB4678EC1A50C40900377732 /* OnScreenControls.m */,",
        "ref_template": ("\t\t{uuid} /* {name} */ = {{isa = PBXFileReference; fileEncoding = 4; "
                         "lastKnownFileType = sourcecode.c.{kind}; path = {name}; "
                         "sourceTree = \"<group>\"; }};"),
    },
    "database": {
        "ref_anchor": "98D5856F1C0ED0E800F6CC00 /* TemporarySettings.m */ = {isa = PBXFileReference;",
        "child_anchor": "98D5856F1C0ED0E800F6CC00 /* TemporarySettings.m */,",
        "ref_template": ("\t\t{uuid} /* {name} */ = {{isa = PBXFileReference; fileEncoding = 4; "
                         "lastKnownFileType = sourcecode.c.{kind}; name = {name}; "
                         "path = Database/{name}; sourceTree = \"<group>\"; }};"),
    },
    "viewcontrollers": {
        "ref_anchor": "FB89462719F646E200339C8A /* StreamFrameViewController.m */ = {isa = PBXFileReference;",
        "child_anchor": "FB89462719F646E200339C8A /* StreamFrameViewController.m */,",
        "ref_template": ("\t\t{uuid} /* {name} */ = {{isa = PBXFileReference; fileEncoding = 4; "
                         "lastKnownFileType = sourcecode.c.{kind}; path = {name}; "
                         "sourceTree = \"<group>\"; }};"),
    },
}

# Build file ids start here; one per compiled file.
BUILD_TAG_BASE = 0xB1

# --- CoreData model version -------------------------------------------------
# Xcode takes the compiled model version from the XCVersionGroup's currentVersion
# inside the pbxproj. Updating .xccurrentversion alone is NOT enough: if they
# disagree the build silently compiles the previous model, and the only symptom
# is missing generated properties much later, while compiling TemporarySettings.m
# ("property 'customOverlayEnabled' not found on object of type 'Settings *'")
# and a missing CustomLayout+CoreDataClass.h. check_pbxproj.py now cross-checks
# the two so this cannot regress silently.
NEW_MODEL_UUID = "C0FFEE000000000000000012"
NEW_MODEL_NAME = "Moonlight v1.12.xcdatamodel"
PREVIOUS_MODEL_UUID = "C0FFEE000000000000000011"
PREVIOUS_MODEL_NAME = "Moonlight v1.11.xcdatamodel"
MODEL_REF_ANCHOR = PREVIOUS_MODEL_UUID + " /* " + PREVIOUS_MODEL_NAME + " */ = {isa = PBXFileReference;"
MODEL_CHILD_ANCHOR = PREVIOUS_MODEL_UUID + " /* " + PREVIOUS_MODEL_NAME + " */,"
MODEL_CURRENT_ANCHOR = "currentVersion = " + PREVIOUS_MODEL_UUID


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


def main():
    with open(PBX, "r", encoding="utf-8") as fh:
        text = fh.read()

    all_uuids = [uuid(tag) for tag, _n, _g, _k, _t in FILES]
    # Each compiled file needs one PBXBuildFile per target it joins.
    build_uuids = {}
    next_build_tag = BUILD_TAG_BASE
    for tag, _name, _group, _kind, targets in FILES:
        phases = target_phases(targets, _kind)
        if not phases:
            continue
        build_uuids[tag] = []
        for _phase in phases:
            build_uuids[tag].append(uuid(next_build_tag))
            all_uuids.append(uuid(next_build_tag))
            next_build_tag += 1

    for candidate in all_uuids:
        if candidate in text:
            die("uuid already present, refusing to run twice: " + candidate)
    if NEW_MODEL_UUID in text:
        die("model version uuid already present, refusing to run twice: " + NEW_MODEL_UUID)

    # ------------------------------------------------ CoreData model version
    # Register the new .xcdatamodel in the version group and make it current.
    text = insert_after_line(
        text,
        MODEL_REF_ANCHOR,
        ('\t\t{uuid} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = wrapper.xcdatamodel; '
         'path = "{name}"; sourceTree = "<group>"; }};').format(uuid=NEW_MODEL_UUID, name=NEW_MODEL_NAME))
    text = insert_after_line(
        text,
        MODEL_CHILD_ANCHOR,
        '\t\t\t\t{uuid} /* {name} */,'.format(uuid=NEW_MODEL_UUID, name=NEW_MODEL_NAME))
    if MODEL_CURRENT_ANCHOR not in text:
        die("currentVersion anchor not found (was the previous model removed?)")
    text = text.replace(
        MODEL_CURRENT_ANCHOR + " /* " + PREVIOUS_MODEL_NAME + " */;",
        "currentVersion = {uuid} /* {name} */;".format(uuid=NEW_MODEL_UUID, name=NEW_MODEL_NAME),
        1)

    # ------------------------------------------------------------ file refs
    for group_key, group in GROUPS.items():
        payload = "\n".join(
            group["ref_template"].format(uuid=uuid(tag), name=name, kind=kind)
            for tag, name, gkey, kind, _t in FILES
            if gkey == group_key
        )
        if payload:
            text = insert_after_line(text, group["ref_anchor"], payload)

    # ---------------------------------------------------------- build files
    build_lines = []
    for tag, name, _group, _kind, _targets in FILES:
        for build_uuid in build_uuids.get(tag, []):
            build_lines.append(
                "\t\t{uuid} /* {name} in Sources */ = {{isa = PBXBuildFile; "
                "fileRef = {ref} /* {name} */; }};".format(
                    uuid=build_uuid, ref=uuid(tag), name=name)
            )
    text = insert_at_top_of_build_file_section(text, "\n".join(build_lines) + "\n")

    # --------------------------------------------------------------- groups
    for group_key, group in GROUPS.items():
        children = "\n".join(
            "\t\t\t\t{uuid} /* {name} */,".format(uuid=uuid(tag), name=name)
            for tag, name, gkey, _kind, _t in FILES
            if gkey == group_key
        )
        if children:
            text = insert_after_line(text, group["child_anchor"], children)

    # -------------------------------------------------------- sources phase
    for tag, name, _group, _kind, targets in FILES:
        for phase_uuid, build_uuid in zip(target_phases(targets, _kind), build_uuids.get(tag, [])):
            text = add_to_sources_phase(
                text,
                phase_uuid,
                "\t\t\t\t{uuid} /* {name} in Sources */,".format(uuid=build_uuid, name=name),
            )

    with open(PBX, "w", encoding="utf-8") as fh:
        fh.write(text)

    ios_count = sum(1 for _t, _n, _g, k, _tg in FILES if k != "h")
    tvos_count = sum(1 for _t, _n, _g, k, tg in FILES if k != "h" and tg == "shared")
    print("pbxproj updated: %d files, %d build entries (%d iOS, %d tvOS)"
          % (len(FILES), sum(len(v) for v in build_uuids.values()), ios_count, tvos_count))


main()
