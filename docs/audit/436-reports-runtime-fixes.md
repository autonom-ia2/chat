# #436 — correções após o primeiro runtime de relatórios

Data: 2026-09-17. Escopo: Reports, Presentation e seus testes/documentação nesta worktree.

## Evidência recebida e limite da conclusão

Lidos `AGENTS.md`, `tmp/email436/reports-first.json`, `reports-first.log`, fontes reais,
factories (somente leitura), policies, handler de exceções e testes existentes de conta.
O JSON/log registra **204 exemplos, 32 falhas, 0 pending**. O baseline do PR1 com
488 testes verdes foi informado pelo parent; não foi reexecutado nesta rodada.

As falhas recebidas se dividem em:

- 8 fixtures: segunda campanha SES da mesma conta criava outra identidade `example.org`.
  Os testes agora reutilizam `campaign.sender_identity`. Factory global intacta.
- 23 de autenticação/contrato HTTP: controller specs usavam `sign_in` sem scope `:user`,
  e expectativas de negação Pundit usavam 403. A autenticação dos controller specs agora
  explicita `scope: :user`, com controle 200 na mesma action antes da negação do agente.
  Nos requests, o mesmo agente prova autenticação em `/api/v1/profile` com 200 e ID correto.
  A negação exige 401 **e** a mensagem específica de Pundit, não apenas qualquer 401.
- 1 de DTO: `Hygiene#can_recheck?` retornava nil para usuário sem membership. O resultado
  agora é estritamente booleano, comparando a decisão real da policy com true.

A mudança 403 → 401 se baseia em `RequestExceptionHandler#handle_with_exception`, que
resgata `Pundit::NotAuthorizedError` e chama `render_unauthorized`, e no baseline existente
`spec/requests/api/v1/accounts/email_campaigns/reputation_spec.rb`, que prova autenticação
do agente antes de esperar 401. Os 404 de isolamento, 200 positivos e 422 de validação
foram preservados. Nenhum mock de autenticação, skip ou remoção de asserção foi introduzido.

## Complaint, métricas e apresentação

- `Reports::Metrics` usa `ComplaintClassifier::REAL_COMPLAINT_SQL` no contador complained
  e no numerador SES de complaint_rate. OnAccount/OnTenant são prevenção; ausência de
  objeto/subtipo, null e subtipo desconhecido permanecem reclamações reais.
- `activity.complaint` continua contando todas as notificações, inclusive duplicatas e
  prevenção. O histórico não é recortado pela janela reputacional de sete dias.
- Provider prevention usa o predicado compartilhado
  `Reputation::Metrics::COUNT_FILTERS[:provider_prevented]` com COUNT DISTINCT recipient_id
  na união de Bounce e Complaint. Uma pessoa com ambos não é contada duas vezes.
- Reclamação real e prevenção podem coexistir para a mesma pessoa. As classes se sobrepõem;
  prevenção posterior/anterior não elimina reclamação real nem bounce permanente histórico.
  Contagens/policies do backend de reputação não foram alteradas.
- A agregação de eventos devolve no máximo dois registros por campanha (aceitos/não aceitos),
  com colunas fixas. Mantém as três consultas de métricas, sem arrays de histórico ou
  materialização de destinatários em Ruby. A asserção existente de até cinco SELECTs do
  Builder permanece intacta.
- `Reports::RecipientOutcomes` lê a última evidência de cada tipo em uma consulta, com
  desempate occurred_at/id e no máximo duas linhas por destinatário da página/lote CSV.
  Substitui o antigo reader de bounce isolado na apresentação; filtros de bounce continuam
  usando `BounceOutcomes`. A asserção de quatro consultas por lote permanece intacta.
- Última Complaint de prevenção apresenta suppressed/unknown/provider_suppression em JSON
  e CSV, preservando estados mais fortes unsubscribed/complained e razões de supressão
  provenientes do registry. Nenhuma linha é regravada. Status de filtro e current_status_counts
  continuam referindo-se ao estado persistido, como no contrato existente.

