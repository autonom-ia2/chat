#!/bin/bash
# Lado M2 do kit de demo em tela real (#2140). Quem chama é o bin/demo, por ssh.
# Tudo aqui age só dentro da demo <slug>: pasta /Users/Shared/chat2you-demos/<slug>,
# banco chatwoot_kitdemo_<slug>, Redis e portas gravados em demo.env. Runbook: docs/runbooks/demo-tela-real.md.
set -euo pipefail

cmd=${1:?comando}
slug=${2:?slug}
shift 2

RAIZ=/Users/Shared/chat2you-demos
L=$RAIZ/$slug
KIT=$L/kit
T=/Users/Shared/maccluster-tools
R=$T/ruby-3.4.4
N=$T/node-v24.11.0
PGBIN=$T/postgresql-17.11/bin
REDISBIN=$T/deps/redis-8.10.2/bin
PG_HOST=127.0.0.1
PG_PORT=55432
PREFIXO_BANCO=chatwoot_kitdemo_
PREFIXO_SNAPSHOT=/Users/Shared/maccluster-workspaces/chat2you/
ESPERA_RAILS_SEGUNDOS=900

falha() { echo "demo[$slug]: $*" >&2; exit 1; }

case "$slug" in
  '' | *[!a-z0-9-]* | -*) falha "slug inválido" ;;
esac

carregar_estado() {
  [ -f "$L/demo.env" ] || falha "demo não existe no M2 ($L/demo.env). Rode: bin/demo up $slug"
  # shellcheck source=/dev/null
  source "$L/demo.env"
  [ "$DB" = "${PREFIXO_BANCO}${slug//-/_}" ] || falha "demo.env aponta para outro banco ($DB)"
}

psql_demo() { "$PGBIN/psql" -h "$PG_HOST" -p "$PG_PORT" -U postgres -v ON_ERROR_STOP=1 "$@"; }

banco_existe() {
  [ "$(psql_demo -d postgres -Atc "SELECT 1 FROM pg_database WHERE datname = '$1'")" = "1" ]
}

# SNAP, DB e as portas vêm do demo.env (carregar_estado).
# shellcheck disable=SC2153
demo_env() {
  /usr/bin/env -i HOME="$HOME" USER="$USER" LOGNAME="$USER" \
    PATH="$R/bin:$N/bin:/usr/bin:/bin:/usr/sbin:/sbin" LANG=en_US.UTF-8 LC_ALL=en_US.UTF-8 \
    GEM_HOME="$R/lib/ruby/gems/3.4.0" GEM_PATH="$R/lib/ruby/gems/3.4.0" \
    BUNDLE_GEMFILE="$SNAP/Gemfile" BUNDLE_IGNORE_CONFIG=1 BUNDLE_FROZEN=true \
    COREPACK_HOME="$T/corepack" COREPACK_ENABLE_NETWORK=0 \
    RAILS_ENV=development RACK_ENV=development NODE_ENV=development DISABLE_SPRING=1 \
    DISABLE_MINI_PROFILER=1 AWS_EC2_METADATA_DISABLED=true \
    POSTGRES_HOST="$PG_HOST" POSTGRES_PORT="$PG_PORT" POSTGRES_DATABASE="$DB" \
    POSTGRES_USERNAME=postgres POSTGRES_PASSWORD= \
    REDIS_URL="redis://127.0.0.1:$REDIS_PORT/0" REDIS_PASSWORD= \
    SECRET_KEY_BASE="$(/bin/cat "$L/chaves/secret")" \
    ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY="$(/bin/cat "$L/chaves/enc_p")" \
    ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY="$(/bin/cat "$L/chaves/enc_d")" \
    ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT="$(/bin/cat "$L/chaves/enc_s")" \
    FRONTEND_URL="http://localhost:$RAILS_PORT" ENABLE_ACCOUNT_SIGNUP=false \
    VITE_RUBY_PORT="$VITE_PORT" VITE_RUBY_HOST=localhost VITE_RUBY_AUTO_BUILD=false \
    VITE_RUBY_DEV_SERVER_CONNECT_TIMEOUT=2 NODE_OPTIONS=--max-old-space-size=4096 \
    WHATSAPP_CLOUD_BASE_URL=http://127.0.0.1:9 CRM_KANBAN_ENABLED=true \
    "$@"
}

