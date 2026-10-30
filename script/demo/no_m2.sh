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
# Role própria da demo: dona do banco, sem superuser, sem CREATEDB e sem CREATEROLE. O Rails e o `bin/demo psql`
# entram com ela; só o kit (criar e apagar banco e role, extensões) usa o postgres.
PREFIXO_ROLE=kitdemo_
PREFIXO_SNAPSHOT=/Users/Shared/maccluster-workspaces/chat2you/
ESPERA_RAILS_SEGUNDOS=900
ESPERA_VITE_SEGUNDOS=120

falha() { echo "demo[$slug]: $*" >&2; exit 1; }

case "$slug" in
  '' | *[!a-z0-9-]* | -* | *-) falha "slug inválido" ;;
esac
[ ${#slug} -le 30 ] || falha "slug longo demais"
ROLE=${PREFIXO_ROLE}${slug//-/_}
# em_uso (mesmo arquivo que o bin/demo usa no M4)
# shellcheck source=script/demo/comum.sh
source "${BASH_SOURCE[0]%/*}/comum.sh" || falha "não carreguei comum.sh"

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
  # Porta vazia ou com letra chegaria ao lsof e ao redis-cli com efeito não verificado: recusa antes.
  local porta
  for porta in "${RAILS_PORT:-}" "${VITE_PORT:-}" "${REDIS_PORT:-}"; do
    case "$porta" in
      '' | *[!0-9]*) falha "porta inválida no demo.env ('$porta'); confira $L/demo.env" ;;
    esac
  done
  # SNAP decide o que o apagar remove: tem de ser <prefixo><id>/src, com id sem "/" e sem começar por ".".
  case "${SNAP:-}" in */src) ;; *) falha "SNAP vazio ou sem /src no demo.env ('${SNAP:-}')" ;; esac
  snapshot_valido "${SNAP%/src}"
  [ "$SLUG" = "$slug" ] || falha "demo.env é de outra demo ($SLUG)"
  [ "$DB" = "${PREFIXO_BANCO}${slug//-/_}" ] || falha "demo.env aponta para outro banco ($DB)"
  # Demo em remoção (o M2 já apagou banco e snapshot): só deixa terminar.
  if [ -f "$L/apagado-no-m2" ]; then
    case "$cmd" in
      apagar | fechar | descer | estado) ;;
      *) falha "demo em remoção: rode bin/demo down $slug --apagar" ;;
    esac
  fi
}

psql_demo() { "$PGBIN/psql" -X -h "$PG_HOST" -p "$PG_PORT" -U postgres -v ON_ERROR_STOP=1 "$@"; }
psql_da_role() { "$PGBIN/psql" -X -h "$PG_HOST" -p "$PG_PORT" -U "$ROLE" -v ON_ERROR_STOP=1 "$@"; }

# Erro do psql para tudo: nunca vira "role não existe".
role_existe() {
  local saida
  saida=$(psql_demo -d postgres -Atc "SELECT 1 FROM pg_roles WHERE rolname = '$ROLE'") ||
    falha "não consegui consultar o Postgres ($PG_HOST:$PG_PORT); não sei se a role $ROLE existe"
  [ "$saida" = "1" ]
}

# Cria (se faltar) a role sem privilégio e o banco dono dela, e as extensões do db/schema.rb como postgres
# (CREATE EXTENSION de algumas exige superuser; o schema:load depois só encontra "já existe").
criar_banco_e_role() {
  local ext lista
  if ! role_existe; then
    psql_demo -d postgres -c "CREATE ROLE \"$ROLE\" LOGIN NOSUPERUSER NOCREATEDB NOCREATEROLE NOREPLICATION NOBYPASSRLS" \
      > /dev/null || falha "não criei a role $ROLE"
  fi
  if ! banco_existe "$DB"; then
    "$PGBIN/createdb" -h "$PG_HOST" -p "$PG_PORT" -U postgres -O "$ROLE" "$DB" || falha "não criei o banco $DB"
  fi
  lista=$("$R/bin/ruby" "$KIT/extensoes.rb" "$SNAP/db/schema.rb") || falha "não li as extensões do db/schema.rb"
  while IFS= read -r ext; do
    [ -n "$ext" ] || continue
    case "$ext" in *[!a-z0-9_]*) falha "extensão com nome inesperado: $ext" ;; esac
    psql_demo -d "$DB" -c "CREATE EXTENSION IF NOT EXISTS \"$ext\"" > /dev/null || falha "não criei a extensão $ext"
  done <<< "$lista"
}

