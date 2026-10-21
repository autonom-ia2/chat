# shellcheck shell=bash
# #2024: funções dos passos de migration do deploy (schema-contra-a-blue.sh e rds-snapshot-antes-da-migration.sh).
# Para ser lido com `source`.

# Roda um comando da AWS. Se falhar, o log público leva só o código do erro (AccessDenied, DBSnapshotAlreadyExists):
# a mensagem completa traz a conta e o ARN.
aws_quieto() {
  local erro status=0 mensagem codigo
  erro=$(mktemp)
  "$@" 2>"$erro" || status=$?
  if [ "$status" -ne 0 ]; then
    mensagem=$(cat "$erro")
    codigo="${mensagem#*(}"
    codigo="${codigo%%)*}"
    case "$codigo" in
      ''|*[!A-Za-z.]*) codigo="sem código" ;;
    esac
    echo "::error::A AWS recusou '$2 $3' ($codigo). Detalhe fora do log público: ver docs/migrations-em-lote.md." >&2
  fi
  rm -f "$erro"
  return "$status"
}

# Commit que a blue ($BLUE_INSTANCE_ID) roda. Mesma leitura do check-rollback-target.sh: a tag Name da instância
# termina no id do run que a criou, e o run traz o commit. Precisa de GITHUB_REPOSITORY e GH_TOKEN.
commit_da_blue() {
  local nome run_id tentativa
  nome=$(aws_quieto aws ec2 describe-instances --instance-ids "$BLUE_INSTANCE_ID" \
    --query "Reservations[0].Instances[0].Tags[?Key=='Name'].Value | [0]" --output text) || return 1
  run_id="${nome##*-}"
  case "$run_id" in
    *[!0-9]*|'') return 1 ;;
  esac
  # Uma falha isolada da API não pode parar o deploy.
  for tentativa in 1 2 3; do
    if gh api "repos/$GITHUB_REPOSITORY/actions/runs/$run_id" --jq .head_sha; then
      return 0
    fi
    sleep $((tentativa * 5))
  done
  return 1
}
