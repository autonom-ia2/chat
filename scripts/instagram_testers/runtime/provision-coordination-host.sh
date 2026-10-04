#!/bin/bash
set +x
set -euo pipefail
umask 077
# NEW ONLY. Run locally on the approved Linux host; never through startup hooks.
fail() { printf 'instagram_coordination_blocked: %s\n' "$1" >&2; exit 1; }
trap 'printf "instagram_coordination_blocked: provisioning failed; preserve partial resources for review, never rerun or reset\n" >&2' ERR
[ "$(id -u)" = 0 ] || fail root_required
[ "$#" = 3 ] || fail 'usage: provision-coordination-host.sh WEBSHARE_DIRECT_IPV4 PORT EXPECTED_EGRESS_IPV4'
B=/opt/instagram-coordination
SSH_CONFIG=/etc/ssh/sshd_config.d/70-instagram-coordination.conf
SSH_HOME=/home/igcoord
VOLUME=instagram_coordination_data
CONTAINER=instagram-coordination-redis
NETWORK=instagram-coordination-bridge
WEB_HOST=$1 WEB_PORT=$2 WEB_EGRESS=$3
for executable in docker python3 openssl ssh-keygen sshd ss getent curl systemctl useradd usermod install timeout; do
  command -v "$executable" >/dev/null || fail "missing_dependency:$executable"
done
# Every inspection must succeed. List queries avoid treating inspect errors as absence.
VERSION=$(docker version --format '{{.Server.Version}}')
VOLUMES=$(docker volume ls --format '{{.Name}}')
CONTAINERS=$(docker ps -a --format '{{.Names}}')
NETWORKS=$(docker network ls --format '{{.Name}}')
USERS=$(getent passwd)
GROUPS_LIST=$(getent group)
LISTENERS=$(ss -H -ltn 'sport = :6381')
export VERSION VOLUMES CONTAINERS NETWORKS USERS GROUPS_LIST LISTENERS
python3 - "$B" "$SSH_CONFIG" "$SSH_HOME" "$WEB_HOST" "$WEB_PORT" "$WEB_EGRESS" <<'PY'
import ipaddress, os, sys
from pathlib import Path

def block(reason):
    raise SystemExit('instagram_coordination_blocked: ' + reason)

major = os.environ['VERSION'].split('.')[0]
if not major.isascii() or not major.isdecimal() or int(major) < 28:
    block('Docker_server_28_required_before_writes')
for path in sys.argv[1:4]:
    if os.path.lexists(path):
        block('preexisting_path:' + path)
for variable, name in [('VOLUMES', 'instagram_coordination_data'),
                       ('CONTAINERS', 'instagram-coordination-redis'),
                       ('NETWORKS', 'instagram-coordination-bridge')]:
    if name in os.environ[variable].splitlines():
        block('preexisting_resource:' + name)
for variable in ('USERS', 'GROUPS_LIST'):
    if any(row.split(':')[0] == 'igcoord' for row in os.environ[variable].splitlines()):
        block('preexisting_ssh_user_or_group:igcoord')
if os.environ['LISTENERS'].strip():
    block('port_6381_in_use')
for address in (sys.argv[4], sys.argv[6]):
    ip = ipaddress.IPv4Address(address)
    if not ip.is_global:
        block('Webshare_Direct_requires_public_IPv4')
port = sys.argv[5]
if not port.isascii() or not port.isdecimal() or not 1 <= int(port) <= 65535:
    block('invalid_Webshare_Direct_port')