Foram acrescentadas regressões para ambos os subtipos, payload ausente/null/desconhecido,
duplicatas, real+prevenção em ordens distintas, união Bounce+Complaint, separação SES/direct,
aceitos/não aceitos e isolamento. Um request percorre os contadores de summary/campaign/detail,
a lista de destinatários e o CSV real, comparando status e razões e verificando estado persistido.

## Validação executada nesta rodada

Sem Rails, RSpec, banco, rede, instalação, leitura de secrets ou Git writes.

- Parser Ruby 3.4.4: **39 arquivos, todos Syntax OK**.
- RuboCop: **39 files inspected, no offenses detected**.
- `GIT_OPTIONAL_LOCKS=0 git diff --check`: saída 0.
- Snapshot SHA-256 de 438 arquivos preexistentes (serviços de email, controllers, factories,
  schema): somente os quatro fontes preexistentes deste recorte mudaram; **434 intactos**.
  Inclui auth, delivery/reputation, factories globais e schema. O novo RecipientOutcomes não
  estava no snapshot inicial.

O manifesto de lint é o anterior de 37 arquivos mais os dois arquivos Ruby novos:

```sh
env -i PATH=/Users/rodrigosilva/.rbenv/versions/3.4.4/bin:/usr/bin:/bin RUBOCOP_CACHE_ROOT=/private/tmp/436-pr2-rubocop /bin/zsh -c 'bundle exec rubocop --no-server --cache false --format simple $(cat /private/tmp/436-pr2-ruby-manifest.txt) app/services/email_campaigns/reports/recipient_outcomes.rb spec/services/email_campaigns/reports/complaint_metrics_436_spec.rb'
```

O parser executou `/Users/rodrigosilva/.rbenv/versions/3.4.4/bin/ruby -c` para cada um
desses 39 arquivos, em ambiente limpo. RuboCop corrigiu somente alinhamento de argumentos
nos três arquivos de spec deste recorte antes da verificação final. Não alterou código externo.

## Próxima execução — somente pelo parent

**Runtime após estas correções continua pendente.** Os 32 erros recebidos tiveram suas
causas tratadas no código/testes; parser/lint não demonstram que a suíte passou.
O parent deve incluir o novo spec no rerun do harness isolado já preparado:

```sh
bundle exec rspec spec/requests/api/v1/accounts/email_campaigns/reports_integration_436_spec.rb spec/controllers/email_campaigns/reports_436_spec.rb spec/services/email_campaigns/presentation/protection_spec.rb spec/services/email_campaigns/reports/recipient_query_436_spec.rb spec/services/email_campaigns/reports/metrics_436_spec.rb spec/services/email_campaigns/reports/complaint_metrics_436_spec.rb spec/services/email_campaigns/reports/presentation_436_spec.rb spec/services/email_campaigns/reports/export_and_issues_436_spec.rb
```

Nenhuma action/rota/integração de classificador foi adiada dentro deste recorte. Git/PR/Project,
runtime, review, aprovação, merge e plano de deploy/rollback continuam com o parent.
Não houve mudança em produção, outra worktree, core auth, factories, schema ou delivery/reputation.

## Arquivos desta correção

```text
app/services/email_campaigns/presentation/hygiene.rb
app/services/email_campaigns/presentation/recipients.rb
app/services/email_campaigns/reports/bounce_outcomes.rb
app/services/email_campaigns/reports/metrics.rb
app/services/email_campaigns/reports/recipient_outcomes.rb (novo)
spec/controllers/email_campaigns/reports_436_spec.rb
spec/requests/api/v1/accounts/email_campaigns/reports_integration_436_spec.rb
spec/services/email_campaigns/reports/metrics_436_spec.rb
spec/services/email_campaigns/reports/presentation_436_spec.rb
spec/services/email_campaigns/reports/complaint_metrics_436_spec.rb (novo)
docs/email-campaigns/reports.md
docs/audit/436-reports-runtime-fixes.md (novo)
```
