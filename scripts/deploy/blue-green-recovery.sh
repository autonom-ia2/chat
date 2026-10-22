#!/bin/bash

# Sourced by both workflows; the publisher transport budget is 25 seconds.
# Allow existing operations to finish after CURRENT moves away from green.
PUBLISHER_TRANSPORT_DRAIN_SECONDS=30

read_target_instance() {
  local targets_json
  targets_json=$(aws elbv2 describe-target-health --target-group-arn "$1" --output json) || return 1
  TARGET_INSTANCE_ID=$(printf '%s' "$targets_json" | jq -er '
    .TargetHealthDescriptions |
    if length == 1 and .[0].Target.Port == 3000 and
      (.[0].Target.Id | type == "string" and startswith("i-") and length > 2)
    then .[0].Target.Id else error("target_instance_invalid") end') || return 1
}

validate_target_pair() {
  read_target_instance "$1" || return 1
  if [ "$TARGET_INSTANCE_ID" != "$2" ]; then
    echo "blue_green_destination_mismatch" >&2
    return 1
  fi
}

# Read the AWS envelopes rather than trusting potentially stale SSM pointers.
read_listener_destination() {
  local listener_json
  listener_json=$(aws elbv2 describe-listeners --listener-arns "$1" --output json) || return 1
  ACTIVE_TG_ARN=$(printf '%s' "$listener_json" | jq -er '
    if (.Listeners | length) != 1 then error("listener_count_invalid") else
      [.Listeners[0].DefaultActions[] | select(.Type == "forward") |
        if .TargetGroupArn then .TargetGroupArn
        else .ForwardConfig.TargetGroups[] | select(.Weight > 0) | .TargetGroupArn end]
      | if length == 1 and (.[0] | type == "string" and length > 0)
        then .[0] else error("listener_destination_invalid") end
    end') || return 1
  read_target_instance "$ACTIVE_TG_ARN" || return 1
  ACTIVE_INSTANCE_ID="$TARGET_INSTANCE_ID"
}

record_previous_destination() {
  local write_status=0
  validate_target_pair "$1" "$2" || return 1
  aws ssm put-parameter --name "$PREVIOUS_TG_PARAMETER" --type String --value "$1" --overwrite || write_status=$?
  if [ "$write_status" -eq 0 ]; then
    aws ssm put-parameter --name "$PREVIOUS_INSTANCE_PARAMETER" --type String --value "$2" --overwrite || write_status=$?
  fi
  if [ "$write_status" -ne 0 ]; then
    # Either response can be lost after a write. Repair both from the validated
    # blue pair, never from a partially written PREVIOUS or an arbitrary target.
    aws ssm put-parameter --name "$PREVIOUS_TG_PARAMETER" --type String --value "$1" --overwrite || return 1
    aws ssm put-parameter --name "$PREVIOUS_INSTANCE_PARAMETER" --type String --value "$2" --overwrite || return 1
  fi
  return "$write_status"
}

reconcile_current_destination() {
  read_listener_destination "$1" || return 1
  if [ "$ACTIVE_TG_ARN" != "$2" ] || [ "$ACTIVE_INSTANCE_ID" != "$3" ]; then
    echo "blue_green_destination_mismatch" >&2
    return 1
  fi
  aws ssm put-parameter --name "$CURRENT_TG_PARAMETER" --type String --value "$ACTIVE_TG_ARN" --overwrite || return 1
  aws ssm put-parameter --name "$CURRENT_INSTANCE_PARAMETER" --type String --value "$ACTIVE_INSTANCE_ID" --overwrite || return 1
}

switch_listener_destination() {
  LISTENER_SWITCH_STATUS=0
  # Só o stdout (o JSON com os ARNs) sai do log público (#2032); o erro continua no stderr.
  aws elbv2 modify-listener --listener-arn "$1" \
    --default-actions "Type=forward,TargetGroupArn=$2" >/dev/null || LISTENER_SWITCH_STATUS=$?
  reconcile_current_destination "$1" "$2" "$3" || return 1
  # Confirmation allows the caller to restore its worker before propagating
  # LISTENER_SWITCH_STATUS. Failed confirmation always aborts recovery here.
}

# Estado EC2 de uma instância. Instância que a AWS já esqueceu (terminada há tempo) conta como terminated;
# qualquer outro erro da API falha, para ninguém agir sobre um estado que não leu.
instance_state() {
  local error_file state status=0
  error_file=$(mktemp)
  state=$(aws ec2 describe-instances --instance-ids "$1" \
    --query 'Reservations[0].Instances[0].State.Name' --output text 2>"$error_file") || status=$?
  if [ "$status" -ne 0 ]; then
    if grep -qF InvalidInstanceID.NotFound "$error_file"; then
      rm -f "$error_file"
      INSTANCE_STATE=terminated
      return 0
    fi
    cat "$error_file" >&2
    rm -f "$error_file"
    return 1
  fi
  rm -f "$error_file"
  INSTANCE_STATE="$state"
}

# #1350: a green só sai do wait_for_image do user data quando a imagem deste commit está no ECR. Sem a imagem, ela
# não rodou o deploy.sh nem migration. Retorna 0 só com ImageNotFoundException; imagem presente ou erro = 1.
green_image_absent() {
  local error_file status=0
  error_file=$(mktemp)
  aws ecr describe-images --repository-name "$1" --image-ids "imageTag=$2" >/dev/null 2>"$error_file" || status=$?
  if [ "$status" -ne 0 ] && grep -qF ImageNotFoundException "$error_file"; then
    rm -f "$error_file"
    return 0
  fi
  if [ "$status" -ne 0 ]; then
    cat "$error_file" >&2
  fi
  rm -f "$error_file"
  return 1
}

# #1350: termina a green que nunca recebeu a imagem e sai com o status que recebeu (o erro original da limpeza, ou
# 0). Se a terminação falhar, o job falha mesmo que o resto tenha dado certo.
terminate_green_without_image() {
  local status=$1
  trap - EXIT
  if aws ec2 terminate-instances --instance-ids "$GREEN_INSTANCE_ID" >/dev/null; then
    echo "Green terminada: não chegou a receber a imagem (#1350)."
  else
    echo "blue_green_unused_green_termination_failed" >&2
    if [ "$status" -eq 0 ]; then
      status=1
    fi
  fi
  exit "$status"
}

# #1979: congelamento em duas chaves, cada uma com um único dono, porque o SSM não lê e grava de forma atômica.
# O rollback grava o pedido (DEPLOY_FREEZE_PARAMETER = on:<run>:<tentativa>:pedido|trava); o deploy manual com descongelar=true
# grava a liberação (DEPLOY_FREEZE_RELEASED_PARAMETER) com o pedido que viu na largada. Congelada = há pedido e ele não
# é o liberado. Liberação velha, mesmo gravada atrasada, nunca solta um rollback mais novo, que tem outro valor.
# Chave que não existe conta como vazia; qualquer outro erro falha, para nenhum deploy seguir sem saber.
read_ssm_value() {
  local error_file status=0
  error_file=$(mktemp)
  SSM_VALUE=$(aws ssm get-parameter --name "$1" --query Parameter.Value --output text 2>"$error_file") || status=$?
  if [ "$status" -ne 0 ]; then
    SSM_VALUE=""
    if grep -qF ParameterNotFound "$error_file"; then
      rm -f "$error_file"
      return 0
    fi
    cat "$error_file" >&2
    rm -f "$error_file"
    return 1
  fi
  rm -f "$error_file"
}

read_deploy_freeze() {
  local released
  read_ssm_value "$DEPLOY_FREEZE_RELEASED_PARAMETER" || return 1
  released="$SSM_VALUE"
  read_ssm_value "$DEPLOY_FREEZE_PARAMETER" || return 1
  DEPLOY_FREEZE_VALUE="$SSM_VALUE"
  case "$DEPLOY_FREEZE_VALUE" in
    ''|off) DEPLOY_FREEZE=off ;;
    on|on:*)
      if [ "$DEPLOY_FREEZE_VALUE" = "$released" ]; then
        DEPLOY_FREEZE=off
      else
        DEPLOY_FREEZE=on
      fi
      ;;
    *)
      echo "deploy_freeze_invalid:$DEPLOY_FREEZE_VALUE" >&2
      return 1
      ;;
  esac
}