PY
docker compose version >/dev/null
sshd -t
systemctl is-active --quiet ssh && SSH_SERVICE=ssh || {
  systemctl is-active --quiet sshd || fail ssh_service_inactive
  SSH_SERVICE=sshd
}
# No credentials, redirects, retries, curlrc or direct fallback. Expected residential
# egress must come from the reviewed Webshare Direct inventory, not this response.
EGRESS=$(curl -q --silent --show-error --fail --max-time 20 --noproxy '' \
  --proxy "http://$WEB_HOST:$WEB_PORT" --write-out '\n%{http_code} %{http_connect}' https://ipv4.webshare.io/)
export EGRESS WEB_EGRESS
python3 - <<'PYPROXY'
import os
lines = [line for line in os.environ['EGRESS'].splitlines() if line]
if lines != [os.environ['WEB_EGRESS'], '200 200']:
    raise SystemExit('instagram_coordination_blocked: Webshare_Direct_egress_or_HTTP_mismatch')
PYPROXY
# Nothing above creates resources. Exclusive mkdir reserves this installation.
mkdir -m 700 "$B"
cd "$B"
install -d -m 700 private tls etc
docker pull redis:7.4-alpine >/dev/null
IMAGE=$(docker image inspect redis:7.4-alpine --format '{{index .RepoDigests 0}}')
[ -n "$IMAGE" ] || fail missing_image_digest
REDIS_UID=$(docker run --rm --entrypoint sh "$IMAGE" -c 'id -u redis')
REDIS_GID=$(docker run --rm --entrypoint sh "$IMAGE" -c 'id -g redis')
export REDIS_IMAGE="$IMAGE" REDIS_UID REDIS_GID
printf '%s\n' "REDIS_IMAGE=$IMAGE" "REDIS_UID=$REDIS_UID" "REDIS_GID=$REDIS_GID" > .env
openssl req -x509 -newkey rsa:3072 -nodes -days 1825 -subj /CN=InstagramCoordinationCA -addext basicConstraints=critical,CA:TRUE -keyout private/ca.key -out tls/ca.crt >/dev/null 2>&1
openssl req -new -newkey rsa:2048 -nodes -subj /CN=ig-coord.internal -keyout tls/server.key -out private/server.csr >/dev/null 2>&1
printf '%s\n' 'subjectAltName=DNS:ig-coord.internal' 'extendedKeyUsage=serverAuth' 'basicConstraints=critical,CA:FALSE' > etc/server.ext
openssl x509 -req -in private/server.csr -CA tls/ca.crt -CAkey private/ca.key -CAcreateserial -days 365 -extfile etc/server.ext -out tls/server.crt >/dev/null 2>&1
openssl verify -CAfile tls/ca.crt -verify_hostname ig-coord.internal tls/server.crt >/dev/null
for u in ig_hub ig_auto ig_admin; do openssl rand -hex 32 > "private/$u.pass"; done
for u in ig_hub ig_auto ig_m4; do ssh-keygen -q -t ed25519 -N '' -f "private/$u.key"; done
openssl rand -hex 32 > private/epoch
python3 - <<'PY'
from pathlib import Path
import hashlib
p = Path('.')
rows = ['user default reset off']
for user in ('ig_hub', 'ig_auto'):
    password = (p / f'private/{user}.pass').read_text().strip()
    rows.append(f'user {user} reset on #{hashlib.sha256(password.encode()).hexdigest()} '
                'resetchannels -@all +ping +select +unwatch +multi +exec +discard +waitaof '
                '(~instagram_tester_coordination:instagram_testers:invite:* -@all +get +set +del +watch) '
                '(~instagram_tester_coordination:integrity:epoch -@all +get)')
    epoch = (p / 'private/epoch').read_text().strip()
    (p / f'private/{user}.env').write_text(
        f'INSTAGRAM_TESTER_COORDINATION_REDIS_URL=rediss://{user}:{password}@ig-coord.internal:16381/0\n'
        f'INSTAGRAM_TESTER_COORDINATION_EPOCH={epoch}\n'
        'INSTAGRAM_TESTER_COORDINATION_REDIS_CA_FILE=/run/igcoord/ca.crt\n')
password = (p / 'private/ig_admin.pass').read_text().strip()
rows.append(f'user ig_admin reset on #{hashlib.sha256(password.encode()).hexdigest()} ~* &* +@all')
(p / 'etc/users.acl').write_text('\n'.join(rows) + '\n')
PY
cat > etc/redis.conf <<'EOF'
bind 0.0.0.0
protected-mode yes
port 0
tls-port 6381
tls-cert-file /tls/server.crt
tls-key-file /tls/server.key
tls-ca-cert-file /tls/ca.crt
tls-auth-clients no
aclfile /etc/igcoord/users.acl
dir /data
databases 1
appendonly yes
appendfsync always
no-appendfsync-on-rewrite no
aof-load-truncated no
auto-aof-rewrite-percentage 100
auto-aof-rewrite-min-size 16mb
save ""
maxmemory 64mb
maxmemory-policy noeviction
maxclients 128
EOF
cat > compose.yml <<'EOF'
services:
  redis:
    image: ${REDIS_IMAGE:?}
    container_name: instagram-coordination-redis
    user: "${REDIS_UID:?}:${REDIS_GID:?}"
    command: ["redis-server", "/etc/igcoord/redis.conf"]
    restart: unless-stopped
    read_only: true
    cap_drop: [ALL]
    security_opt: ["no-new-privileges:true"]
    cpus: 0.25
    mem_limit: 256m
    memswap_limit: 256m
    pids_limit: 64
    tmpfs: ["/tmp:size=16m"]
    ports: ["127.0.0.1:6381:6381"]
    networks: [coordination]
    volumes: ["./etc:/etc/igcoord:ro", "./tls:/tls:ro", "data:/data"]
    logging:
      driver: json-file
      options: {max-size: "10m", max-file: "3"}
volumes:
  data:
    external: true
    name: instagram_coordination_data
networks:
  coordination:
    external: true
    name: instagram-coordination-bridge
EOF
chown "$REDIS_UID:$REDIS_GID" tls etc tls/ca.crt tls/server.crt tls/server.key etc/redis.conf etc/users.acl
chmod 750 tls etc
chmod 640 tls/ca.crt tls/server.crt tls/server.key etc/redis.conf etc/users.acl
docker volume create "$VOLUME" >/dev/null
docker network create --driver bridge --internal "$NETWORK" >/dev/null
docker run --rm --network none --entrypoint sh -v "$VOLUME:/data" "$IMAGE" -c "chown $REDIS_UID:$REDIS_GID /data"
docker compose -p instagram-coordination up -d >/dev/null
# Admin password only travels on stdin; never argv, Docker metadata or logs.
redis_admin() {
  { cat private/ig_admin.pass; printf '%s\n' "$@"; } |
    timeout --signal=TERM --kill-after=2s 10s docker exec -i "$CONTAINER" sh -c 'IFS= read -r REDISCLI_AUTH; export REDISCLI_AUTH; exec redis-cli -e --raw --tls --cacert /tls/ca.crt --user ig_admin -h 127.0.0.1 -p 6381'
}
READY=no
for i in $(seq 1 20); do
  if PONG=$(redis_admin PING 2>/dev/null) && [ "$PONG" = PONG ]; then READY=yes; break; fi
  sleep 1
done
[ "$READY" = yes ] || fail Redis_TLS_startup_failed
# Same connection: NX initialization followed by fsync proof. No startup epoch setter.
SYNC=$(redis_admin "SET instagram_tester_coordination:integrity:epoch $(cat private/epoch) NX" 'WAITAOF 1 0 5000')
[ "$SYNC" = "$(printf 'OK\n1\n0')" ] || fail epoch_initialization_or_persistence_failed
for user in ig_hub ig_auto; do
  CHECK=$(redis_admin "ACL DRYRUN $user GET instagram_tester_coordination:integrity:epoch")
  [ "$CHECK" = OK ] || fail epoch_read_ACL_failed
  for command in SET DEL; do
    arguments=instagram_tester_coordination:integrity:epoch
    [ "$command" != SET ] || arguments="$arguments denied"
    if CHECK=$(redis_admin "ACL DRYRUN $user $command $arguments"); then
      STATUS=0
    else
      STATUS=$?
    fi
    case "$CHECK" in
      "User $user has no permissions to access the 'instagram_tester_coordination:integrity:epoch' key"|"This user has no permissions to access the 'instagram_tester_coordination:integrity:epoch' key") ;;
      *) fail "epoch_write_ACL_failed:$STATUS" ;;
    esac
  done
