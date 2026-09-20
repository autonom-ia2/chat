# Guia Autonom.ia - desenho técnico da fatia "Guia"

> **Registro histórico — desenho da V1, read-only.** Este documento descreve o Guia
> como ele foi desenhado em junho de 2026: só leitura, sem consultar os dados da conta
> e sem executar nada. Esse desenho foi substituído pelas issues #533 (o Guia consulta
> o que a conta tem, com a permissão de quem pergunta) e #536 (o Guia executa ações,
> sempre com confirmação na tela). Fica como registro de decisão — não leia como
> descrição do comportamento atual.


Data: 2026-06-20.

Escopo: desenhar um agente interno read-only que conhece a plataforma, responde "onde fica / como faço" em linguagem natural e pode levar o usuário para a tela correta. Este documento não implementa nada.

Arquivos lidos como base:

- Rotas FE: `app/javascript/dashboard/routes/dashboard/**/*.routes.js`, `app/javascript/dashboard/routes/dashboard/*/routes.js`, `app/javascript/dashboard/routes/index.js`, `app/javascript/dashboard/routes/dashboard/dashboard.routes.js`, `app/javascript/dashboard/modules/search/search.routes.js`.
- Sidebar e navegação: `app/javascript/dashboard/components-next/sidebar/Sidebar.vue`, `app/javascript/dashboard/composables/useAccount.js`, `app/javascript/dashboard/helper/routeHelpers.js`, `app/javascript/shared/helpers/mitt.js`, `app/javascript/shared/constants/busEvents.js`.
- Flags: `config/features.yml`, `app/controllers/dashboard_controller.rb`, `app/javascript/shared/store/globalConfig.js`, `app/services/{crm,email_campaigns,campaign_imports,whatsapp_api_campaigns}/config.rb`, `app/services/autonomia/agents/config.rb`.
- RAG/Autonomia: `app/models/autonomia/agents/{agent,source,knowledge_entry}.rb`, `app/services/autonomia/agents/{retriever,embedding_service,answerer,prompt_builder,copilot}.rb`, `app/services/autonomia/agents/knowledge/{ingestor,reviewer}.rb`, jobs em `app/jobs/autonomia/agents/knowledge`.
- Copiloto atual: `app/javascript/dashboard/components/autonomia/copilot/*`, `app/javascript/dashboard/api/autonomiaCopilot.js`, `app/javascript/dashboard/store/modules/autonomiaCopilot.js`, `app/javascript/dashboard/routes/dashboard/Dashboard.vue`.
- Backend do copiloto: `app/controllers/api/v1/accounts/autonomia/conversation_copilot_controller.rb`, `app/services/autonomia/copilot/conversation_chat.rb`, `app/services/crm/ai/responses_client.rb`.

## 1. Decisão de arquitetura

O Guia deve nascer como uma variação read-only do runtime Autonomia, não como monkey patch de frontend:

- Um agente interno "Guia da Plataforma" por conta habilitada, `actuation: internal`, `status: active`, `agent_type: custom`, com `instruction/scaffold` ocultos como nos agentes guiados.
- Conhecimento configurável via `Autonomia::Agents::Source` e `Autonomia::Agents::KnowledgeEntry`, usando a ingestão atual: upload/link/texto markdown -> chunk -> embedding -> revisão -> retrieval.
- Widget global reutilizando a casca visual do `AutonomiaCopilotContainer`, mas sem depender de `currentChat` nem de `conversation_id`.
- Endpoint novo read-only, sem herdar o controller admin-only de Autonomia, mas com gate por conta e permissão de rota. O endpoint só responde e devolve `nav_target`; não chama operações de domínio.
- Navegação feita no FE por `router.push(accountScopedRoute(routeName, params, query))`, com route names allow-listed e validados.

Não usar `CRM_COPILOT_ENABLED` como gate do Guia. Esse flag hoje pertence ao copiloto de conversa e é combinado com `CRM_KANBAN_ENABLED`. O Guia é da plataforma inteira. V1 deve usar o gate existente de Autonomia:

- ENV master: `AUTONOMIA_AGENTS_ENABLED=true`.
- Gate por conta: `accounts.internal_attributes['autonomia_agents_enabled']`, exposto no payload como `autonomia_agents_enabled`.
- Usuário autenticado em conta ativa. O conteúdo responde de forma read-only para qualquer papel da conta, mas a navegação só deve apontar para rotas que o usuário pode acessar.

Se o produto quiser kill switch separado depois, adicionar `AUTONOMIA_GUIDE_ENABLED` é simples, mas não é necessário para V1.

