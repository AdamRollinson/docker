#!/bin/bash

# Compare the pinned PHP releases in php-versions.txt with what php.net publishes. With
# --update, rewrite each line that is behind to the newest release, with its checksum and
# tarball URL, so the build compiles exactly what was checked here.
#
# A minor with a final release follows php.net's releases feed; a minor without one yet (the
# next PHP, during its alphas and release candidates) follows the pre-release feed, which also
# gives the release manager's download path. A final release always beats a pre-release, so a
# pin moves from 8.6.0_rc4 to 8.6.0 on its own. Pins keep Alpine's spelling (8.6.0_rc4) for
# the image tags; php.net spells the same release 8.6.0RC4.
#
# The PECL extensions in php/pecl-extensions.txt are checked as well: --update applies newer
# releases within the same major.minor, anything larger is only reported.

set -euo pipefail

DIR="$(dirname "$0")"
VERSIONS_FILE="$DIR/php-versions.txt"
PECL_FILE="$DIR/php/pecl-extensions.txt"
UPDATE=false
[ "${1:-}" = "--update" ] && UPDATE=true

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# php.net spelling to Alpine spelling: 8.6.0RC4 -> 8.6.0_rc4, 8.6.0alpha1 -> 8.6.0_alpha1
alpine_spelling() {
    printf '%s' "$1" | tr 'A-Z' 'a-z' | sed -E 's/([0-9])(rc|beta|alpha)/\1_\2/'
}

# True when $1 is a strictly newer version than $2 (either spelling); a final release always
# beats a pre-release of the same base
is_newer() {
    local a b a_base b_base a_pre="" b_pre=""
    a=$(alpine_spelling "$1"); b=$(alpine_spelling "$2")
    a_base="${a%%_*}"; b_base="${b%%_*}"
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

sha256() {
    if command -v sha256sum >/dev/null; then sha256sum | cut -d' ' -f1; else shasum -a 256 | cut -d' ' -f1; fi
}

# Newest release of a minor as "<version> <sha256> <url> <tags>" (version in Alpine spelling,
# tags comma-separated, "-" when none), or nothing when php.net has nothing for it
latest_release() {
    local minor=$1 json
    json=$(curl -sSf --max-time 20 "https://www.php.net/releases/index.php?json&version=${minor}") || return 1
    if ! printf '%s' "$json" | jq -e 'has("error")' >/dev/null; then
        printf '%s' "$json" | jq -r '
            (.source[] | select(.filename | endswith(".tar.xz"))) as $f
            | [.version, $f.sha256, "https://www.php.net/distributions/" + $f.filename,
               ((.tags // []) | if length == 0 then "-" else join(",") end)] | join(" ")'
        return
    fi
    [ -f "$TMP/pre-release.json" ] \
        || curl -sSfL --max-time 20 "https://www.php.net/pre-release-builds.php?format=json" > "$TMP/pre-release.json" \
        || return 1
    jq -r --arg m "$minor." '
        to_entries[] | select(.key | startswith($m)) | .value.release
        | select(.version != null and (.enabled // true) and .files.xz.path != null)
        | [.version, .files.xz.sha256, .files.xz.path, "pre-release"] | join(" ")' "$TMP/pre-release.json" \
        | head -n1
}

updates=0
skipped=0
while read -r minor pinned pinned_sha pinned_url; do
    latest=$(latest_release "$minor") || latest="unavailable"
    if [ "$latest" = "unavailable" ] || [ -z "$latest" ]; then
        echo "PHP $minor: pinned $pinned, php.net has no release for it (${latest:-none}), skipping"
        skipped=$((skipped + 1))
        continue
    fi
    read -r version sha url tags <<< "$latest"
    version=$(alpine_spelling "$version")
    channel=""
    case "$pinned" in *_*) channel=" [pre-release channel, tag ${minor}-$(printf '%s' "${pinned#*_}" | tr -d '0-9')]" ;; esac
    security=""
    case ",$tags," in *,security,*) security=" (security release)" ;; esac

    if [ "$version" = "$pinned" ]; then
        if [ "$sha" != "${pinned_sha:-}" ] || [ "$url" != "${pinned_url:-}" ]; then
            echo "PHP $minor: pinned $pinned, but its checksum or URL differs from php.net${channel}, update available"
        else
            echo "PHP $minor: pinned $pinned, php.net $version${channel}"
            continue
        fi
    elif ! is_newer "$version" "$pinned"; then
        echo "PHP $minor: pinned $pinned, php.net has older $version (pin is ahead), skipping"
        skipped=$((skipped + 1))
        continue
    else
        echo "PHP $minor: pinned $pinned, php.net $version${security}${channel}, update available"
    fi

    updates=$((updates + 1))
    if $UPDATE; then
        awk -v m="$minor" -v line="$minor $version $sha $url" '$1 == m && $0 !~ /^[[:space:]]*#/ { print line; next } { print }' \
            "$VERSIONS_FILE" > "$TMP/versions" && cat "$TMP/versions" > "$VERSIONS_FILE"
        echo "PHP $minor: updated to $version"
        case "$pinned:$version" in
            *_*:*_*) ;;
            *_*:*) echo "PHP $minor: final release, the bare ${minor} tag will be published from this build and the pre-release channel tag stops moving" ;;
        esac
    fi
done < <(grep -Ev '^[[:space:]]*(#|$)' "$VERSIONS_FILE")

# PECL: one stable-release lookup per extension, compared with every pinned line for it
pecl_updates=0
while read -r image name source pinned_sha minors; do
    case "$source" in https://*) continue ;; esac
    stable=$(curl -sSf --max-time 20 "https://pecl.php.net/rest/r/${name}/stable.txt" 2>/dev/null) || {
        echo "PECL $name: lookup failed"; continue; }
    if ! is_newer "$stable" "$source"; then
        echo "PECL $name ($minors): pinned $source, latest stable $stable"
        continue
    fi
    if [ "${stable%.*}" != "${source%.*}" ]; then
        echo "PECL $name ($minors): pinned $source, latest stable $stable is a new major or minor, update by hand"
        continue
    fi
    echo "PECL $name ($minors): pinned $source, latest stable $stable, update available"
    pecl_updates=$((pecl_updates + 1))
    if $UPDATE; then
        new_sha=$(curl -sSfL "https://pecl.php.net/get/${name}-${stable}.tgz" | sha256)
        awk -v img="$image" -v n="$name" -v old="$source" -v line="$image $name $stable $new_sha $minors" \
            '$1 == img && $2 == n && $3 == old { print line; next } { print }' "$PECL_FILE" > "$TMP/pecl" \
            && cat "$TMP/pecl" > "$PECL_FILE"
        echo "PECL $name: updated to $stable"
    fi
done < <(grep -Ev '^[[:space:]]*(#|$)' "$PECL_FILE")

if [ "$updates" -eq 0 ] && [ "$skipped" -eq 0 ]; then
    echo "All pinned PHP releases match php.net"
elif [ "$updates" -eq 0 ]; then
    echo "$skipped pin(s) could not be reconciled with php.net, see above"
elif ! $UPDATE; then
    echo "$updates PHP update(s) available, run with --update to apply"
fi
if [ "$pecl_updates" -gt 0 ] && ! $UPDATE; then
    echo "$pecl_updates PECL update(s) available, run with --update to apply"
fi
