#!/bin/bash

# Compare the pinned PHP releases in php-versions.txt with what Alpine edge
# currently ships, for both amd64 and arm64. With --update, rewrite the file
# so each minor points at the newest release available on both architectures.

set -euo pipefail

VERSIONS_FILE="$(dirname "$0")/php-versions.txt"
ARCHES=(x86_64 aarch64)
REPOS=(community testing)
UPDATE=false
[ "${1:-}" = "--update" ] && UPDATE=true

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Print the upstream version (without the Alpine -rN suffix) of a package in edge
# for one architecture, searching the repos in order. Prints nothing if absent.
edge_version() {
    local pkg=$1 arch=$2 repo index version
    for repo in "${REPOS[@]}"; do
        index="$TMP/$repo-$arch"
        if [ ! -f "$index" ]; then
            curl -sSfL "https://dl-cdn.alpinelinux.org/alpine/edge/$repo/$arch/APKINDEX.tar.gz" \
                | tar -xzOf - APKINDEX > "$index"
        fi
        version=$(awk -v p="$pkg" '
            BEGIN { RS = ""; FS = "\n" }
            {
                name = ""; ver = ""
                for (i = 1; i <= NF; i++) {
                    if ($i ~ /^P:/) name = substr($i, 3)
                    if ($i ~ /^V:/) ver = substr($i, 3)
                }
                if (name == p) { print ver; exit }
            }' "$index")
        if [ -n "$version" ]; then
            echo "${version%-r*}"
            return
        fi
    done
}

# True when $1 is a strictly newer version than $2
is_newer() {
    [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n1)" = "$1" ]
}

updates=0
while read -r minor pinned; do
    pkg="php${minor//./}"
    amd64=$(edge_version "$pkg" x86_64)
    arm64=$(edge_version "$pkg" aarch64)

    if [ -z "$amd64" ] || [ -z "$arm64" ]; then
        echo "PHP $minor: pinned $pinned, $pkg missing from edge (amd64='$amd64' arm64='$arm64'), skipping"
        continue
    fi
    if [ "$amd64" != "$arm64" ]; then
        echo "PHP $minor: pinned $pinned, edge architectures disagree (amd64=$amd64 arm64=$arm64), skipping"
        continue
    fi
    if [ "$amd64" = "$pinned" ]; then
        echo "PHP $minor: pinned $pinned, up to date"
        continue
    fi
    if ! is_newer "$amd64" "$pinned"; then
        echo "PHP $minor: pinned $pinned, edge has older $amd64, skipping"
        continue
    fi

    echo "PHP $minor: pinned $pinned, edge has $amd64"
    updates=$((updates + 1))
    if $UPDATE; then
        sed -i.bak "s/^${minor//./\\.} ${pinned//./\\.}\$/$minor $amd64/" "$VERSIONS_FILE"
        rm -f "$VERSIONS_FILE.bak"
        echo "PHP $minor: updated to $amd64"
    fi
done < <(grep -Ev '^[[:space:]]*(#|$)' "$VERSIONS_FILE")

if [ "$updates" -eq 0 ]; then
    echo "All pinned PHP releases match Alpine edge"
elif ! $UPDATE; then
    echo "$updates update(s) available, run with --update to apply"
fi
