# Runbook — mesclar contatos duplicados pelo nono dígito (#990)

O mesmo celular brasileiro gravado duas vezes na mesma conta, com e sem o nono dígito
(`+55 DD 9XXXXXXXX` e `+55 DD XXXXXXXX`). Fica o contato **com** o nono dígito; o outro é absorvido
pelo `ContactMergeAction` do Chatwoot (`Contacts::NinthDigitMergeAction`).

- Código: `app/services/contacts/ninth_digit_duplicate_merger.rb`, `app/services/contacts/ninth_digit_merge_action.rb`,
  `lib/tasks/contacts_ninth_digit.rake`.
- Workflow: `.github/workflows/ops-contacts-merge-ninth-digit.yml` (runner `.github/scripts/ops_ssm_rake.sh`).
- **Nunca** por console ou `rails runner` em produção.

## O que a mescla faz, por par

Numa transação só:

1. reaponta para o contato que fica as linhas que o `ContactMergeAction` não move: `campaign_import_rows`,
   `campaign_recipients`, `email_campaign_recipients`, `whatsapp_api_campaign_recipients`, `crm_cards`,
   `crm_follow_ups`, `crm_meeting_guests`, `csat_survey_responses`;
2. soma as etiquetas do absorvido (sem diferença de maiúsculas);
3. dá ao contato que fica a empresa do absorvido, se ele não tiver nenhuma;
4. move conversas, notas, contact_inboxes, ligações e leads da Prospecção (o `ContactMergeAction`) e as mensagens
   num único `UPDATE` (sem rajada de `MESSAGE_UPDATED`/webhooks). Logo antes de apagar o absorvido, move tudo de novo,
   para não apagar o que tenha chegado nele no meio do caminho.

O índice de busca avançada não é refeito para as mensagens movidas (não há job de reindexação): elas guardam o
remetente antigo no índice até a próxima edição.

## O que é pulado (e aparece no relatório)

| saída | motivo |
|---|---|
| `skip: ambiguous_group` | mais de dois contatos para o mesmo número |
| `skip: email_conflict` | os dois têm e-mail, e são diferentes |
| `skip: identifier_conflict` | os dois têm identifier, e são diferentes |
| `skip: company_conflict` | os dois têm empresa, e são diferentes |
| `skip: blocked_mismatch` | só um dos dois está bloqueado |
| `skip: name_conflict` | os dois têm nome, e são diferentes sem contar caixa, acento e espaços (`name_differs=true`): outra pessoa ou número reciclado. Nome que é só um telefone conta como vazio |
| `skip: shared_campaign` | os dois estão na mesma campanha de WhatsApp |
| `skip: missing` | um dos contatos sumiu durante a execução |
| `failed: <Classe>` | erro; o par é desfeito por inteiro e a execução termina com falha |

A saída tem só ids, contagens e flags — nada de nome, telefone ou e-mail. Os logs do Rails ficam em `warn` e sem
argumentos de job durante a task.

## Passo a passo

**Quando:** fora do horário comercial. Durante a mescla, conversas do contato absorvido mudam de dono, e um
atendimento em andamento pode ver o contato trocar.

1. **Commit em produção.** Pegue o SHA do último deploy com sucesso do stack:
   ```sh
   gh run list --workflow deploy-hub2you-blue-green.yml --status success -L 1 --json headSha -q '.[0].headSha'
   ```
   (`deploy-autonomia-blue-green.yml` para o outro stack). O workflow aborta se `/app/.git_sha` no container for
   outro commit.
2. **DRY-RUN:**
   ```sh
   gh workflow run ops-contacts-merge-ninth-digit.yml --ref main \
     -f stack=hub2you -f account_id=<ID> -f mode=dry_run -f expected_sha=<sha> -f confirm_production=false
   ```
3. **Conferir** o log do job: uma linha por par e a linha `totals:`. Olhar os `skip:` (principalmente
   `name_conflict`) e o tamanho de `conversations` e `repoint[...]`. Pares pulados ficam para decisão manual.
4. **Snapshot do RDS** do stack, manual, antes do apply (é o rollback; ver abaixo). Anotar o identificador do snapshot.
5. **APPLY:**
   ```sh
   gh workflow run ops-contacts-merge-ninth-digit.yml --ref main \
     -f stack=hub2you -f account_id=<ID> -f mode=apply -f expected_sha=<sha> -f confirm_production=true
   ```
   Sem `confirm_production=true` o job falha antes de tocar a instância.
6. **Conferir** que cada par saiu `merged` e que não houve `failed:`. Rodar o DRY-RUN de novo: os pares mesclados
   não aparecem mais (idempotente).

## Proteções do workflow

- só a partir do `main`, no environment `production` (com as aprovações configuradas nele);
- na fila de concorrência do deploy do stack (`deploy-<stack>-blue-green`): não roda durante um blue-green. Atenção:
  se já houver um deploy **pendente** nessa fila, disparar este workflow o substitui na fila — confira antes;
- comando fixo; `account_id` só com dígitos; `expected_sha` com 40 caracteres hexadecimais;
- prazo: SSM com `executionTimeout` de 3000 s, polling até estado final por até 3300 s, job com 60 min.

## Limite da saída

Não há destino de saída no CloudWatch ou no S3 configurado para esses stacks. O SSM devolve no máximo
**24.000 caracteres** de stdout e 8.000 de stderr. Por isso:

- a saída completa vai para `/var/log/chatwoot-ops/contacts-merge_ninth_digit_duplicates-<modo>-<data>.log` na
  instância (o caminho aparece no log do job);
- as últimas linhas (a de `totals:`) são repetidas no stderr, e sobrevivem ao corte do stdout.

## Rollback

A mescla apaga o contato absorvido e não tem desfazer por código. O rollback é **restaurar o snapshot do RDS**
tirado no passo 4, o que volta o banco inteiro àquele momento e perde o que entrou depois. Só faz sentido logo após um
apply errado, e só com OK do Rodrigo. Para um par isolado, o caminho é recriar o contato à mão a partir do snapshot
restaurado em outra instância.
