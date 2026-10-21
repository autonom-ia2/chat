#!/bin/bash
# #2024: snapshot manual do RDS tirado pelo próprio deploy, antes de a green rodar as migrations.
#
#   criar   - se o commit deste deploy traz migration que o da blue não tem, pede o snapshot e grava o id em
#             RDS_SNAPSHOT_ID ($GITHUB_ENV). Sem saber o commit da blue, tira o snapshot do mesmo jeito.
#   esperar - espera o snapshot pedido ficar "available". Roda antes de lançar a green, que é quem roda o db:migrate
#             (num rerun a imagem já está no ECR e ela começa na hora). Snapshot que passa de 30 min falha o deploy
#             antes de existir green.
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
    # Só um código da AWS (AccessDenied, DBSnapshotAlreadyExists) sai no log; qualquer outra coisa pode ser um ARN.
    case "$codigo" in
      ''|*[!A-Za-z.]*) codigo="sem código" ;;
    esac
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

# Sai 0 quando o snapshot deve ser tirado. Toda dúvida (commit da blue, fetch, diff) tira o snapshot: aqui o `set -e`
# não vale, porque a função é chamada num `||`, então cada erro é tratado à mão.
traz_migration_nova() {
  local blue novas
  if ! blue=$(commit_da_blue) || [ -z "$blue" ]; then
    echo "::warning::Não deu para saber o commit da blue: o snapshot é tirado mesmo assim."
    return 0
  fi
  if ! git fetch --no-tags --depth=1 origin "$blue"; then
    echo "::warning::Não deu para buscar o commit da blue (${blue:0:10}): o snapshot é tirado mesmo assim."
    return 0
  fi
  if ! novas=$(git diff --name-only "$blue" "$GITHUB_SHA" -- db/migrate); then
    echo "::warning::Não deu para comparar com a blue (${blue:0:10}): o snapshot é tirado mesmo assim."
    return 0
  fi
  if [ -z "$novas" ]; then
    echo "Nenhuma migration nova desde a blue (${blue:0:10})."
    return 1
  fi
  printf 'Migrations novas desde a blue (%s):\n%s\n' "${blue:0:10}" "$novas"
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
