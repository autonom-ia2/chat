# PR #443 — fechamento dos achados do review externo de 17/09/2026

Base revisada externamente: `main cd30dba0c922f0716866ec6f46d1d0f79222b864` → PR #443 `28fb2997e8222d63c8c8ab10c2df977aadc3a76a`. O review externo classificou dois P1 e um P2 e não alterou a aplicação. Este documento registra a correção local; **não autoriza merge/deploy**.

## P1 — feedback superseded em shadow/warning

`Evaluator#block_superseded!` não fica mais restrito a `enforce`. Observação superseded somente pode **adicionar** proteção: `shadow/warning` usam `LegacyDecision`, `enforce` usa a policy nova. `current_metrics` obsoletos não são publicados e o caminho não pode liberar. Regressões PostgreSQL com duas conexões cobrem `shadow`, `warning` e `enforce`; o gate final de reputação, já incluindo provider, executou **43 exemplos, zero falhas**; o cumulativo confirma os três modos.

## P1 — poll SES nocivo concluindo fora de ordem

`ProviderMonitor` continua impedindo telemetria antiga de substituir telemetria mais nova. Uma resposta tardia nociva incrementa `harmful_generation` e adiciona monotonicamente `blocked=true`, preservando `status/telemetry/checked_at` mais novos. Durante o fechamento interno foi identificada uma segunda janela: a coleta saudável do `ProviderRelease` podia terminar antes do nocivo e, ainda assim, limpar o latch no lock final. O release agora captura `harmful_generation` após a coleta e exige a mesma geração sob o lock; qualquer nocivo persistido nesse intervalo invalida a liberação. Regressão determinística controla exatamente `healthy collected → harmful persisted → final release lock`, além das duas ordens anteriores. O gate final de reputação (Evaluator + monitor + release/concurrency) executou **43 exemplos, zero falhas**. `unknown/error` preservado sobre um estado já bloqueado não incrementa `harmful_generation`; somente observação realmente nociva invalida uma release concorrente. Nenhuma coleta externa ocorre sob row lock.

## P2 — exclusão pelo web antigo após schema novo

As FKs de `email_campaign_import_issues` para `email_campaigns` e `email_campaign_imports` agora têm `ON DELETE CASCADE`; o `schema.rb` preserva o contrato. Spec PostgreSQL: **2 exemplos, zero falhas**. Compatibilidade de upgrade foi repetida depois do schema final: schema real da `main` → migrations da #443 até `20260916123000` (incluindo `harmful_generation`) → fixture de account/campaign/import criada pelo código da `main` + linha na tabela nova simulando o worker candidato → DELETE autenticado pelo controller/request stack real da `main`. Resultado: HTTP 204 e `campaigns=0`, `imports=0`, `issues=0`, sem FK/500.

## Gates integrados após os três fixes

Ambiente descartável: PostgreSQL 17 em loopback, Redis em loopback, `RAILS_ENV=test`, AWS metadata desabilitada, credenciais AWS apontadas para `/dev/null`, nenhum e-mail real e nenhum acesso à produção.

- seletor cumulativo da #443 + novo spec de FK: **907 exemplos, zero falhas, um pending preexistente de `Account has_many autonomia_account_links`**;
- contratos Ruby puros: **9 arquivos, 57 testes, 50.876 asserções, zero falhas/erros/skips**;
- RuboCop cumulativo: **185 arquivos, zero infrações**;
- `git diff --check`: aprovado.

A primeira tentativa do gate P1 do provider terminou antes de executar exemplos porque o PostgreSQL descartável local havia parado; o serviço foi recriado em loopback e o mesmo gate passou. Isso foi falha de harness, não evidência de produto. O fechamento também testou explicitamente a janela coleta saudável → nocivo persistido → lock final do release; o fence `harmful_generation` impediu a liberação e manteve o latch.

## Limites e próximos gates

O frontend não foi alterado por estes três fixes; os gates frontend/browser continuam válidos apenas como evidência anterior até o CI da nova #443 repeti-los. Antes de reconsiderar merge: commit/push dos fixes na branch da #443, CI próprio verde no novo SHA e nova revisão adversarial independente. O rollout é consolidado: #438–#442 não são deploys separados; #443 é um merge/um blue-green, seguido de ativações `shadow → warning → enforce` somente por decisão operacional explícita.
