#!/bin/bash
# Diagnóstico da green no deploy blue-green (#2004). Roda no fim do job Deploy Green, antes da limpeza que termina a
# green, e só lê: describe-* e comandos SSM de leitura na green. Nada aqui muda tráfego, worker, instância ou
# parâmetro; qualquer falha (permissão, SSM fora do ar, API) vira uma linha no pacote e o script segue.
#
# O repositório é público: Step Summary, log do job e artifact são abertos. Por isso só sai daqui dado estrutural
# (target health, estado e status checks da EC2, docker ps, código HTTP do health local, df, free). Log da aplicação
# e do sistema (web, worker, cloud-init) pode ter dado de cliente: vai num send-command à parte cuja saída o workflow
# nunca lê; fica no histórico do SSM, na conta AWS, e o resumo só diz o CommandId e como ler.
#
# Sempre: horário de lançamento da green e fim do cloud-init (vão para a tabela de tempos do job seguinte).
# Só quando um passo crítico falhou ou demorou: o pacote, sanitizado, no Step Summary e em
# $RUNNER_TEMP/deploy-diagnostico (o passo seguinte do workflow sobe como artifact).
#
# Entradas (env): GREEN_INSTANCE_ID, GREEN_TG_ARN e BLUE_TG_ARN (quando existirem), JOB_STATUS, GH_TOKEN,
# GITHUB_REPOSITORY, GITHUB_RUN_ID, GITHUB_RUN_ATTEMPT, RUNNER_TEMP, GITHUB_OUTPUT, GITHUB_STEP_SUMMARY.

DIAG_SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Quanto o diagnóstico pode segurar a limpeza (ou, no deploy saudável, a trava) esperando o SSM: 2 s por tentativa.
DIAG_SSM_ATTEMPTS=30
BOOT_SSM_ATTEMPTS=6
# Repositório público: só os campos de estado, nunca ARN (que traz o ID da conta) nem ID de instância (#2032). O
# sanitizador corta o que sobrar.
DIAG_TARGET_HEALTH_QUERY='TargetHealthDescriptions[].{Port:Target.Port,State:TargetHealth.State,Reason:TargetHealth.Reason,Description:TargetHealth.Description}'
DIAG_INSTANCE_STATUS_QUERY='InstanceStatuses[].{State:InstanceState.Name,System:SystemStatus.Status,Instance:InstanceStatus.Status,Ebs:AttachedEbsStatus.Status}'
# Teto por arquivo no Step Summary (o limite do GitHub é 1 MiB por passo).
DIAG_SUMMARY_BYTES=20000

diag_sanitize() {
  python3 "$DIAG_SCRIPT_DIR/deploy-telemetry.py" sanitize
}

# Grava em $1 a saída sanitizada do comando que vem depois. Erro do comando fica no arquivo, nunca para o script.
diag_capture() {
  local file=$1
  shift
  { "$@" 2>&1 || echo "(falhou com status $?)"; } | diag_sanitize > "$DIAG_DIR/$file"
}

# Manda um comando de leitura para a green e devolve a saída crua em DIAG_SSM_OUTPUT. A saída crua só fica na
# memória: quem chama sanitiza antes de gravar.
diag_ssm_read() {
  local params=$1 attempts=$2 command_id ping status=""
  DIAG_SSM_OUTPUT=""
  ping=$(aws ssm describe-instance-information --filters "Key=InstanceIds,Values=$GREEN_INSTANCE_ID" \
    --query 'InstanceInformationList[0].PingStatus' --output text 2>&1) || ping="erro"
  if [ "$ping" != "Online" ]; then
    DIAG_SSM_OUTPUT="SSM da green fora do ar (PingStatus=$ping): sem logs de dentro da instância."
    return 1
  fi
  if ! command_id=$(aws ssm send-command --instance-ids "$GREEN_INSTANCE_ID" --document-name AWS-RunShellScript \
    --parameters "$params" --query 'Command.CommandId' --output text 2>&1); then
    DIAG_SSM_OUTPUT="send-command recusado: $command_id"
    return 1
  fi
  for _ in $(seq 1 "$attempts"); do
    sleep 2
    status=$(aws ssm get-command-invocation --command-id "$command_id" --instance-id "$GREEN_INSTANCE_ID" \
      --query Status --output text 2>/dev/null) || status=""
    case "$status" in Success|Failed|Cancelled|TimedOut) break ;; esac
  done
  DIAG_SSM_OUTPUT=$(aws ssm get-command-invocation --command-id "$command_id" --instance-id "$GREEN_INSTANCE_ID" \
    --query StandardOutputContent --output text 2>&1) || DIAG_SSM_OUTPUT="get-command-invocation falhou: $DIAG_SSM_OUTPUT"
  DIAG_SSM_OUTPUT="status da invocação: ${status:-sem resposta}
