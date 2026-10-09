# Auditoria local — #436 reputação, revisão corretiva

Data: 2026-09-16. Worktree autorizado: `/Users/rodrigosilva/dev/worktrees/chat2you/436-email-reputation`. Branch já existente `feat/436-email-reputation`. Nenhum commit, publicação ou integração externa nesta entrega.

O fechamento atual está na seção **Fechamento de classificação — 2026-09-16**. As seções anteriores preservam o histórico da revisão; seus resultados e pendências não substituem o fechamento.

## Evidência recebida e limite de execução

Lidos primeiro `tmp/email436/reputation-independent-review.md`, `tmp/email436/reputation-rspec-first.log`, documentação e implementação atuais. O parent já havia executado **48 exemplos com seis falhas** no ambiente isolado. Esse resultado pertence à versão anterior, não constitui aprovação desta revisão. O schema existente já havia sido gerado pelo parent e **não foi editado manualmente** aqui.

Autorizado: corrigir código deste worktree, escrever regressões e executar RuboCop/sintaxe/testes puros com Ruby 3.4.4. Proibido e não executado nesta revisão: Rails, rake, RSpec, qualquer DB/migration, AWS, SSH, produção, SMTP, secrets, leitura de `.env` real/dados de clientes, eval pago, GitHub, commits/push/merge/reset/clean, instalação de pacotes e acesso a outros worktrees. A skill de revisão de código e a de depuração sistemática orientaram inspeção e correções; a de verificação limita as alegações à evidência executada.

## Correções e decisões

1. **P1 monitor:** lookup existente e criação concorrente sob índice único, removendo validator que impedia `create_or_find_by!`. Estado inicial válido. Poll antigo não substitui `checked_at` mais novo; erro/unknown não apaga bloqueio. Falhas de persistência não são disfarçadas como erro de telemetria.
2. **P1 retomada:** decisão de retomada usa política efetivamente aplicada. Shadow/warning com 100 aceites/seis transitórios preservam pausa/flag e não enfileiram sem exceção. Enforce usa política nova, conservando bloqueios históricos até revisão explícita.
3. **P1 classificação (corrigida no fechamento abaixo):** `Permanent/Suppressed` conta como permanente/bounce nocivo; prevenção exclui apenas `OnAccountSuppressionList`, `OnTenantSuppressionList`, `EmailValidationSuppressed` e `UnsubscribedRecipient`. Uma consulta agrupada calcula a coorte; resumo SQL de três valores fixa a memória/resultado do fingerprint. Duplicatas não alteram; correções de classificação alteram o conjunto nocivo.
4. **P1 locks/concorrência:** geração reservada antes da coleta, coleta fora dos locks, CAS antes da publicação. Feedback invalida versão dentro da transação de gravação. Lease persistida agrupa enqueues; job antigo com lease substituída não coleta. Sweep recupera feedback durável/enqueue perdido. Retomada real da campanha também coleta fora do lock; publicação/transição seguem account → state → campaign. Operações JSONB preservam atributos não relacionados.
5. **P1 retenção:** FK de estado ON DELETE CASCADE; auditorias mantêm account_id/actor_id lógicos sem FKs restritivas, inclusive registros globais sem account. Log permanece append-only. Nenhuma alteração em account.rb.
6. **P2 incidentes:** estado aponta para incidente mais recente; snapshot só muda em nova pausa após liberação. Cada pausa tem evidência imutável na auditoria. Data original válida de flag legada é preservada; métricas iniciais desconhecidas ficam null, sem copiar motivo legado arbitrário para público.
7. **Política global:** monitor continua desligado por padrão; guardas preventivas 0.05/0.001, configuráveis apenas de modo mais conservador. PROBATION/SHUTDOWN/sending disabled bloqueiam. Saúde torna elegível para revisão, não libera latch. `ProviderRelease` exige SuperAdmin persistido, motivo e nova consulta saudável com ambas as taxas frescas. Emergência de configuração não pode ser superada. Transições auditadas sem payload bruto.
8. **Payload:** allowlist pública sem ator, motivo interno, orçamento, fingerprint ou histórico. Histórico separado exige SuperAdmin e fica restrito ao tenant. GET também considera bloqueio global na capacidade de retomada. Handler global de auth preservado: Pundit negado retorna 401; isolamento de campanha retorna 404. Specs incluem controles positivos de autenticação.
9. **Seis falhas do parent:** além do bug do monitor, specs concorrentes usam fixtures não transacionais e conferem PIDs PostgreSQL distintos; SES Client é carregado no spec de timeout; recipient de feedback é materializado antes da transação revertida; expectativas 401 preservam contrato real.

Migrações renomeadas, classes inalteradas: **20260916121000, 20260916121100, 20260916121200**. Naquele handoff, a reconstrução do DB sintético/schema estava pendente; o log posterior do parent está registrado no fechamento. Manifesto e APIs em [436-reputation-manifest.md](436-reputation-manifest.md); contrato detalhado em [reputation.md](../email-campaigns/reputation.md).

## Revisão independente desta correção