# Só o rollback chama.
write_deploy_freeze() {
  aws ssm put-parameter --name "$DEPLOY_FREEZE_PARAMETER" --type String --value "$1" --overwrite >/dev/null
}

# Só o deploy manual com descongelar=true chama, com o pedido que viu na largada.
release_deploy_freeze() {
  aws ssm put-parameter --name "$DEPLOY_FREEZE_RELEASED_PARAMETER" --type String --value "$1" --overwrite >/dev/null
}

abort_if_frozen() {
  read_deploy_freeze || return 1
  if [ "$DEPLOY_FREEZE" = on ]; then
    echo "::error::Produção congelada por um rollback (#1979): este deploy não sobe. Para soltar, deploy manual (workflow_dispatch, action=deploy) com descongelar=true."
    return 1
  fi
}

# #1979: rerun de um deploy velho não volta a produção para trás. Falha quando $1 é ancestral estrito do commit da
# última imagem construída (RUNTIME_IMAGE_PARAMETER, gravado antes do tráfego). Erro ao ler ou comparar não trava o
# deploy: rerun é raro, e travar todo deploy por uma falha de API repetiria a produção parada. Precisa de GH_TOKEN.
abort_if_older_than_published() {
  local published published_sha relation
  if ! published=$(aws ssm get-parameter --name "$RUNTIME_IMAGE_PARAMETER" --query Parameter.Value --output text); then
    echo "::warning::Não deu para ler a última imagem construída: a conferência de rerun foi pulada."
    return 0
  fi
  published_sha="${published##*:}"
  if [ "$published_sha" = "$1" ]; then
    return 0
  fi
  case "$published_sha" in
    *[!0-9a-f]*|'')
      echo "::warning::A imagem publicada ($published_sha) não tem SHA de commit: a conferência de rerun foi pulada."
      return 0
      ;;
  esac
  if [ "${#published_sha}" -ne 40 ]; then
    echo "::warning::A imagem publicada ($published_sha) não tem SHA de commit: a conferência de rerun foi pulada."
    return 0
  fi
  if ! relation=$(gh api "repos/$GITHUB_REPOSITORY/compare/$1...$published_sha" --jq .status); then
    echo "::warning::Não deu para comparar $1 com a última imagem construída ($published_sha): a conferência de rerun foi pulada."
    return 0
  fi
  if [ "$relation" = ahead ]; then
    echo "::error::$1 é mais velho que a última imagem construída ($published_sha): rerun de deploy antigo não sobe. Para subir a main atual, dispare um deploy novo pelo workflow_dispatch."
    return 1
  fi
}

