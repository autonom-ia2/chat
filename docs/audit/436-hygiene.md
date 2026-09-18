# #436 / PR438 — bloqueios adversariais (2026-09-17)

Escopo local: branch `feat/436-01-email-hygiene`. Este delta substitui os contratos anteriores sobre locks, expiração temporária e replay de evidência corrigida. Os resultados de banco registrados abaixo, de rodadas anteriores, **não validam este delta**. Não há declaração de pronto para merge.

## Correções e evidência de código

1. **Blue/green PR438 web + PR439 worker:** `UnsubscribeController#suppress!` e `Sns::EventProcessor#process` agora adquirem Account antes de recipient; a inserção de estado/mirror acontece depois, na mesma transação. Antes, recipient podia ser retido enquanto a FK do novo estado aguardava Account, fechando o ciclo com worker Account → campaign → recipient. O novo writer aguarda Account sem possuir recipient. Counters são atualizados depois do bloco de locks; verificação da assinatura SNS acontece antes do EventProcessor. Não há rede/DNS sob locks, classes de reputação PR439 ou mudança na resposta genérica 200 do descadastro. Busca por `SuppressionRegistry`, `EmailSuppressionState.create/insert` e `EmailSuppression.create/find_or_create/insert` em `app` e `enterprise` encontrou somente esses dois callers e os inserts internos do registry; nenhum outro caminho recipient → Account ou override Enterprise foi encontrado.
2. **Quarentena independente da ordem:** o registry seleciona até o threshold de eventos `record/temporary_failure` mais recentes na janela inclusiva `[agora - 7 dias, agora]`. Com três eventos, a expiração é o maior valor entre a expiração existente e o `occurred_at` mais recente +72h. Para T, T-1d, T-6d recebidos em T, ordem cronológica e inversa bloqueiam até T+72h e expiram exatamente nesse instante. Eventos fora da janela/futuros não contam; replay não infla contagem; estado forte não perde prioridade.
3. **Mesma chave com evidência corrigida:** evidência forte de prioridade estritamente maior que a original e que as correções já aceitas gera `action=correction`, chave determinística `correction:<ID original>:<motivo>` e `metadata.corrects_event_id`. A chave fica abaixo de 200 caracteres mesmo se a chave original tiver 200. O evento original conserva todos os atributos; a correção usa seu occurred_at histórico e os novos source/metadata. Append, agregados, promoção do estado e mirror permanente são atômicos. Replay igual/mais fraco é duplicata, inclusive após uma correção; uma evidência ainda mais forte pode ser anexada uma vez. unknown/temporary/provider → hard_bounce promove; hard_bounce → provider não. Unsubscribe, complaint, manual e hard_bounce não são rebaixados, inclusive quando vieram de outra chave; motivo legado desconhecido permanece autoritativo. `occurrences` conta a nova entrada de auditoria; correções não são novos eventos temporários. PR442 pode reapresentar sua chave durável após rebase; nenhum backfill foi executado aqui.

## Regressões adicionadas

- `spec/services/email_campaigns/hygiene_concurrency_spec.rb`: quatro casos PostgreSQL sem fixtures transacionais, usando **duas conexões reais**. A conexão que modela PR439 segura Account/campaign; `pg_blocking_pids` confirma que o writer PR438 está aguardando essa conexão antes de o worker tentar recipient. Exercita HTTP real dentro do Rack (sem socket de rede) para opt-out assinado e EventProcessor para opt-out SNS, hard bounce e complaint. Verifica persistência no estado, legado, eventos e status; 200 isolado não basta. Helpers de coordenação são compartilhados pelos quatro cenários. **Não executados nesta rodada.**
- `spec/services/email_campaigns/suppression_registry_spec.rb`: ordem cronológica/inversa T/T-1d/T-6d, replay, bloqueio até o segundo anterior e expiração exata em T+72h, max da expiração existente; promoção de unknown/temporary/provider com chave de 200 caracteres; preservação integral do original; idempotência, cadeia de correções, prioridade independente e rollback em falha do mirror. **Não executados nesta rodada.**
- `spec/pure/email_campaigns/suppression_registry_test.rb`: quatro testes offline, 68 asserções, seis permutações da ordem, exclusão de eventos antigos/futuros, max da expiração, correções/idempotência e histórico original. Adaptador em memória apenas para decisões; não prova SQL/FK/transações/locks.
- `spec/pure/email_campaigns/hygiene_test.rb`: duas chamadas ao método privado de decisão ajustadas à assinatura sem occurred_at; as asserções de proteção foram preservadas.

