# Guia Autonom.ia - KB extra nativa Chatwoot

> **Registro histórico — desenho da V1, read-only.** Este documento descreve o Guia
> como ele foi desenhado em junho de 2026: só leitura, sem consultar os dados da conta
> e sem executar nada. Esse desenho foi substituído pelas issues #533 (o Guia consulta
> o que a conta tem, com a permissão de quem pergunta) e #536 (o Guia executa ações,
> sempre com confirmação na tela). Fica como registro de decisão — não leia como
> descrição do comportamento atual.


Escopo: lacunas nativas do dashboard Chatwoot nesta fork, com foco em orientar usuarios por perfil. Este arquivo deve ser ingerido como conhecimento editavel/atualizavel no RAG do Guia Autonom.ia; nao e logica de produto.

Base de URL: as rotas do frontend usam `frontendURL(...)`, portanto os paths abaixo ja consideram o prefixo `/app`.

## Route names usados

- `portals_index` - `/app/accounts/:accountId/portals/:navigationPath`
- `portals_new` - `/app/accounts/:accountId/portals/new`
- `portals_articles_index` - `/app/accounts/:accountId/portals/:portalSlug/:locale/:categorySlug?/articles/:tab?`
- `portals_articles_new` - `/app/accounts/:accountId/portals/:portalSlug/:locale/:categorySlug?/articles/new`
- `portals_articles_edit` - `/app/accounts/:accountId/portals/:portalSlug/:locale/:categorySlug?/articles/:tab?/edit/:articleSlug`
- `portals_categories_index` - `/app/accounts/:accountId/portals/:portalSlug/:locale/categories`
- `portals_categories_articles_index` - `/app/accounts/:accountId/portals/:portalSlug/:locale/categories/:categorySlug/articles`
- `portals_categories_articles_new` - `/app/accounts/:accountId/portals/:portalSlug/:locale/categories/:categorySlug/articles/new`
- `portals_categories_articles_edit` - `/app/accounts/:accountId/portals/:portalSlug/:locale/categories/:categorySlug/articles/:articleSlug`
- `portals_locales_index` - `/app/accounts/:accountId/portals/:portalSlug/locales`
- `portals_settings_index` - `/app/accounts/:accountId/portals/:portalSlug/settings`
- `labels_list` - `/app/accounts/:accountId/settings/labels/list`
- `attributes_list` - `/app/accounts/:accountId/settings/custom-attributes/list`
- `settings_inbox_new` - `/app/accounts/:accountId/settings/inboxes/new`
- `settings_inbox_show` - `/app/accounts/:accountId/settings/inboxes/:inboxId/:tab?`
- `agent_bots` - `/app/accounts/:accountId/settings/agent-bots`
- `settings_applications` - `/app/accounts/:accountId/settings/integrations`
- `settings_applications_integration` - `/app/accounts/:accountId/settings/integrations/:integration_id`
- `settings_integrations_dashboard_apps` - `/app/accounts/:accountId/settings/integrations/dashboard_apps`
- `search` - `/app/accounts/:accountId/search/:tab?`
- `security_settings_index` - `/app/accounts/:accountId/settings/security`
- `profile_settings_index` - `/app/accounts/:accountId/profile/settings`
- `profile_settings_mfa` - `/app/accounts/:accountId/profile/mfa`
- `auditlogs_list` - `/app/accounts/:accountId/settings/audit-logs/list`
- `billing_settings_index` - `/app/accounts/:accountId/settings/billing`