## 2. KB configurável e atualizável

### 2.1 Dois KBs com o mesmo schema

Usar dois documentos markdown editáveis, ingeridos como sources do agente "Guia da Plataforma":

- `guia-produto.md`: conhecimento global do produto. Contém os ~50 fluxos oficiais da plataforma, os nomes reais de rota, caminhos de sidebar, flags e permissões.
- `guia-conta.md`: conhecimento específico da conta. Contém overrides ou complementos: nomenclatura interna, fluxos operacionais próprios, módulos que a conta usa ou não usa, processo de suporte local.

Os dois KBs usam o schema idêntico abaixo. O título `### <Título do fluxo>` é a chave humana do fluxo e também o identificador usado para detectar overrides no futuro.

```markdown
### <Título do fluxo>
- intent: 2-4 perguntas em linguagem natural
- onde_fica: caminho no menu/sidebar
- rota: route NAME real + path
- gate: feature flag / permissão / papel
- pre_requisitos: o que precisa antes (ou "nenhum")
- passos: 3-6 passos curtos
- gotchas: erros/confusões comuns (ou "—")
- nav_target: route name para levar o usuário
```

Exemplo real para o seed:

```markdown
### Importar base de campanha
- intent: Como importar uma base de contatos? Onde fica importar base de campanha? Como subir uma planilha de campanha?
- onde_fica: Contatos > Importar base de campanha
- rota: contacts_campaign_imports + /app/accounts/:accountId/contacts/campaign-imports
- gate: AUTONOMIA_AGENTS_ENABLED=true, CAMPAIGN_IMPORT_ENABLED=true, feature CRM, papel administrator
- pre_requisitos: arquivo CSV ou XLSX com nome e telefone; usuário administrador
- passos: Abra Contatos. Entre em Importar base de campanha. Envie o arquivo. Revise os erros. Confirme a importação quando o arquivo estiver válido.
- gotchas: se qualquer linha for inválida, nada é importado; a rota redireciona para Contatos quando CAMPAIGN_IMPORT_ENABLED está off
- nav_target: contacts_campaign_imports
```

### 2.2 Como armazenar no RAG existente

O modelo atual prende `Source` e `KnowledgeEntry` a `account_id` e `autonomia_agent_id`. A forma mais segura para V1 é tratar "global do produto" como conteúdo global sincronizado para agentes por conta, não como records cross-account compartilhados.

Fluxo proposto:

1. Criar, por conta habilitada, um agente de sistema:
   - `Autonomia::Agents::Agent`
   - `name: "Guia da Plataforma"`
   - `actuation: internal`
   - `status: active`
   - `mode: guided`
   - `enabled: false` se quiser impedir conexão a inbox; o uso do Guia busca por `config['system_key'] == 'platform_guide'`, não por canais.
   - `config['system_key'] = 'platform_guide'`
   - `config['hidden_from_hub'] = true`
2. Criar duas sources nesse agente:
   - `source_type: md`, `reference: guia-produto.md`, `kind: knowledge`, `metadata['guide_scope'] = 'product'`.
   - `source_type: md`, `reference: guia-conta.md`, `kind: knowledge`, `metadata['guide_scope'] = 'account'`.
3. Rodar a ingestão atual:
   - `Autonomia::Agents::Knowledge::IngestJob.perform_later(source.id)`
   - `ProcessJob` chama `Ingestor`, `EmbeddingService`, `Reviewer`, `Reviewer.recompute_overall!`.
4. Retrieval segue isolado por agente e conta:
   - `Autonomia::Agents::Retriever.new(agent: guide_agent).retrieve(query)`.
   - Sources `needs_resend` e `needs_review` continuam fora do retrieval pelo código atual.

Esse desenho reaproveita:

- ActiveStorage em `Source#file`.
- `Source#begin_ingestion!`, `mark_ready!`, `mark_reviewed!`.
- Processors existentes para `txt`/`md`/`docx`/`xlsx`/`json`/`link`.
- `KnowledgeEntry` com `neighbor`.
- `Retriever` com filtro por agente e gate de source revisada.
- `Answerer`/`ResponsesClient` e o portão de confiança.

### 2.3 Atualização sem deploy

O conteúdo não deve viver em constante Ruby, JS ou arquivo versionado como fonte de verdade. O arquivo versionado pode existir só como seed inicial. A fonte de verdade em produção deve ser DB/ActiveStorage.

Operação de atualização:

