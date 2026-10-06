#!/usr/bin/env bash
# #990: runs ONE allow-listed rake task in the chatwoot-web container of the active (current) instance via SSM.
# Used by .github/workflows/ops-campaign-audience-backfill.yml and ops-contacts-merge-ninth-digit.yml.
#
# Inputs (env), all validated here; nothing free-form reaches the remote command:
#   OPS_TASK           campaign_journey:backfill_audience_links | contacts:merge_ninth_digit_duplicates
#   OPS_MODE           dry_run | apply (apply adds APPLY=1)
#   OPS_CONFIRM        true is required for apply
#   OPS_EXPECTED_SHA   40-char lowercase commit; aborts when /app/.git_sha in the container differs
#   OPS_ACCOUNT_ID     digits only; required by contacts:merge_ninth_digit_duplicates
#   CURRENT_INSTANCE_PARAMETER  SSM parameter with the active instance id
#
# Output: SSM keeps at most 24,000 characters of stdout and 8,000 of stderr per invocation, and no CloudWatch/S3 output
# destination is configured for these stacks. So the full output is written to a log file on the instance
# (/var/log/chatwoot-ops/, path printed at start and end), stdout carries the run as far as the 24k limit, and the last
# lines (totals) are repeated on stderr so they are never lost to truncation. The output is printed while polling.
set -euo pipefail

POLL_SECONDS=10
DELIVERY_TIMEOUT_SECONDS=600
EXECUTION_TIMEOUT_SECONDS=3000
POLL_DEADLINE_SECONDS=3300

fail() {
  echo "::error::$1"
  exit 1
}

case "${OPS_TASK:-}" in
  campaign_journey:backfill_audience_links | contacts:merge_ninth_digit_duplicates) ;;
  *) fail "task not allowed" ;;
esac

case "${OPS_MODE:-}" in
  dry_run) APPLY_ENV='' ;;
  apply)
    [ "${OPS_CONFIRM:-false}" = "true" ] || fail "mode=apply requires confirm_production=true"
    APPLY_ENV='-e APPLY=1'
    ;;
  *) fail "mode must be dry_run or apply" ;;
esac

SHA="${OPS_EXPECTED_SHA:-}"
case "$SHA" in
  '' | *[!0-9a-f]*) fail "expected_sha must be a full lowercase commit sha" ;;
esac
[ "${#SHA}" -eq 40 ] || fail "expected_sha must have 40 characters"

ACCOUNT_ENV=''
if [ "$OPS_TASK" = "contacts:merge_ninth_digit_duplicates" ]; then
  case "${OPS_ACCOUNT_ID:-}" in
    '' | *[!0-9]*) fail "account_id must be digits only" ;;
  esac
  ACCOUNT_ENV="-e ACCOUNT_ID=$OPS_ACCOUNT_ID"
fi

LOG_NAME="${OPS_TASK//:/-}-${OPS_MODE}"
REMOTE=$(cat <<EOF
set -u
running="\$(docker exec chatwoot-web cat /app/.git_sha)"
if [ "\$running" != "$SHA" ]; then echo "runtime sha mismatch: running=\$running expected=$SHA" >&2; exit 3; fi
mkdir -p /var/log/chatwoot-ops
LOG="/var/log/chatwoot-ops/$LOG_NAME-\$(date -u +%Y%m%dT%H%M%SZ).log"
echo "runtime sha ok; full log on host: \$LOG"
rc=0
docker exec -e RAILS_LOG_TO_STDOUT=false $APPLY_ENV $ACCOUNT_ENV chatwoot-web bundle exec rails $OPS_TASK > "\$LOG" 2>&1 || rc=\$?
cat "\$LOG"
echo "full log on host: \$LOG" >&2
tail -n 5 "\$LOG" >&2
exit "\$rc"
EOF
)

PARAMS="$(REMOTE="$REMOTE" EXEC_TIMEOUT="$EXECUTION_TIMEOUT_SECONDS" python3 -c \
  'import json, os; print(json.dumps({"commands": [os.environ["REMOTE"]], "executionTimeout": [os.environ["EXEC_TIMEOUT"]]}))')"

INSTANCE_ID="$(aws ssm get-parameter --name "$CURRENT_INSTANCE_PARAMETER" --query 'Parameter.Value' --output text)"
echo "Active instance: $INSTANCE_ID | task: $OPS_TASK | mode: $OPS_MODE"

COMMAND_ID="$(aws ssm send-command \
  --instance-ids "$INSTANCE_ID" \
  --document-name 'AWS-RunShellScript' \
  --timeout-seconds "$DELIVERY_TIMEOUT_SECONDS" \
  --comment "ops $OPS_TASK ($OPS_MODE)" \
  --parameters "$PARAMS" \
  --query 'Command.CommandId' --output text)"
echo "SSM command: $COMMAND_ID"

deadline=$(($(date +%s) + POLL_DEADLINE_SECONDS))
printed=0
STATUS=Pending
while [ "$(date +%s)" -lt "$deadline" ]; do
  sleep "$POLL_SECONDS"
  # Right after send-command the invocation may not exist yet; the error is printed and polling goes on.
  INVOCATION="$(aws ssm get-command-invocation --command-id "$COMMAND_ID" --instance-id "$INSTANCE_ID" --output json)" || continue
  STATUS="$(printf '%s' "$INVOCATION" | python3 -c 'import json, sys; print(json.load(sys.stdin)["Status"])')"
  STDOUT_NOW="$(printf '%s' "$INVOCATION" | python3 -c 'import json, sys; print(json.load(sys.stdin).get("StandardOutputContent", ""), end="")')"
  if [ "${#STDOUT_NOW}" -gt "$printed" ]; then
    printf '%s\n' "${STDOUT_NOW:$printed}"
    printed=${#STDOUT_NOW}
  fi
  case "$STATUS" in
    Success | Failed | TimedOut | Cancelled) break ;;
  esac
done
echo "Status: $STATUS"

case "$STATUS" in
  Success | Failed | TimedOut | Cancelled) ;;
  *) fail "SSM command still $STATUS after ${POLL_DEADLINE_SECONDS}s; check it in the console: $COMMAND_ID" ;;
esac

echo "----- stderr (last lines, survive the 24k stdout limit) -----"
printf '%s' "$INVOCATION" | python3 -c 'import json, sys; print(json.load(sys.stdin).get("StandardErrorContent", ""))'

[ "$STATUS" = "Success" ] || fail "SSM command did not succeed (status=$STATUS)"