# Erro do psql (Postgres fora, autenticação) para tudo: nunca vira "banco não existe".
banco_existe() {
  local saida
  saida=$(psql_demo -d postgres -Atc "SELECT 1 FROM pg_database WHERE datname = '$1'") ||
    falha "não consegui consultar o Postgres ($PG_HOST:$PG_PORT); não sei se o banco $1 existe"
  [ "$saida" = "1" ]
}

# SNAP, DB e as portas vêm do demo.env (carregar_estado). Ambiente limpo (env -i): nenhuma variável do shell
# entra. E-mail vai para uma porta morta (sem SMTP_ADDRESS o Rails usaria sendmail, que entrega de verdade) e a
# Cloud API do WhatsApp também. O Sidekiq não roda na demo: job enfileirado não executa.
# As chaves (SECRET_KEY_BASE e as do Active Record) nunca passam pelo argv, que qualquer usuário vê no `ps`: o
# bash abaixo lê cada uma do arquivo 0600 em $L/chaves e exporta no próprio ambiente, que o processo herda.
# Arquivo ausente ou vazio para tudo. O `env` final aceita VAR=valor antes do comando (DEMO_FLAG=... no flag).
# shellcheck disable=SC2016
CARREGAR_CHAVES='set -euo pipefail
ler() { local v; v=$(< "$DEMO_CHAVES/$1") || exit 1; [ -n "$v" ] || { echo "chave vazia: $1" >&2; exit 1; }; printf %s "$v"; }
SECRET_KEY_BASE=$(ler secret) || exit 1
ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY=$(ler enc_p) || exit 1
ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY=$(ler enc_d) || exit 1
ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT=$(ler enc_s) || exit 1
export SECRET_KEY_BASE ACTIVE_RECORD_ENCRYPTION_PRIMARY_KEY ACTIVE_RECORD_ENCRYPTION_DETERMINISTIC_KEY
export ACTIVE_RECORD_ENCRYPTION_KEY_DERIVATION_SALT
unset DEMO_CHAVES
exec /usr/bin/env "$@"'
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
    POSTGRES_USERNAME="$ROLE" POSTGRES_PASSWORD= \
    REDIS_URL="redis://127.0.0.1:$REDIS_PORT/0" REDIS_PASSWORD= \
    DEMO_CHAVES="$L/chaves" \
    FRONTEND_URL="http://localhost:$RAILS_PORT" ENABLE_ACCOUNT_SIGNUP=false \
    VITE_RUBY_PORT="$VITE_PORT" VITE_RUBY_HOST=localhost VITE_RUBY_AUTO_BUILD=false \
    VITE_RUBY_DEV_SERVER_CONNECT_TIMEOUT=2 NODE_OPTIONS=--max-old-space-size=4096 \
    WHATSAPP_CLOUD_BASE_URL=http://127.0.0.1:9 CRM_KANBAN_ENABLED=true \
    SMTP_ADDRESS=127.0.0.1 SMTP_PORT=9 SMTP_USERNAME= SMTP_PASSWORD= MAILER_SENDER_EMAIL=demo@demo.invalid \
    /bin/bash -c "$CARREGAR_CHAVES" demo_env "$@"
}

# PIDs que escutam na porta, em ESCUTA. O lsof roda sem -w: código acima de 1 OU qualquer linha no stderr conta como
# "porta ocupada" e para tudo (medido em 23/10: em operação normal o stderr sai vazio). Nunca vira "porta livre".
# O resultado vai em variável, não em $(...): falha dentro de um subshell não pararia o script.
escutando() {
  local saida codigo=0 erro
  erro=$(/usr/bin/mktemp "${TMPDIR:-/tmp}/demo-porta.XXXXXX") || falha "mktemp falhou; não sei quem escuta na porta $1"
  [ -n "$erro" ] && [ -f "$erro" ] || falha "mktemp falhou; não sei quem escuta na porta $1"
  saida=$(/usr/sbin/lsof -t -iTCP:"$1" -sTCP:LISTEN 2> "$erro") || codigo=$?
  if [ "$codigo" -gt 1 ] || [ -s "$erro" ]; then
    /usr/bin/head -3 "$erro" >&2
    /bin/rm -f "$erro"
    falha "lsof falhou ou avisou na porta $1 (saída $codigo); conto como porta ocupada e não sigo"
  fi
  /bin/rm -f "$erro"
  ESCUTA=$saida
}

