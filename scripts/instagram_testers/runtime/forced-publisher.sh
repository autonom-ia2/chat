#!/bin/sh

set -eu

fail() {
  if [ "${channel_child-}" != "" ]; then
    kill "$channel_child" 2>/dev/null || true
  fi
  printf '%s\n' 'instagram_publisher_transport_failed' >&2
  exit 2
}

[ "$#" -eq 0 ] || fail
[ "$(/usr/bin/id -u 2>/dev/null)" = "0" ] || fail
[ "${SUDO_USER-}" = "chatwoot_publisher" ] || fail

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
# Browser observations use the same bounded transport, with canonical Ruby key
# order and no result data or authorization URL in the acknowledgement.
browser_errors='invalid_username|invalid_selection|meta_unavailable|meta_session_expired|unknown_status|invite_rejected|invite_unknown|rate_limited|forbidden|not_enabled|busy|proxy_unavailable|session_update_rejected|operator_required'
browser_request_pattern() {
  prefix='\{"id":"'"$uuid"'","request_id":"'"$uuid"'","action":"'"$1"'","state":"'"$2"'","deadline":"'"$timestamp"'","app_id":"[0-9]{1,40}"'
  target=''
  [ "$1" = 'search' ] || target=',"target_id":"[0-9]{1,40}"'
  claim=''
  [ "$3" = 'read' ] || claim=',"claim":"'"$uuid"'"'
  printf '%s' "$prefix$target,\"username\":\"[a-z0-9._]{1,30}\"$claim\}"
}
browser_search_read=$(browser_request_pattern 'search' '(queued|running)' 'read')
browser_role_read=$(browser_request_pattern '(status|authorization|invite)' '(queued|running)' 'read')
browser_search_claim=$(browser_request_pattern 'search' 'running' 'claim')
browser_role_claim=$(browser_request_pattern '(status|authorization|invite)' 'running' 'claim')
browser_read='\{"type":"browser_operation","operation":"read","request":(null|'"$browser_search_read"'|'"$browser_role_read"')\}'
browser_claim='\{"type":"browser_operation","operation":"claim","request":('"$browser_search_claim"'|'"$browser_role_claim"')\}'
browser_complete='\{"type":"browser_operation","operation":"complete","id":"'"$uuid"'","request_id":"'"$uuid"'",("state":"ready"|"state":"(failed|expired)","error_code":"('"$browser_errors"')")\}'
browser_permit='\{"type":"browser_operation","operation":"invite_permit","id":"'"$uuid"'","request_id":"'"$uuid"'","claim":"'"$uuid"'",("decision":"write","status":"absent"|"decision":"noop","status":"pending"|"error_code":"('"$browser_errors"')")\}'

validate_frame() {
  frame=$1
  limit=$2
  [ "$(printf '%s' "$frame" | /usr/bin/wc -c | /usr/bin/tr -d ' ')" -le "$limit" ] || fail
  printf '%s' "$frame" | /usr/bin/grep -Eq "^($session|$operator|$bootstrap|$browser_read|$browser_claim|$browser_complete|$browser_permit)$" || fail
}

if [ "${SSH_ORIGINAL_COMMAND-}" = "instagram_publisher_channel_v1" ]; then
  channel_dir=$(/usr/bin/mktemp -d /tmp/instagram-publisher-channel.XXXXXX) || fail
  channel_fifo="$channel_dir/output"
  cleanup_channel() {
    /bin/rm -f "$channel_fifo" 2>/dev/null || true
    /bin/rmdir "$channel_dir" 2>/dev/null || true
  }
  channel_signal() {
    kill "${channel_child-}" 2>/dev/null || true
    cleanup_channel
    exit 143
  }
  trap cleanup_channel EXIT
  trap channel_signal HUP INT TERM
  /usr/bin/mkfifo "$channel_fifo" || fail
  exec 3<>"$channel_fifo" || fail
  exec 4<&0 || fail
  /usr/bin/docker exec -i chatwoot-web bundle exec ruby scripts/instagram_testers/session_publisher.rb --channel <&4 >&3 2>/dev/null &
  channel_child=$!
  exec 4<&-
  exec 3>&-
  while IFS= read -r frame; do
    validate_frame "$frame" 2048
    printf '%s\n' "$frame"
  done <"$channel_fifo"
  wait "$channel_child" || fail
  exit 0
fi

[ "${SSH_ORIGINAL_COMMAND-}" = "" ] || fail
result=$(/usr/bin/docker exec -i chatwoot-web bundle exec ruby scripts/instagram_testers/session_publisher.rb 2>/dev/null) || fail
line_count=$(printf '%s\n' "$result" | /usr/bin/wc -l | /usr/bin/tr -d ' ')
[ "$line_count" = "1" ] || fail
validate_frame "$result" 1024
printf '%s\n' "$result"
