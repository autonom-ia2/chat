#!/bin/bash
# #1979: o rollback só troca o tráfego se a instância anterior veio do commit esperado. A tag Name que o deploy dá à
# green termina no id do run que a criou, e o run traz o commit. Rodado duas vezes: antes de congelar (erro de
# digitação falha na hora, sem congelar nada) e dentro da trava do deploy, logo antes de trocar o tráfego.
# Usa ESPERADO_SHA, PREVIOUS_INSTANCE_PARAMETER, GITHUB_REPOSITORY e GH_TOKEN.
set -euo pipefail

instance_sha() {
  local name run_id
  name=$(aws ec2 describe-instances --instance-ids "$1" \
    --query "Reservations[0].Instances[0].Tags[?Key=='Name'].Value | [0]" --output text)
  run_id="${name##*-}"
  case "$run_id" in
    *[!0-9]*|'') return 1 ;;
  esac
  gh api "repos/$GITHUB_REPOSITORY/actions/runs/$run_id" --jq .head_sha
}

# Para o caso de a anterior não ser a esperada: quem ainda existe, e de que commit veio.
list_candidates() {
  local id state sha
  echo "Instâncias de deploy que ainda existem (id, estado, commit):"
  aws ec2 describe-instances \
    --filters Name=tag:ManagedBy,Values=github-actions Name=instance-state-name,Values=running,stopped \
    --query 'Reservations[].Instances[].[InstanceId,State.Name]' --output text |
    while read -r id state; do
      sha=$(instance_sha "$id" || echo '?')
      echo "  $id $state ${sha:0:10}"
    done
}

esperado=$(printf '%s' "${ESPERADO_SHA:-}" | tr 'A-F' 'a-f')
case "$esperado" in
  *[!0-9a-f]*)
    echo "::error::esperado_sha só aceita o SHA do commit (0-9, a-f). Nada foi trocado."
    exit 1
    ;;
esac

previous_instance_id=$(aws ssm get-parameter --name "$PREVIOUS_INSTANCE_PARAMETER" --query Parameter.Value --output text)
if ! previous_sha=$(instance_sha "$previous_instance_id"); then
  echo "::error::A anterior $previous_instance_id não diz de que deploy veio. Nada foi trocado."
  list_candidates
  exit 1
fi
echo "A anterior $previous_instance_id veio do commit $previous_sha."

if [ "${#esperado}" -lt 7 ]; then
  echo "::error::Informe esperado_sha (7+ caracteres). A anterior roda ${previous_sha:0:10}: se é para lá que o tráfego deve voltar, dispare de novo com esperado_sha=${previous_sha:0:10}. Nada foi trocado."
  exit 1
fi
case "$previous_sha" in
  "$esperado"*)
    echo "Confere: o rollback volta para $previous_sha."
    ;;
  *)
    echo "::error::A anterior roda ${previous_sha:0:10}, não $esperado: um deploy subiu depois daquele que se quer desfazer. Nada foi trocado."
    list_candidates
    exit 1
    ;;
esac
