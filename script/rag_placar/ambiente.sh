#!/bin/bash
# #1431 — a régua do RAG roda no banco LOCAL de teste próprio da frente, nunca em produção.
#   script/rag_placar/ambiente.sh schema               cria o banco e carrega o schema (apaga o que houver nele)
#   script/rag_placar/ambiente.sh runner <args...>     bundle exec rails runner no ambiente da régua
#   script/rag_placar/ambiente.sh rake <args...>       bundle exec rails <tarefa> no ambiente da régua
# LOG_LEVEL=info: em debug o RubyLLM loga o corpo do pedido, e com PDF grande o formatador do Faraday estoura o
# Regexp.timeout (achado da F0).
set -euo pipefail
cd "$(dirname "$0")/../.."
eval "$(rbenv init - bash)"
export RAILS_ENV=test LOG_LEVEL=info POSTGRES_DATABASE="${RAG_PLACAR_BANCO:-chatwoot_test_1431}"

# O schema apaga o banco: só num banco de teste local.
case "$POSTGRES_DATABASE" in
  chatwoot_test_*) ;;
  *) echo "banco recusado: $POSTGRES_DATABASE (a régua só roda em chatwoot_test_*)" >&2; exit 1 ;;
esac

acao=${1:?uso: ambiente.sh schema|runner|rake ...}
shift
case "$acao" in
  schema) bundle exec rails db:create db:schema:load ;;
  runner) bundle exec rails runner "$@" ;;
  rake) bundle exec rails "$@" ;;
  *) echo "ação desconhecida: $acao" >&2; exit 1 ;;
esac
