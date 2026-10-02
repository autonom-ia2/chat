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

Em `APPLY=true`, a configuração completa da sessão e a lista completa de Apps são lidas primeiro. O backfill preserva os Apps existentes, sincroniza Chatwoot + resolver brasileiro em uma única atualização da sessão e só depois grava as referências locais. Se o WAHA falhar, `lock_to_single_conversation` e `phone_numbers_app_id` não são alterados.

A atualização da sessão causa um restart técnico único, mas não faz logout nem remove o pareamento. A operação deve ser feita um ambiente por vez.

Se houver caixa sem `session`/`app_id`, divergência de App/sessão ou erro remoto, o processo registra `SKIP`/`FAILED`. Em modo APPLY, qualquer `SKIP` ou `FAILED` torna a migração incompleta e encerra com erro.

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
