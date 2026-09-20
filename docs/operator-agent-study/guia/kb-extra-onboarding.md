# Guia Autonom.ia - KB extra onboarding e suporte

> **Registro histórico — desenho da V1, read-only.** Este documento descreve o Guia
> como ele foi desenhado em junho de 2026: só leitura, sem consultar os dados da conta
> e sem executar nada. Esse desenho foi substituído pelas issues #533 (o Guia consulta
> o que a conta tem, com a permissão de quem pergunta) e #536 (o Guia executa ações,
> sempre com confirmação na tela). Fica como registro de decisão — não leia como
> descrição do comportamento atual.


Escopo: fluxos complementares de onboarding, meta-ajuda e suporte humano para o Guia Autonom.ia. Este arquivo e conhecimento global do produto, mantido por super-admin, e nao deve conter dados ou segredos de contas.

Base de URL: as rotas do frontend usam `frontendURL(...)`, portanto os paths abaixo ja consideram o prefixo `/app`.

## Route names usados

- `settings_applications` - `/app/accounts/:accountId/settings/integrations`
- `settings_applications_integration` - `/app/accounts/:accountId/settings/integrations/:integration_id`
- `crm_kanban_index` - `/app/accounts/:accountId/crm`
- `onboarding_account_details` - `/app/accounts/:accountId/onboarding`
- `settings_inbox_list` - `/app/accounts/:accountId/settings/inboxes/list`
- `settings_inbox_new` - `/app/accounts/:accountId/settings/inboxes/new`
- `settings_inboxes_page_channel` - `/app/accounts/:accountId/settings/inboxes/new/:sub_page`
- `settings_inboxes_add_agents` - `/app/accounts/:accountId/settings/inboxes/new/:inbox_id/agents`
- `settings_inbox_finish` - `/app/accounts/:accountId/settings/inboxes/new/:inbox_id/finish`
- `settings_inbox_show` - `/app/accounts/:accountId/settings/inboxes/:inboxId/:tab?`
- `agent_list` - `/app/accounts/:accountId/settings/agents/list`
- `settings_teams_new` - `/app/accounts/:accountId/settings/teams/new`
- `general_settings_index` - `/app/accounts/:accountId/settings/general`
- `profile_settings_index` - `/app/accounts/:accountId/profile/settings`

## Fluxos

### Configurar a chave de IA da plataforma
- intent: Onde coloco a chave da OpenAI?; Como habilito a IA do CRM Kanban?; Por que a IA da Autonom.ia nao funciona?; Onde configuro a IA da plataforma?
- onde_fica: Configuracoes > Integracoes > CRM Kanban AI; depois CRM > CRM Kanban > editar funil > IA
- rota: `settings_applications_integration` - `/app/accounts/:accountId/settings/integrations/:integration_id` com `integration_id=crm_kanban_ai`; relacionado: `crm_kanban_index` - `/app/accounts/:accountId/crm`
- perfil: `administrator` cadastra ou troca a chave da conta. `agent` nao cadastra chave; diga para pedir a um administrator. Custom role `crm_manage_ai` ou `crm_admin` pode ajustar a IA do funil no CRM quando a rota do CRM estiver liberada, mas nao acessa a tela de Integracoes; se nao puder, diga que a credencial precisa ser configurada por um administrator.
- gate: feature flag `integrations`; `CRM_KANBAN_ENABLED=true`; `CRM_AI_ENABLED=true`; app de integracao `crm_kanban_ai` ativo; fallback de sistema usa `CAPTAIN_OPEN_AI_API_KEY` e `CAPTAIN_OPEN_AI_ENDPOINT` em `InstallationConfig`; Autonom.ia tambem exige `AUTONOMIA_AGENTS_ENABLED=true` e conta habilitada.
- pre_requisitos: chave OpenAI valida; acesso de administrator; opcionalmente API Base URL quando nao usar `https://api.openai.com`.
- passos: 1. Abra Configuracoes > Integracoes; 2. Entre em CRM Kanban AI; 3. Clique para configurar ou adicionar a integracao; 4. Preencha API Key, API Base URL se necessario e mantenha Enable CRM Kanban AI marcado; 5. Salve e depois abra CRM Kanban para configurar a IA por funil.
- gotchas: a integracao generica `openai` nao e a mesma coisa que `crm_kanban_ai`; se ja existir um hook `crm_kanban_ai` vazio ou desativado, ele impede o fallback para a chave global de sistema; a chave global de fallback e configuracao de super-admin, nao da conta; a tela de IA do funil ajusta criterios/auto-move/follow-up, mas nao cria a credencial.
- nav_target: `settings_applications_integration` com `integration_id=crm_kanban_ai`