$DIAG_SSM_OUTPUT"
}

# Fim do cloud-init em epoch, lido da linha "cloud_init_fim_epoch N" da saída crua. Só dígitos saem daqui.
diag_boot_done() {
  local line value
  while IFS= read -r line; do
    case "$line" in
      "cloud_init_fim_epoch "*)
        value="${line#cloud_init_fim_epoch }"
        case "$value" in ''|*[!0-9]*) ;; *) echo "$value"; return 0 ;; esac
        ;;
    esac
  done <<< "$1"
}

# Comandos cuja saída o workflow lê: só estrutura. O curl guarda só o código HTTP e o tempo, nunca o corpo; o
# cloud-init status sem --long dá só o estado (done/error/running).
diag_structural_params() {
  jq -nc '{commands: [
    "exec 2>&1",
    "stat -c \"cloud_init_fim_epoch %Y\" /run/cloud-init/result.json",
    "echo \"== saude local\"; curl -s -o /dev/null -w \"HTTP %{http_code} em %{time_total}s\\n\" --max-time 10 http://127.0.0.1:3000/",
    "echo \"== docker ps\"; docker ps -a --format \"table {{.Names}}\\t{{.Image}}\\t{{.Status}}\"",
    "echo \"== df\"; df -h",
    "echo \"== free\"; free -m",
    "echo \"== cloud-init\"; cloud-init status",
    "true"
  ]}'
}

# Logs que podem ter dado de cliente. A saída deste comando NUNCA é lida pelo workflow: fica só no SSM.
DIAG_LOGS_COMMANDS=(
  "echo \"== cloud-init-output.log (fim)\"; tail -n 200 /var/log/cloud-init-output.log"
  "echo \"== web (fim)\"; journalctl -u chatwoot-web.service --no-pager -n 200"
  "echo \"== worker (fim)\"; journalctl -u chatwoot-worker.service --no-pager -n 200"
  "true"
)

# Manda o comando de logs e devolve só o CommandId (validado: hex e hífen) em DIAG_LOGS_COMMAND_ID.
diag_ssm_send_logs() {
  local params command_id ping
  DIAG_LOGS_COMMAND_ID=""
  ping=$(aws ssm describe-instance-information --filters "Key=InstanceIds,Values=$GREEN_INSTANCE_ID" \
    --query 'InstanceInformationList[0].PingStatus' --output text 2>/dev/null) || return 1
  [ "$ping" = "Online" ] || return 1
  params=$(jq -nc '{commands: $ARGS.positional}' --args "exec 2>&1" "${DIAG_LOGS_COMMANDS[@]}") || return 1
  command_id=$(aws ssm send-command --instance-ids "$GREEN_INSTANCE_ID" --document-name AWS-RunShellScript \
    --comment "deploy #2004: logs da green, leitura so pela conta AWS" \
    --parameters "$params" --query 'Command.CommandId' --output text 2>/dev/null) || return 1
  case "$command_id" in ''|*[!0-9a-f-]*) return 1 ;; esac
  DIAG_LOGS_COMMAND_ID="$command_id"
}