escutando() { /usr/sbin/lsof -tiTCP:"$1" -sTCP:LISTEN 2>/dev/null || true; }

cwd_do_pid() {
  local linha
  linha=$(/usr/sbin/lsof -a -p "$1" -d cwd -Fn 2>/dev/null | /usr/bin/tail -1)
  echo "${linha#n}"
}

# Uma porta "é nossa" quando quem escuta nela roda dentro do snapshot desta demo.
porta_livre_ou_nossa() {
  local porta=$1 pid
  for pid in $(escutando "$porta"); do
    case "$(cwd_do_pid "$pid")" in
      "$SNAP"*) ;;
      *) falha "porta $porta ocupada por outro processo (pid $pid). Use outro slug." ;;
    esac
  done
}

# --- checar: antes do snapshot, confirma que banco e portas desta demo estão livres ---
checar() {
  local rails=$1 vite=$2 redis=$3 outro porta
  [ ! -e "$L/demo.env" ] || falha "demo já iniciada"
  DB="${PREFIXO_BANCO}${slug//-/_}"
  if banco_existe "$DB"; then
    falha "o banco $DB já existe sem demo registrada. Confira com o dono antes de apagar."
  fi
  for outro in "$RAIZ"/*/demo.env; do
    [ -f "$outro" ] || continue
    if /usr/bin/grep -qxF "RAILS_PORT=$rails" "$outro" || /usr/bin/grep -qxF "REDIS_PORT=$redis" "$outro"; then
      falha "portas $rails/$redis já usadas por $(dirname "$outro"). Use outro slug."
    fi
  done
  for porta in "$rails" "$vite" "$redis"; do
    [ -z "$(escutando "$porta")" ] || falha "porta $porta ocupada por outro processo. Use outro slug."
  done
  echo "banco $DB e portas $rails/$vite/$redis livres"
}

# --- clonar-base: cria no M2 o diretório do snapshot novo como clone APFS do snapshot chat2you mais recente ---
# O bin/demo completa a cópia com rsync (só a diferença). node_modules vem junto no clone e o pnpm acerta.
clonar_base() {
  local destino=$1 base='' d
  case "$destino" in
    "$PREFIXO_SNAPSHOT"*/* | *..*) falha "destino suspeito: $destino" ;;
    "$PREFIXO_SNAPSHOT"?*) ;;
    *) falha "destino fora de $PREFIXO_SNAPSHOT: $destino" ;;
  esac
  [ ! -e "$destino" ] || falha "destino já existe: $destino"
  for d in $(/bin/ls -td "$PREFIXO_SNAPSHOT"*/); do
    d=${d%/}
    if [ -f "$d/.maccluster-workspace.json" ] && [ -f "$d/src/Gemfile" ] && [ -d "$d/src/node_modules" ]; then
      base=$d
      break
    fi
  done
  [ -n "$base" ] || falha "nenhum snapshot chat2you com node_modules no M2 para servir de base"
  echo "base no M2: $base (clone APFS)"
  mkdir "$destino"
  /bin/cp -c -R "$base/src" "$destino/src"
  # Logs, pids e caches da outra demo não vêm junto.
  /bin/rm -rf "$destino/src/log" "$destino/src/tmp" "$destino/src/storage" "$destino/src/public/vite-dev" \
    "$destino/src/public/vite-test"
  mkdir -p "$destino/src/log" "$destino/src/tmp/pids"
}

# --- iniciar: grava demo.env e as chaves locais da demo (nunca reaproveita outra demo) ---
iniciar() {
  local snap=$1 base=$2 origem=$3 rails=$4 vite=$5 redis=$6
  checar "$rails" "$vite" "$redis" > /dev/null
  [ -d "$snap" ] || falha "snapshot não chegou ao M2: $snap"
  case "$snap" in
    "$PREFIXO_SNAPSHOT"*/src) ;;
    *) falha "snapshot fora de $PREFIXO_SNAPSHOT: $snap" ;;
  esac
  mkdir -p "$L/chaves" "$L/redis"
  chmod 700 "$L/chaves"
  /usr/bin/openssl rand -hex 64 > "$L/chaves/secret"
  for k in enc_p enc_d enc_s; do /usr/bin/openssl rand -hex 16 > "$L/chaves/$k"; done
  chmod 600 "$L/chaves/"*
  printf '%s=%q\n' SLUG "$slug" SNAP "$snap" BASE_SHA "$base" ORIGEM "$origem" DB "$DB" \
    RAILS_PORT "$rails" VITE_PORT "$vite" REDIS_PORT "$redis" > "$L/demo.env.tmp"
  mv "$L/demo.env.tmp" "$L/demo.env"
  echo "demo $slug registrada: banco $DB, Rails $rails, Vite $vite, Redis $redis"
}

