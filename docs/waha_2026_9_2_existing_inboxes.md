# WAHA 2026.9.2 — backfill de caixas existentes

## Objetivo

Atualizar caixas WhatsApp API já provisionadas sem recriar Inbox, sessão WAHA ou pareamento.

O backfill deixa cada sessão com:

- App Chatwoot no WAHA:
  - `conversations.outgoing = message`
  - `conversations.syncMessageStatus = true`
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
- Nos dois WAHA, `WAHA_APPS_ON` está atualmente em `calls,chatwoot,mcp`.
- Nenhuma configuração foi alterada durante o inventário.

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

Aplicação explícita:

```bash
APPLY=true bundle exec rails waha:backfill_existing_inboxes
```

## Segurança operacional

O dry-run lê o App remoto e informa somente IDs internos e o tipo de mudança; não imprime telefone, token nem configuração sensível.

Antes de qualquer escrita, o backfill valida a identidade do vínculo remoto. O App Chatwoot precisa apontar para a mesma instalação (`config.url`, tolerando apenas `/` final), a mesma conta (`accountId`), a mesma Inbox (`inboxId`) e o mesmo identificador do canal (`inboxIdentifier`). Também é exigida coerência local entre `Channel::Api` e `Inbox`. Qualquer divergência é bloqueante e não é corrigida automaticamente.

Depois da identidade validada, o backfill exige que a sessão esteja `WORKING` e faz uma consulta somente leitura para confirmar que o módulo `brazilian-phone-numbers` está realmente carregado no WAHA. Se o vínculo divergir, o módulo estiver indisponível ou a sessão não estiver operacional, a sessão é ignorada sem escrita e, em `APPLY=true`, o lote para imediatamente.

Em `APPLY=true`, a configuração completa da sessão e a lista completa de Apps são capturadas como snapshot antes da atualização. O backfill preserva os Apps existentes, sincroniza Chatwoot + resolver brasileiro e só grava `lock_to_single_conversation`/`phone_numbers_app_id` depois que a sessão retorna a `WORKING` e o estado remoto desejado é confirmado por leitura.

Se a atualização remota falhar, ficar em `STARTING`/`STOPPED` ou não puder ser confirmada, o backfill tenta restaurar o snapshot anterior. Uma sessão que estava `WORKING` só é considerada recuperada depois de voltar a `WORKING` e ter configuração e Apps anteriores confirmados. Mesmo com recuperação bem-sucedida, o lote para e exige revisão antes de continuar. Falha de recuperação é registrada como `CRITICAL`/`recovery_failed`.

A atualização da sessão causa um restart técnico, mas não faz logout nem remove o pareamento. A operação deve ser feita uma sessão por vez.

Se houver caixa sem `session`/`app_id`, divergência de App/sessão, preflight inválido ou erro remoto, o processo registra `SKIP`, `FAILED`, `RECOVERED` ou `CRITICAL`. Em modo APPLY, qualquer `SKIP` ou falha interrompe o lote.

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
