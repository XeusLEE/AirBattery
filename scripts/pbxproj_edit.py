#!/usr/bin/env python3
"""Line-level editor for AirBattery.xcodeproj/project.pbxproj (standard library only).

Usage (run from the repository root):

  python3 scripts/pbxproj_edit.py add-source <repo-relative .swift path> --group <GroupName>
      Adds the file to the AirBattery app target. If no PBXGroup named <GroupName>
      exists, one is created (name only, no path) under the "AirBattery" group and the
      file reference uses `sourceTree = SOURCE_ROOT; path = <repo-relative path>`.
      If the group exists and has a `path` (ViewModel, BatteryInfo, ...), the file
      must live in that group's directory and the reference uses
      `sourceTree = "<group>"; path = <file name>`.

  python3 scripts/pbxproj_edit.py add-localization <lang> --variant Localizable.strings|InfoPlist.strings
      Adds `<lang>.lproj/<variant>` to the matching PBXVariantGroup and <lang> to the
      project's knownRegions (if missing).

Both commands are idempotent (already present: no change, exit 0), generate unique
24-character uppercase hex object IDs, only insert lines into the existing section
blocks (nothing else is reformatted), and finish with `plutil -lint`; if the result
is not a valid plist the original bytes are restored and the exit status is 1.
Exit status 2 means the request itself was invalid (nothing was written).

`--project <path>` (after the subcommand) edits another pbxproj file, e.g. a copy.
"""
import argparse
import posixpath
import re
import secrets
import subprocess
import sys
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
DEFAULT_PROJECT = REPO_ROOT / "AirBattery.xcodeproj" / "project.pbxproj"

AIRBATTERY_GROUP = "1841D44D2AA6071C0022A1BE"  # PBXGroup "AirBattery"
APP_SOURCES_PHASE = "1841D4472AA6071C0022A1BE"  # PBXSourcesBuildPhase of the AirBattery target
VARIANT_GROUPS = {
    "Localizable.strings": "1841D47A2AA8DEF20022A1BE",
    "InfoPlist.strings": "189BD5EB2BDE69660056D06C",
}

HEX_ID = r"[0-9A-F]{24}"
OBJECT_END = "\n\t\t};\n"
LIST_END = "\n\t\t\t);\n"


class EditError(Exception):
    """The requested edit cannot be applied; the file is left untouched."""


# --- generic text helpers ----------------------------------------------------

def quote(value):
    """Quote a pbxproj string the way Xcode does: bare when it is a plain token."""
    if re.fullmatch(r"[A-Za-z0-9_.$/]+", value):
        return value
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def unquote(value):
    if len(value) >= 2 and value[0] == value[-1] == '"':
        return value[1:-1].replace('\\"', '"').replace("\\\\", "\\")
    return value


def new_id(text, *taken):
    """A 24-character uppercase hex ID that appears nowhere in the file."""
    while True:
        candidate = secrets.token_hex(12).upper()
        if candidate not in text and candidate not in taken:
            return candidate


def insert_before(text, anchor_line, lines):
    """Insert `lines` (no trailing newlines) before the first line equal to `anchor_line`."""
    needle = "\n" + anchor_line + "\n"
    idx = text.find(needle)
    if idx < 0:
        raise EditError("anchor line not found: %s" % anchor_line)
    return text[: idx + 1] + "\n".join(lines) + "\n" + text[idx + 1:]


def section_text(text, name):
    begin = "/* Begin %s section */\n" % name
    end = "/* End %s section */" % name
    start = text.find(begin)
    stop = text.find(end, start)
    if start < 0 or stop < 0:
        raise EditError("section %s not found" % name)
    return text[start + len(begin): stop]


def find_object(text, obj_id):
    """(start, end) of a multi-line object `\\t\\t<id> /* comment */ = {` ... `\\t\\t};`."""
    m = re.search(r"^\t\t" + obj_id + r"(?: /\* [^\n]* \*/)? = \{\n", text, re.M)
    if not m:
        raise EditError("object %s not found" % obj_id)
    end = text.find(OBJECT_END, m.end())
    if end < 0:
        raise EditError("object %s is not terminated" % obj_id)
    return m.start(), end + len(OBJECT_END)