subir_redis() {
  if "$REDISBIN/redis-cli" -p "$REDIS_PORT" ping >/dev/null 2>&1; then
    [ "$("$REDISBIN/redis-cli" -p "$REDIS_PORT" config get dir | /usr/bin/tail -1)" = "$L/redis" ] ||
      falha "Redis na porta $REDIS_PORT não é desta demo"
    return
  fi
  "$REDISBIN/redis-server" --port "$REDIS_PORT" --bind 127.0.0.1 --save "" --appendonly no \
    --daemonize yes --dir "$L/redis" --logfile "$L/redis.log"
  local n=0
  until "$REDISBIN/redis-cli" -p "$REDIS_PORT" ping >/dev/null 2>&1; do
    n=$((n + 1))
    [ $n -le 20 ] || falha "Redis não subiu na porta $REDIS_PORT (log $L/redis.log)"
    sleep 0.5
  done
}

preparar() {
  carregar_estado
  [ ! -f "$L/preparado" ] || return 0
  subir_redis
  cd "$SNAP"
  echo "pnpm install (painel)..."
  demo_env pnpm install --frozen-lockfile --prefer-offline > "$L/pnpm.log" 2>&1 ||
    { /usr/bin/tail -30 "$L/pnpm.log"; falha "pnpm install falhou (log: $L/pnpm.log)"; }
  echo "pnpm install (playwright, para os prints)..."
  (cd tests/playwright && demo_env pnpm install --frozen-lockfile --prefer-offline --ignore-scripts) > "$L/pnpm-pw.log" 2>&1 ||
    { /usr/bin/tail -30 "$L/pnpm-pw.log"; falha "pnpm install do playwright falhou (log: $L/pnpm-pw.log)"; }
  echo "banco $DB: create + schema:load + seed..."
  demo_env bundle exec rails db:create db:schema:load db:seed > "$L/banco.log" 2>&1 ||
    { /usr/bin/tail -30 "$L/banco.log"; falha "preparo do banco falhou (log: $L/banco.log)"; }
  echo "dados de exemplo da conta + idioma pt-BR..."
  demo_env bundle exec rails runner "$KIT/preparar_conta.rb" > "$L/conta.log" 2>&1 ||
    { /usr/bin/tail -30 "$L/conta.log"; falha "seed da conta falhou (log: $L/conta.log)"; }
  /usr/bin/tail -1 "$L/conta.log"
  /usr/bin/touch "$L/preparado"
}

# Processos de longa duração: o subir chama estes por nohup, com cwd no snapshot (o descer confere o cwd).
_rails() { carregar_estado; cd "$SNAP"; demo_env bundle exec rails s -p "$RAILS_PORT" -b 127.0.0.1; }
_vite() { carregar_estado; cd "$SNAP"; demo_env bundle exec vite dev; }

subir() {
  carregar_estado
  subir_redis
  porta_livre_ou_nossa "$RAILS_PORT"
  porta_livre_ou_nossa "$VITE_PORT"
  if [ -z "$(escutando "$VITE_PORT")" ]; then
    nohup /bin/bash "$KIT/no_m2.sh" _vite "$slug" > "$L/vite.log" 2>&1 < /dev/null &
  fi
  if [ -z "$(escutando "$RAILS_PORT")" ]; then
    /bin/rm -f "$SNAP/tmp/pids/server.pid"
    nohup /bin/bash "$KIT/no_m2.sh" _rails "$slug" > "$L/rails.log" 2>&1 < /dev/null &
  fi
  echo "esperando o login responder em http://127.0.0.1:$RAILS_PORT/app/login (a 1a vez compila, leva minutos)..."
  local inicio=$SECONDS codigo
  while :; do
    codigo=$(/usr/bin/curl -s -o /dev/null -w '%{http_code}' --max-time 10 "http://127.0.0.1:$RAILS_PORT/app/login" || true)
    [ "$codigo" = "200" ] && break
    if [ $((SECONDS - inicio)) -gt "$ESPERA_RAILS_SEGUNDOS" ]; then
      /usr/bin/tail -20 "$L/rails.log"
      falha "Rails não respondeu em ${ESPERA_RAILS_SEGUNDOS}s (último HTTP $codigo; log $L/rails.log)"
    fi
    sleep 5
  done
  [ -n "$(escutando "$VITE_PORT")" ] || { /usr/bin/tail -20 "$L/vite.log"; falha "Vite não subiu (log $L/vite.log)"; }
  echo "painel no ar em $((SECONDS - inicio))s"
}