### Primeiros passos numa conta nova
- intent: O que configurar primeiro numa conta nova?; Qual checklist inicial da plataforma?; Como comecar o onboarding?; Depois de criar a conta, para onde vou?
- onde_fica: Onboarding inicial da conta; depois Sidebar > Configuracoes e Sidebar > CRM
- rota: `onboarding_account_details` - `/app/accounts/:accountId/onboarding`; relacionados: `settings_inbox_new` - `/app/accounts/:accountId/settings/inboxes/new`, `agent_list` - `/app/accounts/:accountId/settings/agents/list`, `settings_teams_new` - `/app/accounts/:accountId/settings/teams/new`, `settings_inbox_show` - `/app/accounts/:accountId/settings/inboxes/:inboxId/:tab?`, `general_settings_index` - `/app/accounts/:accountId/settings/general`
- perfil: `administrator` faz o checklist completo. `agent` e custom roles nao criam caixas, agentes, times ou configuracoes da conta; diga que eles podem ajustar perfil/notificacoes e pedir ao administrator para concluir o onboarding. Custom roles com permissoes operacionais podem usar as telas liberadas depois que a conta estiver configurada.
- gate: `onboarding_account_details` aceita `administrator`, `agent` e `custom_role`; criacao de canais exige feature `inbox_management`; convite de agentes exige `agent_management`; times exigem `team_management`; IA/CRM exigem `CRM_KANBAN_ENABLED=true` e, para IA, `CRM_AI_ENABLED=true`.
- pre_requisitos: nenhum; para conectar canais, ter credenciais do canal escolhido.
- passos: 1. Complete os dados da conta, idioma, fuso e site no onboarding; 2. Crie a primeira caixa de entrada; 3. Convide agentes e associe-os a caixa; 4. Configure horario de atendimento e mensagens basicas da caixa; 5. Crie times ou filas se a operacao tiver mais de uma equipe; 6. Configure a chave de IA/CRM se a conta usar Kanban ou agentes Autonom.ia.
- gotchas: sem agentes vinculados a caixa, usuarios podem nao ver conversas do canal; horario de atendimento fica dentro da caixa, nao nas configuracoes gerais; agents/custom roles veem menos itens na sidebar porque a navegacao respeita permissoes reais.
- nav_target: `settings_inbox_new`

### Visao geral dos canais
- intent: Qual canal devo conectar?; Como conecto WhatsApp, Instagram ou email?; Onde crio live-chat do site?; Como comeco com Telegram ou API?
- onde_fica: Configuracoes > Caixas de entrada > Nova caixa
- rota: `settings_inbox_new` - `/app/accounts/:accountId/settings/inboxes/new`; canal especifico: `settings_inboxes_page_channel` - `/app/accounts/:accountId/settings/inboxes/new/:sub_page` com `sub_page=whatsapp`, `whatsapp_api`, `instagram`, `email`, `website`, `telegram` ou `api`
- perfil: `administrator` cria canais e conclui o wizard. `agent` e custom roles nao criam caixas; diga para pedir a um administrator e, se ja houver caixa criada, orientar apenas como acessar conversas permitidas.
- gate: feature flag `inbox_management`; permissao `administrator`; Website exige feature `channel_website`; Email exige `channel_email`; Instagram exige feature `channel_instagram` e `INSTAGRAM_APP_ID`; WhatsApp oficial depende das credenciais Meta/WhatsApp no `window.chatwootConfig`; WhatsApp API depende de `WAHA_API_URL` e `WAHA_API_KEY`; Telegram e API aparecem como canais nativos sem feature especifica de conta.
- pre_requisitos: credenciais do provedor escolhido; para WhatsApp API, numero em formato `55DDNNNNNNNNN`; para Instagram, conta/authorization da Meta; para email, conta Google/Microsoft ou endereco para encaminhamento; para site, dominio do site; para Telegram, token do bot; para API, webhook opcional.
- passos: 1. Abra Nova caixa e escolha o canal; 2. Para WhatsApp oficial, escolha Cloud/Twilio e siga a autorizacao ou configuracao manual; 3. Para WhatsApp API, informe modo humano ou IA, nome da caixa e telefone; 4. Para Instagram, autorize o perfil; para email, escolha Google, Microsoft ou encaminhamento; 5. Para site, Telegram ou API, preencha os campos do canal; 6. Adicione agentes e finalize o wizard.
- gotchas: `settings_inboxes_page_channel` precisa do `sub_page` correto; WhatsApp API nesta fork e o conector WAHA, nao a campanha WhatsApp API; Instagram fica desabilitado se o app id nao estiver configurado; email via Google/Microsoft pode exigir credenciais OAuth; o passo de agentes usa `settings_inboxes_add_agents` e o final usa `settings_inbox_finish`.
- nav_target: `settings_inbox_new`