def object_attr(text, obj_id, key):
    start, end = find_object(text, obj_id)
    m = re.search(r"^\t\t\t" + key + r" = (.*);$", text[start:end], re.M)
    return unquote(m.group(1)) if m else None


def _list_span(text, key, obj_id):
    """Offsets (first entry, end-of-entries) of the `key = (` list, within object obj_id if given."""
    lo, hi = (find_object(text, obj_id) if obj_id else (0, len(text)))
    open_tag = "\t\t\t" + key + " = (\n"
    i = text.find(open_tag, lo, hi)
    if i < 0:
        raise EditError("list %s not found%s" % (key, " in object " + obj_id if obj_id else ""))
    j = text.find(LIST_END, i + len(open_tag) - 1, hi)
    if j < 0:
        raise EditError("list %s is not terminated" % key)
    return i + len(open_tag), j + 1


def list_entries(text, key, obj_id=None):
    """The entry lines of the list, stripped of indentation and trailing comma."""
    start, end = _list_span(text, key, obj_id)
    return [line.strip().rstrip(",") for line in text[start:end].splitlines() if line.strip()]


def append_to_list(text, key, line, obj_id=None):
    """Append `line` (already indented, with trailing comma) as the last entry of the list."""
    _, end = _list_span(text, key, obj_id)
    return text[:end] + line + "\n" + text[end:]


# --- group helpers -----------------------------------------------------------

def find_group_by_name(text, name):
    pattern = (r"^\t\t(" + HEX_ID + r") /\* " + re.escape(name) + r" \*/ = \{\n"
               r"\t\t\tisa = PBXGroup;\n")
    ids = re.findall(pattern, section_text(text, "PBXGroup"), re.M)
    if len(ids) > 1:
        raise EditError("group name %s is ambiguous (%s)" % (name, ", ".join(ids)))
    return ids[0] if ids else None


def parent_group(text, group_id):
    pattern = r"^\t\t(" + HEX_ID + r")(?: /\* [^\n]* \*/)? = \{\n(.*?)\n\t\t\};"
    for m in re.finditer(pattern, section_text(text, "PBXGroup"), re.M | re.S):
        if ("\t\t\t\t" + group_id + " /*") in m.group(2):
            return m.group(1)
    return None


def group_directory(text, group_id):
    """Repo-relative directory of a group, joining the `path` of each ancestor group."""
    parts = []
    while group_id:
        path = object_attr(text, group_id, "path")
        if path:
            parts.insert(0, path)
        group_id = parent_group(text, group_id)
    return "/".join(parts)


# --- commands ----------------------------------------------------------------

def add_source(text, src, group_name):
    src = posixpath.normpath(src.replace("\\", "/"))
    if src.startswith(("/", "../")) or not src.endswith(".swift"):
        raise EditError("expected a repo-relative .swift path, got %s" % src)
    if not (REPO_ROOT / src).is_file():
        raise EditError("%s does not exist under %s" % (src, REPO_ROOT))
    base = posixpath.basename(src)
    child_comment = "/* %s */" % base

    group_id = find_group_by_name(text, group_name)
    if group_id and any(e.endswith(child_comment) for e in list_entries(text, "children", group_id)):
        return text, "no change: %s is already in group %s" % (src, group_name)

    if group_id and object_attr(text, group_id, "path") is not None:
        group_dir = group_directory(text, group_id)
        if posixpath.dirname(src) != group_dir:
            raise EditError("%s is not inside the directory of group %s (%s/)"
                            % (src, group_name, group_dir))
        path_value, source_tree = base, '"<group>"'
    else:
        path_value, source_tree = src, "SOURCE_ROOT"

    file_ref = new_id(text)
    build_file = new_id(text, file_ref)
    text = insert_before(text, "/* End PBXBuildFile section */", [
        "\t\t%s /* %s in Sources */ = {isa = PBXBuildFile; fileRef = %s %s; };"
        % (build_file, base, file_ref, child_comment)])
    text = insert_before(text, "/* End PBXFileReference section */", [
        "\t\t%s %s = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; "
        "path = %s; sourceTree = %s; };" % (file_ref, child_comment, quote(path_value), source_tree)])

    child_line = "\t\t\t\t%s %s," % (file_ref, child_comment)
    if group_id:
        text = append_to_list(text, "children", child_line, group_id)
    else:
        group_id = new_id(text, file_ref, build_file)
        text = insert_before(text, "/* End PBXGroup section */", [
            "\t\t%s /* %s */ = {" % (group_id, group_name),
            "\t\t\tisa = PBXGroup;",
            "\t\t\tchildren = (",
            child_line,
            "\t\t\t);",
            "\t\t\tname = %s;" % quote(group_name),
            '\t\t\tsourceTree = "<group>";',
            "\t\t};",
        ])
        text = append_to_list(text, "children", "\t\t\t\t%s /* %s */," % (group_id, group_name),
                              AIRBATTERY_GROUP)

    text = append_to_list(text, "files", "\t\t\t\t%s /* %s in Sources */," % (build_file, base),
                          APP_SOURCES_PHASE)
    return text, "added %s to group %s (fileRef %s, buildFile %s)" % (src, group_name, file_ref, build_file)


