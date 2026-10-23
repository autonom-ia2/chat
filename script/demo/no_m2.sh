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
  '' | *[!a-z0-9-]* | -* | *-) falha "slug inválido" ;;
esac
[ ${#slug} -le 30 ] || falha "slug longo demais"
# em_uso (mesmo arquivo que o bin/demo usa no M4)
# shellcheck source=script/demo/comum.sh
source "$(dirname "${BASH_SOURCE[0]}")/comum.sh"

carregar_estado() {
  [ -f "$L/demo.env" ] || falha "demo não existe no M2 ($L/demo.env). Rode: bin/demo up $slug"
  # Sem `source`: o arquivo é lido como dado (chave=valor), nunca executado.
  local chave valor
  while IFS='=' read -r chave valor; do
    case "$chave" in
      SLUG) SLUG=$valor ;; SNAP) SNAP=$valor ;; BASE_SHA) BASE_SHA=$valor ;; ORIGEM) ORIGEM=$valor ;;
      DB) DB=$valor ;; RAILS_PORT) RAILS_PORT=$valor ;; VITE_PORT) VITE_PORT=$valor ;; REDIS_PORT) REDIS_PORT=$valor ;;
      *) falha "chave desconhecida no demo.env: $chave" ;;
    esac
  done < "$L/demo.env"
  [ "$SLUG" = "$slug" ] || falha "demo.env é de outra demo ($SLUG)"
  [ "$DB" = "${PREFIXO_BANCO}${slug//-/_}" ] || falha "demo.env aponta para outro banco ($DB)"
}

psql_demo() { "$PGBIN/psql" -X -h "$PG_HOST" -p "$PG_PORT" -U postgres -v ON_ERROR_STOP=1 "$@"; }

banco_existe() {
  [ "$(psql_demo -d postgres -Atc "SELECT 1 FROM pg_database WHERE datname = '$1'")" = "1" ]
}

# SNAP, DB e as portas vêm do demo.env (carregar_estado). Ambiente limpo (env -i): nenhuma variável do shell
# entra. E-mail vai para uma porta morta (sem SMTP_ADDRESS o Rails usaria sendmail, que entrega de verdade) e a
# Cloud API do WhatsApp também. O Sidekiq não roda na demo: job enfileirado não executa.
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
    SMTP_ADDRESS=127.0.0.1 SMTP_PORT=9 SMTP_USERNAME= SMTP_PASSWORD= MAILER_SENDER_EMAIL=demo@demo.invalid \
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

# Confere que o snapshot não tem .env nem credencial (no M4 o MacCluster já exclui ignorados e sensíveis).
sem_segredo() {
  local achados
  achados=$(
    /usr/bin/find "$1" -maxdepth 1 -name '.env*' ! -name '*.example' ! -name '*.sample' ! -name '*.template'
    /usr/bin/find "$1/config" -maxdepth 1 \( -name 'master.key' -o -name 'credentials*' \))
  [ -z "$achados" ] || { echo "$achados"; falha "snapshot com arquivo de segredo; não sobe"; }
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
  # Logs, pids, caches e uploads da outra demo não vêm junto.
  /bin/rm -rf "$destino/src/log" "$destino/src/tmp" "$destino/src/storage" "$destino/src/public/vite-dev" \
    "$destino/src/public/vite-test"
  # Nem segredo: o dotenv-rails leria um .env herdado no 1o boot. Some antes de qualquer boot.
  /bin/rm -rf "$destino/src/config/credentials" "$destino/src/config/master.key"
  /bin/rm -f "$destino/src/config/credentials.yml.enc" "$destino/src"/.env "$destino/src"/.env.*
  sem_segredo "$destino/src"
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
  local v
  for v in "$snap" "$base" "$origem"; do
    case "$v" in *$'\n'* | *$'\r'*) falha "valor com quebra de linha não entra no demo.env" ;; esac
  done
  printf '%s=%s\n' SLUG "$slug" SNAP "$snap" BASE_SHA "$base" ORIGEM "$origem" DB "$DB" \
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
  [ ! -f "$L/apagado-no-m2" ] || falha "demo em remoção: termine com bin/demo down $slug --apagar"
  [ ! -f "$L/preparado" ] || return 0
  sem_segredo "$SNAP"
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
  if em_uso "$snapdir"; then falha "snapshot em uso: $snapdir"; fi
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
    DEMO_SENHA="$senha" DEMO_ESTADO_DIR="$L" DEMO_RELATO="$L/relato.json" \
    "$N/bin/node" "$KIT/prints.cjs" "$jornadas" "$saida"
}