1. Admin de plataforma ou admin da conta abre uma tela de gestão do Guia.
2. Edita o markdown ou faz upload de novo `guia-produto.md`/`guia-conta.md`.
3. Backend substitui o attachment da `Source` correspondente e chama `Autonomia::Agents::Knowledge::IngestJob`.
4. A UI mostra `pending/processing/ready/failed` usando o mesmo contrato de `sources/_source.json.jbuilder`.
5. `resync` usa o endpoint/padrão já existente em `SourcesController#resync`.

Escopo por conta:

- `guia-conta.md` é editado pelo admin da própria conta e só afeta o agente Guia daquela conta.
- Não há risco cross-account porque as entries continuam com `account_id` e `autonomia_agent_id`.

Escopo global do produto:

- V1 pragmático: seed/sync cria ou atualiza a source `guia-produto.md` em cada conta habilitada. O conteúdo é igual, os records são isolados.
- Para atualização global sem deploy: uma ação admin de plataforma publica uma nova versão e enfileira um job que itera contas habilitadas, substitui a source `guide_scope=product` e reingere.
- Não hardcodar conta dona, domínio ou IDs. Se houver uma "conta de manutenção", ela deve ser configurada por GlobalConfig/ENV e validada, nunca literal no código.

Risco importante: o `Reviewer` atual marca fallback `needs_review` quando a IA/credencial falha, e o `Retriever` exclui `needs_review`. Para uma KB de sistema, isso pode deixar o Guia sem conhecimento depois de uma atualização. Mitigação: adicionar override admin "aceitar fonte do Guia" ou só promover a nova versão após revisão `accepted`.

## 3. Catálogo inicial de 50 fluxos

Esta tabela é o seed do `guia-produto.md`. Cada linha vira um bloco markdown com o schema obrigatório. Os paths abaixo usam o prefixo real `/app` produzido por `frontendURL`.

