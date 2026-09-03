# Rollback do upgrade Chatwoot 4.17.1 (deploy de 2026-09-03)

Válido enquanto as instâncias 4.15.1 existirem (elas são terminadas 5 minutos
após o **próximo** deploy bem-sucedido de cada stack). Snapshots e imagens
taggeadas `rollback-` não expiram.

Estado que subiu: `main` = `776d7eeec4` (Chatwoot 4.17.1, Rails 7.2.3.1).
Épico: autonom-ia2/chat#274.

## O que existe de rollback, por stack

| | hub2you (chat.hub2you.ai) | autonomia (agents.autonomia.site) |
|---|---|---|
| Conta AWS | `354307071110` (perfil CLI `hub2you`) | `140023375763` (credencial em `~/dev/Appsell/credential.env`) |
| Green 4.17.1 (no ar) | `i-0d2831943aff7891b` · TG `cw-hub2-green-245/a860cf4ba6ce04a5` | `i-07ada012b4efa52c9` · TG `cw-auto-green-237/e6e4e41e42eba796` |
| Blue 4.15.1 (parado, rollback) | `i-0c56f8fe53cfb8d12` · TG `cw-hub2-green-242/9cc0825ce286f833` · imagem `850445fd` | `i-0ce6dda908ebf857c` · TG `cw-auto-green-235/e26bbec221495b74` · imagem `7281261a` |
| Listener 443 | `arn:aws:elasticloadbalancing:us-east-1:354307071110:listener/app/chatwoot-autonomia-prod-ec2/464e18b9554cab60/6a4364c69884a430` | `arn:aws:elasticloadbalancing:us-east-1:140023375763:listener/app/chatwoot-autonomia-prod-ec2/683d6fd8206c13ad/48599e78c182fcbc` |
| Snapshot RDS pré-deploy | `chatwoot-autonomia-prod-pre-deploy-4171-20260903` (e `…-pre-4171-20260902`) | `chatwoot-autonomia-prod-pre-deploy-4171-20260903` |
| Imagens ECR 4.15.1 (`chatwoot-autonomia-prod`) | tags `rollback-pre-4171-850445fd` (era o que estava no ar) e `rollback-pre-4171-7281261a` | tag `rollback-pre-4171-7281261a` (era o que estava no ar) |
| Órfã parada (não faz parte do rollback) | `i-0c8207a1f7bd8f161` (imagem `7281261a`) | — |

Prefixo comum dos comandos da conta autonomia:

```bash
bash -c 'set -a; . ~/dev/Appsell/credential.env; set +a; unset AWS_PROFILE; aws <comando>'
```

## Opção A — voltar o tráfego para a instância 4.15.1 (minutos, sem tocar banco)

Preferida. O banco migrado (aditivo) convive com o código 4.15.1.

1. Ligar a instância blue e esperar ela ficar `running` + health `healthy` no TG antigo:

```bash
aws ec2 start-instances --profile hub2you --region us-east-1 --instance-ids i-0c56f8fe53cfb8d12
```

```bash
aws elbv2 describe-target-health --profile hub2you --region us-east-1 --target-group-arn arn:aws:elasticloadbalancing:us-east-1:354307071110:targetgroup/cw-hub2-green-242/9cc0825ce286f833
```

2. Trocar o listener (o workflow `rollback` faz exatamente isto: `Actions → Deploy Hub2You Chatwoot Blue Green → Run workflow → action=rollback, confirm_production=true`, na `main`). Manual:

```bash
aws elbv2 modify-listener --profile hub2you --region us-east-1 --listener-arn arn:aws:elasticloadbalancing:us-east-1:354307071110:listener/app/chatwoot-autonomia-prod-ec2/464e18b9554cab60/6a4364c69884a430 --default-actions Type=forward,TargetGroupArn=arn:aws:elasticloadbalancing:us-east-1:354307071110:targetgroup/cw-hub2-green-242/9cc0825ce286f833
```

3. Parar o worker do green para não haver dois Sidekiq em versões diferentes nas mesmas filas:

```bash
aws ssm send-command --profile hub2you --region us-east-1 --instance-ids i-0d2831943aff7891b --document-name AWS-RunShellScript --parameters 'commands=["sudo systemctl stop chatwoot-worker.service"]'
```

4. Conferir `curl https://chat.hub2you.ai/api` → `"version":"4.15.1"`.

Autonomia: mesmos passos com `i-0ce6dda908ebf857c`, TG `cw-auto-green-235/e26bbec221495b74`, listener `…/683d6fd8206c13ad/48599e78c182fcbc`, green `i-07ada012b4efa52c9`, usando o prefixo de credencial acima.

Efeito colateral aceito: contas mantêm as flags `whatsapp_embedded_signup_*`
ligadas e os bits reaproveitados (`unread_count_for_filters`,
`branded_email_templates`) aparecem como `quoted_email_reply` /
`insert_article_in_reply` no 4.15.1. Inofensivo.

## Opção B — instância 4.15.1 já terminada: subir a imagem taggeada

Só se a Opção A não for possível. Na instância que estiver no ar, apontar o
runtime para a imagem de rollback e rodar o `deploy.sh` (ele faz pull,
`db:chatwoot_prepare` e reinicia web/worker). O `chatwoot_prepare` do 4.15.1
contra o banco 4.17.1 não reverte nada: só confere que não há migration pendente
dele.

```bash
aws ssm send-command --profile hub2you --region us-east-1 --instance-ids <instancia-no-ar> --document-name AWS-RunShellScript --parameters 'commands=["sudo /opt/chatwoot/deploy.sh 354307071110.dkr.ecr.us-east-1.amazonaws.com/chatwoot-autonomia-prod:rollback-pre-4171-850445fd"]'
```

Autonomia: `140023375763.dkr.ecr.us-east-1.amazonaws.com/chatwoot-autonomia-prod:rollback-pre-4171-7281261a`.

Depois, atualizar o parâmetro SSM `/chatwoot/prod/runtime-image` para a mesma
URI, senão o próximo boot da instância volta para a imagem 4.17.1.

## Opção C — restaurar o banco (último recurso; perde dados gravados após o snapshot)

Só se houver corrupção de dados, não para bug de aplicação.

```bash
aws rds restore-db-instance-from-db-snapshot --profile hub2you --region us-east-1 --db-instance-identifier chatwoot-autonomia-prod-restore-20260903 --db-snapshot-identifier chatwoot-autonomia-prod-pre-deploy-4171-20260903 --db-instance-class db.t4g.micro --db-subnet-group-name chatwoot-autonomia-prod --vpc-security-group-ids sg-0098582d27daa127f --no-publicly-accessible
```

Depois: trocar `POSTGRES_HOST` no parâmetro `/chatwoot/prod/env` para o endpoint
da instância restaurada, reiniciar web/worker e fazer a Opção A ou B para o
código 4.15.1. Autonomia: mesmo comando com a credencial da conta
`140023375763` (subnet group e security group da instância
`chatwoot-autonomia-prod` daquela conta).

## Não fazer

- Não terminar `i-0c56f8fe53cfb8d12` nem `i-0ce6dda908ebf857c` enquanto o hold de 48 h durar.
- Não apagar as tags `rollback-pre-4171-*` nem os snapshots `…-pre-deploy-4171-20260903`.
- Não mergear código na `main` durante o hold: o deploy automático termina as instâncias 4.15.1 cinco minutos depois (sobram só snapshot e imagens).
- Nunca `rails runner`/`rails console` nas EC2 de produção (derrubou o Chatwoot em 2026-07-27); usar `psql` via SSM quando precisar ler o banco.
