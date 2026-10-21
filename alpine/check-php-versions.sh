#!/bin/bash

# Compare the pinned PHP releases in php-versions.txt with what Alpine currently
# ships, for both amd64 and arm64. With --update, rewrite the file so each minor
# points at the newest release available on both architectures.
#
# The Dockerfiles install from the base image's stable release repositories plus
# edge main, community and testing, and apk picks the newest version it can see
# across all of them. A security release can land in the stable branch before edge
# (or the other way round), so the same set of repositories is consulted here.
#
# Each line also shows the latest upstream release from php.net, so a security
# fix that Alpine has not packaged yet is visible. Upstream never drives the
# bump: pinning a release apk cannot install only breaks the build.
# Set CHECK_UPSTREAM=false to skip the php.net lookup (offline use).

set -euo pipefail

VERSIONS_FILE="$(dirname "$0")/php-versions.txt"
ARCHES=(x86_64 aarch64)

# Alpine release branch of the base image, read from its FROM line (alpine:3.24 -> v3.24)
ALPINE_RELEASE="${ALPINE_RELEASE:-v$(grep -oE '^FROM alpine:[0-9]+\.[0-9]+' "$(dirname "$0")/base/Dockerfile" | sed 's/^FROM alpine://')}"
# Repositories as "<branch>/<repo>", in the order apk sees them in the Dockerfiles
REPOS=("${ALPINE_RELEASE}/main" "${ALPINE_RELEASE}/community" edge/main edge/community edge/testing)
UPDATE=false
[ "${1:-}" = "--update" ] && UPDATE=true

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# Print the newest upstream version (without the Alpine -rN suffix) of a package across
# every repository apk would consult, for one architecture. Prints nothing if absent
# everywhere. An index can list several versions while a release rolls out, so every
# candidate is considered and the newest wins, exactly as apk resolves it.
edge_version() {
    local pkg=$1 arch=$2 repo index candidate best=""
    for repo in "${REPOS[@]}"; do
        index="$TMP/${repo//\//-}-$arch"
        if [ ! -f "$index" ]; then
            curl -sSfL "https://dl-cdn.alpinelinux.org/alpine/$repo/$arch/APKINDEX.tar.gz" \
                | tar -xzOf - APKINDEX > "$index" 2>/dev/null || : > "$index"
        fi
        while IFS= read -r candidate; do
            candidate="${candidate%-r*}"
            if [ -z "$best" ] || is_newer "$candidate" "$best"; then
                best="$candidate"
            fi
        done < <(awk -v p="$pkg" '
            BEGIN { RS = ""; FS = "\n" }
            {
                name = ""; ver = ""
                for (i = 1; i <= NF; i++) {
                    if ($i ~ /^P:/) name = substr($i, 3)
                    if ($i ~ /^V:/) ver = substr($i, 3)
                }
                if (name == p) print ver
            }' "$index")
    done
    [ -n "$best" ] && echo "$best"
}

# Latest upstream release for a minor from php.net, printed as "<version>|<tags>"
# in Alpine's spelling (8.6.0RC3 -> 8.6.0_rc3). Prints nothing when the branch is
# not released yet or php.net cannot be reached.
upstream_release() {
    local minor=$1 json version tags
    [ "${CHECK_UPSTREAM:-true}" = "true" ] || return 0
    json=$(curl -sSf --max-time 10 "https://www.php.net/releases/index.php?json&version=${minor}" 2>/dev/null) || { echo "unavailable"; return 0; }
    case "$json" in *'"error"'*) return 0 ;; esac
    version=$(printf '%s' "$json" | grep -oE 'php-[0-9]+\.[0-9]+\.[0-9]+[A-Za-z0-9]*\.tar' | head -n1 \
        | sed -E 's/^php-//; s/\.tar$//' | tr 'A-Z' 'a-z' | sed -E 's/([0-9])(rc|beta|alpha)/\1_\2/')
    tags=$(printf '%s' "$json" | grep -oE '"tags":\[[^]]*\]' | head -n1 | sed -E 's/"tags":\[//; s/\]//; s/"//g')
    [ -n "$version" ] && printf '%s|%s\n' "$version" "$tags"
}

