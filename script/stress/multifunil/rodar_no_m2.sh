#!/bin/bash
# Roda o teste de estresse do multifunil (#1140) no M2, num snapshot do MacCluster, com IA de verdade. Nunca no CI.
#
# Uso (no M4, de dentro da worktree):
#   script/stress/multifunil/rodar_no_m2.sh <snapshot> <fase A|B> <teto_da_fase_usd> [ids|todas] [rodadas]
#   (STRESS_LOG_LEVEL=info grava no log/test.log do snapshot as linhas de info do sistema)
# Ex.: script/stress/multifunil/rodar_no_m2.sh 20261016-052100-b6c59773-a6900788ad-7818e594 A 1.20
#
# - Copia script/stress/multifunil/ para o src do snapshot no M2 (o snapshot é reaproveitado entre rodadas).
# - Banco PRÓPRIO chatwoot_stress no Postgres de teste do M2 (127.0.0.1:55432) e Redis db 11 (56379/11). Nunca o
#   chatwoot_test compartilhado. Preparar uma vez: db:create db:schema:load com POSTGRES_DATABASE=chatwoot_stress.
# - As chaves (OPENAI_API_KEY e TYPESAFE_API_KEY) saem do credentials.env do M4 direto para um arquivo 600 no M2, pelo
#   stdin do ssh, sem passar pela tela; o arquivo é apagado ao sair, com erro ou sem.
# - Traz o resultado para tmp/stress/fase-<FASE>/resultado.json desta worktree.
set -Eeuo pipefail
SNAP="${1:?snapshot}"; FASE="${2:?fase}"; TETO="${3:?teto da fase em US$}"; SO="${4:-todas}"; RODADAS="${5:-1}"; LOG="${STRESS_LOG_LEVEL:-warn}"
AQUI="$(cd "$(dirname "$0")" && pwd -P)"
RAIZ="$(cd "$AQUI/../../.." && pwd -P)"
WS="/Users/Shared/maccluster-workspaces/chat2you/$SNAP/src"
CRED=/Users/rodrigosilva/dev/claudete-ops/.secrets/credentials.env
SEGREDO="/Users/Shared/maccluster-test-services/stress-segredos-$$.env"

/usr/bin/tar -C "$RAIZ" -cf - script/stress/multifunil | ssh m2 "cd '$WS' && /usr/bin/tar -xf -"
trap 'ssh m2 "/bin/rm -f $SEGREDO" >/dev/null 2>&1 || true' EXIT
/usr/bin/grep -E '^(export )?(OPENAI_API_KEY|TYPESAFE_API_KEY)=' "$CRED" | ssh m2 "umask 077; /bin/cat > $SEGREDO"

ssh m2 /bin/bash -s -- "$WS" "$FASE" "$TETO" "$SO" "$SEGREDO" "$RODADAS" "$LOG" <<'REMOTO'
set -Eeuo pipefail
WS="$1"; FASE="$2"; TETO="$3"; SO="$4"; SEGREDO="$5"; RODADAS="$6"; LOG="$7"; [[ "$SO" == todas ]] && SO=""
R=/Users/Shared/maccluster-tools/ruby-3.4.4
N=/Users/Shared/maccluster-tools/node-v24.11.0
cd "$WS"
# Chaves de criptografia descartáveis, só deste banco de teste (o cofre de credenciais exige alguma).
CHAVES=/Users/Shared/maccluster-test-services/stress-cofre.env
[[ -f "$CHAVES" ]] || { umask 077; printf 'P=%s\nD=%s\nS=%s\n' "$(openssl rand -hex 16)" "$(openssl rand -hex 16)" "$(openssl rand -hex 16)" > "$CHAVES"; }
P=$(/usr/bin/sed -n 's/^P=//p' "$CHAVES"); D=$(/usr/bin/sed -n 's/^D=//p' "$CHAVES"); S=$(/usr/bin/sed -n 's/^S=//p' "$CHAVES")
/usr/bin/env -i HOME="$HOME" USER="$USER" PATH="$R/bin:$N/bin:/usr/bin:/bin:/usr/sbin:/sbin" LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 \
  GEM_HOME="$R/lib/ruby/gems/3.4.0" GEM_PATH="$R/lib/ruby/gems/3.4.0" BUNDLE_GEMFILE="$WS/Gemfile" BUNDLE_IGNORE_CONFIG=1 BUNDLE_FROZEN=true \
  RAILS_ENV=test RACK_ENV=test DISABLE_SPRING=1 LOG_LEVEL="$LOG" TZ=America/Sao_Paulo \
  POSTGRES_HOST=127.0.0.1 POSTGRES_PORT=55432 POSTGRES_DATABASE=chatwoot_stress POSTGRES_USERNAME=postgres POSTGRES_PASSWORD= \
  POSTGRES_STATEMENT_TIMEOUT=60s REDIS_URL=redis://127.0.0.1:56379/11 REDIS_PASSWORD= \
  ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY="$P" ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY="$D" ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT="$S" \
  CRM_KANBAN_ENABLED=true CRM_AI_ENABLED=true CRM_AI_MEDIA_ENABLED=false \
  STRESS_MULTIFUNIL=1 STRESS_FASE="$FASE" STRESS_TETO_USD="$TETO" STRESS_SO="$SO" STRESS_RODADAS="$RODADAS" STRESS_SEGREDOS_ARQUIVO="$SEGREDO" \
  "$R/bin/ruby" "$R/bin/bundle" exec "$R/bin/ruby" "$R/bin/rails" runner script/stress/multifunil/run.rb 2>&1 \
  | /usr/bin/grep -v -e 'DEPRECATION' -e 'enum :' -e 'called from' -e 'Positional arguments' -e '^$'
REMOTO

/bin/mkdir -p "$RAIZ/tmp/stress/fase-$FASE"
scp -q "m2:$WS/tmp/stress/fase-$FASE/resultado.json" "$RAIZ/tmp/stress/fase-$FASE/resultado.json"
echo "[stress] resultado em $RAIZ/tmp/stress/fase-$FASE/resultado.json"