def add_localization(text, lang, variant):
    if not re.fullmatch(r"[A-Za-z][A-Za-z0-9_-]*", lang):
        raise EditError("invalid language identifier: %s" % lang)
    variant_group = VARIANT_GROUPS[variant]
    child_comment = "/* %s */" % lang
    if any(e.endswith(child_comment) for e in list_entries(text, "children", variant_group)):
        return text, "no change: %s is already in %s" % (lang, variant)

    file_ref = new_id(text)
    text = insert_before(text, "/* End PBXFileReference section */", [
        '\t\t%s %s = {isa = PBXFileReference; lastKnownFileType = text.plist.strings; '
        'name = "%s"; path = "%s.lproj/%s"; sourceTree = "<group>"; };'
        % (file_ref, child_comment, lang, lang, variant)])
    text = append_to_list(text, "children", "\t\t\t\t%s %s," % (file_ref, child_comment), variant_group)

    regions = [unquote(e) for e in list_entries(text, "knownRegions")]
    region_note = ""
    if lang not in regions:
        text = append_to_list(text, "knownRegions", "\t\t\t\t%s," % quote(lang))
        region_note = ", knownRegions"
    return text, "added %s.lproj/%s to %s (fileRef %s%s)" % (lang, variant, variant, file_ref, region_note)


# --- entry point -------------------------------------------------------------

def main(argv=None):
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--project", type=Path, default=DEFAULT_PROJECT,
                        help="pbxproj file to edit (default: %(default)s)")
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0],
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    sub = parser.add_subparsers(dest="command", required=True)
    p_src = sub.add_parser("add-source", parents=[common],
                           help="compile a .swift file into the AirBattery app target")
    p_src.add_argument("path", help="repo-relative path of the .swift file")
    p_src.add_argument("--group", required=True, help="PBXGroup name (created if missing)")
    p_loc = sub.add_parser("add-localization", parents=[common],
                           help="add <lang>.lproj/<variant> to its variant group and knownRegions")
    p_loc.add_argument("lang", help="language identifier, e.g. tr")
    p_loc.add_argument("--variant", required=True, choices=sorted(VARIANT_GROUPS))
    args = parser.parse_args(argv)

    original = args.project.read_bytes()
    text = original.decode("utf-8")
    try:
        if args.command == "add-source":
            new_text, message = add_source(text, args.path, args.group)
        else:
            new_text, message = add_localization(text, args.lang, args.variant)
    except EditError as exc:
        print("error: %s" % exc, file=sys.stderr)
        return 2

    if new_text == text:
        print(message)
        return 0

    args.project.write_bytes(new_text.encode("utf-8"))
    lint = subprocess.run(["plutil", "-lint", str(args.project)], capture_output=True, text=True)
    if lint.returncode != 0 or ": OK" not in lint.stdout:
        args.project.write_bytes(original)
        print("error: plutil -lint rejected the edited file; original restored.\n%s%s"
              % (lint.stdout, lint.stderr), file=sys.stderr)
        return 1
    print(message)
    return 0


if __name__ == "__main__":
    sys.exit(main())
