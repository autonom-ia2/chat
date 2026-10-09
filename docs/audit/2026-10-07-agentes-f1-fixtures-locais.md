# Fixtures locais da primeira tela F1

Data: 2026-10-07  
Estado: preparação local; o script ainda não foi executado.

Este registro documenta o seed de prova da primeira tela real do redesign (`F1 — Seus agentes`). Ele foi
preparado para a worktree `docs/agentes-ia-prd` e fica fora do produto: não altera rotas, autenticação,
permissões, flags globais, dados de cliente ou qualquer ambiente publicado.

## Guarda de execução

O arquivo `.codex/preview/seed-agents.rb` deve ser chamado somente por um `rails runner` em
`RAILS_ENV=development`. Antes de tocar qualquer dado, ele exige o banco PostgreSQL
`chat2you_agentes_ia_prd` e host vazio/local (`localhost`, `127.0.0.1` ou `::1`). Um banco, host ou ambiente
fora desse conjunto faz o processo falhar. O banco M2 ainda não foi definido; por isso não há segunda
identidade autorizada no script. O processo não executa nesta etapa e não houve leitura ou escrita de banco.

O script não cria token de autenticação, sessão, segredo de canal ou credencial de provedor. Os usuários são
sintéticos, usam e-mails no domínio reservado `.invalid` e uma senha forte é construída somente durante a
criação; ela não é impressa nem transformada em token. A senha persistida pelo Devise é o hash normal do
modelo, sem senha em claro no seed ou no relatório. Em OSS, `editor` e `admin` são ambos
`AccountUser#administrator?`; `viewer` é `agent`, porque custom roles pertencem à superfície Enterprise e
não devem ser inventados pelo fixture.

## Dados que o seed prepara

As contas `F1 Preview A`, `F1 Preview B` e `F1 Preview Vazia` recebem as flags internas locais
`autonomia_agents_enabled` e `autonomia_agents_redesign`, além de um marcador privado de namespace. Cada uma
recebe os três membros sintéticos (admin, editor e viewer). A conta A recebe a matriz completa:

| Chave local | Estado | Fatos persistidos para a tela |
|---|---|---|
| `clara` | E5 | agente externo feminino, ativo, Web Widget local vinculado e eventos de resposta/handoff em janelas de 7/30 dias |
| `lia-cotacao` | E5 | `insurance_quote`, externo, ativo, Web Widget local e eventos próprios; não usa o fluxo de conexão do redesign |
| `interno` | E5 | atuação `internal`, ativo, sem caixa e sem `stats` no payload |
| `rascunho-e1` | E1 | guiado, rascunho sem instrução, thread guiada vazia persistida |
| `rascunho-e2` | E2 | guiado, rascunho e thread guiada persistida com mensagem de usuário/`needs_more_info` |
| `rascunho-mutacao` | E1 | rascunho guiado separado, reservado para o teste de exclusão; não substitui a fixture E1 usada nos demais cenários |
| `rascunho-e2m` | E2m | manual, rascunho sem instrução; a tela deve seguir para o painel legado compatível |
| `rascunho-e3-person` | E3 | teste local concluído e depois instrução alterada por escritor real, causando invalidação `person`; thread guiada pronta para retomar |
| `rascunho-e3-material` | E3 | teste local concluído e depois fingerprint de fonte de conhecimento alterado, com invalidação material pelo escritor real; thread guiada pronta para retomar |
| `pronto-para-ligar` | E4 | teste local concluído com `TestDigest`/`AgentStateStore`, resultado de IA real deliberadamente adiado; thread guiada pronta para retomar |
| `sem-canal` | E5 | externo, ativo, instrução presente, nenhum vínculo de inbox |
| `pausado` | E6 | externo, antes ativo para passar pelo `InboxConnector`, depois pausado/desabilitado, mantendo o vínculo |

O seed também cria uma `Clara B` em B para que a checagem account-scoped tenha uma diferença observável;
a conta vazia permanece sem agentes. Os nomes e marcadores são dados de preview, não IDs, números ou objetos
copiados do mockup. A mídia não entra na projeção de conhecimento nem no digest da lista.

Na conta A, `clara-handoff` é uma conversa pendente criada na caixa da Clara e atribuída ao `AgentBot`
espelho do `AgentInbox` nativo. O manifesto registra seus IDs reais (`id`, `displayId`, `agentId`,
`agentBotId`, `agentInboxId`, `inboxId`) em `accounts.a.conversations.claraHandoff` e no alias
`pauseConversation`; após a pausa do agente, o contrato esperado é GET da conversa com estado `open` e sem
`meta.assignee`. A conversa usa contato e `ContactInbox` sintéticos do mesmo namespace e metadados locais;
não há mensagem, telefone, número de cliente ou provedor externo.

O membro `admin` é um administrador da conta, criado como usuário comum. O seed também cria um ator
`SuperAdmin` sintético, com e-mail `.invalid`, como membro da mesma conta, somente para o cenário local que
precisa desse ator; ele não é encontrado nem promovido a partir de usuário real.
O `editor` usa o mesmo papel `administrator` porque a implementação OSS não tem um papel editorial separado.
Em runtime Enterprise, o seed associa `viewer` a um `CustomRole` local com `autonomia_view`; essa é a forma
real como `AccountUser#permission_granted?` libera leitura para um membro `agent`, sem promover a pessoa.
Se o modelo Enterprise não estiver carregado, o seed não fabrica autorização: o usuário viewer permanece
`agent` sem `autonomia_view`, e o cenário “Só ver” fica explicitamente bloqueado até a sessão usar um runtime
Enterprise local ou um papel já existente. Nenhum usuário real é promovido.

