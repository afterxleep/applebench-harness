#!/bin/bash
# Turns each fixture in Fixtures/ into a standalone local git repository under
# .applebench/fixtures/<name>, generating the Xcode project with XcodeGen.
# Example tasks reference these repositories via local paths.
#
# Each fixture's reference solution is copied to .applebench/solutions/<name>.patch
# — outside every agent checkout — so `applebench run <id> --agent solution`
# can prove the fixture is solvable without ever showing the fix to an agent.
set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"

# shellcheck source=Scripts/taskset.sh
. "$(dirname "$0")/taskset.sh"
dest="$root/.applebench/fixtures"
solutions="$root/.applebench/solutions"
verification="$root/.applebench/verification"

if ! command -v xcodegen >/dev/null 2>&1; then
    echo "error: xcodegen is required (brew install xcodegen)" >&2
    exit 1
fi

# Every directory under Fixtures/. Optional filter:
#   ./Scripts/prepare-fixtures.sh BuildFixture CounterFixture
if [ "$#" -gt 0 ]; then
    fixtures=("$@")
else
    fixtures=()
    for dir in "$taskset_fixtures"/*; do
        [ -d "$dir" ] || continue
        fixtures+=("$(basename "$dir")")
    done
fi

mkdir -p "$solutions"

# On a full run, drop snapshots whose fixture no longer exists. A retired
# fixture otherwise lingers under .applebench/ forever, and the leak check
# has no authored source to judge it against.
if [ "$#" -eq 0 ] && [ -d "$dest" ]; then
    for snapshot in "$dest"/*/; do
        [ -d "$snapshot" ] || continue
        name="$(basename "$snapshot")"
        if [ ! -d "$taskset_fixtures/$name" ]; then
            echo "Removing retired snapshot $name..."
            rm -rf "$snapshot" "$verification/$name" "$solutions/$name.patch"
        fi
    done
fi

# A snapshot is only a benchmark item if the agent has to diagnose the defect.
# Stripping the authoring files does not strip a comment, so refuse to build a
# snapshot out of a fixture that names its own bug in shipped source.
if ! "$root/Scripts/check-fixture-leaks.sh" --sources-only "$taskset_fixtures" >/dev/null 2>&1; then
    echo "error: a fixture discloses its planted defect in shipped source." >&2
    "$root/Scripts/check-fixture-leaks.sh" --sources-only "$taskset_fixtures" >&2 || true
    exit 1
fi

for fixture in "${fixtures[@]}"; do
    src="$taskset_fixtures/$fixture"
    out="$dest/$fixture"
    if [ ! -d "$src" ]; then
        echo "error: no such fixture: Fixtures/$fixture" >&2
        exit 1
    fi
    echo "Preparing $fixture..."
    rm -rf "$out"
    mkdir -p "$out"
    cp -R "$src/." "$out/"

    # Whether this fixture's graded tests are withheld from the agent. They
    # are, unless a task on this fixture needs the agent to change the project
    # or to author a test target of its own — overlaying a pre-generated
    # project onto that work would throw the answer away.
    isolate="$("$root/Scripts/fixture-isolation.py" "$fixture")"

    (
        cd "$out"
        # Xcode-app fixtures carry a project.yml; plain Swift packages don't.
        # A project.solution.yml, where present, is the fixed configuration the
        # solution patch was generated from — authoring only.
        if [ -f project.yml ]; then
            xcodegen generate --quiet

            # A fixture graded only on the built product declares no test
            # target, so there is nothing to withhold and this is a no-op.
            withheld=""
            if [ "$isolate" = "isolate" ]; then
                withheld="$("$root/Scripts/make-agent-spec.py" project.yml project.agent.yml)"
            fi

            if [ -n "$withheld" ]; then
                # Keep the real project and the graded tests outside every
                # checkout. The runner overlays them back onto the workspace
                # after the agent has exited and its diff is captured.
                bundle="$verification/$fixture"
                rm -rf "$bundle"
                mkdir -p "$bundle"
                cp -R "$fixture.xcodeproj" "$bundle/"
                cp project.yml "$bundle/"
                for suite in Tests UITests; do
                    if [ -d "$suite" ]; then cp -R "$suite" "$bundle/"; fi
                done

                # Regenerate the project the agent receives, with no test
                # target in it at all.
                rm -rf "$fixture.xcodeproj"
                xcodegen generate --quiet --spec project.agent.yml
                for suite in Tests UITests; do
                    rm -rf "$suite"
                done
                echo "  withheld: $withheld"
            fi
            rm -f project.agent.yml
        fi
        # The reference solution lives outside every checkout.
        if [ -f solution.patch ]; then
            cp solution.patch "$solutions/$fixture.patch"
        else
            echo "  warning: Fixtures/$fixture/solution.patch is missing; the fixture cannot be proven solvable" >&2
            rm -f "$solutions/$fixture.patch"
        fi
        # The agent must see a normal, self-contained repository: no fixture
        # authoring files (project*.yml), no README (they describe the planted
        # bug), and no solution patch.
        rm -rf .solution
        rm -f project.yml project.solution.yml README.md solution.patch
        git init --quiet
        git add -A
        git -c user.email=fixtures@applebench.local -c user.name=AppleBench \
            commit --quiet -m "Fixture snapshot: $fixture"
    )
done

echo "Fixtures ready under $dest"
echo "Solutions ready under $solutions"
