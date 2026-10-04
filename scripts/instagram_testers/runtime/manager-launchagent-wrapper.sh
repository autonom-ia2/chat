#!/bin/sh

# KeepAlive.SuccessfulExit=false restarts crashes. The manager uses exit 2 for
# operator_required only; operational failures use exit 1 and restart.
# Map that terminal state to a clean exit so launchd does
# not reopen a browser/profile until an operator explicitly starts it again.

set +e

/usr/local/bin/node /ABSOLUTE/PATH/TO/scripts/instagram_testers/session-manager.mjs &
child=$!
trap 'kill "$child" 2>/dev/null || true; wait "$child" 2>/dev/null || true; exit 143' INT TERM
wait "$child"
status=$?
trap - INT TERM

if [ "$status" -eq 2 ]; then
  printf '%s\n' 'instagram_manager_operator_required' >&2
  exit 0
fi

if [ "$status" -eq 0 ]; then
  exit 0
fi

printf '%s\n' 'instagram_manager_failed' >&2
exit 1