### Usar o proprio Guia Autonom.ia
- intent: O que o Guia faz?; Voce consegue me levar para uma tela?; O Guia pode configurar por mim?; Como pergunto onde fica uma funcao?
- onde_fica: Widget/atalho global do Guia dentro do dashboard, quando habilitado
- rota: —; o Guia e um assistente global read-only, nao uma pagina de dashboard propria
- perfil: `administrator`, `agent` e custom roles podem perguntar ao Guia quando o recurso estiver habilitado para a conta. Se o usuario pedir uma tela bloqueada para o perfil dele, diga que o perfil atual nao tem acesso, explique o motivo e ofereca caminho alternativo ou orientacao para acionar um administrator.
- gate: `AUTONOMIA_AGENTS_ENABLED=true`; conta com `autonomia_agents_enabled=true` ou habilitacao global por conta; credencial de IA resolvivel pela conta ou sistema; o Guia tambem deve respeitar feature flags e permissoes de cada rota antes de navegar.
- pre_requisitos: usuario autenticado em uma conta ativa; Guia habilitado para a conta.
- passos: 1. Pergunte em linguagem natural onde fica ou como fazer algo; 2. O Guia identifica seu perfil e as flags da conta; 3. Ele responde com o caminho no menu e os pre-requisitos; 4. Quando houver uma rota permitida, ele pode abrir a tela certa; 5. Para acoes sensiveis, ele orienta os passos, mas nao executa por voce.
- gotchas: o Guia e read-only: nao cria, edita, envia, apaga, integra ou desfaz nada; ele nao deve revelar segredos nem burlar permissoes; rotas com parametros, como `:inboxId` ou `:agentId`, precisam de um item real escolhido antes da navegacao; se uma feature estiver desligada, o Guia deve explicar o gate em vez de prometer a tela.
- nav_target: —

### Escalar para suporte humano
- intent: Quando devo falar com suporte humano?; Como abro um chamado?; Onde contato o suporte?; O Guia nao resolveu, o que faco?
- onde_fica: Menu do perfil/avatar > Contate o suporte, quando o item estiver disponivel; em white-label/custom branded, usar o canal de suporte definido pela operacao Autonom.ia
- rota: —; a acao do menu chama `window.$chatwoot.toggle()` e nao tem route name de dashboard
- perfil: `administrator`, `agent` e custom roles podem escalar quando o item estiver visivel. Se o item nao aparecer, diga que o atalho de suporte nao esta habilitado para esta instalacao/perfil e oriente usar o canal humano contratado ou pedir ao administrator/super-admin da plataforma.
- gate: feature flag `contact_chatwoot_support_team`; `CHATWOOT_INBOX_TOKEN` configurado em `GlobalConfig`; widget `$chatwoot` carregado; o item nativo fica oculto em instancia custom branded por `CustomBrandPolicyWrapper`.
- pre_requisitos: usuario logado; widget de suporte instalado e configurado, ou canal externo de suporte informado pela operacao.
- passos: 1. Tente primeiro pedir ao Guia o caminho, gate ou erro observado; 2. Escale se houver bloqueio de permissao, instabilidade, credencial externa, dado divergente ou erro que o Guia nao consegue resolver; 3. Abra o menu do perfil/avatar; 4. Clique em Contate o suporte se aparecer; 5. Informe conta, tela, horario aproximado, mensagem de erro e o que estava tentando fazer.
- gotchas: o Guia nao abre chamado por conta propria; em white-label o item nativo de suporte pode ficar escondido mesmo com a feature ligada; nao envie senhas, tokens, chaves OpenAI, credenciais de S3/SMTP ou dados sensiveis em texto aberto.
- nav_target: —
