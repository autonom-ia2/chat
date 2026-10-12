# Agendamento WhatsApp-first: como voltar atrás

Runbook de rollback do épico #1187 (termo RA-12). Vale para os dois stacks (Hub2You e Autonom.ia). Toda volta em
produção pede OK do Rodrigo, menos o rollback de emergência do deploy, que se faz e se avisa na hora
(`docs/processo-de-release.md`).

As migrations do épico só acrescentam (tabelas, colunas, índices). Nenhuma volta exige reverter o banco.

## 1. Uma conta: desligar a flag (o mais comum)

- **Onde:** Super Admin › Accounts › a conta › Edit › em Features, desmarcar **"Agendamento WhatsApp-first (CRM)"**
  (`crm_booking_v2`) › Save.
- **Efeito:** as rotas novas passam a responder 404, a página pública nova e o link curto `/a/...` param, o menu volta ao
  Calendário solto e o botão "Agendamento" do Kanban volta para a gaveta antiga. As reuniões já marcadas continuam no
  calendário. O cron de avisos não envia nada para conta sem a flag.
- **ETA:** imediato, sem deploy nem restart. A pessoa só precisa recarregar o painel.

## 2. Todas as contas: desligar a flag em lote

Usar quando a liberação geral (#1399) der problema. O bit vem do mapeamento do `config/features.yml`
(`crm_booking_v2` é o 15º item da coluna `feature_flags_ext_1`, máscara 16384). Confira antes:

```sql
-- 1) conferir (leitura) e guardar a lista, para poder religar só estas contas
BEGIN READ ONLY;
SELECT id FROM accounts WHERE (feature_flags_ext_1 & 16384) <> 0 ORDER BY id;
COMMIT;

-- 2) desligar em todas as contas
BEGIN;
UPDATE accounts SET feature_flags_ext_1 = feature_flags_ext_1 & ~16384 WHERE (feature_flags_ext_1 & 16384) <> 0;
COMMIT;
```

- **Como rodar:** psql via SSM dentro do `chatwoot-web` (nunca `rails runner`). A instância muda a cada deploy: achar a
  que está `running` com `aws ec2 describe-instances`. Rodar nos dois stacks.
- **ETA:** cerca de 5 minutos, contando a busca da instância nos dois stacks. Vale na hora, sem restart.
- **Contas novas:** o padrão fica em `installation_configs.ACCOUNT_LEVEL_FEATURE_DEFAULTS`, gravado como YAML dentro do
  jsonb. Não editar por SQL. Para as contas novas voltarem a nascer sem a flag, abrir um PR com `enabled: false` no
  `config/features.yml` e uma migration que chame `FeatureFlagRollout.padrao!('crm_booking_v2', false)` (o mesmo que o
  `down` da migration `20261023100000`). Vai pela fila normal, cerca de 10 minutos depois do merge.

## 3. O deploy inteiro: voltar a imagem anterior

Usar quando o problema é do código do deploy, não da flag.

```sh
gh workflow run deploy-hub2you-blue-green.yml -R autonom-ia2/chat -f action=rollback
gh workflow run deploy-autonomia-blue-green.yml -R autonom-ia2/chat -f action=rollback
```

- **Efeito:** o tráfego volta para a instância anterior. Só volta **um degrau**: a instância de dois deploys atrás é
  terminada cerca de 5 minutos depois de cada deploy. Se já houver outro deploy por cima, o caminho é um PR com
  `git revert` pela fila (`docs/processo-de-release.md`, item 9).
- **Banco:** fica como está; as migrations do épico são aditivas e o código anterior as ignora.
- **ETA:** 1 a 2 minutos para a troca do tráfego; com `git revert`, cerca de 10 minutos depois do merge.
