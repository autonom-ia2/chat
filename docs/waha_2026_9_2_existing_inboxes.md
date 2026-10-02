# WAHA 2026.9.2 — backfill de caixas existentes

## Objetivo

Atualizar caixas WhatsApp API já provisionadas sem recriar Inbox, sessão WAHA ou pareamento.

O backfill deixa cada sessão com:

- Filtro de Status do WhatsApp (Stories) na sessão:
  - `config.ignore.status = true` por padrão
  - `WAHA_IGNORE_STATUS=false` mantém o opt-in explícito da instalação para importar Status
  - demais filtros e campos da configuração da sessão preservados
- App Chatwoot no WAHA:
  - `conversations.outgoing = message`
  - `conversations.syncMessageStatus = true`
  - `conversations.sort = created_newest`
  - `conversations.status = null` (qualquer status, incluindo resolvida)
- App `brazilian-phone-numbers` habilitado:
  - `strict = false`
  - `lookup = true`
  - cache em memória por 24h
  - cache persistente por 31 dias
- Inbox no Chat2You:
  - `lock_to_single_conversation = true`
  - referência `phone_numbers_app_id` para cleanup futuro

Apps não relacionados da sessão (`calls`, `mcp` etc.) e suas configurações são preservados.

## Ambientes WAHA

- Chat2You: WAHA `wa-hub`, acessível pelo host operacional `ssh hubsegs`.
- Autonom.ia: WAHA `wa-autonomia`, acessível pelo host operacional `ssh autonomia`.

O rake deve ser executado no ambiente da aplicação que possui o banco da respectiva instalação, não dentro do container WAHA.

## Inventário somente leitura — 2026-10-02

- Hub/Chat2You: 33 Apps Chatwoot encontrados; 0 já compatíveis; 0 Apps `brazilian-phone-numbers`.
- Autonom.ia: 6 Apps Chatwoot encontrados; 0 já compatíveis; 0 Apps `brazilian-phone-numbers`.
- Naquele inventário, os dois WAHA tinham `WAHA_APPS_ON=calls,chatwoot,mcp`.
- Nenhuma configuração foi alterada durante o inventário.

Esse é o registro histórico do inventário. O [handoff posterior](audit/2026-10-02-waha-2026-9-2-post-review-handoff.md) registra a habilitação e persistência de `brazilian-phone-numbers` no Portainer. O código da branch continua sem deploy; este documento não substitui a validação do estado real antes do piloto autorizado.

## Pré-requisito de deploy

Antes do deploy do Chat2You/Autonom.ia que contém este código, habilitar o App no respectivo WAHA:

```text
WAHA_APPS_ON=calls,chatwoot,mcp,brazilian-phone-numbers
```

Fazer um ambiente por vez e confirmar que o WAHA volta saudável antes de seguir. Sem esse pré-requisito, criação de novas caixas e o backfill devem falhar, em vez de criar uma integração parcialmente configurada.

## Uso

Dry-run é o padrão:

```bash
bundle exec rails waha:backfill_existing_inboxes
```

Escopo opcional por conta:

```bash
ACCOUNT_ID=123 bundle exec rails waha:backfill_existing_inboxes
```

Piloto em uma única caixa (IDs ilustrativos; substituir pelos IDs revisados):

```bash
INBOX_ID=456 bundle exec rails waha:backfill_existing_inboxes
ACCOUNT_ID=123 INBOX_ID=456 bundle exec rails waha:backfill_existing_inboxes
```

`INBOX_ID` é opcional e deve ser um inteiro positivo. Valor vazio, inválido, zero ou negativo interrompe o comando antes de criar o cliente WAHA. Quando os dois filtros são informados, a caixa precisa pertencer à conta indicada. Caixa inexistente, de outra conta ou sem provider WAHA resulta em `total=0`, sem leitura remota ou escrita; isso não comprova uma migração. O relatório inicial mostra conta e caixa selecionadas, ou `ALL` para filtro ausente.

Aplicação do piloto, somente após autorização explícita para produção e revisão do dry-run com `total=1`:

```bash
APPLY=true ACCOUNT_ID=123 INBOX_ID=456 bundle exec rails waha:backfill_existing_inboxes
```

Usar os mesmos filtros na revalidação em dry-run. O filtro limita o processamento à caixa selecionada; o PUT mantém o snapshot completo dos Apps dessa sessão, com as proteções de concorrência e recuperação descritas abaixo.

Aplicação explícita:

```bash
APPLY=true bundle exec rails waha:backfill_existing_inboxes
```

## Segurança operacional

O dry-run lê o App remoto e informa somente IDs internos e o tipo de mudança; não imprime telefone, token nem configuração sensível.

Antes de qualquer escrita, o backfill valida a identidade do vínculo remoto. O App Chatwoot precisa apontar para a mesma instalação (`config.url`, tolerando apenas `/` final), a mesma conta (`accountId`), a mesma Inbox (`inboxId`) e o mesmo identificador do canal (`inboxIdentifier`). Também é exigida coerência local entre `Channel::Api` e `Inbox`. Qualquer divergência é bloqueante e não é corrigida automaticamente.

Depois da identidade validada, o backfill exige que a sessão esteja `WORKING` e faz uma consulta somente leitura para confirmar que o módulo `brazilian-phone-numbers` está realmente carregado no WAHA. Se o vínculo divergir, o módulo estiver indisponível ou a sessão não estiver operacional, a sessão é ignorada sem escrita e, em `APPLY=true`, o lote para imediatamente.

