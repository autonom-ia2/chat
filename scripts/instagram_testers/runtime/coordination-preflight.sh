#!/bin/bash
set -euo pipefail
set +x
APP_DIR=/opt/chatwoot
# This file holds image/region only; Redis credentials stay in Docker env-files.
# shellcheck source=/dev/null
source "$APP_DIR/runtime.env"
# #1540 stderr contract, read by the deploy (boot and SSM steps): the sentinel line, then on
# failure exactly one verdict line. `instagram_coordination_preflight_failed step=<code>`
# is an Instagram failure: the deploy suspends Instagram assisted here instead of aborting.
# `instagram_coordination_preflight_host_failed step=<code>` is a host/Docker failure and
# stays fatal. INSTAGRAM_STEPS lists check.sh's suspending codes (the boot also
# suspends on tunnel_install_failed). A failing `ss` ends as tunnel_timeout: suspending is the
# safe side, and iproute is installed at boot. Rails output goes to
# stdout, so stderr stays far below SSM's 8000-char cut.
echo instagram_coordination_preflight_ran >&2
INSTAGRAM_STEPS=' tunnel_timeout tunnel_inactive coordination_ping_failed proxy_configuration_invalid proxy_preflight_failed rails_preflight_failed '
reported=''
rails_output=''
host_fail() {
  reported=1
  echo "instagram_coordination_preflight_host_failed step=$1" >&2
  exit 1
}
fail() {
  case "$INSTAGRAM_STEPS" in *" $1 "*) ;; *) host_fail preflight_failed ;; esac
  reported=1
  echo "instagram_coordination_preflight_failed step=$1" >&2
  # Legacy tunnel tokens stay (after the code) for existing greps.
  case "$1" in tunnel_*) echo "instagram_coordination_$1" >&2 ;; esac
  exit 1
}
# Any other failure after the sentinel is the host's, never a reason to suspend.
trap 'status=$?; [ -z "$rails_output" ] || rm -f "$rails_output"; if [ "$status" -ne 0 ] && [ -z "$reported" ]; then echo "instagram_coordination_preflight_host_failed step=preflight_failed" >&2; fi' EXIT
systemctl is-active --quiet instagram-coordination-tunnel.service || fail tunnel_inactive

# An active unit only means ssh started. ssh binds its -L listeners only after
# it authenticated (ExitOnForwardFailure), so wait until ssh itself listens on
# both forwards before the Rails preflight; on a fresh green this takes seconds.
# The check reads local sockets only: it opens no channel to Redis or the proxy.
# A listening forward does not prove the far end is up; the Rails preflight
# below still checks Redis and the proxy for real.
gateway=$(docker network inspect bridge --format '{{(index .IPAM.Config 0).Gateway}}') || host_fail host_gateway_unavailable
# The traceback would only push the code down the short stderr; the code says it all.
python3 -c 'import ipaddress, sys; ipaddress.IPv4Address(sys.argv[1])' "$gateway" 2>/dev/null || host_fail host_gateway_unavailable
wait_seconds=60
ssh_listens_on() {
  ss -Hltnp | awk -v address="$1" '$4 == address && index($0, "\"ssh\"") { found = 1 } END { exit !found }'
}
tunnel_ready() {
  ssh_listens_on "$gateway:16381" && ssh_listens_on "$gateway:16380"
}
deadline=$((SECONDS + wait_seconds))
until tunnel_ready; do
  if ! systemctl is-active --quiet instagram-coordination-tunnel.service; then
    fail tunnel_inactive
  fi
  if [ "$SECONDS" -ge "$deadline" ]; then
    fail tunnel_timeout
  fi
  sleep 1
done

rails_output=$(mktemp)
rails_status=0
docker run --rm --env-file "$APP_DIR/.env" --env-file "$APP_DIR/instagram-tester.env" \
  --env-file "$APP_DIR/igcoord/redis.env" \
  --add-host ig-coord.internal:host-gateway --add-host ig-proxy.internal:host-gateway \
  -v "$APP_DIR/igcoord/ca.crt:/run/igcoord/ca.crt:ro" \
  "$IMAGE_URI" bundle exec rails runner scripts/instagram_testers/runtime/coordination_preflight.rb 2>"$rails_output" || rails_status=$?
cat "$rails_output"
[ "$rails_status" -ne 0 ] || exit 0
# The Ruby script's own lines: it announces itself, then classifies StandardError and ScriptError.
step=''
ruby_started=''
while IFS= read -r line || [ -n "$line" ]; do
  case "$line" in
    instagram_coordination_preflight_rails_started) ruby_started=1 ;;
    "instagram_coordination_preflight_failed step="*) step=${line#*step=} ;;
  esac
done < "$rails_output"
# Docker or Rails boot never reached the script: host/application failure, fatal.
[ -n "$ruby_started" ] || host_fail host_docker_failed
if [ -z "$step" ]; then
  # Killed by a signal (OOM, docker stop): the host's failure. A plain crash is the script's.
  [ "$rails_status" -lt 128 ] || host_fail host_rails_killed
  step=rails_preflight_failed
fi
case "$INSTAGRAM_STEPS" in *" $step "*) ;; *) step=rails_preflight_failed ;; esac
fail "$step"