escuta() { escutando "$1"; [ -n "$ESCUTA" ]; }

# Um processo pelo PID: PROC_GRUPO, PROC_INICIO (lstart) e PROC_COMANDO; tudo vazio se ele não existe.
# Erro do ps ou do awk para tudo (nunca vira "processo não existe").
ler_processo() {
  local tabela linha pid d1 d2 d3 d4 d5
  # Formato fixo do lstart: o mesmo locale e fuso ao gravar (lancar) e ao conferir (grupo_da_demo).
  tabela=$(LC_ALL=C TZ=UTC /bin/ps -ww -axo pid=,pgid=,lstart=,command=) || falha "ps falhou; não sei quem é o processo $1"
  linha=$(printf '%s\n' "$tabela" | /usr/bin/awk -v p="$1" '$1 == p') || falha "awk falhou lendo o ps"
  PROC_GRUPO='' PROC_INICIO='' PROC_COMANDO=''
  [ -n "$linha" ] || return 0
  read -r pid PROC_GRUPO d1 d2 d3 d4 d5 PROC_COMANDO <<< "$linha"
  PROC_INICIO="$d1 $d2 $d3 $d4 $d5"
}

# Cada servidor da demo roda num grupo de processos próprio. O lancar grava o PGID (pids/<nome>.pgid) e o instante
# em que o líder nasceu (pids/<nome>.inicio). O grupo só é "da demo" se o líder ainda existe, nasceu nesse instante
# e o comando dele é exatamente o que o lancar executou (comparação de texto, sem regex). PGID solto por reboot ou
# morte e depois reaproveitado por outro processo não confere: GRUPO fica vazio, ninguém recebe sinal e a porta
# decide. GRUPO_SITUACAO: sem-registro | confere | nao-confere. GRUPO_GRAVADO: o PGID do arquivo (ou vazio).
grupo_da_demo() {
  local nome=$1 pgid inicio
  GRUPO=''
  GRUPO_GRAVADO=''
  if [ ! -f "$L/pids/$nome.pgid" ]; then
    GRUPO_SITUACAO=sem-registro
    return 0
  fi
  [ -f "$L/pids/$nome.inicio" ] ||
    falha "pids/$nome.pgid sem pids/$nome.inicio: o $nome subiu por uma versão anterior do kit, que não grava o" \
      "início do processo. Pare à mão (passo a passo em docs/runbooks/demo-tela-real.md, 'Demo de kit antigo')" \
      "e depois apague $L/pids/$nome.pgid"
  pgid=$(/bin/cat "$L/pids/$nome.pgid") || falha "não li pids/$nome.pgid"
  inicio=$(/bin/cat "$L/pids/$nome.inicio") || falha "não li pids/$nome.inicio"
  case "$pgid" in '' | *[!0-9]*) falha "pids/$nome.pgid inválido ('$pgid')" ;; esac
  GRUPO_GRAVADO=$pgid
  ler_processo "$pgid"
  if [ "$PROC_GRUPO" = "$pgid" ] && [ "$PROC_INICIO" = "$inicio" ] &&
    [ "$PROC_COMANDO" = "/bin/bash $KIT/no_m2.sh _$nome $slug" ]; then
    GRUPO=$pgid
    GRUPO_SITUACAO=confere
  else
    GRUPO_SITUACAO=nao-confere
  fi
}

# Processos vivos do grupo, em MEMBROS. Se o ps ou o awk falhar, para tudo (nunca vira "grupo morto").
membros_do_grupo() {
  local tabela
  tabela=$(/bin/ps -axo pid=,pgid=) || falha "ps falhou; não sei se o grupo $1 morreu"
  MEMBROS=$(printf '%s\n' "$tabela" | /usr/bin/awk -v g="$1" '$2 == g { print $1 }') ||
    falha "awk falhou; não sei se o grupo $1 morreu"
}

