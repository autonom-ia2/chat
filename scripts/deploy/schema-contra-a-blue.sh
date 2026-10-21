#!/bin/bash
# #2024: confere, antes de lançar a green, se a blue aguenta o schema deste commit (compatibilidade_com_a_blue.rb).
# Grava BLUE_SHA em $GITHUB_ENV para o snapshot do RDS. Sem saber o commit da blue o deploy para aqui: sem ele não dá
# para saber se a green vai remover algo que a blue ainda grava. A green ainda não existe, então nada foi mexido.
# Usa BLUE_INSTANCE_ID, GITHUB_SHA, GITHUB_REPOSITORY, GITHUB_ENV, RUNNER_TEMP e GH_TOKEN.
set -euo pipefail
# shellcheck source=scripts/deploy/blue-aws.sh
source "$(dirname "${BASH_SOURCE[0]}")/blue-aws.sh"

if ! blue=$(commit_da_blue) || [ -z "$blue" ]; then
  echo "::error::Não deu para saber de que commit veio a blue $BLUE_INSTANCE_ID. Sem ele não dá para conferir se ela aguenta o schema novo; a green não foi lançada. Rodar o deploy de novo."
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