diag_summary() {
  local reasons=$1 file
  {
    echo "### Diagnóstico da green"
    echo
    echo "Motivo:"
    printf '%s\n' "$reasons" | sed 's/^/- /'
    echo
    echo "Só dado estrutural, sanitizado (o repositório é público). Os logs do web, do worker e do cloud-init ficam no SSM da conta AWS: veja 50-logs-no-ssm.txt."
    for file in "$DIAG_DIR"/*.txt; do
      [ -e "$file" ] || continue
      echo
      echo "<details><summary>$(basename "$file")</summary>"
      echo
      echo '~~~~text'
      head -c "$DIAG_SUMMARY_BYTES" "$file"
      echo
      echo '~~~~'
      echo '</details>'
    done
  } >> "${GITHUB_STEP_SUMMARY:-/dev/null}"
}

collect_green_diagnostics() {
  local launch jobs_file reasons boot_done boot_params
  DIAG_DIR="$RUNNER_TEMP/deploy-diagnostico"
  jobs_file="$RUNNER_TEMP/deploy-jobs.json"
  mkdir -p "$DIAG_DIR"
  if [ -z "${GREEN_INSTANCE_ID:-}" ]; then
    echo "Sem green neste deploy: nada a coletar."
    return 0
  fi

  launch=$(aws ec2 describe-instances --instance-ids "$GREEN_INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].LaunchTime' --output text 2>&1) || launch=""
  case "$launch" in [0-9][0-9][0-9][0-9]-*) ;; *) launch="" ;; esac
  echo "green_launch_time=$launch" >> "$GITHUB_OUTPUT"

  if ! gh api "repos/$GITHUB_REPOSITORY/actions/runs/$GITHUB_RUN_ID/attempts/$GITHUB_RUN_ATTEMPT/jobs?per_page=100" \
    > "$jobs_file"; then
    echo "::warning::API do GitHub indisponível: o diagnóstico decide só pelo status do job."
    : > "$jobs_file"
  fi
  reasons=$(python3 "$DIAG_SCRIPT_DIR/deploy-telemetry.py" critical "$jobs_file" "${JOB_STATUS:-}")
  if [ ! -s "$jobs_file" ] && [ "${BLUE_WORKER_STOPPED:-false}" = "true" ]; then
    # Sem a API não dá para saber se a falha foi na troca de workers; com o worker da blue parado, a limpeza que o
    # religa vem primeiro.
    reasons=""
  fi

  if [ -z "$reasons" ] && [ "${JOB_STATUS:-}" != "success" ]; then
    # Falha fora dos passos críticos (ex.: troca de workers): a limpeza vem logo depois e não espera o SSM.
    echo "green_boot_done=" >> "$GITHUB_OUTPUT"
    echo "Job falhou fora dos passos críticos: sem pacote de diagnóstico, a limpeza segue."
    return 0
  fi
  if [ -z "$reasons" ]; then
    boot_params=$(jq -nc '{commands: ["stat -c \"cloud_init_fim_epoch %Y\" /run/cloud-init/result.json"]}')
    diag_ssm_read "$boot_params" "$BOOT_SSM_ATTEMPTS" || true
    boot_done=$(diag_boot_done "$DIAG_SSM_OUTPUT")
    echo "green_boot_done=$boot_done" >> "$GITHUB_OUTPUT"
    echo "Passos críticos sem falha nem demora: sem pacote de diagnóstico."
    return 0
  fi

  echo "::warning::Coletando diagnóstico da green: $(printf '%s' "$reasons" | tr '\n' ';')"
  printf '%s\n' "$reasons" > "$DIAG_DIR/00-motivo.txt"
  if [ -n "${GREEN_TG_ARN:-}" ]; then
    diag_capture 10-target-health-green.txt aws elbv2 describe-target-health --target-group-arn "$GREEN_TG_ARN" \
      --query "$DIAG_TARGET_HEALTH_QUERY" --output json
  fi
  if [ -n "${BLUE_TG_ARN:-}" ]; then
    diag_capture 11-target-health-blue.txt aws elbv2 describe-target-health --target-group-arn "$BLUE_TG_ARN" \
      --query "$DIAG_TARGET_HEALTH_QUERY" --output json
  fi
  diag_capture 20-ec2-status-checks.txt aws ec2 describe-instance-status --instance-ids "$GREEN_INSTANCE_ID" \
    --include-all-instances --query "$DIAG_INSTANCE_STATUS_QUERY" --output json

  # Logs primeiro, para rodarem enquanto o comando estrutural espera; a saída deles não é lida.
  if diag_ssm_send_logs; then
    {
      echo "Logs do web, do worker e do cloud-init da green (podem ter dado de cliente; não saem do SSM)."
      echo "CommandId: $DIAG_LOGS_COMMAND_ID"
      echo "Para ler, com acesso à conta AWS desta stack:"
      echo "aws ssm list-command-invocations --command-id $DIAG_LOGS_COMMAND_ID --details"
    } > "$DIAG_DIR/50-logs-no-ssm.txt"
  else
    echo "Comando de logs não foi enviado (SSM fora do ar ou recusado)." > "$DIAG_DIR/50-logs-no-ssm.txt"
  fi

  if [ "${JOB_STATUS:-}" != "success" ] && [ "${BLUE_WORKER_STOPPED:-false}" = "true" ]; then
    # Worker da blue parado e o Sidekiq na green: a limpeza que o religa vem logo depois e não espera o SSM. O
    # comando de logs acima já foi (sem espera); o estrutural fica de fora.
    echo "green_boot_done=" >> "$GITHUB_OUTPUT"
    echo "Worker da blue parado: o comando estrutural não foi esperado, para não atrasar a limpeza." \
      > "$DIAG_DIR/40-ssm-green.txt"
  else
    diag_ssm_read "$(diag_structural_params)" "$DIAG_SSM_ATTEMPTS" || true
    boot_done=$(diag_boot_done "$DIAG_SSM_OUTPUT")
    echo "green_boot_done=$boot_done" >> "$GITHUB_OUTPUT"
    printf '%s\n' "$DIAG_SSM_OUTPUT" | diag_sanitize > "$DIAG_DIR/40-ssm-green.txt"
    DIAG_SSM_OUTPUT=""
  fi

  diag_summary "$reasons"
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  collect_green_diagnostics
fi
