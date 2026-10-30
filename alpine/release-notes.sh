#!/bin/bash

# Write GitHub release notes for one pinned PHP release to stdout, with the manifest digest
# of every image carrying that exact tag. Used by the release job in docker-build.yml and
# handy locally:  alpine/release-notes.sh 8.4 8.4.27 8.4 <git sha>
#
# Exits 3 when an image does not carry the exact tag yet (nothing to release).

set -euo pipefail

minor=${1:?minor}; patch=${2:?patch}; tag=${3:?moving tag}; sha=${4:-$(git rev-parse HEAD 2>/dev/null || echo unknown)}
registry="${DOCKER_REGISTRY:-rollogi}"
repo_url="${REPO_URL:-https://github.com/AdamRollinson/docker}"

rows=""
for image in php php-nginx php-nginx-dev php-fpm php-dev; do
    ref="${registry}/${image}:${patch}"
    digest=$(docker buildx imagetools inspect "$ref" --format '{{.Manifest.Digest}}' 2>/dev/null) || { echo "ERROR: ${ref} is not published" >&2; exit 3; }
    rows="${rows}| \`${registry}/${image}\` | \`${tag}\`, \`${patch}\` | \`${digest}\` |
"
done

case "$patch" in
    *_*) channel="This is a pre-release of PHP ${minor}. The exact tag and the \`${tag}\` channel tag are published; the bare \`${minor}\` tag will appear with the final release." ;;
    *)   channel="The \`${tag}\` tag now points at this release." ;;
esac

cat <<NOTES
PHP ${patch} images built from [\`${sha:0:12}\`](${repo_url}/commit/${sha}) for \`linux/amd64\` and \`linux/arm64\`.

${channel}

| Image | Tags | Manifest digest |
|-------|------|-----------------|
${rows}
Each architecture was built natively, scanned with Trivy (CRITICAL and HIGH, fixed vulnerabilities only) and smoke tested before the digests were joined. Every manifest list carries an SBOM, SLSA provenance and the project's OpenVEX statement, and is signed keylessly with cosign:

\`\`\`bash
cosign verify \\
  --certificate-oidc-issuer https://token.actions.githubusercontent.com \\
  --certificate-identity-regexp '^${repo_url}/\\.github/workflows/docker-build\\.yml@refs/heads/main\$' \\
  ${registry}/php-nginx:${patch}
\`\`\`

Pull the exact tag to pin, or the \`${tag}\` tag to follow this minor. Documentation: https://docker.rollogi.co.uk
NOTES
