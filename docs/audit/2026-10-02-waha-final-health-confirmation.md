# WAHA — saúde na confirmação final da migração

Data: 2026-10-02.
Issue: https://github.com/autonom-ia2/chat/issues/851.
PR de origem: https://github.com/autonom-ia2/chat/pull/842.
Worktree: `/Users/rodrigosilva/dev/chat2you-waha-2026-9-2`.
Branch: `feat/waha-2026-9-2-chatwoot-sync`.
Base: `5f565dc3be07c9c47c2379cccbdacb489a6986ba`.

## Escopo e causa

Rodrigo autorizou a correção do P1 de saúde final após o fechamento da consistência do snapshot (#850).
Handoff integralmente relido antes das alterações. Somente este item foi tratado; R1–R5/N1–N3,
a consistência do planejamento e os testes em quarentena foram preservados.

O executor esperava WORKING no polling, mas na leitura posterior de confirmação comparava somente
configuração e Apps. Se a sessão parasse entre essas leituras, o executor retornava UPDATED e gravava
a referência do resolver e a trava da conversa, apesar da sessão STOPPED. O lote avançava para outra caixa.

## Correção

`verify_remote_state!` exige agora `status == WORKING` na mesma leitura final que confirma configuração
e Apps. STOPPED nessa leitura levanta o `VerificationError` existente antes da transação local.
Como o PUT já foi tentado, o R1 restaura o snapshot original e confirma a saúde da recuperação.
O resultado é RECOVERED quando a recuperação é confirmada ou CRITICAL quando falha; ambos contam
como falha e interrompem o lote. Nenhuma alteração local da migração é gravada.

Não há nova estratégia de polling, retry, merge de Apps ou recuperação. A recuperação já exigia WORKING
na sua confirmação final e permanece intacta. Nenhum override Enterprise do executor/updater encontrado.

## Testes novos e validação

Dois exemplos no updater usam serviços reais com cliente simulado e banco local de teste:

- Polling WORKING seguido de STOPPED na confirmação final, com recuperação saudável.
- A mesma falha inicial, seguida de STOPPED também na confirmação final da recuperação.

Ambos incluem uma segunda caixa e um App calls. Verificam restauração de configuração e Apps originais,
preservação de calls, exatamente dois PUTs (tentativa e recuperação), `updated=0`, `failed=1`, `total=1`,
`halted=true`, atributos locais intactos e nenhuma leitura do App da segunda caixa. O cenário de
recuperação saudável exige RECOVERED; o outro exige CRITICAL e `recovery_failed=1`. Nenhum registra UPDATED.

Ruby 3.4.4 via rbenv, `RAILS_ENV=test POSTGRES_HOST=localhost POSTGRES_DATABASE=chatwoot_test`.
HTTP externo bloqueado pelo harness; nenhuma conexão ou operação de produção.

- Antes: `bundle exec rspec spec/services/waha/existing_inbox_updater_spec.rb:586`:
  **2 exemplos, 2 falhas**. Ambos registravam UPDATED, gravavam atributos locais, não recuperavam e
  avançavam para a segunda caixa (`updated=1`, `total=2`).
- Focados: `bundle exec rspec spec/services/waha/existing_inbox_updater_spec.rb spec/lib/tasks/rake/task_waha_backfill_spec.rb`:
  **55 exemplos, zero falhas**.
- Regressão do handoff:
  `bundle exec rspec spec/services/waha spec/controllers/api/v1/accounts/waha_inboxes_controller_spec.rb spec/models/channel/api_spec.rb spec/listeners/reporting_event_listener_spec.rb spec/listeners/webhook_listener_spec.rb spec/services/reporting_events spec/models/conversation_spec.rb spec/lib/tasks/rake/task_waha_backfill_spec.rb`:
  **310 exemplos, zero falhas, três pendentes preexistentes**.
- Quarentenas intactas: WebhookListener:127 e Conversation:774/802. Não contam como aceites aprovados.
- `bundle exec rubocop app/services/waha/existing_inbox_migration_executor.rb spec/services/waha/existing_inbox_updater_spec.rb`:
  **2 arquivos, zero infrações**, sem autocorreção ou relaxamento de regras.
- `git diff --check`: aprovado. Guia não tocado; `pnpm guia:check` não aplicável.

Revisão independente somente leitura aprovou o fechamento deste P1 sem novos achados no delta.
Confirmou a ordem verificação/persistência, o fail-stop e a recuperação R1; sintaxe Ruby 3.4.4 e diff check
também aprovados pelo revisor. As saídas completas das suítes foram lidas antes do commit.
Hooks normais e comparação do patch commitado com o revisado devem preceder o push; resultados Git
serão registrados na Issue/PR após conclusão, sem `--no-verify`.

## Limites e pendências

A confirmação final é uma observação de saúde, não uma garantia de disponibilidade futura.
A sessão pode parar depois dessa leitura. GET/PUT e verificação/transação local não são atômicos.
Manter a janela sem escritores paralelos durante piloto e recuperação; esta correção não autoriza
restaurar snapshots antigos diante de mudanças concorrentes em produção.

O P2 de duplicidade do resolver permanece pendente e não foi implementado. Também permanecem
revalidação do lote na base final, atualização do candidato #848 (ainda na árvore anterior), escolha
da instalação/caixa do piloto, evidência de runtime/rollback e aceites reais da WAHA.
Sem UI, Guia, refatoração ampla, merge, deploy, backfill real, produção, logout, QR, pareamento ou auth.
