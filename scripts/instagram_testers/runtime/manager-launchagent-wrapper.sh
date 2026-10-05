#!/bin/sh

# A recovery child exits only after publication; resume continuous refresh.
# An operator_required exit waits for an explicit typed reconnect before login.
set +e

while :; do
  /usr/local/bin/node /ABSOLUTE/PATH/TO/scripts/instagram_testers/session-manager.mjs &
  child=$!
  trap 'kill "$child" 2>/dev/null || true; wait "$child" 2>/dev/null || true; exit 143' INT TERM
  wait "$child"
  status=$?
  trap - INT TERM

  if [ "$status" -eq 2 ]; then
    printf '%s\n' 'instagram_manager_operator_required' >&2
    /usr/local/bin/node /ABSOLUTE/PATH/TO/scripts/instagram_testers/runtime/operator-waiter.mjs &
    child=$!
    trap 'kill "$child" 2>/dev/null || true; wait "$child" 2>/dev/null || true; exit 143' INT TERM
    wait "$child"
    status=$?
    trap - INT TERM
    [ "$status" -eq 0 ] && continue
  fi
  [ "$status" -eq 0 ] && exit 0
  printf '%s\n' 'instagram_manager_failed' >&2
  exit 1
done
