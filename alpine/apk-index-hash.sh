#!/bin/bash

# Print a hash of every package name and version in the Alpine repositories the Dockerfiles
# install from (the base image's release branch, main and community), for both amd64 and
# arm64. CI passes it to the builds as APK_INDEX_HASH, an ARG declared just before each apk
# step, so a cached apk layer is reused only while Alpine has published nothing new. Without
# it the weekly rebuild hits the layer cache and ships the packages from the first build,
# security fixes included. PHP itself is compiled from a pinned tarball, so no image needs
# edge.
#
# Only P:/V: pairs are hashed, so a regenerated index with unchanged contents keeps the hash.
# Fails if any index cannot be fetched rather than printing a hash that would reuse the cache.

set -euo pipefail

ARCHES=(x86_64 aarch64)

# Alpine release branch of the base image, read from its FROM line (alpine:3.24 -> v3.24)
ALPINE_RELEASE="${ALPINE_RELEASE:-v$(grep -oE '^FROM alpine:[0-9]+\.[0-9]+' "$(dirname "$0")/base/Dockerfile" | sed 's/^FROM alpine://')}"
REPOS=("${ALPINE_RELEASE}/main" "${ALPINE_RELEASE}/community")

for repo in "${REPOS[@]}"; do
    for arch in "${ARCHES[@]}"; do
        curl -sSfL "https://dl-cdn.alpinelinux.org/alpine/$repo/$arch/APKINDEX.tar.gz" \
            | tar -xzOf - APKINDEX \
            | awk -v r="$repo/$arch" '
                BEGIN { RS = ""; FS = "\n" }
                {
                    name = ""; ver = ""
                    for (i = 1; i <= NF; i++) {
                        if ($i ~ /^P:/) name = substr($i, 3)
                        if ($i ~ /^V:/) ver = substr($i, 3)
                    }
                    if (name != "") print r, name, ver
                }'
    done
done | LC_ALL=C sort | sha256sum | cut -d' ' -f1