### Gerenciar Central de Ajuda
- intent: Onde fica a Central de Ajuda?; Como crio artigo ou categoria?; Como mudo idioma do portal?; Onde configuro portal de help center?
- onde_fica: Sidebar > Central de Ajuda > Artigos, Categorias, Idiomas ou Configuracoes
- rota: `portals_index` - `/app/accounts/:accountId/portals/:navigationPath`; relacionados: `portals_articles_index`, `portals_articles_new`, `portals_articles_edit`, `portals_categories_index`, `portals_locales_index`, `portals_settings_index`, `portals_new`
- perfil: `administrator`, `agent` ou custom role com `knowledge_base_manage` acessam as rotas de conteudo liberadas pela meta; criar o primeiro portal (`portals_new`) exige `administrator` ou custom role com `knowledge_base_manage`. Se o perfil nao puder, diga que a Central de Ajuda nao esta liberada para aquele usuario e oriente pedir permissao `knowledge_base_manage` ou acesso de administrador.
- gate: feature flag `help_center`
- pre_requisitos: para editar conteudo, portal existente; para publicar em varios idiomas, locales adicionados ao portal
- passos: 1. Abra Central de Ajuda na sidebar; 2. Entre em Artigos para listar, criar, editar, publicar ou filtrar por status; 3. Use Categorias para organizar artigos; 4. Use Idiomas para gerenciar locales do portal; 5. Use Configuracoes para nome, slug, dominio/widget e ajustes do portal.
- gotchas: se nao houver portal, a tela redireciona para `portals_new`; agentes sem permissao de criacao podem precisar de um admin para criar o primeiro portal; a sidebar usa `portals_index` com `navigationPath`, mas a tela final cai nas rotas `portals_*`; dominio customizado/SSL so faz polling em Cloud.
- nav_target: `portals_index`

### Gerenciar catalogo de etiquetas
- intent: Onde crio uma etiqueta nova?; Como edito cor ou nome de uma label?; Como escondo etiqueta da sidebar?; Onde apago uma etiqueta?
- onde_fica: Sidebar > Configuracoes > Etiquetas
- rota: `labels_list` - `/app/accounts/:accountId/settings/labels/list`
- perfil: somente `administrator`. Se o perfil nao puder, diga que ele pode aplicar etiquetas onde tiver acesso, mas criar/editar/excluir o catalogo de etiquetas exige administrador.
- gate: feature flag `labels`
- pre_requisitos: nenhum
- passos: 1. Abra Configuracoes; 2. Entre em Etiquetas; 3. Clique em adicionar etiqueta ou edite uma existente; 4. Preencha nome, descricao, cor e a opcao de exibir na sidebar; 5. Salve ou confirme a exclusao quando necessario.
- gotchas: esta tela gerencia o catalogo, diferente de aplicar etiqueta em conversa/contato; o nome e salvo em lowercase; a opcao `show_on_sidebar` controla se aparece na sidebar; etiquetas ocultas ainda podem existir e ser usadas por fluxos customizados.
- nav_target: `labels_list`

### Gerenciar atributos customizados
- intent: Onde crio campo customizado?; Como adiciono atributo de contato?; Como adiciono atributo de conversa?; Como edito lista de opcoes de um atributo?
- onde_fica: Sidebar > Configuracoes > Atributos customizados
- rota: `attributes_list` - `/app/accounts/:accountId/settings/custom-attributes/list`
- perfil: somente `administrator`. Se o perfil nao puder, diga que ele pode ver/preencher atributos nas telas onde tiver acesso, mas criar/editar/excluir atributos customizados exige administrador.
- gate: feature flag `custom_attributes`; badges de obrigatoriedade de resolucao dependem de `conversation_required_attributes`
- pre_requisitos: definir se o atributo e de conversa ou contato antes de criar
- passos: 1. Abra Configuracoes > Atributos customizados; 2. Escolha a aba Conversa ou Contato; 3. Clique para adicionar atributo; 4. Informe nome, chave, descricao e tipo; 5. Para tipo lista, cadastre as opcoes; para texto, use regex se precisar validar; 6. Salve.
- gotchas: tipos disponiveis: texto, numero, link, data, lista e checkbox; a chave nao pode conter espacos; depois de criado, a chave e o tipo ficam travados para edicao; atributos usados no pre-chat ou como obrigatorios aparecem com badges.
- nav_target: `attributes_list`

