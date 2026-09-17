# #436 — PR2 reports/API integration

Data: 2026-09-17. Worktree: `436-reports-integration`.
Base confirmada por leitura: `97db2438274f08b1f988d9d45d7703bb24dd2d0e`.

Integração local sobre os arquivos de relatórios/DTO previamente copiados. Foram lidos
`AGENTS.md`, `docs/email-campaigns/reports.md`, `docs/audit/436-resume-contract.md`, as fontes
de reports/presentation/query, controllers/policies/Jbuilders/rotas relacionados e os
produtores reais do PR1. A busca em `enterprise/app` e `enterprise/config` não encontrou
overrides correspondentes de campanhas de email/relatórios.

Sem Git writes, commits, rebase, rede, Rails, RSpec, banco, SSH, AWS, SMTP, instalação,
leitura de `.env` ou alteração de outra worktree. Nenhuma mudança em delivery, admission,
registry, reputation core, migrations, CI, UI ou traduções. Issue/branch/PR/Project,
execução Rails isolada, review, aprovação, merge e deploy pertencem ao parent.
Este registro não declara PR pronta nem aprovação de release.

## Contratos implementados

- `GET campaigns`: aplica `CampaignQuery` com whitelist de status, alias `attention`,
  busca literal, rejeição de arrays/hashes/conflitos e datas não vazias com 422.
  Preserva `{payload:{campaigns:[...]}}` e os campos legados.
- O partial de campanha acrescenta `preflight` e `protection`, normaliza `pause_reason`
  somente na resposta e limita `last_error`, `ai_error` e dados de importação a campos/códigos
  públicos. JSON estruturado de pausa e diagnósticos internos não são regravados.
  Os campos estatísticos e o preflight legítimo de `recipient_import.result` são preservados;
  actor, note e campos arbitrários do resultado não são serializados.
- Um `Presentation::Campaign` e um `Presentation::Protection` por lista/request.
  GET não chama Reputation::Metrics, Observation, Evaluator, DNS, monitor ou enqueue.
  As agregações de Reports::Metrics continuam sendo consultas locais de relatório.
- Todas as respostas bem-sucedidas existentes de campanhas que renderizam `show` passam
  por reload da campanha/conta e uma apresentação nova depois da mutação.
  `POST campaigns/:id/reevaluate` agora retorna `{payload:<campaignDTO>}`, em vez de
  transmitir o payload interno de Guardrail. Reevaluation não limpa a pausa.
- `POST campaigns/:id/recheck` usa `EmailCampaignPolicy#recheck?` e lookup da conta.
  Chama o método real `RecipientPreflightJob.enqueue(id, recheck: true)`; aceita/coalesce
  a análise com HTTP 202 e devolve o campaignDTO. Import ativo e campanhas terminais
  recebem 422. O enqueue mantém seu protocolo de locks; o controller não o envolve em
  lock de campanha. O status `analysing` reflete o marcador/lease persistidos, sem declarar
  DNS concluído ou alterar o status da campanha.
- `POST resume` mantém a autorização própria e delega ao `EmailCampaign#resume!` real:
  coleta/CAS de geração, policy, provider e higiene continuam no fluxo do PR1. Nenhum
  `release_eligible` ou capability recebido do cliente é usado como autorização.
  A entrada HTTP também exige candidato pending, sem sent_at/receipt e sem supressão;
  enforce exige evidência ready com checked_at e validade futura. Campanha vazia, toda
  protegida ou composta apenas por linhas ambíguas recebe 422. Nenhum lock foi acrescentado
  ao redor do serviço de resume, preservando coleta fora dos locks e a ordem
  account → state → campaign do produtor.
- A apresentação mantém os dois caminhos do contrato: pausa manual sem bloqueio não
  exige amostra SES nem avaliação prévia; conta protegida exige evidência reputacional
  atual. Shadow/warning não criam veto de DNS. O gate SES continua autoritativo e direct
  inbox ignora somente esse gate. No GET enforce, a verificação usa o escopo unresolved
  real e a união de supressões em SQL, sem materializar batches: no máximo dois EXISTS
  de elegibilidade por campanha, além das demais consultas da apresentação.