Subagente `independent_review`, exclusivamente leitura/estática neste worktree, sem runtime/banco:

- Encontrou janela pós-commit da versão: corrigida com invalidação transacional; acrescentado teste de duas conexões que suspende o callback pós-commit antes do enqueue.
- Encontrou `GET resume_allowed` ignorando provider: corrigido e coberto por request spec.
- Encontrou lock externo ainda existente em `EmailCampaign#resume!`: removido antes da coleta; transição movida para bloco de publicação, com teste do caminho real.
- Encontrou dependência residual de autoload de `Ses::Error`: spec carrega Client explicitamente.
- Releu as correções e informou **nenhum achado novo nos caminhos revisados**. Isso é revisão estática, não aprovação de runtime nem autorização de merge.

## Verificação offline da revisão anterior

Ruby **3.4.4** selecionado com `RBENV_VERSION=3.4.4`; rbenv inicializado antes de Bundler. Cache RuboCop limitado a `tmp/cache/reputation-rubocop`, com `--no-server --cache false`. Arquivos Ruby/Jbuilder alterados ou novos, excluindo schema gerado: **56**.

| Checagem final | Evidência | Exit / tempo |
| --- | --- | --- |
| `ruby -c` em cada arquivo do manifesto | 56 arquivos, sintaxe válida | 0 / 2,263s |
| `ruby spec/services/email_campaigns/reputation/policy_test.rb` | 5 testes, 25 assertions, zero falhas | 0 / 0,394s |
| `ruby spec/services/email_campaigns/reputation/provider_config_test.rb` | 2 testes, 18 assertions, zero falhas | 0 / 0,254s |
| Mutação somente em memória removendo guarda legada | falha específica em `test_legacy_protection_cannot_be_released_by_the_new_policy`; 5 testes, uma falha esperada | 1 / 0,247s |
| `bundle exec rubocop --no-server --cache false --format simple <manifesto>` | 56 files inspected, no offenses detected | 0 / 2,679s |
| `git diff --check` | sem problemas | 0 / 0,042s |

Baseline puro antes das alterações: quatro testes/20 assertions, zero falhas. A guarda nova foi testada presente e ausente por mutação em memória; nenhum arquivo de produção foi temporariamente revertido. Primeira tentativa da mutação tinha erro de sintaxe no comando e foi corrigida; não é tratada como teste de regressão. Passagens intermediárias de lint apontaram complexidade/formatação, corrigidas sem desabilitar cops globalmente.

Logs: `tmp/email436/revision-{syntax,policy,provider-config,policy-mutant,rubocop,diff-check}.log`; resumo `revision-validation.json`; lista reproduzível `revision-ruby-manifest.txt`.

SHA256 do conjunto Ruby/Jbuilder final validado: `bad22597a173500d6aa14e3cd78e4d91a286820b0fdbd003e460de491d0e1597`. Cálculo: caminhos relativos ordenados, concatenar `path + NUL + bytes + NUL`. Documentação, config e schema não integram esse hash.

## Handoff da revisão anterior (atualizado pelo fechamento abaixo)

1. Reconstruir DB/schema com migrações renomeadas; não tentar reutilizar a versão antiga dos triggers.
2. Executar os specs Rails escritos: regressões de política/prevenção, incidentes, coalescing/correções, deleção real via DeleteObjectJob, autorização/redação e provider latch/release. Nenhum foi executado por este agente.
3. Executar testes concorrentes não transacionais com conexões reais: 50 mil destinatários e outcomes nocivos, resultado de fingerprint com uma única linha; JSON/admissão durante coleta; retomada real; avaliações fora de ordem; janela commit/enqueue; polls/criação concorrentes e reentrada/advisory lock. Os testes retêm auditorias sintéticas append-only após limpar seus demais registros.
4. Integrar higiene/UI/report sem perder invalidação dentro da transação e enqueue após commit; SQL que contorne callbacks exige ambos explicitamente. Confirmar ordem de locks do fluxo final de higiene. Preservar alterações pendentes do parent.
5. Revisar novamente o conjunto integrado e registrar evidência de runtime. Atualizar Issue/PR/Project pelo parent; merge, deploy e plano de rollback dependem de aprovação explícita.

**Status daquela revisão: correções verificadas offline; runtime ainda pendente naquele momento. Ver evidência posterior e pendências atuais abaixo.**


## Fechamento de classificação — 2026-09-16

Evidência relida: `tmp/email436/reputation-v2-rspec-second.log` registra **84 exemplos, zero falhas**, em 6,86s (carga 2,62s), executados pelo parent após a migração revisada. Substitui a pendência de runtime daquela versão; não valida as alterações desta rodada. Nenhum Rails/RSpec/DB foi executado aqui.

