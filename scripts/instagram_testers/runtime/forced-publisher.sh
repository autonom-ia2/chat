#!/bin/sh

set -eu

fail() {
  printf '%s\n' 'instagram_publisher_transport_failed' >&2
  exit 2
}

[ "${SSH_ORIGINAL_COMMAND-}" = "" ] || fail
[ "$#" -eq 0 ] || fail
[ "$(/usr/bin/id -u 2>/dev/null)" = "0" ] || fail
[ "${SUDO_USER-}" = "chatwoot_publisher" ] || fail

result=$(/usr/bin/docker exec -i chatwoot-web bundle exec rails runner scripts/instagram_testers/session_publisher.rb 2>/dev/null) || fail

line_count=$(printf '%s\n' "$result" | /usr/bin/wc -l | /usr/bin/tr -d ' ')
[ "$line_count" = "1" ] || fail
printf '%s' "$result" | /usr/bin/grep -Eq '^\{"version":(null|"[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}")\}$' || fail
printf '%s\n' "$result"
