#!/bin/bash
# #1431 — uma rodada da régua: grava a chave da OpenAI só no banco local de teste, ingere cada base, roda o placar
# (busca e, com RESPOSTA=1, resposta e juiz) e apaga a chave no fim, mesmo se a rodada cair.
#   TETO_USD=1 RESPOSTA=1 SAIDA=/fora/do/repo script/rag_placar/rodar.sh <tipo>:<arquivo>[,<arquivo>...]:<perguntas.yml> ...
# Vários arquivos separados por vírgula viram materiais do mesmo agente (as fotos).
# IA paga: só com teto aprovado. A chave sai do arquivo de segredos sem ser impressa; nada de chave no repo nem no log.
# As rodadas são sempre uma de cada vez: duas em paralelo disputam a mesma chave no mesmo banco.
set -euo pipefail
cd "$(dirname "$0")/../.."
: "${TETO_USD:?defina TETO_USD (teto aprovado da rodada)}"
: "${SAIDA:?defina SAIDA, fora de qualquer repositório}"
SEGREDOS=/Users/rodrigosilva/dev/claudete-ops/.secrets/credentials.env
AMBIENTE=script/rag_placar/ambiente.sh

apagar_chave() {
  "$AMBIENTE" runner "InstallationConfig.where(name: 'CAPTAIN_OPEN_AI_API_KEY').delete_all" >/dev/null 2>&1 || true
}
trap apagar_chave EXIT
# Uma rodada morta à força (kill -9) não passa pelo trap: a chave dela sai aqui, antes da nova.
apagar_chave

# A chave vai por variável de ambiente só para o processo do runner; o código Ruby não a imprime.
RAG_PLACAR_CHAVE=$(grep -m1 '^OPENAI_API_KEY=' "$SEGREDOS" | cut -d= -f2-) \
  "$AMBIENTE" runner "c = InstallationConfig.find_or_initialize_by(name: 'CAPTAIN_OPEN_AI_API_KEY'); c.value = ENV.fetch('RAG_PLACAR_CHAVE'); c.save!; puts 'chave gravada'"

for base in "$@"; do
  IFS=: read -r tipo arquivos perguntas <<<"$base"
  IFS=, read -r -a lista <<<"$arquivos"
  agente=$("$AMBIENTE" runner script/rag_placar/ingerir.rb "$tipo" "${lista[@]}" | tail -1 | ruby -rjson -e 'puts JSON.parse($stdin.read)["agente"]')
  echo "== $tipo (${#lista[@]} arquivo(s)) agente=$agente"
  AGENTES=$agente PERGUNTAS=$perguntas SAIDA="$SAIDA/$tipo" "$AMBIENTE" rake autonomia:rag:placar
done
