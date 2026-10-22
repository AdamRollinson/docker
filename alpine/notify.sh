#!/bin/bash

# POST a JSON notification to NOTIFY_WEBHOOK_URL if it is set; a no-op otherwise. The payload
# carries the message under both "text" (Slack, Mattermost, Rocket.Chat, Google Chat) and
# "content" (Discord), plus structured fields for anything that parses JSON itself.
#
#   alpine/notify.sh <status> <title> <message> [run_url]
#
# status is "success", "failure" or "info".

set -euo pipefail

status=${1:?status}; title=${2:?title}; message=${3:?message}; run_url=${4:-}
[ -n "${NOTIFY_WEBHOOK_URL:-}" ] || { echo "NOTIFY_WEBHOOK_URL not set, skipping notification"; exit 0; }

case "$status" in
    success) icon="✅" ;;
    failure) icon="❌" ;;
    *)       icon="ℹ️" ;;
esac
text="${icon} ${title}"$'\n'"${message}"
[ -n "$run_url" ] && text="${text}"$'\n'"${run_url}"

payload=$(jq -cn \
    --arg text "$text" --arg status "$status" --arg title "$title" \
    --arg message "$message" --arg run_url "$run_url" \
    --arg repo "${GITHUB_REPOSITORY:-}" --arg sha "${GITHUB_SHA:-}" \
    '{text: $text, content: $text, status: $status, title: $title, message: $message,
      run_url: $run_url, repository: $repo, sha: $sha,
      source: "docker-build"}')

code=$(curl -sS -o /dev/null -w '%{http_code}' --max-time 15 \
    -H "Content-Type: application/json" -X POST -d "$payload" "$NOTIFY_WEBHOOK_URL") || code="000"
echo "notification sent (${status}), webhook answered ${code}"
case "$code" in 2*) ;; *) echo "WARNING: webhook did not accept the notification" >&2 ;; esac