## Validação local desta rodada

Ruby 3.4.4 via `eval "$(rbenv init -)"`; dependências já instaladas. Comandos sem boot Rails, instalações ou conexões externas:

| Comando | Resultado |
| --- | --- |
| `bundle exec ruby -rwebmock -e 'WebMock.enable!; WebMock.disable_net_connect!; load ARGV.fetch(0)' <cada um dos cinco spec/pure/email_campaigns/*_test.rb>` | **28 testes / 50.717 asserções**, zero falhas/erros/skips |
| `RUBOCOP_CACHE_ROOT=/tmp/email436-adversarial-rubocop bundle exec rubocop --no-server --cache false <sete arquivos Ruby deste delta>` | **7 arquivos, zero infrações** |
| `ruby -c <cada um dos sete arquivos Ruby deste delta>` | **7 × Syntax OK** |
| `git diff --check` (somente leitura) | exit 0 |

Os sete arquivos Ruby são os três arquivos de produção citados e os quatro arquivos de teste citados acima. Alterações adicionais apenas em `docs/email-campaigns/hygiene.md` e neste audit. UI, reputação, provedores, reports, migrations/schema, envs e o untracked preexistente `.husky/_/` foram preservados.

Contraprova offline: `git show HEAD:app/services/email_campaigns/suppression_registry.rb` foi lido para uma árvore temporária `/tmp/email436-adversarial-before-frurvcw0`, com o mesmo teste novo e HygieneConfig local. O comando puro acima contra essa árvore terminou com **4 testes / 8 asserções / 4 falhas esperadas**, sem erros/skips (seed 23773): expiração T-3d em vez de T+72h e promoção rejeitada como duplicate. A primeira execução revelou que o adaptador de teste herdava `Struct#count`; ele foi corrigido para contar eventos antes desta contraprova válida. A árvore temporária não substituiu código do checkout nem escreveu objetos Git. Não houve contraprova PostgreSQL executada.

## Handoff ao pai

Executar em PostgreSQL isolado os specs de registry, concorrência, mixed-version, unsubscribe e SNS; manter fixtures transacionais desabilitadas nos casos de threads e pool com ao menos duas conexões. Os quatro testes de overlap precisam falhar no código anterior (erro/deadlock ou ausência de persistência) e passar no corrigido. Conferir os 18 exemplos Rails adicionados junto às regressões preexistentes antes de qualquer conclusão de integração. O novo teste puro ainda está untracked e deve entrar no commit do pai.

Sem execução Rails/RSpec/DB, AWS, SSH, rede, produção, instalação, escrita Git ou ações remotas de Issue/PR/Project. Commit, atualização de Project, review e aprovação ficam com o pai; merge/deploy continuam pendentes de aprovação explícita. Rollback de comportamento segue shadow/DNS=false, preservando estado/auditoria; retirar estas correções reintroduz o risco de lock durante a sobreposição e os defeitos de replay/quarentena. Nenhuma alteração de schema exige rollback nesta rodada.

---

# Histórico — fechamento de higiene (2026-09-16)

**Registro histórico; não declara PR pronto.** Esta seção substituiu os contratos anteriores de classificação/supressão de provedor; o delta de 2026-09-17 acima é o mais recente. Foram lidos AGENTS.md, este manifesto e tmp/email436/pr0-closure-review.md. Os 85 exemplos Rails/zero falhas registrados pelo pai são anteriores a este delta; não validam as novas regressões.

## Delta exato