# The helper is shipped by the workflow, never required on an older target.
# Failure propagates before stopping the remaining worker whenever target is online.
# Optional $2: marker line written in the same command, so later steps know the suspension (#1540).
suspend_instagram_assisted() {
  local script parameters command_id
  script=$(cat "$(dirname "${BASH_SOURCE[0]}")/suspend-instagram-assisted.py") || return 1
  parameters=$(jq -cn --arg script "sudo python3 - <<'INSTAGRAM_RECOVERY'
$script
INSTAGRAM_RECOVERY" --arg marker "${2:-}" '{commands: (["set -eu", $script, "sudo systemctl daemon-reload"] +
    if $marker == "" then [] else ["printf \"%s\\n\" \"" + $marker + "\" | sudo tee /opt/chatwoot/instagram-assisted-suspended >/dev/null"] end)}') || return 1
  # JSON completo: no formato `commands=[...]` o AWS CLI não decodifica o \n do JSON e o script chega quebrado (#1406).
  command_id=$(aws ssm send-command --instance-ids "$1" \
    --document-name AWS-RunShellScript --parameters "$parameters" \
    --query 'Command.CommandId' --output text) || return 1
  aws ssm wait command-executed --command-id "$command_id" --instance-id "$1" || {
    echo "instagram_recovery_suspension_failed" >&2
    return 1
  }
}


# Primeiro `<prefixo><código>` da entrada; código só com [a-z_]. Sem a linha, imprime vazio; malformado, falha.
instagram_step_after() {
  local line step='' found=''
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in "$1"*) [ -n "$found" ] || { found=1; step=${line#"$1"}; } ;; esac
  done
  if [ -n "$found" ]; then
    case "$step" in ''|*[!a-z_]*) return 1 ;; esac
  fi
  echo "$step"
}

# Código de um check.sh que falhou: exige a sentinela (em qualquer linha: o sudo pode imprimir antes) e uma linha de
# veredito do Instagram; quais códigos são do Instagram decide a INSTAGRAM_STEPS do coordination-preflight.sh. Veredito
# de host ou nenhum veredito: a falha não é do Instagram. Mesma função do deploy.sh da green.
instagram_preflight_verdict() {
  local line ran='' step=''
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in
      instagram_coordination_preflight_ran) ran=1 ;;
      "instagram_coordination_preflight_failed step="*) [ -n "$step" ] || step="${line#*step=}" ;;
    esac
  done
  [ -n "$ran" ] || return 1
  case "$step" in ''|*[!a-z_]*) return 1 ;; esac
  echo "$step"
}

