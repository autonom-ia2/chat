#!/bin/bash
set -euo pipefail
set +x
APP_DIR=/opt/chatwoot
# This file holds image/region only; Redis credentials stay in Docker env-files.
# shellcheck source=/dev/null
source "$APP_DIR/runtime.env"
systemctl is-active --quiet instagram-coordination-tunnel.service
docker run --rm --env-file "$APP_DIR/.env" --env-file "$APP_DIR/instagram-tester.env" \
  --env-file "$APP_DIR/igcoord/redis.env" \
  --add-host ig-coord.internal:host-gateway --add-host ig-proxy.internal:host-gateway \
  -v "$APP_DIR/igcoord/ca.crt:/run/igcoord/ca.crt:ro" \
  "$IMAGE_URI" bundle exec rails runner scripts/instagram_testers/runtime/coordination_preflight.rb
