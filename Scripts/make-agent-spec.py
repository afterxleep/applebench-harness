#!/usr/bin/env python3
"""Writes the agent-facing XcodeGen spec: the fixture's spec with its test
targets removed.

An agent that can read the graded assertions is not diagnosing anything, and
the file names and class names alone give most of it away. So the project the
agent receives has no test target at all — no target, no file reference, no
class name. The real spec is kept outside the checkout and the tests are
overlaid back onto the workspace at grading time, once the agent has exited.

Usage:
    make-agent-spec.py <project.yml> <output.yml>
"""
import re
import sys


TEST_TARGET = re.compile(r"(UITests|Tests)$")
KEY = re.compile(r"^(\s*)([A-Za-z0-9_.-]+):\s*$")


def test_target_names(lines):
    """Target names under the top-level `targets:` mapping that are test
    bundles. Matched by name, which is the convention every fixture follows."""
    names = set()
    in_targets = False
    for line in lines:
        if line.startswith("targets:"):
            in_targets = True
            continue
        if line and not line[0].isspace():
            in_targets = False
        if not in_targets:
            continue
        match = KEY.match(line)
        if match and len(match.group(1)) == 2 and TEST_TARGET.search(match.group(2)):
            names.add(match.group(2))
    return names


def strip(text):
    lines = text.splitlines()
    names = test_target_names(lines)
    if not names:
        return None, names

    out = []
    dropping_deeper_than = None
    for line in lines:
        if dropping_deeper_than is not None:
            indent = len(line) - len(line.lstrip())
            if not line.strip() or indent > dropping_deeper_than:
                continue
            dropping_deeper_than = None

        match = KEY.match(line)
        if match:
            indent, key = len(match.group(1)), match.group(2)
            # The test target's own definition.
            if key in names:
                dropping_deeper_than = indent
                continue
            # A scheme's test action, which can only name test targets.
            if key == "test" and indent == 4:
                dropping_deeper_than = indent
                continue

        # Any remaining reference, such as a scheme's build entry. Test target
        # names are strict suffixes of the app target's, so the app's own
        # entries never match.
        if any(name in line for name in names):
            continue

        out.append(line)

    return "\n".join(out).rstrip() + "\n", names


def main():
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    source, destination = sys.argv[1], sys.argv[2]
    stripped, names = strip(open(source).read())
    # No test target is not an error: a fixture graded only on the built
    # product has nothing to withhold. Print nothing and let the caller skip.
    if stripped is None:
        return 0
    with open(destination, "w") as handle:
        handle.write(stripped)
    print(" ".join(sorted(names)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
