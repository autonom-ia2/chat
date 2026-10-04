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
[ "$(printf '%s' "$result" | /usr/bin/wc -c | /usr/bin/tr -d ' ')" -le 1024 ] || fail
uuid='[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}'
session='\{"type":"session","version":(null|"'"$uuid"'")\}'
timestamp='[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]{3}Z'
manager='(null|\{"state":"(healthy|operator_required|failed)","control_available":false,"observed_at":"'"$timestamp"'"\}|\{"state":"operator_required","control_available":true,"observed_at":"'"$timestamp"'"\})'
request='(null|\{"id":"'"$uuid"'","action":"reconnect","state":"(queued|running|operator_required|succeeded|failed)","actor_id":[1-9][0-9]{0,15},"created_at":"'"$timestamp"'","updated_at":"'"$timestamp"'","expires_at":"'"$timestamp"'"\})'
operator='\{"type":"operator","manager":'"$manager"',"request":'"$request"'\}'
# Metadata is validated and emitted in this canonical order by the Ruby publisher.
name_unit='([^"\\[:cntrl:]]|\\["\\/]|\\u[0-9a-fA-F]{4})'
name="$name_unit{1,240}($name_unit{1,240})?"
metadata='\{"INSTAGRAM_META_DEVELOPER_APP_ID":"[0-9]{1,40}","INSTAGRAM_META_BUSINESS_ID":"[0-9]{1,40}","INSTAGRAM_TESTER_APP_NAME":"'"$name"'","INSTAGRAM_TESTER_ADMIN_USER_ID":"[0-9]{1,40}","INSTAGRAM_TESTER_ROLES_DOC_ID":"[0-9]{1,40}"\}'
bootstrap='\{"type":"bootstrap","metadata":'"$metadata"',"revision":"[0-9a-f]{64}","version":(null|"'"$uuid"'")\}'
printf '%s' "$result" | /usr/bin/grep -Eq "^($session|$operator|$bootstrap)$" || fail
printf '%s\n' "$result"