- `bounce_classifier.rb`: NoEmail passou de permanent/mailbox_not_found para permanent/permanent_failure. O subtipo informa que não foi possível extrair o endereço do bounce; nenhum subtipo isolado comprova caixa inexistente. Suppressed passou de unknown/provider_suppression para **permanent/provider_suppression**: é supressão GLOBAL SES e conta na taxa AWS. OnAccountSuppressionList, OnTenantSuppressionList e EmailValidationSuppressed retornam unknown/provider_suppression; UnsubscribedRecipient retorna unknown/unsubscribe. Unknown é a classificação de entrega, não ausência de proteção local.
- `suppression_registry.rb` e `email_suppression.rb`: provider_suppression agora é motivo forte, ativo e sem expiração, aceito por block!/record!, espelhado na tabela permanente legada na mesma transação e exposto pelo lookup de motivos. Prioridade: unsubscribe > complaint > manual > hard_bounce > provider_suppression > temporary_failure; motivos legados desconhecidos continuam autoritativos. O bloqueio é por tenant/endereço, não afirma caixa inválida, não remove restrição SES e não pode ser liberado por uma referência arbitrária. Nenhuma API de provedor foi alterada.
- `sns/event_processor.rb`: o motivo provider_suppression prevalece sobre a classificação permanent ao escolher a proteção; Suppressed não vira hard_bounce. UnsubscribedRecipient usa unsubscribe, registra o evento de opt-out na transição e atualiza apenas status/timestamps sob lock, inclusive se um nome legado for inválido. Mantém payload Bounce original, deduplicação, prioridade de opt-out e proteção contra regressão por delivery/complaint/bounce.
- `spec/services/email_campaigns/sns/event_processor_spec.rb`: matriz de todos os subtipos nomeados, estado/mirror duráveis, metadata e replay; opt-out SES com nome legado inválido, promoção de provider para unsubscribe, opt-out já existente e prioridade após MailboxFull e cada subtipo de proteção.
- `spec/services/email_campaigns/suppression_registry_spec.rb`: provider permanente não expira após um ano, não é rebaixado por falhas temporárias, bloqueia importação/claim futuros, é visível ao leitor legado, isola tenants, preserva opt-out legado, rejeita release e reverte estado/auditoria se falhar o mirror. O teste anterior que esperava provider_suppression sem bloqueio foi substituído explicitamente pelo novo requisito; as asserções de ausência de hard-bounce inventado, payload e classificação foram mantidas/ampliadas.
- `spec/pure/email_campaigns/hygiene_test.rb`: matriz offline dos subtipos, promoção da quarentena para bloqueio permanente e decisão de espelhar sem rebaixar opt-out. O harness substitui estado/persistência; **não comprova transações, SQL ou durabilidade real**.
- Spec de retenção movido, sem cópia, de `spec/services/email_campaigns/hygiene_account_retention_spec.rb` para `spec/models/email_suppression_state_retention_spec.rb`, usando described_class. Manifesto atualizado; as duas infrações originais foram corrigidas sem exceção de path ou enfraquecimento de cop.
- `docs/email-campaigns/hygiene.md`: tabela completa e contratos de integração atualizados. Nenhuma alteração de migração/schema nesta rodada. Não há backfill dos registros provider_suppression observacionais antigos; replay já consumido não os promove automaticamente.

## Validação executada — apenas offline

- Red de classificação antes da correção: `ruby spec/pure/email_campaigns/hygiene_test.rb`, seed 12010, **11 testes / 103 asserções / 2 falhas / 0 erros / 0 skips**, exit 1. Falhas reproduziram NoEmail como mailbox_not_found e Suppressed como unknown. Resultado no stdout desta execução; não se alega red Rails.
- Final: `/Users/rodrigosilva/.rbenv/versions/3.4.4/bin/ruby spec/pure/email_campaigns/hygiene_test.rb`, seed 49621: **13 testes / 120 asserções / zero falhas, erros ou skips**, exit 0. Log: `tmp/email436/pr0-final-closure-pure.log`.
- `/Users/rodrigosilva/.rbenv/versions/3.4.4/bin/ruby spec/pure/email_campaigns/preflight_batch_test.rb`, seed 28465: **4 testes / 50.506 asserções / zero falhas, erros ou skips**, exit 0, 0,065315s. Resultado no stdout desta rodada; não houve alteração desse arquivo.
- `ruby -c` em todos os **47 arquivos Ruby do manifesto, exceto db/schema.rb**: zero falhas, exit 0. Log: `tmp/email436/pr0-final-closure-syntax.log`.
- Após `eval "$(rbenv init -)"`, `bundle exec rubocop --cache false --format simple <47 arquivos Ruby do manifesto, exceto db/schema.rb>`: **47 files inspected, no offenses detected**, exit 0. Log: `tmp/email436/pr0-final-closure-rubocop.log`. Primeira execução identificou somente quatro usos de Time.at sem UTC nos novos testes puros; foram corrigidos para Time.at(...).utc. Nenhuma configuração de lint alterada.
- Comandos expandidos e exit codes: `tmp/email436/pr0-final-closure-check-commands.json` e `tmp/email436/pr0-final-closure-lint-command.json`.
- **Rails/RSpec/DB não executados.** Nenhum comando Git, instalação, rede externa, AWS, SSH, SMTP, arquivo de env real ou credencial. Não foram editados db/schema.rb, .env.example, app/models/email_campaign.rb, delivery engines/claim/senders, UI, reports ou reputação. Arquivos Ruby compartilhados do manifesto foram somente lidos pelo lint/syntax.