# Confere a porta e deixa GRUPO/GRUPO_SITUACAO prontos para quem chama. Porta livre: ok. Porta ocupada: só segue se
# todos os que escutam estão no grupo confirmado da demo.
porta_nossa_ou_livre() {
  local nome=$1 porta=$2 pid
  grupo_da_demo "$nome"
  escutando "$porta"
  [ -n "$ESCUTA" ] || return 0
  if [ "$GRUPO_SITUACAO" = sem-registro ]; then
    falha "porta $porta ($nome) escutando e a demo não tem pids/$nome.pgid: é processo de fora ou o $nome subiu" \
      "por uma versão anterior do kit. Pare à mão (docs/runbooks/demo-tela-real.md, 'Demo de kit antigo')"
  fi
  for pid in $ESCUTA; do
    ler_processo "$pid"
    [ -n "$GRUPO" ] && [ "$PROC_GRUPO" = "$GRUPO" ] ||
      falha "porta $porta ($nome) ocupada por processo que não é desta demo (pid $pid, grupo ${PROC_GRUPO:-?}," \
        "registro $GRUPO_SITUACAO); não mandei sinal"
  done
}

# Confere que o Redis na porta é o desta demo (dir = $L/redis). Erro do redis-cli para tudo.
redis_da_demo() {
  local saida dir
  saida=$("$REDISBIN/redis-cli" -p "$REDIS_PORT" config get dir) ||
    falha "redis-cli falhou na porta $REDIS_PORT; não sei de quem é esse Redis"
  dir=$(printf '%s\n' "$saida" | /usr/bin/tail -1) || falha "tail falhou lendo o Redis"
  [ "$dir" = "$L/redis" ]
}

# --- checar: antes do snapshot, confirma que banco e portas desta demo estão livres ---
checar() {
  local rails=$1 vite=$2 redis=$3 outro porta
  [ ! -e "$L/demo.env" ] || falha "demo já iniciada"
  DB="${PREFIXO_BANCO}${slug//-/_}"
  if banco_existe "$DB"; then
    falha "o banco $DB já existe sem demo registrada. Confira com o dono antes de apagar."
  fi
  if role_existe; then
    falha "a role $ROLE já existe sem demo registrada. Confira com o dono antes de apagar."
  fi
  local linha codigo
  for outro in "$RAIZ"/*/demo.env; do
    [ -f "$outro" ] || continue
    for linha in "RAILS_PORT=$rails" "REDIS_PORT=$redis"; do
      codigo=0
      /usr/bin/grep -qxF -- "$linha" "$outro" || codigo=$?
      case "$codigo" in
        0) falha "portas $rails/$redis já usadas por ${outro%/*}. Use outro slug." ;;
        1) ;;
        *) falha "grep falhou lendo $outro (saída $codigo); não sei se as portas estão livres" ;;
      esac
    done
  done
  for porta in "$rails" "$vite" "$redis"; do
    ! escuta "$porta" || falha "porta $porta ocupada por outro processo. Use outro slug."
  done
  echo "banco $DB e portas $rails/$vite/$redis livres"
}

# Confere que o snapshot não tem .env nem credencial (no M4 o MacCluster já exclui ignorados e sensíveis).
sem_segredo() {
  local na_raiz em_config
  na_raiz=$(/usr/bin/find "$1" -maxdepth 1 -name '.env*' ! -name '*.example' ! -name '*.sample' ! -name '*.template') ||
    falha "find falhou em $1; não sei se há .env no snapshot"
  em_config=$(/usr/bin/find "$1/config" -maxdepth 1 \( -name 'master.key' -o -name 'credentials*' \)) ||
    falha "find falhou em $1/config; não sei se há credencial no snapshot"
  [ -z "$na_raiz$em_config" ] || { printf '%s\n' "$na_raiz" "$em_config"; falha "snapshot com arquivo de segredo; não sobe"; }
}

# --- clonar-base: cria no M2 o diretório do snapshot novo como clone APFS do snapshot chat2you mais recente ---
# O bin/demo completa a cópia com rsync (só a diferença). node_modules vem junto no clone e o pnpm acerta.
clonar_base() {
  local destino=$1 base='' d
  snapshot_valido "$destino"
  [ ! -e "$destino" ] || falha "destino já existe: $destino"
  # Um clone pendente por demo: o anterior tem de ser descartado (ou registrado) antes de outro.
  [ ! -e "$L/clone-pendente" ] ||
    falha "já há um clone pendente desta demo (caminho em $L/clone-pendente); descarte-o antes (o up falho deveria ter feito)"
  local candidatos
  candidatos=$(/bin/ls -td "$PREFIXO_SNAPSHOT"*/) || falha "não consegui listar os snapshots em $PREFIXO_SNAPSHOT"
  while IFS= read -r d; do
    d=${d%/}
    if [ -f "$d/.maccluster-workspace.json" ] && [ -f "$d/src/Gemfile" ] && [ -d "$d/src/node_modules" ]; then
      base=$d
      break
    fi
  done <<< "$candidatos"
  [ -n "$base" ] || falha "nenhum snapshot chat2you com node_modules no M2 para servir de base"
  echo "base no M2: $base (clone APFS)"
  # Registro do clone ainda não registrado: só o descartar-snapshot com este mesmo caminho pode apagá-lo.
  printf '%s\n' "$destino" > "$L/clone-pendente"
  mkdir -m 700 "$destino"
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
  case "$snap" in */src) ;; *) falha "snapshot sem /src: $snap" ;; esac
  snapshot_valido "${snap%/src}"
  mkdir -p "$L/redis"
  # Chaves nascem 0600 numa pasta 0700 (umask antes do openssl, não chmod depois).
  (umask 077 && mkdir -p "$L/chaves") || falha "não criei $L/chaves"
  chmod 700 "$L/chaves"
  umask 077
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
  /bin/rm -f "$L/clone-pendente"
  echo "demo $slug registrada: banco $DB, Rails $rails, Vite $vite, Redis $redis"
}