# #1540: o preflight do Instagram na green não para o deploy. Só um check.sh que rodou e falhou (status Failed, com
# sentinela e código) suspende o Instagram assistido nela, pelo mesmo caminho da recuperação, grava o marcador,
# reinicia o que já roda e segue com um aviso. Qualquer outro status, erro de API, de leitura ou da suspensão é fatal.
# Deixa INSTAGRAM_GREEN_SUSPENDED=true quando a green está sem Instagram (agora ou antes deste passo).
check_green_instagram_or_suspend() {
  local command_id invocation status output error step host_step
  INSTAGRAM_GREEN_SUSPENDED=false
  command_id=$(aws ssm send-command --instance-ids "$1" --document-name AWS-RunShellScript \
    --parameters 'commands=["set -eu","if sudo test -e /opt/chatwoot/instagram-assisted-suspended; then sudo cat /opt/chatwoot/instagram-assisted-suspended; else sudo /opt/chatwoot/igcoord/check.sh; fi"]' \
    --query 'Command.CommandId' --output text) || return 1
  # O waiter também falha quando o check falha; quem decide é o status lido abaixo.
  aws ssm wait command-executed --command-id "$command_id" --instance-id "$1" || true
  # The waiter gives up after about 100 s; a slow but legitimate check (60 s tunnel wait plus
  # Rails boot) must not turn into a fatal "unexpected status". Keep reading until it ends.
  # Runner-side knob (this helper runs on the GitHub runner, never on the hosts); tests use 0.
  local deadline=$((SECONDS + ${INSTAGRAM_CHECK_WAIT_SECONDS:-600}))
  while :; do
    invocation=$(aws ssm get-command-invocation --command-id "$command_id" --instance-id "$1" \
      --query '{Status:Status,Output:StandardOutputContent,Error:StandardErrorContent}' --output json) || return 1
    status=$(printf '%s' "$invocation" | jq -er '.Status | strings') || return 1
    case "$status" in Pending|InProgress|Delayed) ;; *) break ;; esac
    [ "$SECONDS" -lt "$deadline" ] || break
    sleep 10
  done
  case "$status" in
    Success)
      output=$(printf '%s' "$invocation" | jq -er '.Output | strings') || return 1
      step=$(instagram_step_after 'INSTAGRAM_ASSISTED_SUSPENDED step=' <<<"$output") || return 1
      if [ -n "$step" ]; then
        INSTAGRAM_GREEN_SUSPENDED=true
        echo "::warning::INSTAGRAM_ASSISTED_SUSPENDED step=$step (suspenso antes deste passo)"
      fi
      return 0
      ;;
    Failed) ;;
    *)
      echo "instagram_preflight_status_unexpected" >&2
      return 1
      ;;
  esac
  error=$(printf '%s' "$invocation" | jq -er '.Error | strings') || return 1
  if ! step=$(instagram_preflight_verdict <<<"$error"); then
    host_step=$(instagram_step_after 'instagram_coordination_preflight_host_failed step=' <<<"$error") || host_step=''
    echo "instagram_preflight_failed_without_verdict host_step=${host_step:-none}" >&2
    return 1
  fi
  echo "INSTAGRAM_ASSISTED_SUSPENDED step=$step" >&2
  suspend_instagram_assisted "$1" "INSTAGRAM_ASSISTED_SUSPENDED step=$step" || return 1
  # The web health loop (18 x 5 s) fits inside the ~100 s command-executed waiter below.
  command_id=$(aws ssm send-command --instance-ids "$1" --document-name AWS-RunShellScript \
    --parameters 'commands=["set -eu","sudo systemctl try-restart chatwoot-worker.service","sudo systemctl restart chatwoot-web.service","for i in $(seq 1 18); do curl -fsS http://127.0.0.1:3000/ >/dev/null && exit 0; sleep 5; done; journalctl -u chatwoot-web.service --no-pager -n 120; exit 1"]' \
    --query 'Command.CommandId' --output text) || return 1
  aws ssm wait command-executed --command-id "$command_id" --instance-id "$1" || {
    echo "instagram_suspended_restart_failed" >&2
    return 1
  }
  INSTAGRAM_GREEN_SUSPENDED=true
  echo "::warning::INSTAGRAM_ASSISTED_SUSPENDED step=$step"
}
