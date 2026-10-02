# WAHA 2026.9.2 — N1: concorrência antes da escrita

Data: 2026-10-02. Issue: https://github.com/autonom-ia2/chat/issues/841.
Worktree: `/Users/rodrigosilva/dev/chat2you-waha-2026-9-2`.
Branch: `feat/waha-2026-9-2-chatwoot-sync`.
Base desta alteração: `255d211c54fa18d0308f500f6d254b47072d692b`.

## Escopo e decisão

Rodrigo autorizou somente N1 após avaliação. Handoff integralmente lido.
R1–R5 preservados; N2 e N3 permanecem pendentes. Sem UI, Guia ou refatoração ampla.
Nenhum acesso operacional a produção, merge, deploy, backfill real, logout ou pareamento.

O PUT substitui a lista completa de Apps. O snapshot antigo podia apagar um App concorrente.
O executor agora relê sessão e Apps antes de marcar uma tentativa de escrita.
Compara status/configuração da sessão e todos os campos dos Apps, ordenados por ID.
Diferença gera SKIP humanizado, zero PUT, zero recuperação, zero gravação local e parada do lote.
Falha de leitura gera FAILED e parada sem escrita. Sem merge silencioso ou retry.
O caminho de recuperação após tentativa real de escrita permanece o mesmo do R1.
A checagem também cobre planos que só precisem persistir mudanças locais.

## Limite operacional

GET + comparação + PUT não são atômicos. A implementação detecta alterações até a leitura final;
não garante proteção contra alteração entre a leitura e o PUT ou durante a recuperação do R1.
No futuro piloto autorizado, impedir escritores paralelos de Apps/configuração da sessão.
Não há liberação para produção: N2, N3, revisão e aceites E2E continuam necessários.

## Testes novos

Nove exemplos adicionados:
- calls incluído após planejamento de snapshot somente Chatwoot;
- configuração concorrente do Chatwoot;
- configuração concorrente do Brazilian Phone Numbers;
- habilitação concorrente de App não relacionado;
- remoção concorrente de App;
- configuração concorrente da sessão;
- sessão deixa de estar WORKING;
- falha da leitura final;
- ordem diferente da lista sem mudança de conteúdo migra normalmente.

Os sete conflitos validam preservação do estado remoto concorrente, ausência de PUT/start,
ausência de alteração local, retorno SKIP (nunca UPDATED) e não processamento da segunda caixa.
O comportamento normal/preservação de Apps e recuperação R1 continuam nos exemplos existentes.

## Validação local

Shell inicializado com `eval "$(rbenv init -)"` e `RBENV_VERSION=3.4.4`.
RSpec com `RAILS_ENV=test POSTGRES_HOST=localhost POSTGRES_DATABASE=chatwoot_test`.
Ruby: `/Users/rodrigosilva/.rbenv/versions/3.4.4/bin/ruby`.
Clientes WAHA simulados; HTTP externo bloqueado pelo WebMock.

- Antes da correção: specs focados com oito falhas novas, incluindo UPDATED indevido e avanço do lote.
- `bundle exec rspec spec/services/waha/existing_inbox_updater_spec.rb`: 29 exemplos, zero falhas.
- `bundle exec rspec spec/services/waha spec/controllers/api/v1/accounts/waha_inboxes_controller_spec.rb spec/models/channel/api_spec.rb spec/listeners/reporting_event_listener_spec.rb`: 80 exemplos, zero falhas.
- Regressão ampliada: comando anterior acrescido de `spec/listeners/webhook_listener_spec.rb spec/services/reporting_events`: 153 exemplos, zero falhas, um pendente preexistente.
- O pendente é a quarentena em `spec/listeners/webhook_listener_spec.rb:127`, não alterada nem contabilizada como aprovação.
- O handoff registra 88 exemplos, mas não lista o comando exato. A bateria atual cobre todos os specs WAHA, Channel API, relatórios e webhooks; não se afirma que foi recuperado o comando histórico exato.
- `bundle exec rubocop app/services/waha/existing_inbox_migration_executor.rb app/services/waha/existing_inbox_updater.rb spec/services/waha/existing_inbox_updater_spec.rb`: três arquivos, zero infrações.
- `git diff --check`: aprovado.
- `pnpm guia:check`: não aplicável; nenhum arquivo do Guia/rota/menu foi alterado.

Saídas completas lidas antes do commit. RuboCop corrigido manualmente e revalidado.
Revisão do diff confirmou preflight anterior à flag de escrita, parada do lote e recuperação R1 preservada.
Sem override Enterprise correspondente ao migrador.

## Governança

Issue #841 criada para N1; branch existente mantida. Item adicionado ao Project jarvis #2.
PR deve permanecer draft enquanto N2/N3 estiverem pendentes; sem aprovação de merge/deploy.
A primeira tentativa de commit foi bloqueada pelo hook: `npx` ausente no PATH.
Correção de ambiente: incluir `/Users/rodrigosilva/.nvm/versions/node/v20.20.2/bin` no PATH,
sem alterar hooks. Commit isolado de N1 e push com hooks normais, sem `--no-verify`.
