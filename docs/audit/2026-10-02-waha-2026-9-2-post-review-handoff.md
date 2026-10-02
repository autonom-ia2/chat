# WAHA 2026.9.2 — revisão pós-R1–R5 e handoff

Data: 2026-10-02
Status: **NÃO LIBERADO PARA MERGE, DEPLOY OU BACKFILL**

## Alvo exato

- Repositório: `autonom-ia2/chat`
- Worktree: `/Users/rodrigosilva/dev/chat2you-waha-2026-9-2`
- Branch: `feat/waha-2026-9-2-chatwoot-sync`
- HEAD desta revisão: `ffac3accecce742c02d2d52eceb573dd4a9a0132`
- Base original do lote: `43901a40c2`

## Produção

O código desta branch **não está em produção**.

Alterações operacionais já feitas e separadas do código:
- `WAHA_APPS_ON=calls,chatwoot,mcp,brazilian-phone-numbers`
- fonte persistente do Portainer atualizada nas VPS:
  - `ssh hubsegs`
  - `ssh hub2you`
  - `ssh vsmulti`
  - `ssh autonomia`
- `groups_waha` do `vsmulti` não foi alterado.

Não executar merge, deploy, backfill, logout, novo pareamento ou alteração de sessão real sem autorização explícita.

## Itens originais

| Item | Estado após revisão |
|---|---|
| R1 — falha parcial / recuperação / fail-stop | Fechado por código e testes |
| R2 — identidade instalação/conta/Inbox/App remoto | Fechado por código e testes |
| R3 — Single Conversation: `created_newest` + qualquer status | Fechado por código e testes |
| R4 — cálculo do ciclo e escopo WAHA | Correção original implementada, porém há novo risco N2 abaixo |
| R5 — fonte do Guia / geração / validação | Fechado; `guia:check` verde |

## Validações verdes no HEAD acima

- RSpec direcionado/ampliado: **88 exemplos, 0 falhas**
- RuboCop em todos os Ruby/Rake alterados: **16 arquivos, 0 infrações**
- `pnpm guia:check`: **174 fluxos, 171 telas, 0 sem explicação**
- `git diff --check`: aprovado
- branch limpa no final da revisão.

## Novos bloqueadores encontrados na revisão crítica

### N1 — P1: snapshot remoto pode apagar mudança concorrente

O migrador lê a lista completa de Apps, monta um snapshot e depois envia a lista completa no `PUT /api/sessions/:session`.

Na WAHA 2026.9.2, `syncSessionApps`:
1. faz upsert dos Apps presentes no payload;
2. **remove Apps remotos que não estejam no payload**.

Reprodução local confirmada:
- snapshot inicial: somente Chatwoot;
- outro processo adiciona `calls_concurrent` depois do snapshot;
- o migrador envia o payload construído com o snapshot antigo;
- resultado observado:
  - `outcome=updated`
  - `concurrent_app_survived=false`

Isso é bloqueador de segurança do backfill.

#### Correção mínima esperada

Antes de qualquer `update_session`:
1. reler sessão e lista de Apps;
2. comparar com o snapshot usado no plano;
3. se houver mudança concorrente em qualquer App/configuração não gerenciada, **abortar sem escrita**;
4. não apagar nem sobrescrever Apps surgidos depois do snapshot;
5. se Chatwoot ou Brazilian Phone Numbers mudou concorrentemente, abortar em vez de mesclar silenciosamente;
6. adicionar teste que reproduza o App concorrente e comprove ausência de escrita destrutiva.

Preferência: optimistic concurrency no nosso lado, não retry cego.

### N2 — P2: R4 depende da ordem de jobs assíncronos

`conversation_opened` e `conversation_resolved` são enviados separadamente para:

- `EventDispatcherJob`
- fila `critical`
- Sidekiq com concorrência configurável e default 10.

O R4 usa registros já persistidos em `reporting_events`. Não há garantia de que o job `conversation_opened` termine antes do `conversation_resolved`.

Reprodução local:
- conversa WAHA single-conversation criada há 3 dias;
- resolução anterior há 2h;
- abertura real há 80 min;
- processar primeiro `conversation_resolved`;
- só depois processar `conversation_opened`.

Resultado:
- o `conversation_resolved` usou `conversation.created_at`;
- valor ficou ~3 dias;
- o `opened` tardio não corrigiu o evento de resolução já persistido.

#### Correção mínima esperada

Tornar o cálculo do ciclo independente da ordem de execução dos jobs.

Não assumir que `conversation_opened` já está em `reporting_events`.

A solução deve:
- continuar restrita a WAHA + `lock_to_single_conversation=true`;
- preservar canais não-WAHA;
- funcionar com snooze/múltiplas aberturas;
- cobrir explicitamente processamento fora de ordem;
- evitar reescrever métricas de outros canais.

Antes de escolher a implementação, revisar quais timestamps/transições confiáveis já existem no evento/modelo e evitar criar infraestrutura desnecessária.

### N3 — bloqueador operacional: falta filtro de piloto por uma Inbox

O rake atual suporta apenas:
- `ACCOUNT_ID`

Não suporta:
- `INBOX_ID`
- `CHANNEL_ID`
- `SESSION`

Para rollout seguro precisamos conseguir executar um piloto em **uma única caixa**.

#### Correção mínima esperada

Adicionar `INBOX_ID` ao rake/updater:
- opcional;
- combinável com `ACCOUNT_ID`;
- dry-run e APPLY;
- escopo exato;
- teste garantindo que somente a Inbox selecionada é processada;
- documentação do comando.

Não ampliar para filtros adicionais se `INBOX_ID` resolver o requisito.

## Ponto operacional a validar no piloto

O executor compara o estado remoto após `PUT /api/sessions` com bastante rigor:
- `session.config`
- projeção dos Apps.

Isso é seguro como fail-closed, mas a WAHA pode normalizar defaults/campos. Antes de lote, o piloto real deve confirmar que uma atualização válida não gera rollback falso por normalização legítima.

## Aceites E2E ainda pendentes

Mesmo depois de N1–N3:

1. mensagem enviada diretamente pelo celular aparece como outgoing normal no Chat2You;
2. não há eco/reenvio/duplicação;
3. entrega/leitura sincronizam corretamente;
4. resolver conversa, cliente voltar e a **mesma conversa** reabrir;
5. número brasileiro com/sem 9º dígito converge para o mesmo chat;
6. Apps WAHA não relacionados permanecem intactos;
7. QR/reconnect não sofre regressão;
8. grupos permanecem fora do escopo do WhatsApp API padrão.

## Ordem de trabalho autorizável

Executar **um item por vez**:

1. N1 — concorrência/snapshot remoto;
2. revisão e testes;
3. N2 — independência da ordem dos jobs;
4. revisão e testes;
5. N3 — `INBOX_ID` para piloto unitário;
6. revisão completa curta;
7. parar e solicitar autorização antes de qualquer merge/deploy/piloto.

## Regras para continuação

- Trabalhar exclusivamente neste worktree/branch.
- Não tocar no checkout principal `/Users/rodrigosilva/dev/chat2you`.
- Não alterar produção.
- Não executar backfill real.
- Não usar `--no-verify`.
- Ruby correto: `/Users/rodrigosilva/.rbenv/versions/3.4.4/bin/ruby`.
- Preservar R1–R5; não reabrir escopo sem evidência.
- Não fazer refatoração ampla ou UI.
- Após cada item: testes focados, regressão WAHA/relatórios, RuboCop, `git diff --check`, commit isolado e push.
- Merge e deploy dependem de aprovação explícita do Rodrigo.