- Erros de configuração têm `error=email_campaign.configuration_invalid` e código
  técnico limitado. Valores/nomes de configuração e exception messages não são enviados.
  Erros de resume também usam allowlist; nunca repassam current_metrics, policy,
  snapshots/override internos ou diagnósticos arbitrários.
- Rotas adicionadas: `GET reports/:id/import_issues`,
  `GET reports/:id/import_issues/export` e `POST campaigns/:id/recheck`.
  Relatórios mantêm `EmailCampaignReportPolicy` e lookup por conta antes de headers CSV.
- CSV preserva as primeiras oito colunas, BOM e neutralização de fórmulas, sem teto de
  10.000 e sem aplicar page. O maior ID filtrado é capturado antes dos headers. Cada lote
  de até 500 refaz os predicados temporais da query e lê supressões sem query cache.
  Trata-se de leitura progressiva: atualizações/deleções podem alterar lotes seguintes;
  não é um snapshot transacional e não mantém transação aberta durante transferência.
- `meta.delivery_evidence` está presente em index/detail dos relatórios: separa entregas
  confirmadas por provider de aceitação direta. O contador legado delivered permanece
  compatível, com sua limitação explícita.

## Conferência com os produtores reais

- `EmailCampaigns::Reputation::Metrics::PREVENTED_SQL` existe nesta base e é a constante
  consumida por Reports::BounceOutcomes. Inclui OnAccountSuppressionList,
  OnTenantSuppressionList, EmailValidationSuppressed e UnsubscribedRecipient.
- Global Suppressed continua permanente; NoEmail usa razão genérica permanente,
  sem afirmar caixa inexistente. Os quatro subtipos acima entram como prevenção nos KPIs.
- Evaluator publica `current_metrics.evaluation_generation` a partir da observação no CAS.
  O DTO exige coincidência com observation_generation e feedback atual para release.
  Não foi fabricado nem preenchido marcador no reader.
- Ratios internos continuam frações. ProtectionMetrics converte para percentual somente
  no DTO, incluindo `0.025 → 2.5`; ausência de denominador continua null.

## Specs e validação

Foi acrescentado um request spec HTTP que usa rotas, policies, serviços, consultas e
Jbuilders reais. Não substitui DTO/Evaluator por stubs. As expectativas de não chamar
coletores no GET e de enqueue/presenter usam spies com o comportamento real preservado.

Os cenários incluem sequência reevaluate → GET ainda pausado → resume, nova geração após
resume, invalidação após feedback, gerações divergentes, pausa manual em shadow/DNS off,
provider bloqueado/direct inbox, preflight enforce, campanhas vazias/protegidas/ambíguas,
import ativo, terminais, isolamento/403/404, erros seguros, filtros estritos, rotas de
issues/CSV, paginação versus exportação e metadata de aceitação direta. O spec de CSV
adiciona alteração/expiração de supressão entre lotes. O teste existente de 10.001 registros
foi preservado; nenhum teste antigo foi removido ou desativado.

Executado localmente, sem carregar Rails:

- Parser Ruby 3.4.4: **37 arquivos, todos Syntax OK**.
- RuboCop do bundle, limitado aos mesmos 37 arquivos: **37 files inspected, no offenses detected**.
- `GIT_OPTIONAL_LOCKS=0 git diff --check`: saída 0.
- SHA-256 versus snapshot inicial: **21 serviços protegidos intactos**, cobrindo reputation,
  direct_inbox, Guardrail, PreflightLease e PreflightDecision. O manifesto abaixo limita
  os arquivos alterados nesta rodada.

O executável rbenv não estava disponível nos PATHs testados. A primeira tentativa não
conseguiu selecionar Ruby/Bundler. Foi usado diretamente o Ruby 3.4.4 já instalado em
`/Users/rodrigosilva/.rbenv/versions/3.4.4/bin`, mantendo `bundle exec`. Uma tentativa de
RuboCop foi bloqueada ao criar cache fora da worktree; a execução final usou
`RUBOCOP_CACHE_ROOT=/private/tmp/436-pr2-rubocop`, `--no-server` e `--cache false`.
Não houve instalação nem alteração de configuração do projeto.