done
useradd --create-home --shell /usr/sbin/nologin igcoord
usermod --password '*' igcoord
install -d -m 700 -o igcoord -g igcoord "$SSH_HOME/.ssh"
{
  for user in ig_hub ig_auto; do
    printf 'restrict,port-forwarding,permitopen="127.0.0.1:6381",permitopen="%s:%s" %s\n' "$WEB_HOST" "$WEB_PORT" "$(cat "private/$user.key.pub")"
  done
  printf 'restrict,port-forwarding,permitopen="%s:%s" %s\n' "$WEB_HOST" "$WEB_PORT" "$(cat private/ig_m4.key.pub)"
} > "$SSH_HOME/.ssh/authorized_keys"
chown igcoord:igcoord "$SSH_HOME/.ssh/authorized_keys"
chmod 600 "$SSH_HOME/.ssh/authorized_keys"
cat > "$SSH_CONFIG" <<'EOF'
Match User igcoord
  AuthenticationMethods publickey
  PubkeyAuthentication yes
  PasswordAuthentication no
  KbdInteractiveAuthentication no
  AuthorizedKeysFile .ssh/authorized_keys
  AuthorizedKeysCommand none
  TrustedUserCAKeys none
  AllowTcpForwarding local
  AllowStreamLocalForwarding no
  MaxSessions 0
  PermitTTY no
  AllowAgentForwarding no
  X11Forwarding no
Match all
EOF
sshd -t
EFFECTIVE=$(sshd -T -C user=igcoord,host=localhost,addr=127.0.0.1)
export EFFECTIVE
python3 - <<'PYSSH'
import os
settings = dict(row.split(' ', 1) for row in os.environ['EFFECTIVE'].splitlines())
required = {'authenticationmethods': 'publickey', 'pubkeyauthentication': 'yes',
            'passwordauthentication': 'no', 'kbdinteractiveauthentication': 'no',
            'authorizedkeysfile': '.ssh/authorized_keys', 'authorizedkeyscommand': 'none',
            'trustedusercakeys': 'none', 'allowtcpforwarding': 'local',
            'allowstreamlocalforwarding': 'no', 'maxsessions': '0', 'permittty': 'no',
            'allowagentforwarding': 'no', 'x11forwarding': 'no'}
if any(settings.get(key) != value for key, value in required.items()):
    raise SystemExit('instagram_coordination_blocked: effective_sshd_restrictions_mismatch')
PYSSH
systemctl reload "$SSH_SERVICE"
printf 'instagram_coordination_provisioned: new resources only; credentials remain local; runtime review required\n'
