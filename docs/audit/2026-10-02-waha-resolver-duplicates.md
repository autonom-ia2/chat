# WAHA — bloquear resolvers duplicados

Data: 2026-10-02. Issue: https://github.com/autonom-ia2/chat/issues/852.
PR de origem: https://github.com/autonom-ia2/chat/pull/842.
Worktree: `/Users/rodrigosilva/dev/chat2you-waha-2026-9-2`.
Branch: `feat/waha-2026-9-2-chatwoot-sync`.
Base: `5737a3c611bd9de1ba7b0dfcc6d860186166ffe6`.

## Causa e correção

A revisão de preparação #846/#848 demonstrou que o planner escolhia o primeiro resolver da lista,
preservava o segundo e podia anunciar `already compliant`. O aceite operacional exige exatamente um.
Rodrigo autorizou continuar a preparação até candidato pronto para avaliar merge/deploy/backfill.
Handoff integralmente relido. Este commit trata somente o P2 de duplicidade.

`find_phone_numbers_app` seleciona todos os Apps pelo nome e levanta `SkipError` quando existem dois ou mais,
antes de construir o snapshot/plano. A condição conta também Apps desabilitados. Zero ou um mantém o
comportamento existente. Mensagem humanizada:

> Mais de um App brazilian-phone-numbers na sessão. Nenhuma alteração foi aplicada; revise a duplicidade.

Dry-run registra SKIP sem plano de atualização. APPLY interrompe antes de PUT/start/recuperação/escrita local
ou processamento da segunda caixa. Não escolhe ID automaticamente, não remove ou mescla Apps e não faz retry.
Documentação operacional atualizada; nenhum Guia, UI, schema, dependência ou workflow alterado.
R1–R5/N1–N3 e as correções #850/#851 preservados. Nenhum override Enterprise do planner/updater encontrado.

## Testes e revisão

Oito exemplos: dry-run/APPLY × caixa compatível/não compatível × duplicata habilitada/desabilitada.
Todos incluem calls e uma segunda caixa; verificam Apps/configuração e atributos locais intactos,
`skipped=1`, `updated=0`, `unchanged=0`, `would_update=0` e nenhuma escrita/start.
APPLY exige `total=1`, `halted=true` e nenhuma leitura do App da segunda caixa. Dry-run usa INBOX_ID.
Os exemplos anteriores continuam cobrindo zero/um resolver, idempotência e preservação de Apps não relacionados.

Ruby 3.4.4 via rbenv, `RAILS_ENV=test POSTGRES_HOST=localhost POSTGRES_DATABASE=chatwoot_test`.
Clientes simulados e HTTP externo bloqueado pelo harness; somente banco local de teste.

- Antes: `bundle exec rspec spec/services/waha/existing_inbox_updater_spec.rb --example 'skips duplicates'`:
  **8 exemplos, 8 falhas**. Sessões ambíguas eram planejadas, atualizadas ou classificadas como compatíveis;
  APPLY avançava para a segunda caixa. Saída completa relida após a primeira apresentação truncada.
- Focados: `bundle exec rspec spec/services/waha/existing_inbox_updater_spec.rb spec/lib/tasks/rake/task_waha_backfill_spec.rb`:
  **63 exemplos, zero falhas**.
- Regressão na versão final:
  `bundle exec rspec spec/services/waha spec/controllers/api/v1/accounts/waha_inboxes_controller_spec.rb spec/models/channel/api_spec.rb spec/listeners/reporting_event_listener_spec.rb spec/listeners/webhook_listener_spec.rb spec/services/reporting_events spec/models/conversation_spec.rb spec/lib/tasks/rake/task_waha_backfill_spec.rb`:
  **318 exemplos, zero falhas, três pendentes preexistentes** (WebhookListener:127 e Conversation:774/802).
- RuboCop: `bundle exec rubocop app/services/waha/existing_inbox_migration_planner.rb spec/services/waha/existing_inbox_updater_spec.rb`:
  **2 arquivos, zero infrações**. Primeiro lint pediu modifier-if; ajuste manual seguido de regressão/lint novos.
- `git diff --check`: aprovado. Guia não tocado; `pnpm guia:check` não aplicável neste item.
- Revisão independente somente leitura: aprovada, sem novo achado no delta; Ruby 3.4.4 `Syntax OK` nos dois arquivos.

Saídas e diff lidos antes do commit. Hooks normais e patch idêntico ao revisado devem preceder o push;
resultado Git será registrado na Issue/PR após conclusão, sem `--no-verify`.

## Próxima etapa e limites

Preparar candidato na main atual, incorporar as três correções e repetir a bateria completa da árvore final.
GET/PUT continua não atômico; exigir janela sem escritores durante piloto e recuperação.
Persistem limites documentados das métricas de abertura/eventos legados e mutabilidade de provider/trava.
Payload inválido do resolver não reproduzido não recebe validação especulativa neste item.
Sem merge, deploy, backfill real, alteração de produção, sessão WAHA, QR, logout, pareamento ou auth.