| # | Fluxo | route name real | path real | gate resumido | nav_target |
|---:|---|---|---|---|---|
| 1 | Conversas - todas | `home` | `/app/accounts/:accountId/dashboard` | conversa: administrator/agent/custom permissions | `home` |
| 2 | Inbox view | `inbox_view` | `/app/accounts/:accountId/inbox-view` | roles + conversation permissions | `inbox_view` |
| 3 | Conversas por caixa | `inbox_dashboard` | `/app/accounts/:accountId/inbox/:inbox_id` | conversa + `inbox_id` | `inbox_dashboard` |
| 4 | Conversas por etiqueta | `label_conversations` | `/app/accounts/:accountId/label/:label` | conversa + `label` | `label_conversations` |
| 5 | Conversas por time | `team_conversations` | `/app/accounts/:accountId/team/:teamId` | conversa + `teamId` | `team_conversations` |
| 6 | Menções | `conversation_mentions` | `/app/accounts/:accountId/mentions/conversations` | conversa | `conversation_mentions` |
| 7 | Não atendidas | `conversation_unattended` | `/app/accounts/:accountId/unattended/conversations` | conversa | `conversation_unattended` |
| 8 | Participando | `conversation_participating` | `/app/accounts/:accountId/participating/conversations` | conversa | `conversation_participating` |
| 9 | Busca global | `search` | `/app/accounts/:accountId/search/:tab?` | roles + conversation/contact/portal permissions | `search` |
| 10 | Notificações | `notifications_index` | `/app/accounts/:accountId/notifications` | administrator/agent/custom_role | `notifications_index` |
| 11 | Contatos | `contacts_dashboard_index` | `/app/accounts/:accountId/contacts` | feature CRM + contact_manage/admin/agent | `contacts_dashboard_index` |
| 12 | Contatos ativos | `contacts_dashboard_active` | `/app/accounts/:accountId/contacts/active` | feature CRM + contact_manage/admin/agent | `contacts_dashboard_active` |
| 13 | Segmentos de contatos | `contacts_dashboard_segments_index` | `/app/accounts/:accountId/contacts/segments/:segmentId` | feature CRM + `segmentId` | `contacts_dashboard_segments_index` |
| 14 | Contatos por etiqueta | `contacts_dashboard_labels_index` | `/app/accounts/:accountId/contacts/labels/:label` | feature CRM + `label` | `contacts_dashboard_labels_index` |
| 15 | Importar base de campanha | `contacts_campaign_imports` | `/app/accounts/:accountId/contacts/campaign-imports` | `CAMPAIGN_IMPORT_ENABLED=true`, administrator | `contacts_campaign_imports` |
| 16 | Empresas | `companies_dashboard_index` | `/app/accounts/:accountId/companies` | feature `companies`, cloud/enterprise | `companies_dashboard_index` |
| 17 | CRM Kanban | `crm_kanban_index` | `/app/accounts/:accountId/crm` | `CRM_KANBAN_ENABLED=true`, CRM view | `crm_kanban_index` |
| 18 | CRM Calendário | `crm_calendar_index` | `/app/accounts/:accountId/crm/calendar` | `CRM_KANBAN_ENABLED=true`, CRM view | `crm_calendar_index` |
| 19 | CRM Dashboard | `crm_dashboard_index` | `/app/accounts/:accountId/crm/dashboard` | `CRM_KANBAN_ENABLED=true`, CRM reports | `crm_dashboard_index` |
| 20 | CRM SLA | `crm_sla_index` | `/app/accounts/:accountId/crm/sla` | `CRM_KANBAN_ENABLED=true`, administrator/crm_admin | `crm_sla_index` |
| 21 | Gestão de campanhas CRM | `crm_campaign_management_index` | `/app/accounts/:accountId/crm/campaign-management` | `CRM_KANBAN_ENABLED=true`, CRM reports | `crm_campaign_management_index` |
| 22 | Tokens de integração CRM | `crm_integration_tokens_index` | `/app/accounts/:accountId/crm/settings/integration-tokens` | `CRM_KANBAN_ENABLED=true`, administrator/crm_admin | `crm_integration_tokens_index` |
| 23 | Campanhas de e-mail | `campaigns_email_index` | `/app/accounts/:accountId/campaigns/email_campaigns` | `EMAIL_CAMPAIGN_ENABLED=true` + `CRM_KANBAN_ENABLED=true`, administrator | `campaigns_email_index` |
| 24 | Remetentes de e-mail | `campaigns_email_sender_index` | `/app/accounts/:accountId/campaigns/email_sender` | `EMAIL_CAMPAIGN_ENABLED=true` + `CRM_KANBAN_ENABLED=true`, administrator | `campaigns_email_sender_index` |
| 25 | Campanhas WhatsApp Oficial | `campaigns_whatsapp_index` | `/app/accounts/:accountId/campaigns/whatsapp` | feature campaigns + whatsapp_campaign, administrator | `campaigns_whatsapp_index` |
| 26 | Campanhas WhatsApp API | `campaigns_whatsapp_api_index` | `/app/accounts/:accountId/campaigns/whatsapp_api` | `WHATSAPP_API_CAMPAIGNS_ENABLED=true`, administrator | `campaigns_whatsapp_api_index` |
| 27 | Campanhas live chat | `campaigns_livechat_index` | `/app/accounts/:accountId/campaigns/live_chat` | feature campaigns, administrator | `campaigns_livechat_index` |
| 28 | Campanhas SMS | `campaigns_sms_index` | `/app/accounts/:accountId/campaigns/sms` | feature campaigns, administrator | `campaigns_sms_index` |
| 29 | Agentes Autonom.ia | `autonomia_agents_index` | `/app/accounts/:accountId/agents` | `AUTONOMIA_AGENTS_ENABLED=true` + conta habilitada, administrator | `autonomia_agents_index` |
| 30 | Construtor de agente | `autonomia_agents_builder` | `/app/accounts/:accountId/agents/new` | Autonomia habilitada, administrator | `autonomia_agents_builder` |
| 31 | Painel de agente | `autonomia_agent_panel` | `/app/accounts/:accountId/agents/:agentId/:tab?` | Autonomia habilitada, administrator + `agentId` | `autonomia_agent_panel` |
| 32 | Relatório geral | `account_overview_reports` | `/app/accounts/:accountId/reports/overview` | feature reports + report_manage/admin | `account_overview_reports` |
| 33 | Relatório de conversas | `conversation_reports` | `/app/accounts/:accountId/reports/conversation` | feature reports + report_manage/admin | `conversation_reports` |
| 34 | Relatório por agente | `agent_reports_index` | `/app/accounts/:accountId/reports/agents_overview` | report_manage/admin | `agent_reports_index` |
| 35 | Relatório por caixa | `inbox_reports_index` | `/app/accounts/:accountId/reports/inboxes_overview` | report_manage/admin | `inbox_reports_index` |
| 36 | Relatório por time | `team_reports_index` | `/app/accounts/:accountId/reports/teams_overview` | report_manage/admin | `team_reports_index` |
| 37 | Relatório por etiqueta | `label_reports_index` | `/app/accounts/:accountId/reports/labels_overview` | report_manage/admin | `label_reports_index` |
| 38 | Relatório CSAT | `csat_reports` | `/app/accounts/:accountId/reports/csat` | feature reports + report_manage/admin | `csat_reports` |
| 39 | Relatório SLA | `sla_reports` | `/app/accounts/:accountId/reports/sla` | feature reports + report_manage/admin | `sla_reports` |
| 40 | Relatório de bots | `bot_reports` | `/app/accounts/:accountId/reports/bot` | feature reports + report_manage/admin | `bot_reports` |
| 41 | Central de ajuda | `portals_index` | `/app/accounts/:accountId/portals/:navigationPath` | feature help_center + knowledge_base_manage/admin | `portals_index` |
| 42 | Novo portal | `portals_new` | `/app/accounts/:accountId/portals/new` | feature help_center + administrator/knowledge_base_manage | `portals_new` |
| 43 | Artigos da central | `portals_articles_index` | `/app/accounts/:accountId/portals/:portalSlug/:locale/:categorySlug?/articles/:tab?` | help_center + portal/locale | `portals_articles_index` |
| 44 | Categorias da central | `portals_categories_index` | `/app/accounts/:accountId/portals/:portalSlug/:locale/categories` | help_center + portal/locale | `portals_categories_index` |
| 45 | Idiomas da central | `portals_locales_index` | `/app/accounts/:accountId/portals/:portalSlug/locales` | help_center + portal | `portals_locales_index` |
| 46 | Configurações da central | `portals_settings_index` | `/app/accounts/:accountId/portals/:portalSlug/settings` | help_center + portal | `portals_settings_index` |
| 47 | Configurações gerais | `general_settings_index` | `/app/accounts/:accountId/settings/general` | administrator | `general_settings_index` |
| 48 | Agentes da conta | `agent_list` | `/app/accounts/:accountId/settings/agents/list` | feature agent_management, administrator | `agent_list` |
| 49 | Times | `settings_teams_list` | `/app/accounts/:accountId/settings/teams/list` | feature team_management, administrator | `settings_teams_list` |
| 50 | Caixas de entrada | `settings_inbox_list` | `/app/accounts/:accountId/settings/inboxes/list` | feature inbox_management, administrator | `settings_inbox_list` |