Correção de fonte primária recebida do parent, sem rede neste agente: [lista global SES](https://docs.aws.amazon.com/ses/latest/dg/sending-email-global-suppression-list.html) confirma que `Permanent/Suppressed` conta na taxa de bounce e quota; [notificações SES](https://docs.aws.amazon.com/ses/latest/dg/notification-contents.html) distingue listas de conta/tenant e `UnsubscribedRecipient`; [eventos Firehose](https://docs.aws.amazon.com/ses/latest/dg/event-publishing-retrieving-firehose-contents.html) inclui `EmailValidationSuppressed`.

Deltas desta rodada:

- `Metrics::PREVENTED_SQL`: sai `Suppressed`; permanece `OnAccountSuppressionList`; entram `OnTenantSuppressionList`, `EmailValidationSuppressed` e `UnsubscribedRecipient`. O mesmo filtro governa contagens e fingerprint. Nenhuma classificação de mailbox-not-found foi introduzida.
- `metrics_spec.rb`: caso global explícito com cinco em 100, duplicata estável e pausa; feedback global tardio fora da coorte permanece nocivo no fingerprint; quatro casos distintos de prevenção; correção `General → NoEmail → Suppressed` continua permanente e muda fingerprint, seguida por `OnAccountSuppressionList` retirando o outcome nocivo.
- `feedback_spec.rb`: preservado o caso de correção para `Suppressed` e acrescentado caso separado de `OnAccountSuppressionList`; ambos invalidam a observação e conservam coalescing, com contagens/fingerprint conferidos.
- `policy_test.rb`: limites independentes da regra de pausa (4/80 não pausa; 5/101 não pausa; 5/100 pausa), defaults de 5% e mínimo cinco e prevenção fora do numerador. Nenhum limiar ou código de política foi alterado.
- Documentação e manifesto distinguem métrica local publicada de amostra representativa AWS e preservação de histórico após liberação. Baseline de usuário, higiene, backfill, UI, migrações e schema intactos nesta rodada.

Conferência estática: `Policy` mantém os defaults 0.05/mínimo 5; `ProviderConfig` mantém guardas 0.05/0.001, só aceita valores mais conservadores e monitor off por padrão; `ProviderMonitor` não libera latch e não converte ausência/erro em saúde. Nenhuma alteração nesses três arquivos. Monitor parado/ausente permanece sem evidência de saúde operacional. Nenhuma consulta AWS, SMTP ou produção.


### Validação executada neste fechamento

Ruby 3.4.4; inicialização `eval "$(rbenv init -)"` antes de Bundler, `RBENV_VERSION=3.4.4`, `RUBOCOP_CACHE_ROOT=tmp/cache/reputation-rubocop`. Sem instalação ou leitura de ambiente/credenciais. Resultados:

| Comando | Resultado |
| --- | --- |
| `ruby spec/services/email_campaigns/reputation/policy_test.rb` | 6 testes, 32 assertions, 0 falhas/erros/skips; exit 0 |
| `ruby spec/services/email_campaigns/reputation/provider_config_test.rb` | 2 testes, 18 assertions, 0 falhas/erros/skips; exit 0 |
| `ruby -c` em cada um dos quatro arquivos Ruby do delta | 4 × Syntax OK; exit 0 |
| RuboCop abaixo | 4 arquivos, nenhuma infração; exit 0 |

Comando exato do lint:

```sh
bundle exec rubocop --no-server --cache false --format simple app/services/email_campaigns/reputation/metrics.rb spec/services/email_campaigns/reputation/metrics_spec.rb spec/services/email_campaigns/reputation/feedback_spec.rb spec/services/email_campaigns/reputation/policy_test.rb
```

Logs locais: `tmp/email436/final-closure-policy.log`, `final-closure-provider-config.log`, `final-closure-syntax.log`, `final-closure-rubocop.log` (todos no mesmo diretório). Os testes puros validam política/configuração; sintaxe e lint **não executam o SQL nem validam as novas regressões Rails**.

### Comandos de specs para o parent — não executados aqui

Usar o ambiente sintético isolado e wrapper já adotados pelo parent, com a migração revisada. Inicializar rbenv e selecionar Ruby 3.4.4 antes de Bundler. Primeiro, regressões diretamente alteradas:

```sh
bundle exec rspec spec/services/email_campaigns/reputation/metrics_spec.rb spec/services/email_campaigns/reputation/feedback_spec.rb
```

Depois, o conjunto integrado (inclui monitor, retenção, liberação e concorrência):

```sh
bundle exec rspec spec/services/email_campaigns/reputation spec/requests/api/v1/accounts/email_campaigns/reputation_spec.rb
```

Os testes puros `*_test.rb` devem continuar em processos Ruby separados, nunca requeridos no processo Rails. Testes de concorrência mantêm conexões reais e fixtures não transacionais conforme o manifesto. O total final de exemplos deve ser registrado após execução; não inferido do log anterior.

**Status atual: delta local concluído e checagens offline aprovadas; execução Rails/DB das novas regressões e revisão integrada pertencem ao parent. Não é declaração de PR pronto, autorização de merge/deploy ou evidência de monitor saudável.** Nenhum Git write, Rails/rake/RSpec/DB, rede, AWS/SSH/SMTP, instalação ou inspeção de credenciais/arquivos de ambiente nesta rodada.
