#!/bin/bash
# #2024: snapshot manual do RDS tirado pelo próprio deploy, antes de a green rodar as migrations.
#
#   criar   - se o commit deste deploy traz migration que o da blue não tem, pede o snapshot e grava o id em
#             RDS_SNAPSHOT_ID ($GITHUB_ENV). Sem saber o commit da blue, tira o snapshot do mesmo jeito.
#   esperar - espera o snapshot pedido ficar "available". Roda antes do build: a green só começa o db:migrate
#             quando a imagem chega ao ECR, então o banco nunca muda antes de o snapshot estar pronto.
#
# Desligado enquanto RDS_SNAPSHOT_DB_INSTANCE (variável do repositório, uma por stack) estiver vazia: as permissões
# do papel do deploy ainda não foram conferidas. Permissões: docs/migrations-em-lote.md.
# Repositório público: erro da AWS sai só com o código (AccessDenied etc.), porque a mensagem traz conta e ARN.
# Usa RDS_SNAPSHOT_DB_INSTANCE, BLUE_INSTANCE_ID, GITHUB_SHA, GITHUB_RUN_ID, GITHUB_RUN_ATTEMPT, GITHUB_REPOSITORY,
# GITHUB_ENV e GH_TOKEN.
set -euo pipefail

aws_quieto() {
  local erro status=0 mensagem codigo
  erro=$(mktemp)
  "$@" 2>"$erro" || status=$?
  if [ "$status" -ne 0 ]; then
    mensagem=$(cat "$erro")
    codigo="${mensagem#*(}"
    codigo="${codigo%%)*}"
    [ "$codigo" != "$mensagem" ] || codigo="sem código"
    echo "::error::A AWS recusou '$2 $3' ($codigo). Detalhe fora do log público: ver docs/migrations-em-lote.md." >&2
  fi
  rm -f "$erro"
  return "$status"
}

# Mesma leitura do check-rollback-target.sh: a tag Name da instância termina no id do run que a criou.
commit_da_blue() {
  local nome run_id
  nome=$(aws_quieto aws ec2 describe-instances --instance-ids "$BLUE_INSTANCE_ID" \
    --query "Reservations[0].Instances[0].Tags[?Key=='Name'].Value | [0]" --output text) || return 1
  run_id="${nome##*-}"
  case "$run_id" in
    *[!0-9]*|'') return 1 ;;
  esac
  gh api "repos/$GITHUB_REPOSITORY/actions/runs/$run_id" --jq .head_sha
}

traz_migration_nova() {
  local blue
  if ! blue=$(commit_da_blue) || [ -z "$blue" ]; then
    echo "Não deu para saber o commit da blue: o snapshot é tirado mesmo assim."
    return 0
  fi
  git fetch --no-tags --depth=1 origin "$blue"
  if git diff --quiet "$blue" "$GITHUB_SHA" -- db/migrate; then
    echo "Nenhuma migration nova desde a blue (${blue:0:10})."
    return 1
  fi
  echo "Migrations novas desde a blue (${blue:0:10}):"
  git diff --name-only "$blue" "$GITHUB_SHA" -- db/migrate
}

criar() {
  if [ -z "${RDS_SNAPSHOT_DB_INSTANCE:-}" ]; then
    echo "::notice::Snapshot automático desligado (RDS_SNAPSHOT_DB_INSTANCE vazia). Deploy com migration segue a regra do snapshot manual."
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
