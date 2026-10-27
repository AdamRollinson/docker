#!/bin/bash

# Record pin changes on the documentation changelog. Reads the unstaged diff of
# php-versions.txt (what check-php-versions.sh --update just changed) and adds one line per
# minor under today's date, newest date first. Run by the bump workflow before it commits;
# safe to run by hand after editing the pins yourself.
#
#   alpine/changelog.sh            # from the working tree diff
#   alpine/changelog.sh 8.4 8.4.26 8.4.27   # one explicit change

set -euo pipefail

root="$(cd "$(dirname "$0")/.." && pwd)"
versions="$root/alpine/php-versions.txt"
changelog="${CHANGELOG_FILE:-$root/docs/content/5.releases/4.changelog.md}"
repo_url="${REPO_URL:-https://github.com/AdamRollinson/docker}"
today="${CHANGELOG_DATE:-$(date -u +%Y-%m-%d)}"

# "<minor> <old> <new>" per changed pin
changes() {
    if [ $# -eq 3 ]; then
        echo "$1 $2 $3"
        return
    fi
    git -C "$root" diff -U0 -- "$versions" | awk '
        /^-[0-9]/ { m = substr($1, 2); old[m] = $2 }
        /^\+[0-9]/ { m = substr($1, 2); if (!(m in old)) print m, "(new)", $2; else if (old[m] != $2) print m, old[m], $2 }'
}

lines=$(changes "$@")
[ -n "$lines" ] || { echo "no pin changes to record"; exit 0; }

entries=""
while read -r minor old new; do
    case "$new" in *_*) kind=" (pre-release, channel tag \`${minor}-$(printf '%s' "${new#*_}" | tr -d '0-9')\`)" ;; *) kind="" ;; esac
    if [ "$old" = "(new)" ]; then
        entries="${entries}- PHP ${minor} added at ${new}${kind}. [Release notes](${repo_url}/releases/tag/php-${new}).
"
    else
        entries="${entries}- PHP ${minor}: ${old} to ${new}${kind}. [Release notes](${repo_url}/releases/tag/php-${new}).
"
    fi
done <<< "$lines"

marker='<!-- entries -->'
grep -q "$marker" "$changelog" || { echo "ERROR: ${changelog} has no ${marker} marker" >&2; exit 1; }

tmp=$(mktemp)
# entries travel through the environment: awk -v mangles escapes and BSD awk rejects newlines
ENTRIES="$entries" awk -v marker="$marker" -v today="$today" '
    BEGIN { state = 0; entries = ENVIRON["ENTRIES"] }
    {
        if (state == 0 && index($0, marker)) {
            print; state = 1; next
        }
        if (state == 1) {
            if ($0 == "") { print; next }
            if ($0 == "## " today) {
                # same day: add the new lines right under the existing heading
                print; print ""; printf "%s", entries; state = 2; skipblank = 1; next
            }
            # a different (older) day or end of list: open a new section first
            print "## " today; print ""; printf "%s", entries; print ""; print; state = 2; next
        }
        if (state == 2 && skipblank && $0 == "") { skipblank = 0; next }
        print
    }
    END { if (state == 1) { print "## " today; print ""; printf "%s", entries } }
' "$changelog" > "$tmp"
mv "$tmp" "$changelog"
printf '%s' "$entries" | sed 's/^/recorded: /'