### Configurar CSAT da caixa
- intent: Como ativo pesquisa de satisfacao?; Onde configuro CSAT?; Como escolho quando enviar avaliacao?; Como configuro CSAT no WhatsApp?
- onde_fica: Sidebar > Configuracoes > Caixas de entrada > selecionar caixa > CSAT
- rota: `settings_inbox_show` - `/app/accounts/:accountId/settings/inboxes/:inboxId/csat`
- perfil: somente `administrator`. Se o perfil nao puder, diga que configurar CSAT e uma configuracao de caixa e precisa de administrador; o usuario pode apenas consultar relatorios se tiver `report_manage`.
- gate: feature flag `inbox_management`; para analisar template com IA em WhatsApp, feature `captain_integration`; para ver respostas em relatorios, feature `reports`
- pre_requisitos: caixa de entrada existente; etiquetas criadas se a regra de envio for baseada em labels
- passos: 1. Abra a caixa em Configuracoes; 2. Entre na aba CSAT; 3. Ative a pesquisa; 4. Defina tipo de exibicao/mensagem ou template, conforme o canal; 5. Configure a regra por etiquetas; 6. Salve.
- gotchas: CSAT e enviado uma vez por conversa; em canais WhatsApp a tela cria/atualiza template dedicado e mostra status de aprovacao; alterar template existente pode pedir confirmacao; se a regra por label nao bater, a pesquisa nao dispara.
- nav_target: `settings_inbox_show`

### Configurar widget do site
- intent: Como configuro o live-chat do site?; Onde altero cor e texto do widget?; Como ativo formulario pre-chat?; Onde pego o script do widget?
- onde_fica: Sidebar > Configuracoes > Caixas de entrada > caixa de website/live-chat
- rota: `settings_inbox_show` - `/app/accounts/:accountId/settings/inboxes/:inboxId/inbox-settings`; relacionados: `/pre-chat-form`, `/business-hours`, `/configuration` na mesma rota
- perfil: somente `administrator`. Se o perfil nao puder, diga que editar widget, pre-chat, disponibilidade e dominio permitido exige administrador da conta.
- gate: feature flag `inbox_management`; criar novo canal de website exige feature `channel_website`
- pre_requisitos: caixa do tipo Website/live-chat ja criada; para criar uma nova, use `settings_inbox_new`
- passos: 1. Abra Configuracoes > Caixas de entrada e selecione a caixa de website; 2. Em Configuracoes, ajuste nome, titulo, tagline, cor, posicao/tipo do bubble, saudacao e recursos do widget; 3. Em Pre-chat, habilite o formulario e escolha campos; 4. Em Horario de atendimento, configure disponibilidade; 5. Em Configuracao, revise HMAC, dominios permitidos e acesso mobile quando aplicavel.
- gotchas: as abas de widget so aparecem para caixas web widget; restringir dominios bloqueia embeds fora da lista; mobile apps podem precisar da opcao de webview; o script aparece no final da criacao e tambem no preview/configuracao da caixa.
- nav_target: `settings_inbox_show`

### Gerenciar agent bots nativos
- intent: Onde crio um bot nativo?; Como conecto um bot webhook/API?; Como ligo um bot a uma caixa?; Onde configuro Dialogflow?
- onde_fica: Sidebar > Configuracoes > Agent Bots; para conectar na caixa: Configuracoes > Caixas de entrada > selecionar caixa > Bot Configuration
- rota: `agent_bots` - `/app/accounts/:accountId/settings/agent-bots`; relacionados: `settings_inbox_show` - `/app/accounts/:accountId/settings/inboxes/:inboxId/bot-configuration`, `settings_applications_integration` - `/app/accounts/:accountId/settings/integrations/:integration_id`
- perfil: somente `administrator`. Se o perfil nao puder, diga que bots e conexao de bots por caixa sao configuracoes administrativas.
- gate: feature flag `agent_bots`; Dialogflow fica em Integracoes e depende da lista de apps de integracao estar disponivel
- pre_requisitos: endpoint HTTPS do bot webhook/API; caixa criada para conectar o bot; credenciais JSON e Project ID se for Dialogflow
- passos: 1. Abra Agent Bots; 2. Crie ou edite um bot com nome, descricao, avatar e webhook URL; 3. Copie o access token e secret quando forem exibidos; 4. Abra a caixa desejada e entre em Bot Configuration; 5. Selecione o bot e salve; 6. Para Dialogflow, va em Aplicacoes > Dialogflow e conecte a uma caixa.
- gotchas: nesta fork, `agent_bots` cria bot do tipo webhook; Dialogflow nao e criado nessa tela, e sim em Integracoes; bots `system_bot` aparecem na lista mas nao podem ser editados/excluidos; desconectar bot da caixa nao apaga o bot do catalogo.
- nav_target: `agent_bots`