Fluxos adicionais óbvios para a próxima leva: `labels_list`, `attributes_list`, `automation_list`, `agent_bots`, `macros_wrapper`, `canned_list`, `settings_applications`, `auditlogs_list`, `custom_roles_list`, `conversation_workflow_index`, `security_settings_index`, `billing_settings_index`, `profile_settings_index`, `captain_assistants_index`.

## 4. Navegação segura

### 4.1 O que já existe

- `useAccount.accountScopedRoute(name, params, query)` monta `{ name, params: { accountId, ...params }, query }`.
- `routeHelpers.js` valida permissão via `route.meta.permissions` e redireciona para rota padrão permitida.
- `Sidebar.vue` já navega por route name real, não por URL literal.
- `mitt` existe em `app/javascript/shared/helpers/mitt.js` e eventos globais vivem em `BUS_EVENTS`.

### 4.2 Contrato `navigate`

O Guia não deve deixar o modelo inventar rota. A resposta backend deve devolver uma sugestão validada:

```json
{
  "text": "Para importar uma base, vá em Contatos > Importar base de campanha. Vou te levar para essa tela.",
  "grounded": true,
  "confidence": 0.82,
  "navigation": {
    "label": "Importar base de campanha",
    "route_name": "contacts_campaign_imports",
    "params": {},
    "query": {}
  }
}
```

No FE:

1. Validar `route_name` contra `guideRouteRegistry`.
2. Validar se a rota existe com `router.resolve`.
3. Validar params obrigatórios. Se faltar `inbox_id`, `teamId`, `agentId`, `portalSlug` etc., navegar para a rota índice segura ou pedir escolha.
4. Chamar `router.push(accountScopedRoute(routeName, params, query))`.
5. Fechar mobile sidebar se necessário.

`guideRouteRegistry` deve ficar em código, por exemplo `app/javascript/dashboard/helper/guideRouteRegistry.js`, com entradas derivadas da tabela acima. O KB ajuda o modelo a escolher, mas o registry decide se pode navegar.

### 4.3 Mapa intenção -> rota

O mapa primário deve estar no KB, nos campos `intent`, `rota` e `nav_target`. O backend recupera o fluxo via RAG e só aceita `nav_target` se:

- aparece no conteúdo recuperado;
- existe no registry;
- passa em `router.resolve` no FE;
- não exige params que a pergunta não forneceu.

