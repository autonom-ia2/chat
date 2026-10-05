#!/bin/sh
set -u
umask 077

case "${1-}" in
  hub2you|autonomia) stack=$1 ;;
  *) printf '%s\n' instagram_vps_invalid_stack >&2; exit 1 ;;
esac
[ "$#" -eq 1 ] || exit 1
root=/opt/instagram-meta/current/scripts/instagram_testers
export INSTAGRAM_TESTER_PUBLISHER_COMMAND_JSON="[\"/usr/bin/node\",\"$root/runtime/vps/publisher-client.mjs\",\"--stack\",\"$stack\"]"

# Only manager -> explicit operator waiter -> manager. systemd owns the cgroup.
while :; do
  /usr/bin/node "$root/session-manager.mjs" &
  child=$!
  trap 'kill "$child" 2>/dev/null || true; wait "$child" 2>/dev/null || true; exit 143' INT TERM
  wait "$child"
  status=$?
  trap - INT TERM
  if [ "$status" -eq 2 ]; then
    /usr/bin/node "$root/runtime/operator-waiter.mjs" &
    child=$!
    trap 'kill "$child" 2>/dev/null || true; wait "$child" 2>/dev/null || true; exit 143' INT TERM
    wait "$child"
    status=$?
    trap - INT TERM
    [ "$status" -eq 0 ] && continue
  fi
  [ "$status" -eq 0 ] && exit 0
  printf '%s\n' instagram_vps_manager_failed >&2
  exit 1
done
