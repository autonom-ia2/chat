#!/bin/bash
# #2024: confere, antes de lançar a green, se a blue aguenta o schema deste commit (compatibilidade_com_a_blue.rb).
# Grava BLUE_SHA em $GITHUB_ENV para o snapshot do RDS. Sem saber o commit da blue o deploy para aqui: sem ele não dá
# para saber se a green vai remover algo que a blue ainda grava. Parando aqui, nenhuma instância nem o banco foram
# tocados (só o parâmetro de env, que o passo das flags de runtime regrava em todo deploy, já foi escrito).
# BLUE_SHA_INFORMADO (input blue_sha do deploy manual) troca só a descoberta do commit da blue; a comparação roda igual.
# Usa BLUE_INSTANCE_ID, GITHUB_SHA, GITHUB_REPOSITORY, GITHUB_ENV, RUNNER_TEMP e GH_TOKEN.
set -euo pipefail
# shellcheck source=scripts/deploy/blue-aws.sh
source "$(dirname "${BASH_SOURCE[0]}")/blue-aws.sh"

informado="${BLUE_SHA_INFORMADO:-}"
if [ -n "$informado" ]; then
  # SHA completo, só hexadecimal minúsculo: é o que a API do GitHub devolve e o que o git fetch aceita por commit.
  case "$informado" in
    *[!0-9a-f]*) valido=false ;;
    *) valido=$([ "${#informado}" -eq 40 ] && echo true || echo false) ;;
  esac
  if [ "$valido" != true ]; then
    echo "::error::blue_sha precisa ser o SHA completo (40 caracteres) do commit que a blue roda. Nenhuma instância nem o banco foram tocados."
    exit 1
  fi
  blue="$informado"
  echo "Commit da blue informado no deploy manual; a comparação roda igual."
elif ! blue=$(commit_da_blue) || [ -z "$blue" ]; then
  echo "::error::Não deu para saber de que commit veio a blue (tag Name da instância ou API do GitHub). Sem ele não dá para conferir se ela aguenta o schema novo; a green não foi lançada e nenhuma instância nem o banco foram tocados. Rodar o deploy de novo ou, no deploy manual, informar blue_sha."
  exit 1
fi
echo "BLUE_SHA=$blue" >> "$GITHUB_ENV"
echo "A blue roda ${blue:0:10}."

git fetch --no-tags --depth=1 origin "$blue"
if git diff --quiet "$blue" "$GITHUB_SHA" -- db/schema.rb db/retiradas.yml; then
  echo "schema.rb igual ao da blue: nada a conferir."
  exit 0
fi

pasta="$RUNNER_TEMP/schema-da-blue"
mkdir -p "$pasta"
git show "$blue:db/schema.rb" > "$pasta/schema.rb"
argumentos=("$pasta/schema.rb" db/schema.rb)
# Commit da blue anterior ao #2024 não tem o arquivo: nada anunciado.
if [ -n "$(git ls-tree --name-only "$blue" -- db/retiradas.yml)" ]; then
  git show "$blue:db/retiradas.yml" > "$pasta/retiradas.yml"
  argumentos+=("$pasta/retiradas.yml")
fi
ruby scripts/deploy/compatibilidade_com_a_blue.rb "${argumentos[@]}"