Para intents ambíguas, o Guia responde e pergunta antes de navegar. Exemplo: "campanhas" pode ser `campaigns_email_index`, `campaigns_whatsapp_index`, `campaigns_whatsapp_api_index`, `campaigns_livechat_index` ou `campaigns_sms_index`.

### 4.4 Highlight fase 2

V1 deve navegar. Highlight fica para V2.

V2 pode reutilizar `mitt`, mas criando eventos próprios em `BUS_EVENTS`:

- `GUIDE_HIGHLIGHT_TARGET`
- `GUIDE_CLEAR_HIGHLIGHT`

Cada tela priorizada registraria poucos targets estáveis, por exemplo `data-guide-target="campaign-import-upload"`. Não fazer DOM scraping por texto/classe Tailwind. Highlight só aponta elementos já allow-listed no registry.

## 5. Widget global

### 5.1 Estado atual

`Dashboard.vue` renderiza globalmente:

- `AutonomiaCopilotLauncher`
- `AutonomiaCopilotContainer`

O widget atual:

- usa os componentes visuais de copiloto (`SidebarActionsHeader`, `CopilotInput`, bubbles, loader);
- é gated por `globalConfig.crmKanbanEnabled && globalConfig.crmCopilotEnabled`;
- depende de `currentChat` e de `conversationDisplayId`;
- chama `AutonomiaCopilotAPI.listAgents(conversationId)` e `chat(conversationId, ...)`;
- reseta histórico quando a conversa muda.

Isso é bom para "copiloto de conversa", mas errado para o Guia.

### 5.2 Modo Guia global

Adicionar um modo/containers próprios, reaproveitando apresentação:

- `app/javascript/dashboard/components/autonomia/guide/AutonomiaGuideLauncher.vue`
- `app/javascript/dashboard/components/autonomia/guide/AutonomiaGuideContainer.vue`
- `app/javascript/dashboard/api/autonomiaGuide.js`
- `app/javascript/dashboard/store/modules/autonomiaGuide.js`

Reuso direto:

- `SidebarActionsHeader`
- `CopilotInput`
- `CopilotAgentMessage`
- `CopilotAssistantMessage`
- `CopilotLoader`
- `useUISettings`

Diferenças:

- Sem `currentChat`.
- Sem seletor de agente.
- Sem botão "usar resposta" para inserir no editor.
- Histórico reseta por conta, não por conversa.
- Abre em qualquer rota do dashboard, inclusive conversas.
- Título fixo: "Guia da Plataforma" ou "Guia Autonom.ia".
- UI setting própria: `is_autonomia_guide_panel_open`.

Gating no FE:

- `globalConfig.autonomiaAgentsEnabled === true`.
- `currentAccount.autonomia_agents_enabled === true`.
- opcionalmente esconder em `no_accounts`, onboarding e suspended.

Gating no BE:

- `Autonomia::Agents::Config.enabled?(Current.account)`.
- conta ativa e usuário autenticado.
- não exigir administrator para conversar com o Guia, porque é read-only.

## 6. Backend read-only

### 6.1 Rotas e controller

Adicionar rotas em `config/routes.rb`, dentro de `namespace :autonomia`:

```ruby
get  'guide',      to: 'guide#show'
post 'guide/chat', to: 'guide#chat'
```

Controller proposto:

- `app/controllers/api/v1/accounts/autonomia/guide_controller.rb`
- herda de `Api::V1::Accounts::BaseController`, não de `Autonomia::BaseController`, para não ficar admin-only.
- `before_action :ensure_guide_enabled`.
- `before_action :set_guide_agent`.

`ensure_guide_enabled`:

- `head :not_found unless Autonomia::Agents::Config.enabled?(Current.account)`.
- Não usar `Crm::Config.enabled?` nem `CRM_COPILOT_ENABLED`.

### 6.2 Serviço

Novo serviço:

- `app/services/autonomia/guide/chat.rb`

Entrada:

- `account`
- `user`
- `message`
- `history`
- `route_context` opcional: route atual do usuário, para respostas do tipo "você já está na tela certa".

Saída:

- `text`
- `grounded`
- `confidence`
- `navigation`
- `used_knowledge`
- `available`

Reuso:

- `Autonomia::Agents::Retriever` para recuperar blocos do KB.
- `Crm::Ai::ResponsesClient` para chamada structured output com `store:false`.
- Lógica de confiança do `Autonomia::Agents::Answerer` ou extração de um helper comum, mantendo threshold.
- `Crm::Ai::CredentialResolver` por conta.

