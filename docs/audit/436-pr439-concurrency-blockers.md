# PR439 — bloqueadores de concorrência P1-03 / P1-04

Data: 2026-09-17. Branch observada: `feat/436-02-email-reputation`; worktree `436-delivery-integration`. Escopo: duas correções de reputação, regressões e runbook. Nenhum Git write, rede, AWS, SSH, produção, instalação ou execução Rails/RSpec/banco. Nenhuma alteração em registry de higiene, UI, relatórios, backfill, schema ou migrações. `.husky/_/` já estava não rastreado e foi preservado.

## Evidência lida

`AGENTS.md`, implementação OSS, referências Enterprise (sem overlay correspondente) e evidências locais em `/Users/rodrigosilva/dev/worktrees/chat2you/436-operations-integration/tmp/email436/adversarial-20260917/`:

- `concurrency-probes-final.json` e `.log`: três caracterizações passam ao reproduzir defeitos, não são testes de aceite. P1-03 registra provider bloqueado antes do claim e dispatch ocorrido; P1-04 registra 10% permanentes, três avaliações superseded, três claims autorizados.
- `review-final.md`, `concurrency_probes_spec.rb` e `pr-review-comments.json`. O último aponta para o [comentário de PR439](https://github.com/autonom-ia2/chat/pull/439#issuecomment-5711749214); nenhuma consulta remota foi feita. O corpo local da revisão é a evidência disponível.

## Decisões e implementação

**P1-03:** ordem de aquisição composta: Account → EmailReputationState (quando existe) → EmailProviderState (SES com monitor habilitado) → campanha → destinatário. Claim final e checagem de dispatch do contrato antigo solicitam o lock global antes de avaliar ProviderGate e executar pending→sent. Lookup/`create_or_find_by!` compartilha o índice único, inclusive quando monitor e claim disputam a primeira linha. ProviderMonitor só adquire essa linha depois de SES/CloudWatch. ProviderRelease continua provider-only após coleta; retomada SES/override adquirem provider depois do estado do tenant e antes de campanha. Nenhum desses caminhos adquire tenant depois de provider.

Prepare, estacionamento, recibos e mutações comuns continuam sem lock global; final admission o solicita explicitamente. DirectInbox não constrói ProviderConfig nem adquire provider. O bloqueio manual via ambiente continua sendo avaliado pelo gate com monitor ligado ou desligado. Leitura e renderização prévias não autorizam envio: se monitor confirma antes de claim obter o lock, claim é negado; se claim já segura a linha, monitor aguarda seu commit e esse envio é legitimamente em voo. I/O externo não ocorre sob essas transações.

**P1-04:** uma observação superseded pode apenas criar BLOCK quando o estado persistido ainda está desbloqueado, a política aplicada é enforce e suas próprias métricas atendem a pausa. Grava blocked, level=paused, snapshot/auditoria imutáveis e flag de compatibilidade; limpa eventual override no início do incidente. Não modifica current_metrics, policy publicada, evaluated_at ou evaluated_feedback_version. O snapshot marca superseded e preserva geração/versão observadas. Se já bloqueado, não reescreve o incidente. Observação segura superseded não libera nem concede override; shadow/warning não publicam esse bloqueio conservador novo.

Após commit, o caminho superseded solicita nova coleta. A lease ativa agrupa esse pedido; finish mantém o sucessor quando há feedback não avaliado **ou geração reservada não publicada**. Não reconhece a versão mais nova por ter criado BLOCK. Token antigo não remove a lease sucessora. Publicação fresca permite concluir a lease sem novo enqueue. Invalidação transacional existente de feedback foi preservada.

## Regressões escritas, ainda não executadas

- `provider_admission_concurrency_spec.rb`: duas conexões com PIDs distintos e `pg_blocking_pids`, sem sleeps de ordenação. Monitor primeiro, com linha presente e ausente; claim primeiro força monitor a esperar. Verifica pending/claim, código de pausa, linha única e negativa do destinatário seguinte. SES/CloudWatch e dispatch simulado do engine registram profundidade transacional zero.
- `concurrency_spec.rb`: 100 aceites/10 permanentes reais; coleta suspensa e feedback transitório confirmado na outra conexão em três ciclos. Cada ciclo verifica BLOCK antes do próximo claim, métricas publicadas intactas, feedback pendente, snapshot original, flag e sucessor da lease. Uma coleta fresca final reconhece feedback e encerra a lease sem apagar o incidente.
- `evaluator_spec.rb`: observação segura superseded não libera bloqueio nem concede override; shadow/warning não publicam evidência superseded como atual.
- `admission_spec.rb`: DirectInbox sem lock/config SES; bloqueio manual com monitor habilitado/desabilitado.
- `feedback_spec.rb`: supersession só por geração exige sucessor mesmo com feedback já avaliado; conclusão antiga não interfere na nova lease.

Auditorias sintéticas append-only permanecem por desenho; limpeza dos testes concorrentes é limitada às fixtures próprias. Novas asserções de runtime não constituem resultados executados.

## Validação offline

Ruby 3.4.4, rbenv inicializado antes de Bundler; `MT_NO_PLUGINS=1` para os testes puros. Logs e lista dos 13 arquivos Ruby: `tmp/email436/pr439-blockers-20260917/`.

- `ruby -c` nos arquivos de `ruby-files.txt`: 13 sintaxes válidas.
- `xargs bundle exec rubocop --no-server --cache false --format simple < tmp/email436/pr439-blockers-20260917/ruby-files.txt`, com `RUBOCOP_CACHE_ROOT=tmp/cache/reputation-rubocop`: 13 arquivos, zero infrações. Ajustes intermediários de formatação foram corrigidos com `-a`; duas exceções locais de contagem de expectativas documentam as provas compostas de concorrência.
- `ruby spec/services/email_campaigns/reputation/policy_test.rb`: 6 testes, 32 asserções, zero falhas/erros.
- `ruby spec/services/email_campaigns/reputation/provider_config_test.rb`: 2 testes, 18 asserções, zero falhas/erros.
- `ruby spec/pure/email_campaigns/complaint_reputation_test.rb`: 5 testes, 30 asserções, zero falhas/erros.
- `git diff --check`: sem problemas (somente leitura).

Testes puros validam política/configuração/classificação; não exercitam os locks nem o SQL novo. A evidência de correção concorrente depende dos specs de banco pelo parent.

## Handoff

Parent: rebase após PR438 e executar no banco sintético isolado as regressões acima, depois a suíte de reputação e os fluxos integrados de entrega/retomada/override/provider release. Comando focal, não executado aqui:

```sh
bundle exec rspec spec/services/email_campaigns/reputation/provider_admission_concurrency_spec.rb spec/services/email_campaigns/reputation/concurrency_spec.rb spec/services/email_campaigns/reputation/evaluator_spec.rb spec/services/email_campaigns/reputation/feedback_spec.rb spec/services/email_campaigns/reputation/admission_spec.rb spec/services/email_campaigns/reputation/provider_concurrency_spec.rb spec/services/email_campaigns/reputation/provider_release_spec.rb
```

Revisar compatibilidade de locks com a correção de PR438 e cada versão intermediária antes de qualquer merge/deploy. Issue/PR/Project e rebase ficam com o parent. Sem alegação de merge-ready. Rollback operacional continua sujeito ao runbook: preservar tabelas/auditorias/flags e impedir admissão durante troca para binário sem as novas garantias; nenhuma ação operacional foi executada.

## Parent runtime gate — 17/09/2026

O parent executou os sete specs de concorrência/avaliação/admissão/provider em PostgreSQL sintético loopback após `db:schema:load`: **54 exemplos, 0 falhas, 0 pending**. Isso inclui as duas barreiras novas: (a) bloqueio do provider confirmado antes do claim impede a autorização; se o claim já detém o lock do provider, o monitor espera e apenas aquele claim já admitido prossegue; (b) observação superseded que já prova risco em `enforce` instala proteção monotônica sem publicar métricas antigas nem liberar, e a fila mantém uma avaliação fresca posterior.

Nenhum acesso/alteração de produção, SES/CloudWatch real, merge ou deploy ocorreu. Evidência local: `tmp/email436/pr439-fix-rspec-full.json` e `pr439-fix-rspec-full.log`.
