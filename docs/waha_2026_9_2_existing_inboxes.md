# WAHA 2026.9.2 — backfill de caixas existentes

## Objetivo

Atualizar caixas WhatsApp API já provisionadas sem recriar Inbox, sessão WAHA ou pareamento.

O backfill altera somente:

- App Chatwoot no WAHA:
  - `conversations.outgoing = message`
  - `conversations.syncMessageStatus = true`
- Inbox no Chat2You:
  - `lock_to_single_conversation = true`

Todo o restante da configuração remota do App é preservado.

## Ambientes WAHA

- Chat2You: WAHA `wa-hub`, acessível pelo host operacional `ssh hubsegs`.
- Autonom.ia: WAHA `wa-autonomia`, acessível pelo host operacional `ssh autonomia`.

O rake deve ser executado no ambiente da aplicação que possui o banco da respectiva instalação, não dentro do container WAHA.

## Inventário somente leitura — 2026-10-02

- Hub/Chat2You: 33 Apps Chatwoot encontrados; 0 já compatíveis.
- Autonom.ia: 6 Apps Chatwoot encontrados; 0 já compatíveis.
- Nenhuma configuração foi alterada durante o inventário.

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

Em `APPLY=true`, o App remoto é atualizado antes da Inbox local. Se o WAHA falhar, `lock_to_single_conversation` não é alterado.

O App Chatwoot do WAHA usa `restartOnChange=true`; um PUT válido reinicia tecnicamente a sessão, mas não faz logout nem remove o pareamento. A operação deve ser feita um ambiente por vez.

Se houver caixa sem `session`/`app_id`, divergência de App/sessão ou erro remoto, o processo registra `SKIP`/`FAILED`. Em modo APPLY, qualquer `SKIP` ou `FAILED` torna a migração incompleta e encerra com erro.

## Verificação pós-aplicação

1. Confirmar `failed=0` e `skipped=0`.
2. Reexecutar em dry-run; as caixas devem aparecer como `already compliant`.
3. Confirmar que as sessões WAHA autenticadas retornam ao estado conectado.
4. Testar uma mensagem enviada pelo celular e confirmar que aparece como saída normal.
5. Testar uma mensagem do Chat2You e confirmar atualização de entregue/lido.
6. Resolver uma conversa, receber nova mensagem do mesmo contato e confirmar reabertura da mesma conversa.

A aplicação em produção só deve ocorrer depois do merge/deploy da branch que contém este backfill.