subir_redis() {
  if "$REDISBIN/redis-cli" -p "$REDIS_PORT" ping >/dev/null 2>&1; then
    redis_da_demo || falha "Redis na porta $REDIS_PORT não é desta demo"
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
  sem_segredo "$SNAP"
  subir_redis
  cd "$SNAP"
  echo "pnpm install (painel)..."
  demo_env pnpm install --frozen-lockfile --prefer-offline > "$L/pnpm.log" 2>&1 ||
    { /usr/bin/tail -30 "$L/pnpm.log"; falha "pnpm install falhou (log: $L/pnpm.log)"; }
  echo "pnpm install (playwright, para os prints)..."
  (cd tests/playwright && demo_env pnpm install --frozen-lockfile --prefer-offline --ignore-scripts) > "$L/pnpm-pw.log" 2>&1 ||
    { /usr/bin/tail -30 "$L/pnpm-pw.log"; falha "pnpm install do playwright falhou (log: $L/pnpm-pw.log)"; }
  echo "role $ROLE e banco $DB (dono: $ROLE) + extensões..."
  criar_banco_e_role
  echo "banco $DB: schema:load + seed (como $ROLE)..."
  demo_env bundle exec rails db:schema:load db:seed > "$L/banco.log" 2>&1 ||
    { /usr/bin/tail -30 "$L/banco.log"; falha "preparo do banco falhou (log: $L/banco.log)"; }
  echo "dados de exemplo da conta + idioma pt-BR..."
  demo_env bundle exec rails runner "$KIT/preparar_conta.rb" > "$L/conta.log" 2>&1 ||
    { /usr/bin/tail -30 "$L/conta.log"; falha "seed da conta falhou (log: $L/conta.log)"; }
  /usr/bin/tail -1 "$L/conta.log"
  /usr/bin/touch "$L/preparado"
}

# Processos de longa duração: o subir chama estes por nohup, cada um num grupo de processos próprio.
_rails() { carregar_estado; cd "$SNAP"; demo_env bundle exec rails s -p "$RAILS_PORT" -b 127.0.0.1; }
_vite() { carregar_estado; cd "$SNAP"; demo_env bundle exec vite dev; }

# Sobe o servidor num grupo de processos novo (setpgrp + exec): o PID lançado é o PGID, e o descer derruba o
# grupo inteiro (wrapper, Rails/Vite e filhos como esbuild e fsevent_watch) e confere que todos morreram.
# Grava o instante em que o líder nasceu (lstart, que não muda no exec) antes do PGID: o grupo_da_demo só aceita o
# grupo se o líder vivo tiver esse mesmo início e o comando "/bin/bash $KIT/no_m2.sh _<nome> <slug>".
lancar() {
  local nome=$1 log=$2 pid
  nohup /usr/bin/perl -e 'setpgrp(0, 0) or die "setpgrp: $!"; exec @ARGV or die "exec: $!"' \
    /bin/bash "$KIT/no_m2.sh" "_$nome" "$slug" > "$log" 2>&1 < /dev/null &
  pid=$!
  ler_processo "$pid"
  [ -n "$PROC_INICIO" ] || falha "o $nome saiu assim que nasceu (log $log)"
  printf '%s\n' "$PROC_INICIO" > "$L/pids/$nome.inicio"
  echo "$pid" > "$L/pids/$nome.pgid"
}