## Integração e validação pendentes do pai

1. Rodar os specs Rails revisados e o spec de retenção no novo caminho, além da regressão PR0 existente, no ambiente sintético autorizado. Validar atomicidade do mirror/rollback, replay, importação/claim, escopo tenant e opt-out com nome inválido; os testes foram escritos, mas não executados aqui.
2. Alinhar reports/reputation SQL: **Suppressed conta no numerador AWS apesar de reason_code=provider_suppression**; não excluir todos os provider_suppression nem classificá-los todos como provider-prevented. OnAccountSuppressionList/OnTenantSuppressionList são nonattempt sem bounce reputation; EmailValidationSuppressed é prevenção; UnsubscribedRecipient é opt-out/nonattempt sem impacto de reputação. O Bounce bruto e bounced_count legado continuam sendo história do provedor, não o numerador de reputação. O evento unsubscribe é adicional e deduplicado.
3. Alinhar a apresentação de provider_suppression como bloqueio por provedor, sem rótulo de caixa inexistente. Deliberar qualquer recuperação de observações históricas separadamente; este delta não faz backfill nem promove replay já consumido.
4. Revisão integrada, CI e fluxo Issue → Branch → PR → Project update → Review → Approval → Merge → Deploy/Rollback permanecem com o pai. Nenhum ready/approval/merge/deploy está implícito neste fechamento.