### Usar busca global
- intent: Como busco uma conversa?; Onde procuro mensagens antigas?; Como acho contato pela busca?; Como encontro artigo da Central de Ajuda?
- onde_fica: Barra superior/sidebar > campo de busca ou atalho Cmd/Ctrl+K
- rota: `search` - `/app/accounts/:accountId/search/:tab?`
- perfil: `administrator` e `agent` podem buscar conforme acesso; custom role com `conversation_manage`, `conversation_unassigned_manage` ou `conversation_participating_manage` ve conversas/mensagens; custom role com `contact_manage` ve contatos; custom role com `knowledge_base_manage` ve artigos. Se o perfil nao puder, explique que a busca so mostra tipos de resultado permitidos ao usuario.
- gate: busca basica sem feature flag propria; artigos exigem `help_center`; filtros avancados exigem `advanced_search` em Cloud/Enterprise e aparecem para `administrator`/`agent`
- pre_requisitos: existir dado acessivel ao usuario; para artigos, Central de Ajuda habilitada
- passos: 1. Abra a busca global pela sidebar ou atalho; 2. Digite o termo e pressione enter; 3. Use as abas Tudo, Contatos, Conversas, Mensagens e Artigos conforme aparecerem; 4. Use Ver mais ou Carregar mais quando houver muitos resultados; 5. Abra o item encontrado para navegar ao detalhe.
- gotchas: a aba Tudo mostra apenas alguns resultados por tipo; filtros avancados de data, remetente e inbox so entram no payload quando `advanced_search` esta ativo; resultados seguem permissao e acesso a inbox/contato/artigo.
- nav_target: `search`

### Configurar seguranca da conta e do usuario
- intent: Onde configuro SSO/SAML?; Como ativo MFA?; Onde troco minha senha?; Por que nao vejo seguranca?
- onde_fica: SAML: Sidebar > Configuracoes > Seguranca; senha/MFA: menu de perfil > Configuracoes do perfil
- rota: `security_settings_index` - `/app/accounts/:accountId/settings/security`; relacionados: `profile_settings_index` - `/app/accounts/:accountId/profile/settings`, `profile_settings_mfa` - `/app/accounts/:accountId/profile/mfa`
- perfil: SAML exige `administrator`; senha e MFA ficam disponiveis para `administrator`, `agent` e `custom_role` no perfil proprio. Se o perfil nao puder acessar SAML, diga que SSO e configuracao administrativa; se MFA/senha nao aparecer, orientar a abrir configuracoes do proprio perfil.
- gate: SAML exige feature `saml`, instalacao Cloud/Enterprise e `allowedLoginMethods` contendo `saml`; MFA exige `window.chatwootConfig.isMfaEnabled`; troca de senha nao tem feature flag especifica
- pre_requisitos: para SAML, dados do IdP: SSO URL, certificado e Entity ID; para MFA, aplicativo autenticador; para senha, senha atual
- passos: 1. Para SAML, abra Configuracoes > Seguranca; 2. Ative SAML e preencha SSO URL, IdP Entity ID e certificado; 3. Confira fingerprint, SP Entity ID e mapeamento de atributos; 4. Para senha, abra Perfil > Configuracoes e use Trocar senha; 5. Para MFA, use Gerenciar 2FA, leia o QR Code, valide o codigo e guarde os codigos de backup.
- gotchas: se `saml` estiver desabilitado ou a instalacao nao for Cloud/Enterprise, a rota pode nao aparecer ou mostrar bloqueio; se login SAML nao estiver em `allowedLoginMethods`, a tela mostra mensagem de desabilitado; `profile_settings_mfa` redireciona para perfil quando MFA global esta desligado.
- nav_target: `security_settings_index`

