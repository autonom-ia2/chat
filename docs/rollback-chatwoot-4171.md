# Rollback do upgrade Chatwoot 4.17.1 (deploy de 2026-09-03)

## Atualização 2026-09-03, segundo release (`bbb09a91ac`: #288 + #289)

Deploy automático de `bbb09a91ac` (público-alvo + horário de atuação do agente,
sugestões de FAQ) nas duas stacks. **Terminou as instâncias `776d7eeec4`**
(`i-0d2831943aff7891b` e `i-07ada012b4efa52c9`); o rollback rápido agora volta
para `7c65a521eb` (release anterior, já validado em produção).

| | hub2you | autonomia |
|---|---|---|
| Green `bbb09a91ac` (no ar) | `i-055e291b2531f18a6` · TG `cw-hub2-green-247/2a46f986e2daccf4` | `i-0f16484ac6e8da74b` · TG `cw-auto-green-239/11cae466e7fda93b` |
| Blue `7c65a521eb` (parado, rollback) | `i-0d6903a05c9517efe` · TG `cw-hub2-green-246/79af6cbf3613d55b` | `i-07800dbe51780788a` · TG `cw-auto-green-238/5f262123fd191d8e` |
| Imagem ECR do blue | tag `rollback-0903-7c65a521eb` | tag `rollback-0903-7c65a521eb` |
| Snapshot RDS pré-release | `chatwoot-autonomia-prod-pre-release-20260903-entrega2` | `chatwoot-autonomia-prod-pre-release-20260903-entrega2` |

Migrations deste release (aditivas): `20260903150000` (tabela
`autonomia_agent_faq_suggestions`) e `20260903150100` (índices concorrentes).
Voltar o tráfego para o blue não exige reverter o banco: o código anterior
ignora a tabela nova. Imagens 4.17.1 puro (`rollback-4171-776d7eeec4`) e 4.15.1
(`rollback-pre-4171-*`) continuam disponíveis para a Opção B.

## Atualização 2026-09-03 (release `7c65a521eb`: #282 + #285 + #286)

O deploy automático de `7c65a521eb` (flags de Embedded Signup, convergência do
SLA, aba Desempenho do agente) rodou nas duas stacks e **terminou as instâncias
4.15.1** (`i-0c56f8fe53cfb8d12` e `i-0ce6dda908ebf857c`). A Opção A abaixo
passa a valer para voltar ao 4.17.1 puro (`776d7eeec4`), não mais ao 4.15.1.
Voltar ao 4.15.1 só pela Opção B (imagem `rollback-pre-4171-*`) ou C (snapshot
`…-pre-deploy-4171-20260903`).

| | hub2you | autonomia |
|---|---|---|
| Green `7c65a521eb` (no ar) | `i-0d6903a05c9517efe` · TG `cw-hub2-green-246/79af6cbf3613d55b` | `i-07800dbe51780788a` · TG `cw-auto-green-238/5f262123fd191d8e` |
| Blue `776d7eeec4` (4.17.1 puro, parado, rollback) | `i-0d2831943aff7891b` · TG `cw-hub2-green-245/a860cf4ba6ce04a5` | `i-07ada012b4efa52c9` · TG `cw-auto-green-237/e6e4e41e42eba796` |
| Imagem ECR 4.17.1 puro | tag `rollback-4171-776d7eeec4` | tag `rollback-4171-776d7eeec4` |
| Snapshot RDS pré-release | `chatwoot-autonomia-prod-pre-release-20260903-sla-desempenho` | `chatwoot-autonomia-prod-pre-release-20260903-sla-desempenho` |

Migrations aplicadas neste release (todas aditivas, sem drop): `20260903120000`
(flags), `20260903140000` (colunas `message_id`, `used_entry_ids`, `model` em
`autonomia_agent_events`), `20260903140100` (índices concorrentes). Voltar o
tráfego para o blue `776d7eeec4` não exige reverter o banco: as colunas e
índices extras são ignorados pelo código antigo, e as flags só ligam recursos
que o fork já tinha.

Para rollback do tráfego use a Opção A trocando os IDs pelos desta tabela
(instância blue `i-0d2831943aff7891b` / `i-07ada012b4efa52c9`, TG 245 / 237,
parar o worker no green 246 / 238).

---

Texto original do runbook (estado do dia do upgrade):

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