## Caminhos reais utilizados

- Agentes são persistidos como `Autonomia::Agents::Agent`, com `status`, `mode`, `enabled`, `actuation`,
  instrução e `config` compatíveis com o modelo atual. O marcador fica no `config` e é filtrado pelo serializer.
- E1 e E2 usam `Autonomia::Agents::BuildThread` com o shape real de `messages`/`state`: E1 tem thread guiada
  vazia e E2 tem thread guiada com resposta/`needs_more_info`; E2m continua sem thread para preservar o
  painel legado.
- E3 material usa `Source#begin_ingestion!`, `#mark_ready!`, `#mark_reviewed!`, `KnowledgeEntry` pronta e
  `Source#invalidate_material_if_changed!`. E3 person usa a escrita de instrução de `Agent` que passa pelo
  estado de teste. O conteúdo é curto e local; não há embedder, revisor pago ou chamada externa.
- E3 e E4 também têm uma `BuildThread` guiada em estado `ready`, associada ao agente, para que a retomada
  aninhada seja exercitada pelo fluxo real. E4 usa `TestDigest.for_agent` e
  `AgentStateStore.start_pending!`/`complete!` com um `AccountUser` administrador, digest corrente,
  `valid_for_state: true` e `result_real_ai_deferred: true`. Isso representa uma fixture de prova previamente
  concluída; não afirma que uma IA paga ou uma conversa real foi executada.
- Canais são `Channel::WebWidget`/`Inbox` locais. Os vínculos de Clara, Lia e Pausado passam pelo
  `Autonomia::Agents::Operate::InboxConnector`; não há WhatsApp, QR, número, token ou convite interno.
- Conversas são sintéticas e pertencem à mesma conta/inbox; `EventLogger#create!` grava `AgentEvent` real para
  respostas e passagens. Só `created_at` é reposicionado dentro das janelas de estatística e cada evento tem
  marcador de seed no `metadata`; nenhum texto de cliente é usado. A lista continua lendo `ListStats` em lote.

## Idempotência e limites

Cada linha criada é localizada pelo marcador `f1-local-v1` combinado com a conta/fixture/slot. Reexecuções
atualizam apenas objetos desse namespace, não apagam registros e não procuram por IDs do mockup. Uma execução
parcial pode ser retomada; qualquer colisão com dado sem marcador deve falhar em vez de sobrescrevê-lo.

O script grava o manifesto que o fixture Playwright lê em `.codex/preview/agents/manifest.json` (ou no caminho
`AGENTS_PREVIEW_MANIFEST`, que deve permanecer sob `.codex/preview`). O JSON contém somente IDs/nomes dos
registros do namespace, estados e credenciais sintéticas `.invalid`; é criado com modo `0600` e não é impresso.
O schema e a guarda do fixture estão em `tests/playwright/fixtures/agents.ts:38-125`; o carregamento exige
`version: 1`, `seed: f1-local-v1`, contas `a`/`empty` e credenciais `admin`/`editor`/`viewer`. A chave
`super_admin` do manifesto é apenas um ator local adicional e não participa do login tipado do fixture.

Este artefato não comprova a tela, a jornada, o contrato HTTP, o layout em 1440/400, claro/escuro, permissões,
acessibilidade, Guia ou produção. Depois que o guard local estiver verificado e a execução for coordenada pela
sessão principal, ela ainda precisa autenticar usuários de preview, chamar os GETs reais, conferir o payload account-scoped,
abrir as telas uma a uma nos quatro cenários de `design/F1.md` e registrar as capturas. Nada disso foi feito
neste passo.

## Correções estáticas antes da primeira execução

A leitura final do script encontrou uma causa concreta antes de qualquer seed: em `ensure_material_source`,
o ramo de criação usava `Source.new(account: agent, agent: agent)`. `Source#account` é uma associação para
`Account`; passar um `Agent` faria o Rails levantar `ActiveRecord::AssociationTypeMismatch` antes de criar a
fonte E3 material. A correção limitada troca a conta por `agent.account` e mantém o agente na associação.

A mesma conferência confirmou que `autonomia_view` não é concedido por `AccountUser#role == agent` no OSS:
`app/models/account_user.rb:67-75` deixa a permissão administrativa como única concessão padrão. O overlay
Enterprise implementa a concessão por `custom_role.permissions` em `enterprise/app/models/enterprise/account_user.rb:1-14`
e o catálogo oficial contém `autonomia_view` em `enterprise/app/models/custom_role.rb:35-81`. O script passou a
usar esse mecanismo somente quando presente e a registrar a limitação quando não estiver carregado; não há
alteração de infraestrutura de autenticação.

Para a primeira tela, a separação de threads foi ajustada antes da execução: E1 usa uma thread guiada vazia,
E2 usa uma thread guiada com mensagem/`needs_more_info`, e E3/E4 recebem threads guiadas `ready` para o
retorno aninhado. O script continua sem declarar resultado de IA paga ou conversa real; esses estados são
fixtures locais construídas pelos writers reais.

Referências do contrato: `docs/agentes-ia-redesign/design/F1.md:3-22,26-70,72-91,169-191`,
`app/services/autonomia/agents/list_projection.rb:10-105`,
`app/services/autonomia/agents/material_projection.rb:1-176`,
`app/services/autonomia/agents/agent_state_store.rb:1-194`,
`app/services/autonomia/agents/operate/inbox_connector.rb:1-93` e
`app/services/autonomia/agents/list_stats.rb:1-78`.
