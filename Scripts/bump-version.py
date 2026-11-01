#!/usr/bin/env python3
"""Bump Pasteup's version, finalize Unreleased notes, and regenerate XcodeGen outputs."""

import argparse
from datetime import date
from pathlib import Path
import re
import shutil
import subprocess
import sys


def setting(source, key, value_pattern):
    # Keep the spec's formatting intact without requiring a YAML dependency.
    # Fail closed if the setting is duplicated or no longer uses the expected format.
    lines = list(re.finditer(rf"^[ \t]*{key}:.*$", source, re.MULTILINE))
    if len(lines) != 1:
        raise ValueError(f"Expected exactly one {key} in project.yml")
    match = re.fullmatch(
        rf"[ \t]*{key}:[ \t]*\"(?P<value>{value_pattern})\"[ \t]*(?:#.*)?",
        lines[0].group(),
    )
    if match is None:
        raise ValueError(f"Invalid {key} in project.yml: expected a quoted numeric value")
    return match.group("value"), (
        lines[0].start() + match.start("value"),
        lines[0].start() + match.end("value"),
    )


def release_notes(source, version, release_date):
    headings = list(re.finditer(r"^##[ \t]+(.+?)[ \t]*$", source, re.MULTILINE))
    unreleased = [heading for heading in headings if heading[1] in ("Unreleased", "[Unreleased]")]
    if len(unreleased) != 1 or unreleased[0] != headings[0]:
        raise ValueError("CHANGELOG.md must start with exactly one Unreleased version section")
    if any(re.match(rf"(?:{re.escape(version)}|\[{re.escape(version)}\])(?:\s|$)", heading[1]) for heading in headings):
        raise ValueError(f"CHANGELOG.md already contains version {version}")

    heading = unreleased[0]
    end = headings[1].start() if len(headings) > 1 else len(source)
    entries = source[heading.end():end].strip("\n")
    section = f"## {version} - {release_date}\n"
    if entries:
        section += f"\n{entries}\n"
    # Keep Unreleased in place and move its entries, including category headings,
    # into the new version. Older versions remain byte-for-byte unchanged.
    return source[:heading.end()] + "\n\n" + section + ("\n" + source[end:] if end < len(source) else "")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("part", choices=("major", "minor", "patch"))
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    spec = root / "project.yml"
    plist = root / "Pasteup/Info.plist"
    changelog = root / "CHANGELOG.md"

    try:
        generator = shutil.which("xcodegen")
        if generator is None:
            raise ValueError("xcodegen is required; install it before bumping the version")
        original = spec.read_bytes()
        source = original.decode("utf-8")
        number = r"(?:0|[1-9][0-9]*)"
        old_version, version_span = setting(source, "CFBundleShortVersionString", rf"{number}\.{number}\.{number}")
        old_build, build_span = setting(source, "CFBundleVersion", r"[1-9][0-9]*")
        parts = list(map(int, old_version.split(".")))
        index = ("major", "minor", "patch").index(args.part)
        parts[index] += 1
        parts[index + 1:] = [0] * (2 - index)
        new_version = ".".join(map(str, parts))
        new_build = str(int(old_build) + 1)
        for (start, end), value in sorted(
            [(version_span, new_version), (build_span, new_build)], reverse=True
        ):
            source = source[:start] + value + source[end:]

        original_changelog = changelog.read_bytes()
        new_changelog = release_notes(original_changelog.decode("utf-8"), new_version, date.today().isoformat())
        original_plist = plist.read_bytes() if plist.exists() else None
        try:
            spec.write_bytes(source.encode("utf-8"))
            changelog.write_bytes(new_changelog.encode("utf-8"))
            subprocess.run([generator, "generate", "--quiet"], cwd=root, check=True)
        except (OSError, subprocess.CalledProcessError, KeyboardInterrupt):
            # Keep the tracked version files consistent if generation fails.
            spec.write_bytes(original)
            changelog.write_bytes(original_changelog)
            if original_plist is None:
                plist.unlink(missing_ok=True)
            else:
                plist.write_bytes(original_plist)
            raise
    except (OSError, ValueError, subprocess.CalledProcessError) as error:
        print(f"Version bump failed: {error}", file=sys.stderr)
        return 1

    print(f"Pasteup {old_version} (build {old_build}) → {new_version} (build {new_build})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