# Human-readable php.net column for one minor, given the release Alpine edge has
upstream_note() {
    local minor=$1 edge=$2 upstream version tags
    upstream=$(upstream_release "$minor")
    if [ "$upstream" = "unavailable" ]; then
        echo ", php.net: lookup failed"
        return 0
    fi
    if [ -z "$upstream" ]; then
        [ "${CHECK_UPSTREAM:-true}" = "true" ] && echo ", php.net: no stable release yet"
        return 0
    fi
    version="${upstream%%|*}"
    tags="${upstream#*|}"
    if [ -n "$edge" ] && is_newer "$version" "$edge"; then
        pending=$((pending + 1))
        case ",$tags," in
            *,security,*) echo ", php.net $version (security release, waiting on Alpine)" ;;
            *)            echo ", php.net $version (waiting on Alpine)" ;;
        esac
    else
        echo ", php.net $version"
    fi
}

# True when $1 is a strictly newer version than $2. Alpine spells pre-releases with an
# underscore (8.6.0_rc3); a final release always beats a pre-release of the same base.
is_newer() {
    local a="$1" b="$2" a_base="${1%%_*}" b_base="${2%%_*}" a_pre="" b_pre=""
    [ "$a" != "$b" ] || return 1
    case "$a" in *_*) a_pre="${a#*_}" ;; esac
    case "$b" in *_*) b_pre="${b#*_}" ;; esac
    if [ "$a_base" != "$b_base" ]; then
        [ "$(printf '%s\n%s\n' "$a_base" "$b_base" | sort -V | tail -n1)" = "$a_base" ]
        return
    fi
    [ -z "$a_pre" ] && [ -n "$b_pre" ] && return 0
    [ -n "$a_pre" ] && [ -z "$b_pre" ] && return 1
    [ "$(printf '%s\n%s\n' "$a_pre" "$b_pre" | sort -V | tail -n1)" = "$a_pre" ]
}

updates=0
skipped=0
pending=0
while read -r minor pinned; do
    pkg="php${minor//./}"
    amd64=$(edge_version "$pkg" x86_64)
    arm64=$(edge_version "$pkg" aarch64)
    note=$(upstream_note "$minor" "$amd64")
    case "$note" in *"waiting on Alpine"*) pending=$((pending + 1)) ;; esac

    if [ -z "$amd64" ] || [ -z "$arm64" ]; then
        echo "PHP $minor: pinned $pinned, $pkg missing from Alpine (amd64='$amd64' arm64='$arm64')${note}, skipping"
        skipped=$((skipped + 1))
        continue
    fi
    if [ "$amd64" != "$arm64" ]; then
        echo "PHP $minor: pinned $pinned, Alpine architectures disagree (amd64=$amd64 arm64=$arm64)${note}, skipping"
        skipped=$((skipped + 1))
        continue
    fi
    if [ "$amd64" = "$pinned" ]; then
        echo "PHP $minor: pinned $pinned, Alpine $amd64${note}"
        continue
    fi
    if ! is_newer "$amd64" "$pinned"; then
        echo "PHP $minor: pinned $pinned, Alpine has older $amd64 (pin is ahead of edge, build will fail)${note}, skipping"
        skipped=$((skipped + 1))
        continue
    fi

    echo "PHP $minor: pinned $pinned, Alpine $amd64${note}, update available"
    updates=$((updates + 1))
    if $UPDATE; then
        sed -i.bak "s/^${minor//./\\.} ${pinned//./\\.}\$/$minor $amd64/" "$VERSIONS_FILE"
        rm -f "$VERSIONS_FILE.bak"
        echo "PHP $minor: updated to $amd64"
    fi
done < <(grep -Ev '^[[:space:]]*(#|$)' "$VERSIONS_FILE")

if [ "$updates" -eq 0 ] && [ "$skipped" -eq 0 ]; then
    echo "All pinned PHP releases match Alpine"
elif [ "$updates" -eq 0 ]; then
    echo "$skipped pin(s) could not be reconciled with Alpine, see above"
elif ! $UPDATE; then
    echo "$updates update(s) available, run with --update to apply"
fi
if [ "$pending" -gt 0 ]; then
    echo "$pending upstream php.net release(s) not yet packaged in Alpine; the pins will follow once they are"
fi
