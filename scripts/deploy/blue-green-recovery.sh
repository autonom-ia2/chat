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
  aws elbv2 modify-listener --listener-arn "$1" \
    --default-actions "Type=forward,TargetGroupArn=$2" || LISTENER_SWITCH_STATUS=$?
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
    echo "Green $GREEN_INSTANCE_ID terminada: não chegou a receber a imagem (#1350)."
  else
    echo "blue_green_unused_green_termination_failed:$GREEN_INSTANCE_ID" >&2
    if [ "$status" -eq 0 ]; then
      status=1
    fi
  fi
  exit "$status"
}

# The helper is shipped by the workflow, never required on an older target.
# Failure propagates before stopping the remaining worker whenever target is online.
suspend_instagram_assisted() {
  local script parameters command_id
  script=$(cat "$(dirname "${BASH_SOURCE[0]}")/suspend-instagram-assisted.py") || return 1
  parameters=$(jq -cn --arg script "sudo python3 - <<'INSTAGRAM_RECOVERY'
$script
INSTAGRAM_RECOVERY" '["set -eu", $script, "sudo systemctl daemon-reload"]') || return 1
  command_id=$(aws ssm send-command --instance-ids "$1" \
    --document-name AWS-RunShellScript --parameters "commands=$parameters" \
    --query 'Command.CommandId' --output text) || return 1
  aws ssm wait command-executed --command-id "$command_id" --instance-id "$1" || {
    echo "instagram_recovery_suspension_failed:$1" >&2
    return 1
  }
}
