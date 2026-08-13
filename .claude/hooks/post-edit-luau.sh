#!/usr/bin/env bash
#
# PostToolUse hook: verify a single Luau file the instant an agent edits it.
#
# This is the load-bearing piece of the template. It runs without anyone
# remembering to run it, which is the point: the model cannot skip it, and a
# human who does not read Luau does not have to catch the mistake by eye.
#
# Order matters:
#   1. stylua   - format first, so lint/type positions match the saved file
#   2. selene   - lint
#   3. rojo     - refresh sourcemap so requires resolve for step 4
#   4. luau-lsp - typecheck (the step that catches hallucinated APIs)
#
# Exit-code policy, deliberately:
#   exit 0  - nothing to say, OR a tool is missing, OR a tool itself crashed
#   exit 2  - a tool ran successfully and found a real problem in YOUR code;
#             stderr is fed back to the agent so it fixes it immediately
#
# The brief for this template said "always exit 0 so a formatter crash can't
# halt the session". That reason is honoured exactly: infrastructure failure
# is always exit 0. But a genuine type error must reach the agent, or the
# whole verification layer is decorative. Broken tooling never blocks; broken
# code always does.
#
# SETTLED - do not change the `exit 2` below to `exit 0`. This split was
# reviewed and confirmed deliberately (SETUP-LOG.md 3.2). Exit 0 on a real
# type error throws the diagnostic away: the agent never sees it, and the
# gate silently becomes decorative for a user who cannot read Luau.

set -uo pipefail

payload="$(cat)"

# jq is the only hard dependency. Without it we cannot read the payload, so
# degrade to a no-op rather than guessing at the file path.
command -v jq >/dev/null 2>&1 || exit 0

file="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // empty' 2>/dev/null)"
[ -n "$file" ] || exit 0

case "$file" in
	*.luau | *.lua) ;;
	*) exit 0 ;;
esac

[ -f "$file" ] || exit 0

root="${CLAUDE_PROJECT_DIR:-$(pwd)}"
cd "$root" 2>/dev/null || exit 0

# Make the path relative to the project root when possible, so tool output is
# readable and the vendored-directory match below is reliable.
rel="${file#"$root"/}"

# Never touch vendored or generated code. Bugs get fixed in our source or in
# net/schema.zap, never inside a dependency and never in generated output.
case "$rel" in
	Packages/* | ServerPackages/* | DevPackages/* | net/generated/* | types/*) exit 0 ;;
esac

findings=""

# --- 1. format ------------------------------------------------------------
if command -v stylua >/dev/null 2>&1; then
	stylua "$rel" >/dev/null 2>&1 || true
fi

# --- 2. lint --------------------------------------------------------------
if command -v selene >/dev/null 2>&1; then
	selene_out="$(selene --display-style quiet "$rel" 2>&1)"
	selene_rc=$?
	# selene exits 1 when it finds lints. Anything higher is selene failing.
	if [ "$selene_rc" -eq 1 ] && [ -n "$selene_out" ]; then
		findings+="--- selene ---"$'\n'"$selene_out"$'\n'
	fi
fi

# --- 3. sourcemap ---------------------------------------------------------
# Built from test.project.json because that tree is a superset of the shipping
# tree: it also contains DevPackages and tests, so one sourcemap resolves
# requires for everything we analyse.
sourcemap_ok=0
if command -v rojo >/dev/null 2>&1 && [ -f test.project.json ]; then
	if rojo sourcemap test.project.json --output sourcemap.json >/dev/null 2>&1; then
		sourcemap_ok=1
	fi
fi

# --- 4. typecheck ---------------------------------------------------------
if command -v luau-lsp >/dev/null 2>&1 && [ "$sourcemap_ok" -eq 1 ] && [ -f types/globalTypes.d.luau ]; then
	analyze_out="$(
		luau-lsp analyze \
			--sourcemap=sourcemap.json \
			--defs=types/globalTypes.d.luau \
			--ignore="**/Packages/**" \
			--ignore="**/ServerPackages/**" \
			--ignore="**/DevPackages/**" \
			"$rel" 2>&1 | grep -v '^\[INFO\]' | grep -v '^\[WARN\] client'
	)"
	analyze_rc="${PIPESTATUS[0]}"
	if [ "$analyze_rc" -ne 0 ] && [ -n "$analyze_out" ]; then
		findings+="--- luau-lsp ---"$'\n'"$analyze_out"$'\n'
	fi
fi

if [ -n "$findings" ]; then
	{
		printf 'Verification failed for %s\n\n' "$rel"
		printf '%s\n' "$findings"
		printf 'Fix these before continuing. Do not leave the file in this state.\n'
	} >&2
	exit 2
fi

exit 0