V1 pode começar chamando `Autonomia::Agents::Answerer` para texto e usar um `Autonomia::Guide::RouteResolver` determinístico que lê `nav_target` do melhor bloco recuperado. Se isso ficar frágil, criar `Autonomia::Guide::Answerer` com schema próprio incluindo `nav_target`, copiando o portão de confiança do `Answerer`.

### 6.3 Portão de confiança

Regra de resposta:

- Se não houver KB aceita, responder indisponível: "Ainda não tenho o guia carregado para esta conta."
- Se a confiança ficar abaixo do threshold, não navegar.
- Se não encontrar rota allow-listed, responder sem navegação.
- Se a pergunta for sobre operação ("apague", "crie", "envie", "importe por mim"), recusar a ação e explicar que o Guia só orienta e navega.
- Se a pergunta exigir params dinâmicos ausentes, orientar e navegar para a tela índice.

O Guia nunca:

- cria, atualiza ou apaga registros;
- envia mensagens, campanhas, eventos ou webhooks;
- chama endpoints de domínio;
- expõe `instruction`, `scaffold`, prompt ou conteúdo interno de código;
- usa transcrição de conversa como contexto.

## 7. Arquivos a criar/editar quando implementar

Backend:

- Criar `app/controllers/api/v1/accounts/autonomia/guide_controller.rb` - endpoint read-only.
- Criar `app/services/autonomia/guide/chat.rb` - orquestra RAG, confidence gate e nav.
- Criar `app/services/autonomia/guide/route_resolver.rb` - valida `nav_target` contra allowlist backend.
- Criar `app/services/autonomia/guide/seed.rb` ou job equivalente - cria agente Guia e sources por conta.
- Editar `config/routes.rb` - adicionar `autonomia/guide`.
- Editar `app/controllers/dashboard_controller.rb` e `app/javascript/shared/store/globalConfig.js` só se for criado um ENV separado. V1 pode evitar isso usando `AUTONOMIA_AGENTS_ENABLED`.
- Editar `app/controllers/api/v1/accounts/autonomia/agents_controller.rb` ou jbuilder/store para esconder agentes `config['system_key'] == 'platform_guide'` do Hub comum.

Frontend:

- Criar `app/javascript/dashboard/components/autonomia/guide/AutonomiaGuideLauncher.vue`.
- Criar `app/javascript/dashboard/components/autonomia/guide/AutonomiaGuideContainer.vue`.
- Criar `app/javascript/dashboard/api/autonomiaGuide.js`.
- Criar `app/javascript/dashboard/store/modules/autonomiaGuide.js`.
- Criar `app/javascript/dashboard/helper/guideRouteRegistry.js`.
- Editar `app/javascript/dashboard/routes/dashboard/Dashboard.vue` para renderizar launcher/container do Guia.
- Editar `app/javascript/shared/constants/busEvents.js` somente na fase 2 de highlight.
- Adicionar chaves em `app/javascript/dashboard/i18n/locale/en/*.json` ou arquivo equivalente usado por este fork. Seguir regra do repo: não atualizar todas as línguas.

KB e seed:

- Seed inicial versionado para dev: `docs/operator-agent-study/guia/kb/guia-produto.md`.
- Template opcional: `docs/operator-agent-study/guia/kb/guia-conta.example.md`.
- Em produção, esses arquivos não são fonte de verdade; o conteúdo editável fica em `autonomia_agent_sources` + ActiveStorage.

Specs:

- Request spec do `guide_controller`: flag off, conta off, usuário comum, resposta grounded, baixa confiança sem nav.
- Service spec de `RouteResolver`: rota válida, rota inexistente, params faltando, route dinâmica com fallback.
- Spec de seed: cria agente internal, sources `guide_scope`, `show_on_hub`/hidden.
- FE unit specs para registry e navegação, se o padrão do projeto permitir.

## 8. Esforço T-shirt

| Peça | Reuso | Novo | Esforço |
|---|---|---|---|
| Seed do agente Guia por conta | `Autonomia::Agents::Agent`, `Source`, jobs de ingestão | system key, ocultar do Hub | M |
| KB produto/conta editável | `SourcesController`, ActiveStorage, `resync` | tela/editor simples para markdown do Guia | M |
| Backend chat read-only | `Retriever`, `ResponsesClient`, `Answerer` | `Guide::Chat`, schema/nav resolver | M |
| Registry de rotas/navegação | `accountScopedRoute`, Vue Router | `guideRouteRegistry`, validação params | S/M |
| Widget global | componentes do copiloto atual | store/API/launcher/container sem conversa | M |
| Gating | `Autonomia::Agents::Config.enabled?`, globalConfig | ajustes para usuário não-admin | S |
| Catálogo dos 50 fluxos | rotas/sidebar reais | redação PT-BR e revisão de KB | M |
| Highlight fase 2 | `mitt`, `BUS_EVENTS` | targets por tela + overlay | M/L |
| Testes | padrões Rails/Vue existentes | mocks de RAG/nav | M |

