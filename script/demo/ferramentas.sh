# shellcheck shell=bash
# Kit de demo (#2965): onde ficam, na máquina da demo, as ferramentas que o kit executa, e a lista das que faltam.
# O no_m2.sh carrega este arquivo (source). O bin/demo também o manda pelo stdin de um bash, seguido da chamada
# `ferramentas_que_faltam`, para conferir cada máquina antes de subir: só leitura, sem deixar pasta nela.
T=/Users/Shared/maccluster-tools
R=$T/ruby-3.4.4
N=$T/node-v24.11.0
# Cliente do Postgres (psql, createdb, dropdb): o M2 tem o 17.11; o M4 só tem o 16.15, o mesmo do servidor de teste
# (medido em 12/11/2026). Nos dois Macs o servidor em 127.0.0.1:55432 é o 16.15.
PGBIN=$T/postgresql-17.11/bin
[ -x "$PGBIN/psql" ] || PGBIN=$T/deps/postgresql-16.15/bin
REDISBIN=$T/deps/redis-8.10.2/bin

# Uma linha por ferramenta que falta: o caminho que deveria existir e poder ser executado. Nada impresso = completa.
# Só entra aqui o que o kit executa pelo caminho. Rails e Vite não entram: o kit os chama pelos bin/rails e bin/vite
# do próprio app, que acham o executável dentro da gem. Assim a demo não depende dos lançadores de gem do Ruby
# compartilhado: em 12/11/2026 o do M4 tinha 27, contra 79 no M2, e o primeiro up no M4 parou em
# "bundler: command not found: vite".
ferramentas_que_faltam() {
  local f
  for f in "$R/bin/ruby" "$N/bin/node" "$N/bin/pnpm" "$PGBIN/psql" "$PGBIN/createdb" "$PGBIN/dropdb" \
    "$REDISBIN/redis-server" "$REDISBIN/redis-cli"; do
    [ -x "$f" ] || echo "$f"
  done
}