parar_porta() {
  local porta=$1 pid n=0
  for pid in $(escutando "$porta"); do
    case "$(cwd_do_pid "$pid")" in
      "$SNAP"*) kill "$pid" ;;
      *) echo "porta $porta: pid $pid não é desta demo, não mexi" >&2 ;;
    esac
  done
  while [ -n "$(escutando "$porta")" ] && [ $n -lt 30 ]; do sleep 1; n=$((n + 1)); done
  [ -z "$(escutando "$porta")" ] || echo "porta $porta ainda escutando depois de 30s" >&2
}

descer() {
  carregar_estado
  parar_porta "$RAILS_PORT"
  parar_porta "$VITE_PORT"
  if "$REDISBIN/redis-cli" -p "$REDIS_PORT" ping >/dev/null 2>&1; then
    if [ "$("$REDISBIN/redis-cli" -p "$REDIS_PORT" config get dir | /usr/bin/tail -1)" = "$L/redis" ]; then
      "$REDISBIN/redis-cli" -p "$REDIS_PORT" shutdown nosave >/dev/null 2>&1 || true
    else
      echo "Redis na porta $REDIS_PORT não é desta demo, não mexi" >&2
    fi
  fi
  echo "servidores da demo $slug desligados"
}

reiniciar_vite() {
  carregar_estado
  parar_porta "$VITE_PORT"
  subir
}