## 9. Riscos e mitigação

| Risco | Impacto | Mitigação |
|---|---|---|
| Drift de route names após upgrade | Guia navega errado | `guideRouteRegistry` em código + spec/linter que faz `router.resolve` dos names críticos |
| Modelo inventa rota | navegação quebrada | backend/FE só aceitam route names allow-listed |
| Params dinâmicos ausentes | erro em rotas como inbox/team/portal/agente | fallback para rota índice ou pergunta de clarificação |
| Fonte do Guia fica `needs_review` | Guia sem respostas | promover versão só após `accepted`; override admin para KB de sistema |
| Agente Guia aparece no Hub | confusão/admin altera agente errado | `config['hidden_from_hub']` e filtro no index |
| Conteúdo global duplicado por conta | custo de ingestão/atualização | publicar em background e só para contas habilitadas; manter checksum/version em metadata |
| `guia-produto` contradiz `guia-conta` | resposta inconsistente | usar títulos iguais para override, prioridade por `guide_scope=account` no resolver |
| Permissões do usuário | Guia aponta tela inacessível | validar rota/meta no FE e responder "seu perfil pode não ter acesso" |
| Acoplamento ao copiloto de conversa | bug por `currentChat` nulo | store/API separados para Guia |
| Escopo virar operação | risco de escrita | endpoint sem ferramentas de escrita; prompt e service recusam verbos operacionais |

## 10. Plano de fatias

### V0 - Seed técnico e prova de RAG

- Criar manualmente um agente Guia em uma conta dev.
- Subir `guia-produto.md` como source markdown.
- Validar que `Retriever` encontra fluxos por perguntas naturais.
- Ajustar redação do schema para chunking bom.

### V1 - Responder e navegar

Entregável de produto: o usuário abre o Guia em qualquer tela, pergunta "onde fica X / como faço Y", recebe resposta curta e é levado para a rota certa quando houver confiança.

Peças:

- Agente Guia por conta habilitada.
- `guia-produto.md` + `guia-conta.md` como sources editáveis.
- Endpoint `POST /api/v1/accounts/:account_id/autonomia/guide/chat`.
- Widget global do Guia.
- `guideRouteRegistry` com os 50 fluxos.
- Navegação por `accountScopedRoute`.
- Sem highlight.
- Sem operações.

Critério de aceite:

- Flag/conta off: widget escondido e endpoint 404.
- Perguntas conhecidas retornam resposta grounded + route name real.
- Perguntas desconhecidas não navegam e encaminham para suporte/admin.
- Usuário sem permissão recebe orientação sem bypass de rota.

### V1.1 - Atualização sem deploy

- Tela/admin flow para editar ou substituir `guia-produto.md` e `guia-conta.md`.
- Botão "Reingerir".
- Status de ingestão/revisão.
- Publicação global do KB produto para contas habilitadas.

### V2 - Highlight guiado

- `BUS_EVENTS.GUIDE_HIGHLIGHT_TARGET`.
- Targets estáveis em 5 telas prioritárias: importação de base, CRM Kanban, campanhas e-mail, caixas de entrada, Autonomia agents.
- Overlay/realce com timeout e botão limpar.
- Registry de highlight separado de route registry.

### V3 - Diagnóstico read-only

Fora desta fatia, mas complementar: depois que o Guia for confiável em navegação, adicionar diagnósticos R0 da plataforma, sem escritas.

## 11. Veredito

A fatia Guia é tecnicamente de baixo risco se ficar estritamente read-only e usar o RAG existente como fonte editável. O principal cuidado é não confundir três coisas:

- KB configurável é DB/ActiveStorage + ingestão, não conteúdo hardcoded.
- Navegação é route name allow-listed, não ferramenta livre do modelo.
- Guia global não é copiloto de conversa; ele pode reutilizar a UI do copiloto, mas precisa de endpoint/store próprios sem `conversation_id`.

Começar por V1 responder+navegar é a melhor fatia: entrega valor real de suporte, usa os pontos fortes já existentes e não abre superfície de escrita.
