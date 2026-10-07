#!/usr/bin/env bash
# Instala pacotes do apt no runner sem deixar um mirror lento segurar o job (#1131).
# Cada tentativa tem teto de tempo; se travar ou falhar, conserta o dpkg e tenta de novo.
# Uso: .github/scripts/apt-install.sh pacote1 pacote2 ...
set -uo pipefail

ATTEMPTS=3
ATTEMPT_TIMEOUT=240
APT_OPTS=(-o Acquire::Retries=3 -o Acquire::http::Timeout=30 -o Acquire::https::Timeout=30 -o DPkg::Lock::Timeout=60)

for attempt in $(seq 1 "$ATTEMPTS"); do
  if timeout -k 10 "$ATTEMPT_TIMEOUT" sudo apt-get "${APT_OPTS[@]}" update -qq &&
     timeout -k 10 "$ATTEMPT_TIMEOUT" sudo DEBIAN_FRONTEND=noninteractive apt-get "${APT_OPTS[@]}" install -y "$@"; then
    exit 0
  fi
  echo "::warning::apt falhou ou passou de ${ATTEMPT_TIMEOUT}s (tentativa ${attempt}/${ATTEMPTS})"
  sudo dpkg --configure -a || true
  sleep 10
done

echo "::error::apt não instalou: $*"
exit 1
