#!/bin/bash
# Roda a conferência dos donos (SÓ LEITURA) no chatwoot-web da stack. Uso: rodar.sh hub2you|autonomia
set -euo pipefail
STACK=$1
DIR=$(cd "$(dirname "$0")" && pwd)
if [ "$STACK" = hub2you ]; then
  export AWS_PROFILE=hub2you
else
  set -a; . /Users/rodrigosilva/dev/Appsell/credential.env; set +a; unset AWS_PROFILE
fi
B=$(base64 < "$DIR/conferir_donos.rb" | tr -d '\n')
CMD="echo $B | base64 -d > /tmp/c2y_donos.rb && docker cp /tmp/c2y_donos.rb chatwoot-web:/tmp/c2y_donos.rb && rm -f /tmp/c2y_donos.rb && docker exec chatwoot-web sh -c 'cd /app 2>/dev/null || cd /; bundle exec ruby /tmp/c2y_donos.rb 2>&1 | grep -a -v -i -E \"warning|deprecat\"; rm -f /tmp/c2y_donos.rb'"
J=$(mktemp); jq -n --arg c "$CMD" '{commands:[$c]}' > "$J"
IID=$(aws ec2 describe-instances --region us-east-1 --filters Name=instance-state-name,Values=running "Name=tag:Name,Values=chatwoot-$STACK-prod-ec2-*" --query "sort_by(Reservations[].Instances[], &LaunchTime)[-1].InstanceId" --output text)
ID=$(aws ssm send-command --region us-east-1 --instance-ids "$IID" --document-name AWS-RunShellScript --timeout-seconds 900 --parameters "file://$J" --query Command.CommandId --output text); rm -f "$J"
sleep 10
for i in $(seq 1 120); do
  O=$(aws ssm get-command-invocation --region us-east-1 --command-id "$ID" --instance-id "$IID" --query '[Status,StandardOutputContent,StandardErrorContent]' --output text 2>&1)
  case "$O" in InProgress*|Pending*|Delayed*) sleep 5;; *) echo "stack=$STACK instancia=$IID"; echo "$O" | sed -E 's/[A-Za-z0-9_\-]{32,}/<REDACTED>/g'; break;; esac
done