### Consultar logs de auditoria
- intent: Onde vejo log de auditoria?; Como descubro quem alterou algo?; Onde vejo atividades administrativas?; Tem historico com IP?
- onde_fica: Sidebar > Configuracoes > Logs de auditoria
- rota: `auditlogs_list` - `/app/accounts/:accountId/settings/audit-logs/list`
- perfil: somente `administrator`. Se o perfil nao puder, diga que logs de auditoria sao restritos a administradores.
- gate: feature flag `audit_logs`; instalacao Cloud/Enterprise
- pre_requisitos: feature habilitada na conta/plano; haver eventos auditaveis
- passos: 1. Abra Configuracoes; 2. Entre em Logs de auditoria; 3. Revise atividade, horario e IP; 4. Navegue pelas paginas no rodape; 5. Use o texto do evento para identificar agente, recurso e alteracao.
- gotchas: a tela nao tem busca/filtro avancado neste componente; os textos sao gerados por chaves de traducao a partir do payload; se a feature estiver desativada, pode aparecer paywall/bloqueio ou a entrada sumir.
- nav_target: `auditlogs_list`

### Gerenciar aplicacoes e dashboard apps
- intent: Onde configuro integracoes?; Como crio app no painel da conversa?; Como conecto Dialogflow, Slack ou webhook?; O que sao dashboard apps?
- onde_fica: Sidebar > Configuracoes > Integracoes; para apps embutidos: Integracoes > Dashboard Apps
- rota: `settings_applications` - `/app/accounts/:accountId/settings/integrations`; relacionados: `settings_integrations_dashboard_apps` - `/app/accounts/:accountId/settings/integrations/dashboard_apps`, `settings_applications_integration` - `/app/accounts/:accountId/settings/integrations/:integration_id`
- perfil: somente `administrator`. Se o perfil nao puder, diga que integrar aplicativos, webhooks e dashboard apps exige administrador.
- gate: feature flag `integrations`; algumas integracoes individuais dependem de feature/credencial propria, como `linear_integration`, `notion_integration`, `shopify_integration`, `crm_integration` ou credenciais globais
- pre_requisitos: credenciais da integracao ou URL do app; para dashboard app, titulo e URL valida; para Dialogflow, Project ID, JSON de credenciais e caixa de entrada
- passos: 1. Abra Configuracoes > Integracoes; 2. Pesquise a aplicacao desejada; 3. Clique em configurar; 4. Para hooks, preencha credenciais e selecione a caixa quando a integracao for por inbox; 5. Para Dashboard Apps, abra a area propria e cadastre titulo e URL; 6. Salve e teste no contexto da conversa/caixa.
- gotchas: Dashboard App usa conteudo do tipo `frame` com URL valida; Dialogflow e uma integracao por inbox, nao um `agent_bot`; algumas integracoes so aparecem como ativas se houver credencial global ou feature habilitada; remover hook desconecta a integracao.
- nav_target: `settings_applications`

### Ver plano e cobranca
- intent: Onde vejo meu plano?; Como abro cobranca?; Onde compro creditos?; Esta instalacao tem billing?
- onde_fica: Sidebar > Configuracoes > Billing/Cobranca
- rota: `billing_settings_index` - `/app/accounts/:accountId/settings/billing`
- perfil: somente `administrator`. Se o perfil nao puder, diga que plano e cobranca sao restritos a administradores.
- gate: rota limitada a instalacao Cloud; em self-hosted/Enterprise white-label, a tela redireciona para `home` e deve ser tratada como nao-aplicavel; medidores de creditos do Captain dependem de `captain_integration`
- pre_requisitos: conta Cloud com dados de assinatura em `custom_attributes`; para comprar creditos, plano diferente de Hacker
- passos: 1. Abra Configuracoes > Billing; 2. Revise plano atual, quantidade de assentos e renovacao; 3. Use Gerenciar assinatura para abrir o portal de cobranca; 4. Revise creditos/limites do Captain quando aparecerem; 5. Use comprar creditos se o plano permitir.
- gotchas: no fork self-hosted/white-label, considerar nao-aplicavel se `isOnChatwootCloud` for falso; quando nao ha billing plan, a tela tenta atualizar uma vez e pode mostrar mensagem de ausencia de billing; compra de creditos nao aparece no plano Hacker.
- nav_target: `billing_settings_index`
