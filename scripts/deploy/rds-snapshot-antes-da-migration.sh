#!/bin/bash
# #2024: snapshot manual do RDS tirado pelo próprio deploy, antes de a green rodar as migrations.
#
#   criar   - se o commit deste deploy traz migration que o da blue (BLUE_SHA, gravado por schema-contra-a-blue.sh)
#             não tem, pede o snapshot e grava o id em RDS_SNAPSHOT_ID ($GITHUB_ENV). Na dúvida, tira o snapshot.
#   esperar - espera o snapshot pedido ficar "available". Roda antes de lançar a green, que é quem roda o db:migrate
#             (num rerun a imagem já está no ECR e ela começa na hora). Snapshot que passa de 30 min falha o deploy
#             antes de existir green.
#
# Desligado enquanto RDS_SNAPSHOT_DB_INSTANCE (secret do repositório, um por stack) estiver vazio. Pré-requisitos e
# permissões: docs/migrations-em-lote.md.
# Usa RDS_SNAPSHOT_DB_INSTANCE, BLUE_SHA, GITHUB_SHA, GITHUB_RUN_ID, GITHUB_RUN_ATTEMPT e GITHUB_ENV.
set -euo pipefail
# shellcheck source=scripts/deploy/blue-aws.sh
source "$(dirname "${BASH_SOURCE[0]}")/blue-aws.sh"

# Sai 0 quando o snapshot deve ser tirado. Toda dúvida (fetch, diff) tira o snapshot: aqui o `set -e` não vale,
# porque a função é chamada num `||`, então cada erro é tratado à mão.
traz_migration_nova() {
  local novas
  if [ -z "${BLUE_SHA:-}" ]; then
    echo "::warning::Sem o commit da blue: o snapshot é tirado mesmo assim."
    return 0
  fi
  if ! git fetch --no-tags --depth=1 origin "$BLUE_SHA"; then
    echo "::warning::Não deu para buscar o commit da blue (${BLUE_SHA:0:10}): o snapshot é tirado mesmo assim."
    return 0
  fi
  if ! novas=$(git diff --name-only "$BLUE_SHA" "$GITHUB_SHA" -- db/migrate); then
    echo "::warning::Não deu para comparar com a blue (${BLUE_SHA:0:10}): o snapshot é tirado mesmo assim."
    return 0
  fi
  if [ -z "$novas" ]; then
    echo "Nenhuma migration nova desde a blue (${BLUE_SHA:0:10})."
    return 1
  fi
  printf 'Migrations novas desde a blue (%s):\n%s\n' "${BLUE_SHA:0:10}" "$novas"
}

criar() {
  if [ -z "${RDS_SNAPSHOT_DB_INSTANCE:-}" ]; then
    echo "::notice::Snapshot automático desligado (secret RDS_SNAPSHOT_DB_INSTANCE vazio). Deploy com migration segue a regra do snapshot manual."
    return 0
  fi
  traz_migration_nova || return 0

  local id="chatwoot-antes-da-migration-${GITHUB_RUN_ID}-${GITHUB_RUN_ATTEMPT}"
  aws_quieto aws rds create-db-snapshot \
    --db-instance-identifier "$RDS_SNAPSHOT_DB_INSTANCE" \
    --db-snapshot-identifier "$id" \
    --tags "Key=CriadoPor,Value=deploy-blue-green" "Key=Commit,Value=$GITHUB_SHA" \
    --query DBSnapshot.Status --output text
  echo "RDS_SNAPSHOT_ID=$id" >> "$GITHUB_ENV"
  echo "Snapshot $id pedido."
}

esperar() {
  if [ -z "${RDS_SNAPSHOT_ID:-}" ]; then
    echo "Sem snapshot para esperar."
    return 0
  fi
  # O waiter da AWS confere a cada 30 s, até 60 vezes (30 min).
  aws_quieto aws rds wait db-snapshot-available --db-snapshot-identifier "$RDS_SNAPSHOT_ID"
  echo "Snapshot $RDS_SNAPSHOT_ID pronto: a green pode rodar as migrations."
}

case "${1:-}" in
  criar) criar ;;
  esperar) esperar ;;
  *)
    echo "uso: $0 criar|esperar" >&2
    exit 2
    ;;
esac