# Descarta um snapshot que o up criou mas não chegou a registrar (sem demo.env).
descartar_snapshot() {
  local snapdir=$1
  [ ! -f "$L/demo.env" ] || falha "a demo está registrada; use bin/demo down $slug --apagar"
  case "$snapdir" in
    "$PREFIXO_SNAPSHOT"*/* | *..*) falha "caminho suspeito: $snapdir" ;;
    "$PREFIXO_SNAPSHOT"?*) ;;
    *) falha "fora de $PREFIXO_SNAPSHOT: $snapdir" ;;
  esac
  [ -d "$snapdir" ] || return 0
  [ -z "$(/usr/sbin/lsof +D "$snapdir" 2>/dev/null || true)" ] || falha "snapshot em uso: $snapdir"
  /bin/rm -rf "$snapdir"
  echo "snapshot não registrado descartado no M2: $snapdir"
}

reiniciar_rails() {
  carregar_estado
  parar_porta "$RAILS_PORT"
  subir
}

migrar() {
  carregar_estado
  cd "$SNAP"
  demo_env bundle exec rails db:migrate > "$L/migrate.log" 2>&1 ||
    { /usr/bin/tail -30 "$L/migrate.log"; falha "db:migrate falhou (log $L/migrate.log)"; }
  echo "db:migrate aplicado no banco $DB"
}

pnpm_de_novo() {
  carregar_estado
  cd "$SNAP"
  demo_env pnpm install --frozen-lockfile --prefer-offline > "$L/pnpm.log" 2>&1 ||
    { /usr/bin/tail -30 "$L/pnpm.log"; falha "pnpm install falhou (log $L/pnpm.log)"; }
  echo "pnpm install refeito"
}

flag() {
  carregar_estado
  cd "$SNAP"
  demo_env DEMO_FLAG="${1:?flag}" DEMO_CONTA="${2:-1}" bundle exec rails runner "$KIT/ligar_flag.rb" > "$L/flag.log" 2>&1 ||
    { /usr/bin/tail -20 "$L/flag.log"; falha "não liguei a flag (log $L/flag.log)"; }
  /usr/bin/tail -1 "$L/flag.log"
}

semear() {
  carregar_estado
  local arquivo=$L/seeds/${1:?arquivo}
  [ -f "$arquivo" ] || falha "seed não chegou: $arquivo"
  cd "$SNAP"
  demo_env DEMO_PASTA="$L" bundle exec rails runner "$arquivo" > "$L/seed.log" 2>&1 ||
    { /usr/bin/tail -30 "$L/seed.log"; falha "seed falhou (log $L/seed.log)"; }
  /usr/bin/grep -v 'INFO\|DEBUG' "$L/seed.log" | /usr/bin/tail -15
}

prints() {
  carregar_estado
  local jornadas=$L/prints-entrada/jornadas.json saida=$L/prints-saida
  [ -f "$jornadas" ] || falha "jornadas não chegaram: $jornadas"
  [ -n "$(escutando "$RAILS_PORT")" ] || falha "painel desligado. Rode: bin/demo up $slug"
  /bin/rm -rf "$saida"
  mkdir -p "$saida"
  local senha=${DEMO_SENHA:-}
  [ -n "$senha" ] || senha=$("$R/bin/ruby" "$KIT/senha_do_seed.rb" "$SNAP/db/seeds.rb" john@acme.inc)
  /usr/bin/env -i HOME="$HOME" PATH="$N/bin:/usr/bin:/bin" LANG=en_US.UTF-8 \
    PW="$SNAP/tests/playwright/node_modules/playwright" BASE="http://localhost:$RAILS_PORT" \
    DEMO_SENHA="$senha" DEMO_ESTADO_DIR="$L" \
    "$N/bin/node" "$KIT/prints.cjs" "$jornadas" "$saida"
}

# Valores do demo.env, um por linha e sem escape (o bin/demo lê com awk).
# shellcheck disable=SC2153
mostrar_estado() {
  carregar_estado
  printf '%s=%s\n' SLUG "$SLUG" SNAP "$SNAP" BASE_SHA "$BASE_SHA" ORIGEM "$ORIGEM" DB "$DB" \
    RAILS_PORT "$RAILS_PORT" VITE_PORT "$VITE_PORT" REDIS_PORT "$REDIS_PORT"
}

# Só um SQL, sempre no banco da demo: opções do psql (outro -d, -h, -p) não passam.
psql_cmd() {
  carregar_estado
  psql_demo -d "$DB" -c "${1:?uso: bin/demo psql <slug> \"SQL\"}"
}

apagar() {
  carregar_estado
  descer
  case "$DB" in "$PREFIXO_BANCO"*) ;; *) falha "banco fora do kit: $DB" ;; esac
  if banco_existe "$DB"; then
    "$PGBIN/dropdb" -h "$PG_HOST" -p "$PG_PORT" -U postgres --force "$DB"
    echo "banco $DB apagado"
  fi
  local snapdir=${SNAP%/src}
  case "$snapdir" in
    "$PREFIXO_SNAPSHOT"*/*|*..*) falha "caminho de snapshot suspeito: $snapdir" ;;
    "$PREFIXO_SNAPSHOT"?*) ;;
    *) falha "snapshot fora de $PREFIXO_SNAPSHOT: $snapdir" ;;
  esac
  if [ -d "$snapdir" ]; then
    [ -f "$snapdir/.maccluster-workspace.json" ] || falha "$snapdir não tem o marcador do MacCluster; não apago"
    local usando
    usando=$(/usr/sbin/lsof +D "$snapdir" 2>/dev/null || true)
    [ -z "$usando" ] || { echo "$usando" | /usr/bin/head -5; falha "snapshot em uso; não apaguei: $snapdir"; }
    /bin/rm -rf "$snapdir"
    echo "snapshot apagado no M2: $snapdir"
  fi
  /bin/rm -rf "$L"
  echo "pasta da demo apagada no M2: $L"
}

case "$cmd" in
  checar) checar "$@" ;;
  clonar-base) clonar_base "$@" ;;
  iniciar) iniciar "$@" ;;
  preparar) preparar ;;
  subir) subir ;;
  descer) descer ;;
  reiniciar-rails) reiniciar_rails ;;
  reiniciar-vite) reiniciar_vite ;;
  descartar-snapshot) descartar_snapshot "$@" ;;
  migrar) migrar ;;
  pnpm) pnpm_de_novo ;;
  flag) flag "$@" ;;
  semear) semear "$@" ;;
  prints) prints ;;
  psql) psql_cmd "$@" ;;
  apagar) apagar ;;
  estado) mostrar_estado ;;
  existe) [ -f "$L/demo.env" ] && echo sim || echo nao ;;
  _rails) _rails ;;
  _vite) _vite ;;
  *) falha "comando desconhecido: $cmd" ;;
esac
