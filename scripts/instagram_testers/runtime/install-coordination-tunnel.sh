#!/bin/bash
set -euo pipefail
set +x
umask 077

if [ "${1:-}" = tunnel ]; then
  [ "$#" -eq 2 ]
  coord_dir="$2"
  {
    IFS= read -r proxy_host
    IFS= read -r proxy_port
  } < "$coord_dir/tunnel.env"
  gateway=$(docker network inspect bridge --format '{{(index .IPAM.Config 0).Gateway}}')
  python3 -c 'import ipaddress, sys; ipaddress.IPv4Address(sys.argv[1])' "$gateway"
  exec ssh -F /dev/null -NTn -g -i "$coord_dir/ssh.key" \
    -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes \
    -o "UserKnownHostsFile=$coord_dir/known_hosts" -o GlobalKnownHostsFile=/dev/null \
    -o UpdateHostKeys=no -o ConnectTimeout=10 -o ExitOnForwardFailure=yes \
    -o ServerAliveInterval=15 -o ServerAliveCountMax=3 \
    -L "$gateway:16381:127.0.0.1:6381" \
    -L "$gateway:16380:$proxy_host:$proxy_port" igcoord@85.31.60.100
fi

[ "${1:-}" = install ] && [ "$#" -eq 3 ] && [ "$(id -u)" -eq 0 ]
region="$2"
app_dir="$3"
coord_dir="$app_dir/igcoord"
source_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
stage_dir=$(mktemp -d /run/instagram-coordination.XXXXXX)
trap 'rm -rf "$stage_dir"' EXIT

for parameter in ssh-key redis-env ca known-hosts; do
  if ! aws ssm get-parameter --region "$region" \
    --name "/chatwoot/prod/instagram-coordination/$parameter" --with-decryption \
    --output json > "$stage_dir/$parameter.json" 2> "$stage_dir/ssm-error"; then
    echo instagram_coordination_fetch_failed >&2
    exit 1
  fi
done

python3 "$source_dir/validate-coordination-env.py" "$stage_dir" "$app_dir"
ssh-keygen -y -P '' -f "$stage_dir/ssh.key" > "$stage_dir/public-key" 2> "$stage_dir/key-error"
ssh-keygen -F 85.31.60.100 -f "$stage_dir/known_hosts" > /dev/null
openssl x509 -in "$stage_dir/ca.crt" -noout > /dev/null 2> "$stage_dir/ca-error"

install -d -m 700 "$coord_dir"
for filename in ssh.key redis.env known_hosts tunnel.env; do
  install -m 600 "$stage_dir/$filename" "$coord_dir/$filename"
done
install -m 644 "$stage_dir/ca.crt" "$coord_dir/ca.crt"
install -m 700 "$source_dir/install-coordination-tunnel.sh" "$coord_dir/tunnel.sh"
install -m 700 "$source_dir/coordination-preflight.sh" "$coord_dir/check.sh"

cat > /etc/systemd/system/instagram-coordination-tunnel.service <<EOF
[Unit]
Description=Instagram dedicated Redis and Webshare SSH tunnel
After=docker.service network-online.target
Wants=network-online.target
Requires=docker.service
PartOf=docker.service

[Service]
ExecStart=/bin/bash $coord_dir/tunnel.sh tunnel $coord_dir
Restart=always
RestartSec=5
MemoryMax=64M
CPUQuota=10%
TasksMax=32
NoNewPrivileges=yes
ProtectSystem=strict
ProtectHome=yes

[Install]
WantedBy=multi-user.target
EOF
systemctl daemon-reload
systemctl enable instagram-coordination-tunnel.service
systemctl restart instagram-coordination-tunnel.service
systemctl is-active --quiet instagram-coordination-tunnel.service