subir() {
  carregar_estado
  subir_redis
  mkdir -p "$L/pids"
  porta_nossa_ou_livre rails "$RAILS_PORT"
  porta_nossa_ou_livre vite "$VITE_PORT"
  # Porta livre não quer dizer grupo morto: o anterior pode estar subindo ou travado sem escutar. O parar_servico
  # derruba o grupo confirmado e espera; só então sobe outro (senão o antigo ficaria órfão, fora do down).
  if ! escuta "$VITE_PORT"; then
    parar_servico vite "$VITE_PORT" || falha "o Vite anterior não parou; não subi outro por cima"
    lancar vite "$L/vite.log"
  fi
  if ! escuta "$RAILS_PORT"; then
    parar_servico rails "$RAILS_PORT" || falha "o Rails anterior não parou; não subi outro por cima"
    /bin/rm -f "$SNAP/tmp/pids/server.pid"
    lancar rails "$L/rails.log"
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
  # Com o Rails já no ar (reiniciar-vite, ou só o Vite relançado), o login responde antes de o Vite escutar.
  local n=0
  until escuta "$VITE_PORT"; do
    if [ $n -ge "$ESPERA_VITE_SEGUNDOS" ]; then
      /usr/bin/tail -20 "$L/vite.log"
      falha "Vite não subiu em ${ESPERA_VITE_SEGUNDOS}s (log $L/vite.log)"
    fi
    sleep 1
    n=$((n + 1))
  done
  echo "painel no ar em $((SECONDS - inicio))s"
}

# Para um servidor da demo pelo grupo gravado, só se o grupo_da_demo o confirmou (líder com o mesmo início e o
# mesmo comando). Registro que não confere nunca dá OK sozinho: sem mandar sinal, conta os processos vivos do PGID
# gravado; só com zero o registro sai (e a porta decide), senão falha.
# Devolve 1 (sem matar mais nada) se a porta continuar escutando ou sobrar processo do grupo depois de 30 s.
parar_servico() {
  local nome=$1 porta=$2 grupo n=0 vivos
  porta_nossa_ou_livre "$nome" "$porta"
  grupo=$GRUPO
  if [ "$GRUPO_SITUACAO" = nao-confere ]; then
    membros_do_grupo "$GRUPO_GRAVADO"
    [ -z "$MEMBROS" ] ||
      falha "pids/$nome.pgid ($GRUPO_GRAVADO) não confere com o processo vivo (início ou comando diferente) e o" \
        "grupo tem processos vivos: ${MEMBROS//$'\n'/ }. Não mandei sinal; confira à mão" \
        "(docs/runbooks/demo-tela-real.md, 'Demo de kit antigo')"
  fi
  MEMBROS=''
  [ -z "$grupo" ] || membros_do_grupo "$grupo"
  [ -z "$MEMBROS" ] || kill -TERM -- "-$grupo" || true
  while :; do
    MEMBROS=''
    [ -z "$grupo" ] || membros_do_grupo "$grupo"
    vivos=$MEMBROS
    escutando "$porta"
    [ -n "$vivos" ] || [ -n "$ESCUTA" ] || break
    if [ $n -ge 30 ]; then
      echo "$nome: depois de 30 s, porta $porta escutando=[${ESCUTA//$'\n'/ }]" \
        "processos do grupo $grupo vivos=[${vivos//$'\n'/ }]" >&2
      return 1
    fi
    sleep 1
    n=$((n + 1))
  done
  /bin/rm -f "$L/pids/$nome.pgid" "$L/pids/$nome.inicio"
  return 0
}