Base factual dos subtipos fornecida pelo pai após verificação das fontes oficiais AWS nesta sessão: [notification contents](https://docs.aws.amazon.com/ses/latest/dg/notification-contents.html), [global suppression](https://docs.aws.amazon.com/ses/latest/dg/sending-email-global-suppression-list.html) e [Firehose event contents](https://docs.aws.amazon.com/ses/latest/dg/event-publishing-retrieving-firehose-contents.html). Este worker não navegou nem realizou validação externa.

---

# #436 / PR0 — correção após revisão adversarial (2026-09-16)

**Implementado localmente; não aprovado para publicação.** Esta seção substitui as decisões técnicas do registro anterior, preservado abaixo. Leitura inicial: este manifesto e `tmp/email436/pr0-independent-review.md`. O log do pai `tmp/email436/hygiene-rspec-full.log` confirma 63 exemplos/zero falhas **antes destas correções**; não comprova o código atual. A falha de baseline SES segue com o pai.

## Correções e contratos

1. **Versões mistas:** estado/auditoria passaram para `email_suppression_states` e `email_suppression_events.email_suppression_state_id`. Nenhuma coluna nova ou observação inativa/temporária na tabela legada. Decisões fortes espelham a tabela permanente na mesma transação; presença legada vence estado novo, expiry e rollback/reupgrade. Nenhuma exclusão de dados, backfill ou trigger. `release!` permite somente estado manual sem qualquer positivo legado; uma autorização textual não libera consentimento/spam nem bloqueios fortes espelhados.
2. **Carga em shadow:** achados locais ficam sem expiry; DNS=false seleciona somente unchecked. DNS=true também seleciona dns_disabled e evidência externa expirada. Lease durável de cinco minutos, token consumível por job, cursor/limite superior persistidos, retomada de lease expirada e escrita/resumo protegidos contra holder obsoleto. Uma agregação por passagem concluída. Limites por job: 100 linhas, dez domínios e dez segundos monotônicos, mais no máximo um domínio já iniciado (três consultas de até dois segundos). Sem locks/transações durante DNS. Índice parcial para pending/unchecked evita varrer o histórico verificado na manutenção padrão.
3. **Deadline DNS:** Timeout envolve o resolver completo, inclusive connect/write/TCP framing após UDP truncado. Timeout → unknown/dns_timeout; Resolv assegura cleanup. Teste offline executa fetch_resource e TCP#recv_reply reais com socket pair, tanto comprimento de frame incompleto quanto corpo incompleto. Nenhum pacote externo. Resolver/deadline injetáveis.
4. **Evidência da importação:** email válido rejeitado por outro campo usa `invalid_recipient`, sem mensagem crua de validator. Nome limitado a 255 caracteres. Cabeçalhos name,email, lotes de 500, row_number e reconciliação mantidos.
5. **Lint:** simplificadas responsabilidades de resolver/validator, registry, gates de envio, scheduler e manutenção. Correções locais de estilo e doubles verificáveis. Exceções estreitas e comentadas apenas para SQL atômico/validado, contexto de specs e duas matrizes/setup de teste offline; nenhum disable geral de arquivo nem mudança na configuração RuboCop.

APIs para integração do pai:

- `EmailSuppression.suppressed?(account, email)` e `.suppressed_set_for(account)`: união legado permanente + estado novo bloqueante.
- `EmailSuppression.blocking_reasons_for(account, emails)`: hash por endereço normalizado, duas consultas em lote; legado vence. Motivo legado desconhecido → `legacy_suppression`.
- `SuppressionRegistry::Result#suppression` agora é **EmailSuppressionState**. Associação dos eventos usa `email_suppression_state`.
- `EmailCampaigns::RecipientPreflightJob.enqueue(campaign.id, recheck: false)`: API pós-commit. `recheck: true` invalida evidência pending somente ao adquirir uma passagem. Retorna true se agendou; false se já está em execução/sem trabalho/inelegível. Chamadas simultâneas coalescem; recheck durante passagem ativa não a reinicia. `(campaign_id, token, cursor)` é continuação interna.
- Novos códigos para backend/UI do pai: `invalid_recipient`, `legacy_suppression`. Fixtures de reports com quarantine em EmailSuppression devem migrar para EmailSuppressionState; arquivos de reports não foram tocados.

Contrato completo em `docs/email-campaigns/hygiene.md`.

## Delta das migrações não implantadas — pai deve reconstruir

- `20260916120000`: remove da proposta todas as alterações em email_suppressions. Cria email_suppression_states com tenant/email únicos e check de normalização; eventos referenciam o estado, com índices de replay/janela atualizados. Acrescenta quatro campos em email_campaigns: preflight_lease_token, preflight_lease_expires_at, preflight_cursor=0, preflight_ceiling=0. Demais campos de preflight/import issues mantidos.
- `20260916120100`: mantém índice de validade e acrescenta `idx_recipients_preflight_unchecked` em `(email_campaign_id,id)`, parcial `status = 0 AND preflight_status = 'unchecked'`, concorrente.
- **Nenhuma migração/banco executado aqui. db/schema.rb não foi editado por esta rodada.** O dump anterior do pai está desatualizado em relação às migrações revisadas. Não aplicar rollback destrutivo; pai reconstrói somente o banco sintético autorizado.

## Evidência executada nesta rodada

Ruby explícito `/Users/rodrigosilva/.rbenv/versions/3.4.4/bin/ruby`; RuboCop com esse diretório no PATH. Nenhum boot da aplicação, Rails/rake/rspec, DB, AWS, SSH, DNS externo, SMTP, paid eval, GitHub ou comando Git; nenhum arquivo .env real ou alteração fora do manifesto/novos arquivos necessários.

- `ruby spec/pure/email_campaigns/hygiene_test.rb`: **10 testes, 105 asserções, zero falhas/erros/skips**, exit 0; seed 31238, 0,245334s. Stdout: `tmp/email436/pr0-fixes-pure-final.log`.
- `ruby spec/pure/email_campaigns/preflight_batch_test.rb`: **4 testes, 50.506 asserções, zero falhas/erros/skips**, exit 0; seed 42601, 0,063941s. Executa o loop de produção com persistência substituída: 50k destinatários lógicos/500 lotes, IDs visitados uma vez, limites de tempo/domínio e avanço de cursor. Stdout: `tmp/email436/pr0-fixes-batch-final.log`. Isso não valida queries ou transações PostgreSQL.
- `ruby -c <cada Ruby do manifesto, exceto db/schema.rb>`: **46 arquivos, zero falhas**, exit 0. Log: `tmp/email436/pr0-fixes-syntax-final.log`.
- `bundle exec rubocop --cache false --format simple <os mesmos 46 arquivos>`: **46 files inspected, no offenses detected**, exit 0. Log: `tmp/email436/pr0-fixes-rubocop-final.log`. Não houve exclusão adicional de arquivo nesta chamada; valem os grandfather/excludes preexistentes do repositório. Nenhuma configuração de cops foi enfraquecida.
- Comandos expandidos/exit codes/durações em `tmp/email436/pr0-fixes-check-commands.json` e `pr0-fixes-lint-command.json`; SHA-256 dos 46 arquivos verificados em `pr0-fixes-validated-files.json`. Não foram calculados hashes de secrets/dados de cliente.
- Red reproduzido antes da correção: achado local tinha expiry; TCP após UDP truncado ultrapassou watchdog externo de três segundos. Log `pr0-fixes-pure-red.log`. O primeiro ensaio do mock precisou definir hash; depois reproduziu o timeout real. No primeiro ensaio do novo harness de lotes, autoload de plugin Minitest instalado tentou carregar o reporter Rails e abortou por colisão do shim antes dos testes; ambos os testes puros agora desabilitam plugins com MT_NO_PLUGINS=1. Nenhuma aplicação/banco foi inicializado. Harness corrigido usa somente stdlib/Minitest.
- Specs Rails foram escritos/ajustados sem execução, respeitando a restrição explícita. Logo **não há evidência red/green Rails**, nem alegação de TDD completo para essas alterações. A cobertura de lote foi acrescentada após a implementação do lease e é regressão retrospectiva, não red/green comprovado.

## Validação restante do pai

1. Reconstruir o DB sintético localhost:15436 e dump do schema após ambas as migrações; confirmar defaults, FKs, check/index únicos e índice parcial/concurrent. Redis sintético 16436 conforme autorização do pai.
2. Rodar todos os specs Rails do manifesto revisado, incluindo novos `hygiene_mixed_version_spec`, `recipient_preflight_lease_spec`, concorrência real sem transações de fixture, importação/name inválido, audit/rollback da transação, unsubscribe/SES/DirectInbox e commit/outbox. O spec de lease observa SQL e exige uma única agregação final; concorrência disputa aquisição e consumo de token via conexões reais.
3. Verificar versões novas→operações legadas reais→novas para unsubscribe/complaint/hard_bounce, lookup/import/send, rollback/reupgrade e expiry com positivo legado. Os specs usam find_or_create_by! real, sem mock para promover estado.
4. Ajustar reports/API/fixtures aos novos contratos por seus respectivos owners. Comparar baseline SES separadamente; não atribuir a falha existente a esta rodada sem reprodução.
5. Reexecutar revisão adversarial independente antes de publicar PR0. Issue/branch/PR/project/review/approval/merge/deploy/rollback permanecem com o pai. **Sem commit nesta rodada e sem declaração de ready.**

---

## Registro histórico anterior à correção (decisões superadas acima)

# #436 / PR 0 — higiene e quarentena

Implementação local autorizada sobre `63bf0eb542`, em 2026-09-16. Sem commit, GitHub, Rails, banco, migração executada, instalação, DNS real, SMTP, AWS, credenciais ou produção por este worker. A inspeção de `app/` e `enterprise/` não encontrou overlay Enterprise para estes serviços.

Decisões: registro único com lock + chave de replay; bloqueios legados/permanentes retidos; 3 eventos transitórios distintos em 7 dias → 72 horas; shadow/DNS=false por padrão; importação atômica de 500 linhas preservada; preflight pós-commit de 100 destinatários com cursor e recuperação pela manutenção; nenhum auto-resume/reenvio; timeout/5xx não retornam a pending. Índice em migração concorrente separada. Migração de dados aditiva recusa down para proteger auditoria. Contratos/limitações/rollback em `docs/email-campaigns/hygiene.md`.

Revisão local também corrigiu preservação de opt-out durante resposta DirectInbox, cancelamento após claim e finalização concorrente enquanto existe claim sem recibo. Specs incluem WebMock sem credential chain, threads/conexões PostgreSQL para replay e claim, isolamento de conta, expiry, modos, importação/rejeições/export, commit/outbox e idempotência dos jobs.

## Evidência executada por este worker

- Ruby 3.4.4 via `eval "$(rbenv init -)"`; somente `ruby -c` e suíte pura, sem Bundler/Rails.
- `ruby spec/pure/email_campaigns/hygiene_test.rb`: **7 testes, 96 asserções, zero falhas/erros/skips**. Resolver injetado e stdlib exercitada sem enviar pacotes. O primeiro ensaio anterior à implementação deu LoadError por arquivos ainda ausentes; não é evidência de red/green funcional dos specs Rails.
- `ruby -c <arquivo>` para cada Ruby do manifesto abaixo: **42 arquivos, zero falhas**. Checagem de linhas >150: nenhuma, excluindo o schema.
- `git diff --check -- <arquivos do manifesto>`: **exit 0**, sem erros. Execução final conjunta de sintaxe, limite de linhas, suíte pura e diff: **exit 0**, 2,16 segundos; seed da suíte pura `34099`.
- **Não executei specs Rails/RSpec, migrações nem testes de banco.** Concorrência/transações ainda dependem da execução isolada do operador pai. `db/schema.rb` foi sincronizado manualmente; comparar com dump após migrações no ambiente isolado.

Durante o trabalho surgiram mudanças concorrentes fora deste PR (reports, frontend/locales e trechos `autonomia_agent_*` do schema). Foram preservadas, não implementadas/revertidas por este worker. Também preservei ajustes concorrentes dos CSVs dos specs para os cabeçalhos existentes `name,email`. O manifesto delimita as alterações deste PR; `db/schema.rb` é compartilhado. Uma checagem ampla de comprimento de linhas encontrou linhas longas externas e duas de fixtures deste PR; as fixtures foram ajustadas e a checagem final foi limitada ao manifesto.

## Validação pendente do operador pai

Aplicar as duas migrações apenas no banco isolado autorizado; conferir schema/defaults/índices; executar os specs Rails listados abaixo junto dos testes SES existentes; verificar as specs sem fixtures transacionais e threads com pool suficiente; revisar alteração de tratamento de timeouts e estados pausados/claims ambíguos. Nenhuma alegação de aprovação Rails/DB neste relatório. Issue/branch/PR/project/review/approval e eventual rollout ficam com o operador pai; rollback comportamental é shadow/DNS=false, retendo schema, bloqueios e auditoria.

## Manifesto deste PR

<!-- BEGIN PR0 FILES -->
.env.example
app/controllers/email_campaigns/unsubscribe_controller.rb
app/jobs/email_campaigns/recipient_import_job.rb
app/jobs/email_campaigns/recipient_import_maintenance_job.rb
app/jobs/email_campaigns/recipient_preflight_job.rb
app/models/email_campaign.rb
app/models/email_campaign_import.rb
app/models/email_campaign_import_issue.rb
app/models/email_campaign_recipient.rb
app/models/email_suppression.rb
app/models/email_suppression_event.rb
app/services/email_campaigns/address_preflight.rb
app/services/email_campaigns/bounce_classifier.rb
app/services/email_campaigns/delivery_claim.rb
app/services/email_campaigns/delivery_engine.rb
app/services/email_campaigns/direct_inbox/delivery_engine.rb
app/services/email_campaigns/direct_inbox/recipient_sender.rb
app/services/email_campaigns/dns/mail_route_resolver.rb
app/services/email_campaigns/domain_validator.rb
app/services/email_campaigns/hygiene_config.rb
app/services/email_campaigns/preflight_decision.rb
app/services/email_campaigns/recipient_importer.rb
app/services/email_campaigns/scheduler.rb
app/services/email_campaigns/sns/event_processor.rb
app/services/email_campaigns/suppression_registry.rb
db/migrate/20260916120000_add_email_campaign_hygiene.rb
db/migrate/20260916120100_add_email_recipient_preflight_index.rb
db/schema.rb
docs/email-campaigns/hygiene.md
docs/audit/436-hygiene.md
spec/controllers/email_campaigns/unsubscribe_controller_spec.rb
spec/factories/email_campaigns.rb
spec/jobs/email_campaigns/recipient_import_job_spec.rb
spec/jobs/email_campaigns/recipient_preflight_commit_spec.rb
spec/jobs/email_campaigns/recipient_preflight_job_spec.rb
spec/models/email_campaign_import_issue_spec.rb
spec/models/email_suppression_event_spec.rb
spec/pure/email_campaigns/hygiene_test.rb
spec/pure/email_campaigns/suppression_registry_test.rb
spec/services/email_campaigns/delivery_hygiene_spec.rb
spec/services/email_campaigns/hygiene_concurrency_spec.rb
spec/services/email_campaigns/preflight_decision_spec.rb
spec/services/email_campaigns/recipient_importer_spec.rb
spec/services/email_campaigns/scheduler_hygiene_spec.rb
spec/services/email_campaigns/sns/event_processor_spec.rb
spec/services/email_campaigns/suppression_registry_spec.rb
app/models/email_suppression_state.rb
app/services/email_campaigns/preflight_lease.rb
spec/services/email_campaigns/hygiene_mixed_version_spec.rb
spec/jobs/email_campaigns/recipient_preflight_lease_spec.rb
spec/pure/email_campaigns/preflight_batch_test.rb
spec/models/email_suppression_state_retention_spec.rb
<!-- END PR0 FILES -->

## Parent regression review corrections

- Removed the redundant new name validator. Direct isolated execution confirmed the existing ApplicationRecord global 255-character string policy already rejects long names on import. The actual regression was the new opt-out transaction rolling back the permanent block when an unrelated legacy name failed validation. Opt-out now performs a narrow status/timestamp update under the recipient lock, and a real long-name/replay regression verifies permanent protection survives. Import still respects the existing global limit and reports invalid_recipient rather than invalid_email.
- Transient replay specs now inspect the separate observation state and assert the legacy permanent-positive table remains empty.
- Account-owned observation states cascade on authorized account deletion. Immutable audit rows retain logical numeric references without restrictive account/state foreign keys; no address is retained in these audit columns. Explicit state deletion remains restricted through the model. A real account-deletion regression test covers the no-legacy-suppression case.
- Revised migration has not been deployed; parent will rebuild a fresh disposable test database and verify schema/tests.

Parent evidence correction: independent review inferred that long names were model-valid from the absence of a local validator; the runtime diagnosis showed inherited `ApplicationRecord#validates_column_content_length` applies. The fix preserves that existing import policy rather than changing a global business rule.

## Parent executed validation — corrected PR0

Fresh main schema loaded into disposable `chat2you_email436_hygiene_v3_test` on loopback PostgreSQL 17/port 15436; both PR0 migrations applied. Redis loopback 16436; inherited/cloud credentials excluded. No production connections.

- Rails regression suite: **85 examples, 0 failures** (`tmp/email436/hygiene-v3-rspec-final.log`). Includes mixed-version legacy opt-out writers, opt-out on invalid legacy names, replay, account deletion retention, import, dispatch admission, lease/recovery and isolated concurrency.
- Offline hygiene/DNS: **10 tests, 105 assertions, 0 failures**; bounded 50k preflight: **4 tests, 50,506 assertions, 0 failures**.
- Existing SES services: **10 examples, 0 failures**, using the expected synthetic HTTPS frontend URL; no network sends.
- Focused PR0 invocation verifies its exact migrated schema before disabling automatic loading of a separately authored pending PR4 migration; it does not disable tests/assertions. Final integrated CI uses normal migration checks.
- Remaining gate before ready-for-merge: final independent closure review and remote CI after publishing this scoped PR.

## Gate do integrador — PR0 isolado, 2026-09-16

Árvore limpa baseada em `cd30dba0c922f0716866ec6f46d1d0f79222b864`, preservando a alteração de blue/green de #437. Apenas os 51 arquivos do manifesto foram copiados. O gate normal de schema do Rails ficou habilitado. PostgreSQL/Redis exclusivos de QA em loopback; HTTP externo bloqueado pelo WebMock, metadados/credenciais AWS desativados.

- RSpec do manifesto + `spec/services/email_campaigns/ses`: **110 exemplos, 0 falhas**. Inclui os 15 casos adicionais de classificação/supressão e as regressões SES preexistentes.
- Higiene pura: **13 testes / 120 asserções**, sem falhas/erros/ignorados. Lotes: **4 testes / 50.506 asserções**, sem falhas/erros/ignorados.
- RuboCop focado: arquivos Ruby alterados, excluindo schema gerado, sem infrações.
- Logs locais: `tmp/email436/pr0-clean-rspec.log`, `pr0-final-rubocop.log`. Suítes reproduzíveis pelos caminhos do manifesto; não dependem desses logs para passar.
- `db/schema.rb` veio do banco isolado com migrações 120000/120100; diferenças adicionais são formatação canônica do dump PostgreSQL, sem DDL fora de e-mail.
- Nenhum teste enviou e-mail real. Não houve leitura/escrita de produção, merge nem deploy. CI remoto ainda será conferido no PR.

## Gate adversarial do parent — 17/09/2026

Após as correções de lock misto blue/green, promoção de evidência corrigida, quarentena fora de ordem e exclusão local de `invalid/review` em `enforce`, o parent reconstruiu o schema apenas no PostgreSQL sintético local e executou a seleção cumulativa do feature mais o novo spec de exclusão: **298 exemplos RSpec, 0 falhas, 1 pending preexistente de Account**. O pending não foi criado nem alterado por #436.

As seis suítes puras em `spec/pure/email_campaigns` passaram com **43 testes / 50.792 asserções, 0 falhas/erros/skips**. RuboCop dos **11 arquivos Ruby alterados/adicionados** passou sem infrações. O preflight atualiza os contadores da campanha quando converte um destinatário determinístico em exclusão local, sem criar `EmailSuppression`/quarentena de tenant. Evidências locais: `tmp/email436/pr438-cumulative.json`, `pr438-fix-pure.log` e `pr438-fix-rubocop.log`.

Nenhum banco/serviço de produção, SES/SMTP/AWS, merge, deploy ou alteração de flag foi utilizado. CI remoto no SHA publicado permanece obrigatório.
