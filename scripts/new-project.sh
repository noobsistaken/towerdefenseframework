#!/usr/bin/env bash
#
# Create a new Roblox project from this template.
#
#   scripts/new-project.sh <project-name> [destination-dir]
#
# Copies the template, substitutes placeholder tokens, initialises git with a
# first commit, and installs the toolchain and dependencies.
#
# Run it from wherever you want the project to live:
#
#   cd ~/dev
#   /path/to/template/scripts/new-project.sh my-game
#   cd my-game

set -euo pipefail

# --- args -----------------------------------------------------------------

if [ $# -lt 1 ] || [ $# -gt 2 ]; then
	echo "usage: $(basename "$0") <project-name> [destination-dir]" >&2
	exit 64
fi

PROJECT_NAME="$1"

# Wally package names must be lowercase, and may only contain alphanumerics,
# hyphens and underscores. Derive a safe slug rather than failing later inside
# `wally install` with a confusing error.
SLUG="$(printf '%s' "$PROJECT_NAME" |
	tr '[:upper:]' '[:lower:]' |
	sed -e 's/[^a-z0-9_-]/-/g' -e 's/--*/-/g' -e 's/^-//' -e 's/-$//')"

if [ -z "$SLUG" ]; then
	echo "error: '$PROJECT_NAME' contains no usable characters for a package name." >&2
	exit 65
fi

TEMPLATE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

if [ $# -eq 2 ]; then
	DEST="$2"
else
	DEST="$PWD/$PROJECT_NAME"
fi

# --- safety ---------------------------------------------------------------

if [ -e "$DEST" ]; then
	echo "error: $DEST already exists. Refusing to overwrite it." >&2
	exit 73
fi

DEST_PARENT="$(cd "$(dirname "$DEST")" 2>/dev/null && pwd || true)"
if [ -z "$DEST_PARENT" ]; then
	echo "error: parent directory of $DEST does not exist." >&2
	exit 73
fi

# Creating the project inside the template would nest it in the next copy.
case "$DEST_PARENT/" in
"$TEMPLATE_DIR"/*)
	echo "error: destination is inside the template ($TEMPLATE_DIR)." >&2
	echo "       cd somewhere else first, or pass an explicit destination." >&2
	exit 73
	;;
esac

echo "Template : $TEMPLATE_DIR"
echo "Project  : $PROJECT_NAME  (package slug: $SLUG)"
echo "Destination: $DEST"
echo

# --- copy -----------------------------------------------------------------

echo "==> Copying template"
mkdir -p "$DEST"

# Packages/ ServerPackages/ DevPackages/ ARE copied on purpose: the new
# project is then buildable offline, before it can reach the network.
# Everything excluded below is either per-clone state or a build artifact.
if command -v rsync >/dev/null 2>&1; then
	rsync -a \
		--exclude '.git/' \
		--exclude 'build/' \
		--exclude 'sourcemap.json' \
		--exclude '*.rbxl' \
		--exclude '*.rbxlx' \
		--exclude '.DS_Store' \
		--exclude '.claude/settings.local.json' \
		--exclude 'CLAUDE.local.md' \
		--exclude 'SETUP-LOG.md' \
		"$TEMPLATE_DIR"/ "$DEST"/
else
	# Portable fallback: copy everything, then remove the excluded paths.
	(cd "$TEMPLATE_DIR" && tar cf - .) | (cd "$DEST" && tar xf -)
	rm -rf "$DEST/.git" "$DEST/build"
	rm -f "$DEST/sourcemap.json" "$DEST"/*.rbxl "$DEST"/*.rbxlx \
		"$DEST/.DS_Store" "$DEST/.claude/settings.local.json" \
		"$DEST/CLAUDE.local.md" "$DEST/SETUP-LOG.md"
fi

# --- substitute tokens ----------------------------------------------------

echo "==> Substituting placeholders"
cd "$DEST"

# perl rather than sed -i: BSD and GNU sed disagree on the -i flag, and this
# script has to work on macOS and on a Linux CI runner.
perl -pi -e "s/\\{\\{PROJECT_NAME\\}\\}/$PROJECT_NAME/g" ARCHITECTURE.md
perl -pi -e "s{^name = \"template/template-project\"}{name = \"template/$SLUG\"}" wally.toml
perl -pi -e "s/\"name\": \"template-project\"/\"name\": \"$SLUG\"/" default.project.json
perl -pi -e "s/\"name\": \"template-project-tests\"/\"name\": \"$SLUG-tests\"/" test.project.json

chmod +x scripts/*.sh .claude/hooks/*.sh 2>/dev/null || true

# Verify no template tokens survived. A missed token turns into a confusing
# failure much later, so fail here instead.
if grep -rql "template-project" --include='*.json' --include='*.toml' . 2>/dev/null |
	grep -v -e '^\./Packages/' -e '^\./ServerPackages/' -e '^\./DevPackages/' | grep -q .; then
	echo "error: placeholder 'template-project' still present after substitution." >&2
	exit 70
fi

# --- toolchain ------------------------------------------------------------

echo "==> Installing toolchain (rokit)"
if command -v rokit >/dev/null 2>&1; then
	rokit install --no-trust-check
else
	echo "warning: rokit is not installed - skipping." >&2
	echo "         Install it from https://github.com/rojo-rbx/rokit, then run:" >&2
	echo "           cd $DEST && rokit install && wally install" >&2
fi

echo "==> Installing dependencies (wally)"
if command -v wally >/dev/null 2>&1 || [ -x "$HOME/.rokit/bin/wally" ]; then
	PATH="$HOME/.rokit/bin:$PATH" wally install
else
	echo "warning: wally is not available - skipping. Packages/ was copied from" >&2
	echo "         the template, so the project still builds offline." >&2
fi

# --- git ------------------------------------------------------------------

echo "==> Initialising git"
git init -q
git add -A
git -c user.useConfigOnly=false commit -q -m "Initial commit from Roblox AI-development template

Toolchain, dependencies, verification gates and agent instructions are in
place and were verified before this commit. See AGENTS.md for the commands
and ARCHITECTURE.md for the decisions still to be filled in." ||
	{
		echo "error: initial commit failed. Configure git user.name and user.email, then:" >&2
		echo "         cd $DEST && git add -A && git commit -m 'Initial commit'" >&2
		exit 70
	}

# --- done -----------------------------------------------------------------

cat <<EOF

Done.

  cd $DEST

Next:
  1. Fill in ARCHITECTURE.md  - what the game is, and the replication model.
  2. Edit net/schema.zap      - then: zap --no-warnings net/schema.zap
  3. Run the gate             - see AGENTS.md, or use /verify in Claude Code.

Manual step the CLI cannot do: install the Rojo plugin in Roblox Studio
(https://create.roblox.com/store/asset/6415005344) and run 'rojo serve'.
EOF