descer() {
  carregar_estado
  local ok=true
  parar_servico rails "$RAILS_PORT" || ok=false
  parar_servico vite "$VITE_PORT" || ok=false
  if escuta "$REDIS_PORT"; then
    redis_da_demo || falha "Redis na porta $REDIS_PORT não é desta demo; não mexi"
    "$REDISBIN/redis-cli" -p "$REDIS_PORT" shutdown nosave >/dev/null 2>&1 || true
    local n=0
    while escuta "$REDIS_PORT" && [ $n -lt 20 ]; do sleep 0.5; n=$((n + 1)); done
    ! escuta "$REDIS_PORT" || { echo "Redis ainda escutando na porta $REDIS_PORT" >&2; ok=false; }
  fi
  $ok || falha "não consegui parar todos os servidores da demo; nada foi apagado"
  echo "servidores da demo $slug desligados"
}

reiniciar_vite() {
  carregar_estado
  parar_servico vite "$VITE_PORT" || falha "o Vite não parou"
  subir
}

# Descarta um snapshot que o up criou mas não chegou a registrar (sem demo.env).
descartar_snapshot() {
  local snapdir=$1
  [ ! -f "$L/demo.env" ] || falha "a demo está registrada; use bin/demo down $slug --apagar"
  snapshot_valido "$snapdir"
  local pendente
  if [ ! -e "$snapdir" ]; then
    # Nada no M2 (o clone nem começou): só limpa o registro, se for deste caminho.
    if [ -f "$L/clone-pendente" ]; then
      pendente=$(/bin/cat "$L/clone-pendente") || falha "não li $L/clone-pendente"
      [ "$pendente" != "$snapdir" ] || /bin/rm -f "$L/clone-pendente"
    fi
    return 0
  fi
  [ -f "$L/clone-pendente" ] || falha "sem registro de clone pendente em $L; não apago $snapdir"
  pendente=$(/bin/cat "$L/clone-pendente") || falha "não li $L/clone-pendente"
  [ "$pendente" = "$snapdir" ] || falha "o clone pendente é $pendente, não $snapdir; não apago"
  marcador_confere "$snapdir"
  snapshot_so_meu "$snapdir"
  if em_uso "$snapdir"; then falha "snapshot em uso: $snapdir"; fi
  /bin/rm -rf "$snapdir"
  /bin/rm -f "$L/clone-pendente"
  echo "snapshot não registrado descartado no M2: $snapdir"
}

# O snapshot só sai se o marcador do MacCluster disser que ele é este: snapshot_id igual ao nome do diretório.
marcador_confere() {
  local dir=$1
  [ -f "$dir/.maccluster-workspace.json" ] || falha "$dir não tem o marcador do MacCluster; não apago"
  "$R/bin/ruby" -rjson -e 'exit(JSON.parse(File.read(ARGV[0]))["snapshot_id"] == ARGV[1] ? 0 : 1)' \
    "$dir/.maccluster-workspace.json" "${dir##*/}" ||
    falha "o marcador de $dir não é deste snapshot (snapshot_id diferente do nome) ou não pôde ser lido; não apago"
}

reiniciar_rails() {
  carregar_estado
  parar_servico rails "$RAILS_PORT" || falha "o Rails não parou"
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
  # Só exibição: linha nenhuma depois do filtro não é erro (o erro do seed já parou acima).
  /usr/bin/grep -v 'INFO\|DEBUG' "$L/seed.log" | /usr/bin/tail -15 || :
}

prints() {
  carregar_estado
  local jornadas=$L/prints-entrada/jornadas.json saida=$L/prints-saida
  [ -f "$jornadas" ] || falha "jornadas não chegaram: $jornadas"
  escuta "$RAILS_PORT" || falha "painel desligado. Rode: bin/demo up $slug"
  /bin/rm -rf "$saida"
  mkdir -p "$saida"
  # A senha vai para um arquivo 0600 (umask antes de criar) e o prints.cjs lê de lá: nunca pelo argv nem ambiente.
  local senha
  senha=$("$R/bin/ruby" "$KIT/senha_do_seed.rb" "$SNAP/db/seeds.rb" john@acme.inc) ||
    falha "não li a senha do seed em $SNAP/db/seeds.rb"
  [ -n "$senha" ] || falha "senha do seed vazia em $SNAP/db/seeds.rb"
  (umask 077 && printf '%s\n' "$senha" > "$L/chaves/senha_seed") || falha "não gravei a senha do seed"
  /usr/bin/env -i HOME="$HOME" PATH="$N/bin:/usr/bin:/bin" LANG=en_US.UTF-8 \
    PW="$SNAP/tests/playwright/node_modules/playwright" BASE="http://localhost:$RAILS_PORT" \
    DEMO_SENHA_ARQUIVO="$L/chaves/senha_seed" DEMO_ESTADO_DIR="$L" DEMO_RELATO="$L/relato.json" \
    "$N/bin/node" "$KIT/prints.cjs" "$jornadas" "$saida"
}

