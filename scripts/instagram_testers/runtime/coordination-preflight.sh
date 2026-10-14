#!/bin/bash
set -euo pipefail
set +x
APP_DIR=/opt/chatwoot
# This file holds image/region only; Redis credentials stay in Docker env-files.
# shellcheck source=/dev/null
source "$APP_DIR/runtime.env"
systemctl is-active --quiet instagram-coordination-tunnel.service

# An active unit only means ssh started. ssh binds its -L listeners only after
# it authenticated (ExitOnForwardFailure), so wait until ssh itself listens on
# both forwards before the Rails preflight; on a fresh green this takes seconds.
# The check reads local sockets only: it opens no channel to Redis or the proxy.
# A listening forward does not prove the far end is up; the Rails preflight
# below still checks Redis and the proxy for real.
gateway=$(docker network inspect bridge --format '{{(index .IPAM.Config 0).Gateway}}')
python3 -c 'import ipaddress, sys; ipaddress.IPv4Address(sys.argv[1])' "$gateway"
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
    echo instagram_coordination_tunnel_inactive >&2
    exit 1
  fi
  if [ "$SECONDS" -ge "$deadline" ]; then
    echo instagram_coordination_tunnel_timeout >&2
    exit 1
  fi
  sleep 1
done

docker run --rm --env-file "$APP_DIR/.env" --env-file "$APP_DIR/instagram-tester.env" \
  --env-file "$APP_DIR/igcoord/redis.env" \
  --add-host ig-coord.internal:host-gateway --add-host ig-proxy.internal:host-gateway \
  -v "$APP_DIR/igcoord/ca.crt:/run/igcoord/ca.crt:ro" \
  "$IMAGE_URI" bundle exec rails runner scripts/instagram_testers/runtime/coordination_preflight.rb