Comando final de lint executado (lista exata de arquivos no arquivo temporário):

```sh
env -i PATH=/Users/rodrigosilva/.rbenv/versions/3.4.4/bin:/usr/bin:/bin RUBOCOP_CACHE_ROOT=/private/tmp/436-pr2-rubocop /bin/zsh -c 'bundle exec rubocop --no-server --cache false --format simple $(cat /private/tmp/436-pr2-ruby-manifest.txt)'
```

O parser foi executado por subprocess, uma vez por entrada do mesmo manifesto, com:

```sh
env -i PATH=/usr/bin:/bin /Users/rodrigosilva/.rbenv/versions/3.4.4/bin/ruby -c CAMINHO_DO_ARQUIVO
```

**Rails/RSpec não foram executados.** Resultado de parser/lint não prova consultas SQL,
enqueue, transações, concorrência, resposta HTTP ou streaming por middleware/proxy.

## Manifesto desta rodada

19 arquivos de código/spec alterados ou criados em relação ao snapshot recebido,
mais este documento. Somar aos arquivos de PR2 já copiados; não substituir o core do PR1.

```text
app/controllers/api/v1/accounts/email_campaigns/base_controller.rb
app/controllers/api/v1/accounts/email_campaigns/campaigns_controller.rb
app/controllers/api/v1/accounts/email_campaigns/reports_controller.rb
app/policies/email_campaign_policy.rb
app/services/email_campaigns/presentation/campaign.rb
app/services/email_campaigns/presentation/configuration.rb
app/services/email_campaigns/presentation/errors.rb
app/services/email_campaigns/presentation/hygiene.rb
app/services/email_campaigns/presentation/import_summary.rb
app/services/email_campaigns/presentation/protection.rb
app/services/email_campaigns/recipient_query.rb
app/services/email_campaigns/reports/builder.rb
app/services/email_campaigns/reports/csv_export.rb
app/services/email_campaigns/reports/recipient_state.rb
app/views/api/v1/accounts/email_campaigns/campaigns/_campaign.json.jbuilder
config/routes.rb
spec/requests/api/v1/accounts/email_campaigns/reports_integration_436_spec.rb
spec/services/email_campaigns/presentation/protection_spec.rb
spec/services/email_campaigns/reports/export_and_issues_436_spec.rb
docs/audit/436-reports-integration.md
```

Os três novos serviços de apresentação são Campaign, Configuration e Errors. O request spec
também é novo. Os demais arquivos do manifesto já existiam no checkout ou no pacote copiado.
`.husky/_/` já estava untracked antes da rodada e não pertence a esta entrega.

## Comandos para o parent

Após integrar/rebasear sobre o PR1 atualizado, no harness Rails isolado em localhost
já preparado pelo parent, sem herdar configuração de produção:

```sh
eval "$(rbenv init -)"
bundle exec rails routes -g 'email_campaigns.*(recheck|reevaluate|resume|import_issues)'
bundle exec rspec spec/requests/api/v1/accounts/email_campaigns/reports_integration_436_spec.rb spec/controllers/email_campaigns/reports_436_spec.rb spec/services/email_campaigns/presentation/protection_spec.rb spec/services/email_campaigns/reports/recipient_query_436_spec.rb spec/services/email_campaigns/reports/metrics_436_spec.rb spec/services/email_campaigns/reports/presentation_436_spec.rb spec/services/email_campaigns/reports/export_and_issues_436_spec.rb
```

O parent deve usar a suíte de concorrência do PR1 para validar seu core após o rebase:

```sh
bundle exec rspec spec/services/email_campaigns/reputation/concurrency_spec.rb spec/services/email_campaigns/reputation/evaluator_spec.rb spec/services/email_campaigns/reputation/feedback_spec.rb spec/jobs/email_campaigns/recipient_preflight_job_spec.rb
```

A revisão deve confirmar o HTTP real do CSV e as contagens SQL dos specs, além das
garantias transacionais que pertencem ao PR1. Não há action/rota/DTO adiado dentro do
recorte PR2 autorizado; execução de integração e review continuam sendo trabalho do parent.