Mais de um App `brazilian-phone-numbers` na lista completa bloqueia o planejamento com `SKIP` humanizado, inclusive se um estiver desabilitado ou a caixa parecer já compatível. Nenhum App é escolhido, removido ou mesclado automaticamente. Dry-run informa a ambiguidade; em APPLY, o lote para sem escrita ou recuperação. Revisar a duplicidade antes de propor uma nova aplicação.

Como `lock_to_single_conversation=true`, o App Chatwoot é normalizado no mesmo plano para `sort=created_newest` e `status=null`. Essa combinação permite localizar também a conversa resolvida e reabri-la, em vez de criar outra. Um `WAHA_CONVERSATION_SORT` legado não pode sobrescrever esse comportamento em novas caixas.

Em `APPLY=true`, a configuração completa da sessão e a lista completa de Apps são capturadas como snapshot antes da atualização. O backfill aplica o filtro de Status definido pela instalação, preserva os demais campos da sessão e todos os Apps existentes, sincroniza Chatwoot + resolver brasileiro e só grava `lock_to_single_conversation`/`phone_numbers_app_id` depois que a sessão retorna a `WORKING` e o estado remoto desejado é confirmado por leitura.

Imediatamente antes da aplicação, o executor relê o estado/configuração da sessão e a lista completa de Apps e compara com o snapshot do planejamento. A ordem da lista não importa; os campos de cada App são comparados integralmente. Uma alteração concorrente gera `SKIP` com motivo explícito, sem PUT, recuperação ou gravação local, e interrompe o lote. Falha nessa leitura gera `FAILED` e também interrompe o lote sem escrita. Não há merge automático nem retry.

Essa comparação não é uma escrita condicional atômica na WAHA: continua existindo uma janela entre a última leitura e o PUT. No piloto autorizado, impedir alterações paralelas de Apps/configuração da sessão durante a operação, inclusive durante uma eventual recuperação. A recuperação do R1 após uma tentativa real de escrita continua usando o snapshot anterior.

Se a atualização remota falhar, ficar em `STARTING`/`STOPPED` ou não puder ser confirmada, o backfill tenta restaurar o snapshot anterior. Uma sessão que estava `WORKING` só é considerada recuperada depois de voltar a `WORKING` e ter configuração e Apps anteriores confirmados. Mesmo com recuperação bem-sucedida, o lote para e exige revisão antes de continuar. Falha de recuperação é registrada como `CRITICAL`/`recovery_failed`.

`session_status_filter` aparece no dry-run quando a configuração antiga ainda importa Status, inclusive em uma caixa já compatível com Chatwoot/resolver. Esse filtro é diferente de `conversations.syncMessageStatus`: entrega/leitura continuam sincronizadas. A aplicação não apaga mensagens ou conversas de Status já importadas.

A atualização da sessão causa um restart técnico, mas não faz logout nem remove o pareamento. A operação deve ser feita uma sessão por vez.

Se houver caixa sem `session`/`app_id`, divergência de App/sessão, preflight inválido ou erro remoto, o processo registra `SKIP`, `FAILED`, `RECOVERED` ou `CRITICAL`. Em modo APPLY, qualquer `SKIP` ou falha interrompe o lote.

## Duração dos ciclos de atendimento

Em WAHA com `lock_to_single_conversation=true`, o início de uma reabertura é persistido junto à transição de status, usando `status_changed_at`, no atributo interno `waha_resolution_cycle_started_at`. Snooze/pending e novas aberturas do mesmo ciclo não substituem o primeiro início. A resolução encerra esse marcador e captura o início concluído no payload do evento antes de enfileirar o job.

O cálculo de `conversation_resolved` usa o timestamp capturado, sem depender de `conversation_opened` ou da resolução anterior já estarem em `reporting_events`. Jobs atrasados continuam usando o início do seu próprio ciclo, mesmo após novas mudanças na conversa. Horário comercial, resolução de bot e rollups usam esse mesmo início.

O primeiro ciclo continua partindo de `created_at`. Eventos antigos já enfileirados sem o timestamp capturado mantêm o cálculo legado; esta alteração não recalcula histórico. Ciclos já em andamento antes da instalação deste código, sem marcador de início, também conservam a origem legada até uma nova reabertura registrada. Canais não-WAHA e WAHA sem trava permanecem no cálculo legado. A métrica do próprio evento `conversation_opened` não foi alterada.

## Verificação pós-aplicação

1. Confirmar `failed=0` e `skipped=0`.
2. Reexecutar em dry-run; as caixas devem aparecer como `already compliant`.
3. Confirmar que as sessões WAHA autenticadas retornam ao estado conectado.
4. Testar uma mensagem enviada pelo celular e confirmar que aparece como saída normal.
5. Testar uma mensagem do Chat2You e confirmar atualização de entregue/lido.
6. Resolver uma conversa, receber nova mensagem do mesmo contato e confirmar reabertura da mesma conversa.
7. Enviar para um número brasileiro conhecido em uma variação 8/9 dígitos e confirmar entrega no chat correto.
8. Confirmar no WAHA que cada sessão possui exatamente um App `brazilian-phone-numbers` habilitado.

A aplicação em produção só deve ocorrer depois do merge/deploy da branch que contém este backfill e depois de habilitar `brazilian-phone-numbers` em `WAHA_APPS_ON`.