# Valores do demo.env, um por linha e sem escape (o bin/demo lê com awk).
# shellcheck disable=SC2153
mostrar_estado() {
  carregar_estado
  printf '%s=%s\n' SLUG "$SLUG" SNAP "$SNAP" BASE_SHA "$BASE_SHA" ORIGEM "$ORIGEM" DB "$DB" \
    RAILS_PORT "$RAILS_PORT" VITE_PORT "$VITE_PORT" REDIS_PORT "$REDIS_PORT"
}

# Um SQL no banco da demo. Opções do psql não passam (o argumento vai inteiro no -c), o psqlrc não é lido (-X)
# e meta-comando (\c outro_banco, \! comando) é recusado.
psql_cmd() {
  carregar_estado
  local sql=${1:?uso: bin/demo psql <slug> \"SQL\"}
  # Com -c, o psql roda SQL puro OU um único meta-comando, que é sempre o texto começando com "\".
  local inicio=${sql#"${sql%%[![:space:]]*}"}
  case "$inicio" in "\\"*) falha 'meta-comando do psql (começa com \) não é aceito; mande só SQL' ;; esac
  psql_demo -d "$DB" -c "$sql"
}

# PIDs dos servidores desta demo, que o descer cuida: quem escuta nas portas dela, os processos pais com cwd no
# snapshot (os wrappers do nohup) e todos os descendentes deles (esbuild do Vite, fsevent_watch do Rails...).
pids_da_demo() {
  local porta pid raizes=''
  for porta in "$RAILS_PORT" "$VITE_PORT"; do
    for pid in $(escutando "$porta"); do
      while [ -n "$pid" ] && [ "$pid" -gt 1 ]; do
        case "$(cwd_do_pid "$pid")" in "$SNAP"*) raizes="$raizes $pid" ;; *) break ;; esac
        pid=$(/bin/ps -o ppid= -p "$pid" | /usr/bin/tr -d ' ')
      done
    done
  done
  [ -n "$raizes" ] || return 0
  /bin/ps -axo pid=,ppid= | /usr/bin/awk -v raizes="$raizes" '
    { pai[$1] = $2 }
    END {
      n = split(raizes, r, " "); for (i = 1; i <= n; i++) dentro[r[i]] = 1
      for (pid in pai) { p = pid; while (p > 1 && !(p in dentro) && (p in pai)) p = pai[p]; if (p in dentro) print pid }
    }'
}

# Confere tudo antes de apagar ou desligar qualquer coisa: se algo recusar, servidores, banco, snapshot e pasta
# ficam como estavam. No fim deixa o marcador `apagado-no-m2` e o demo.env: o bin/demo apaga o snapshot do M4 e só
# depois chama `fechar`, que apaga a pasta. Se o M4 falhar, repetir `bin/demo down <slug> --apagar` termina.
apagar() {
  carregar_estado
  if [ -f "$L/apagado-no-m2" ]; then
    echo "M2 já apagado antes; falta só o M4"
    return 0
  fi
  case "$DB" in "$PREFIXO_BANCO"*) ;; *) falha "banco fora do kit: $DB" ;; esac
  local snapdir=${SNAP%/src}
  case "$snapdir" in
    "$PREFIXO_SNAPSHOT"*/* | *..*) falha "caminho de snapshot suspeito: $snapdir" ;;
    "$PREFIXO_SNAPSHOT"?*) ;;
    *) falha "snapshot fora de $PREFIXO_SNAPSHOT: $snapdir" ;;
  esac
  if [ -d "$snapdir" ]; then
    [ -f "$snapdir/.maccluster-workspace.json" ] || falha "$snapdir não tem o marcador do MacCluster; não apago"
  fi
  if [ -d "$snapdir" ]; then
    # shellcheck disable=SC2046
    if em_uso "$snapdir" $(pids_da_demo); then falha "snapshot em uso por outro processo; nada foi apagado nem desligado: $snapdir"; fi
  fi
  descer
  if banco_existe "$DB"; then
    "$PGBIN/dropdb" -h "$PG_HOST" -p "$PG_PORT" -U postgres --force "$DB"
    echo "banco $DB apagado"
  fi
  if [ -d "$snapdir" ]; then
    /bin/rm -rf "$snapdir"
    echo "snapshot apagado no M2: $snapdir"
  fi
  /usr/bin/touch "$L/apagado-no-m2"
}

fechar() {
  [ -f "$L/apagado-no-m2" ] || falha "fechar só depois do apagar"
  case "$L" in "$RAIZ"/?*) ;; *) falha "pasta suspeita: $L" ;; esac
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
  fechar) fechar ;;
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