# Valores do demo.env, um por linha e sem escape (o bin/demo lê com awk).
# shellcheck disable=SC2153
mostrar_estado() {
  carregar_estado
  printf '%s=%s\n' SLUG "$SLUG" SNAP "$SNAP" BASE_SHA "$BASE_SHA" ORIGEM "$ORIGEM" DB "$DB" \
    RAILS_PORT "$RAILS_PORT" VITE_PORT "$VITE_PORT" REDIS_PORT "$REDIS_PORT"
  if [ -f "$L/apagado-no-m2" ]; then echo "EM_REMOCAO=sim"; else echo "EM_REMOCAO=nao"; fi
}

# Um SQL no banco da demo, como a role da demo (sem superuser, sem CREATEDB): ela não cria nem apaga outro banco
# e não lê banco de que não é dona. Opções do psql não passam (o argumento vai inteiro no -c), o psqlrc não é lido
# (-X) e meta-comando (\c outro_banco, \! comando) é recusado.
psql_cmd() {
  carregar_estado
  local sql=${1:?uso: bin/demo psql <slug> \"SQL\"}
  # Com -c, o psql roda SQL puro OU um único meta-comando, que é sempre o texto começando com "\".
  local inicio=${sql#"${sql%%[![:space:]]*}"}
  case "$inicio" in "\\"*) falha 'meta-comando do psql (começa com \) não é aceito; mande só SQL' ;; esac
  psql_da_role -d "$DB" -c "$sql"
}


# Ordem: (a) confere caminho e marcador; (b) desce os servidores da demo pelo grupo gravado e confere que portas e
# processos pararam (senão falha antes de qualquer dropdb ou rm); (c) em_uso no snapshot, sem exceção nenhuma: se
# algo ainda o segura, recusa com a demo parada (reversível: up de novo). Só então apaga. No fim deixa o marcador
# `apagado-no-m2` e o demo.env: o bin/demo apaga o snapshot do M4 e só depois chama `fechar`, que apaga a pasta. Se o M4 falhar, repetir `bin/demo down <slug> --apagar` termina.
apagar() {
  carregar_estado
  if [ -f "$L/apagado-no-m2" ]; then
    echo "M2 já apagado antes; falta só o M4"
    return 0
  fi
  case "$DB" in "$PREFIXO_BANCO"*) ;; *) falha "banco fora do kit: $DB" ;; esac
  case "$ROLE" in "$PREFIXO_ROLE"?*) ;; *) falha "role fora do kit: $ROLE" ;; esac
  # Prova positiva da role antes de mexer em qualquer coisa: se existir, tem de ser sem privilégio.
  if role_existe; then
    local super
    super=$(psql_demo -d postgres -Atc "SELECT rolsuper::text || rolcreatedb::text || rolcreaterole::text FROM pg_roles WHERE rolname = '$ROLE'") ||
      falha "não li a role $ROLE"
    [ "$super" = "falsefalsefalse" ] || falha "a role $ROLE tem privilégio (super/createdb/createrole: $super); não é do kit, nada apagado"
  fi
  local snapdir=${SNAP%/src}
  snapshot_valido "$snapdir"
  if [ -d "$snapdir" ]; then
    marcador_confere "$snapdir"
    snapshot_so_meu "$snapdir"
  fi
  descer
  if [ -d "$snapdir" ] && em_uso "$snapdir"; then
    falha "demo parada, nada apagado: algo ainda segura $snapdir. Suba de novo com bin/demo up $slug ou repita o down"
  fi
  if banco_existe "$DB"; then
    "$PGBIN/dropdb" -h "$PG_HOST" -p "$PG_PORT" -U postgres --force "$DB"
    echo "banco $DB apagado"
  fi
  if [ -d "$snapdir" ]; then
    /bin/rm -rf "$snapdir"
    echo "snapshot apagado no M2: $snapdir"
  fi
  if role_existe; then
    psql_demo -d postgres -c "DROP ROLE \"$ROLE\"" > /dev/null || falha "não apaguei a role $ROLE (ainda é dona de algo?)"
    echo "role $ROLE apagada"
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
