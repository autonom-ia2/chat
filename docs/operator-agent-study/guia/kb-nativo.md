# Guia Autonom.ia - KB nativo Chatwoot

> **Registro histórico — desenho da V1, read-only.** Este documento descreve o Guia
> como ele foi desenhado em junho de 2026: só leitura, sem consultar os dados da conta
> e sem executar nada. Esse desenho foi substituído pelas issues #533 (o Guia consulta
> o que a conta tem, com a permissão de quem pergunta) e #536 (o Guia executa ações,
> sempre com confirmação na tela). Fica como registro de decisão — não leia como
> descrição do comportamento atual.


Escopo: fluxos nativos mais usados do dashboard Chatwoot nesta fork. Este arquivo deve ser ingerido como conhecimento editavel/atualizavel no RAG do Guia Autonom.ia; nao e logica de produto.

Base de URL: as rotas do frontend usam `frontendURL(...)`, portanto os paths abaixo ja consideram o prefixo `/app`.

## Features e flags observadas

- Feature flags Chatwoot usadas nos fluxos nativos: `crm`, `inbox_management`, `agent_management`, `team_management`, `labels`, `automations`, `canned_responses`, `macros`, `integrations`, `reports`, `custom_roles`, `sla`.
- Permissoes de conversa usadas nas rotas: `administrator`, `agent`, `conversation_manage`, `conversation_unassigned_manage`, `conversation_participating_manage`.
- Outras permissoes usadas nas rotas: `contact_manage`, `report_manage`, `knowledge_base_manage`.
- Flags ENV/globalConfig observadas nesta fork: `CRM_KANBAN_ENABLED`, `CRM_CALENDAR_MEETINGS_ENABLED`, `AUTONOMIA_AGENTS_ENABLED`, `EMAIL_CAMPAIGN_ENABLED`, `CAMPAIGN_IMPORT_ENABLED`, `WHATSAPP_API_CAMPAIGNS_ENABLED`.
- Observacao: `CAMPAIGN_IMPORT_ENABLED`, `EMAIL_CAMPAIGN_ENABLED`, `WHATSAPP_API_CAMPAIGNS_ENABLED` e `AUTONOMIA_AGENTS_ENABLED` controlam recursos custom/nao-core. Nos fluxos nativos abaixo, aparecem apenas como gotcha quando ajudam a evitar confusao.

## Route names usados

- `settings_inbox_new` - `/app/accounts/:accountId/settings/inboxes/new`
- `settings_inbox_show` - `/app/accounts/:accountId/settings/inboxes/:inboxId/:tab?`
- `home` - `/app/accounts/:accountId/dashboard`
- `inbox_conversation` - `/app/accounts/:accountId/conversations/:conversation_id`
- `inbox_dashboard` - `/app/accounts/:accountId/inbox/:inbox_id`
- `label_conversations` - `/app/accounts/:accountId/label/:label`
- `team_conversations` - `/app/accounts/:accountId/team/:teamId`
- `folder_conversations` - `/app/accounts/:accountId/custom_view/:id`
- `conversation_mentions` - `/app/accounts/:accountId/mentions/conversations`
- `conversation_unattended` - `/app/accounts/:accountId/unattended/conversations`
- `contacts_dashboard_index` - `/app/accounts/:accountId/contacts`
- `contacts_dashboard_segments_index` - `/app/accounts/:accountId/contacts/segments/:segmentId`
- `contacts_dashboard_labels_index` - `/app/accounts/:accountId/contacts/labels/:label`
- `agent_list` - `/app/accounts/:accountId/settings/agents/list`
- `custom_roles_list` - `/app/accounts/:accountId/settings/custom-roles/list`
- `settings_teams_new` - `/app/accounts/:accountId/settings/teams/new`
- `automation_list` - `/app/accounts/:accountId/settings/automation/list`
- `canned_list` - `/app/accounts/:accountId/settings/canned-response/list`
- `macros_new` - `/app/accounts/:accountId/settings/macros/new`
- `account_overview_reports` - `/app/accounts/:accountId/reports/overview`
- `conversation_reports` - `/app/accounts/:accountId/reports/conversation`
- `agent_reports_index` - `/app/accounts/:accountId/reports/agents_overview`
- `inbox_reports_index` - `/app/accounts/:accountId/reports/inboxes_overview`
- `team_reports_index` - `/app/accounts/:accountId/reports/teams_overview`
- `label_reports_index` - `/app/accounts/:accountId/reports/labels_overview`
- `sla_reports` - `/app/accounts/:accountId/reports/sla`
- `general_settings_index` - `/app/accounts/:accountId/settings/general`
- `profile_settings_index` - `/app/accounts/:accountId/profile/settings`
- `settings_integrations_webhook` - `/app/accounts/:accountId/settings/integrations/webhook`
- `settings_applications` - `/app/accounts/:accountId/settings/integrations`

### Criar caixa de entrada
- intent: Como crio uma caixa de entrada?; Onde adiciono um novo canal?; Quero conectar um WhatsApp, email, site ou API.; Como comeco um inbox novo?
- onde_fica: Configuracoes > Caixas de entrada > Nova caixa
- rota: `settings_inbox_new` - `/app/accounts/:accountId/settings/inboxes/new`
- gate: feature flag `inbox_management`; papel `administrator`
- pre_requisitos: ter credenciais/dados do canal escolhido quando o canal exigir
- passos: 1. Abra Configuracoes; 2. Entre em Caixas de entrada; 3. Clique em adicionar nova caixa; 4. Escolha o tipo de canal; 5. Preencha os dados e avance para agentes/finalizacao.
- gotchas: cada canal pede dados diferentes; canais sociais/email podem exigir autorizacao externa; a etapa final pode mostrar webhook, script ou instrucoes de DNS.
- nav_target: `settings_inbox_new`

### Editar configuracoes da caixa
- intent: Onde altero uma caixa existente?; Como mudo nome, saudacao ou configuracoes do inbox?; Onde vejo as abas de configuracao da caixa?
- onde_fica: Configuracoes > Caixas de entrada > selecionar caixa
- rota: `settings_inbox_show` - `/app/accounts/:accountId/settings/inboxes/:inboxId/:tab?`
- gate: feature flag `inbox_management`; papel `administrator`
- pre_requisitos: caixa de entrada ja criada
- passos: 1. Abra Configuracoes; 2. Entre em Caixas de entrada; 3. Selecione a caixa; 4. Use as abas de configuracao; 5. Atualize os campos necessarios e salve.
- gotchas: a rota usa `:tab?`; abas como `configuration`, `collaborators`, `business-hours` e `inbox-settings` aparecem conforme o tipo de canal.
- nav_target: `settings_inbox_show`

### Gerenciar agentes da caixa
- intent: Como coloco agentes em uma caixa?; Onde removo um agente do inbox?; Por que um agente nao ve uma caixa?; Como ajusto autoatribuicao da caixa?
- onde_fica: Configuracoes > Caixas de entrada > selecionar caixa > Colaboradores
- rota: `settings_inbox_show` - `/app/accounts/:accountId/settings/inboxes/:inboxId/collaborators`
- gate: feature flag `inbox_management`; papel `administrator`
- pre_requisitos: caixa criada; agentes convidados/ativos na conta
- passos: 1. Abra a caixa em Configuracoes; 2. Entre na aba Colaboradores; 3. Marque ou desmarque agentes; 4. Ajuste as opcoes de atribuicao quando necessario; 5. Salve.
- gotchas: o agente precisa estar ativo na conta; sem estar associado a caixa, ele pode nao receber/visualizar conversas daquele canal.
- nav_target: `settings_inbox_show`

### Definir horario de atendimento da caixa
- intent: Onde configuro horario comercial?; Como mudo dias e horas de atendimento?; Como configuro disponibilidade da caixa?
- onde_fica: Configuracoes > Caixas de entrada > selecionar caixa > Horario de atendimento
- rota: `settings_inbox_show` - `/app/accounts/:accountId/settings/inboxes/:inboxId/business-hours`
- gate: feature flag `inbox_management`; papel `administrator`
- pre_requisitos: caixa criada
- passos: 1. Abra a caixa em Configuracoes; 2. Entre na aba Horario de atendimento; 3. Ative/ajuste os dias da semana; 4. Configure faixas de horario; 5. Salve.
- gotchas: mensagens e automacoes podem considerar a disponibilidade da caixa; confira fuso horario e intervalos antes de salvar.
- nav_target: `settings_inbox_show`

### Atribuir conversa
- intent: Como atribuo uma conversa a alguem?; Onde passo atendimento para outro agente?; Como atribuo a conversa a um time?
- onde_fica: Conversas > abrir conversa > painel de acoes/atribuicao
- rota: `inbox_conversation` - `/app/accounts/:accountId/conversations/:conversation_id`
- gate: permissoes de conversa: `administrator`, `agent`, `conversation_manage`, `conversation_unassigned_manage`, `conversation_participating_manage`
- pre_requisitos: conversa existente; agente/time disponivel e com acesso ao inbox
- passos: 1. Abra a conversa; 2. Localize o bloco de atribuicao no painel lateral; 3. Escolha agente ou time; 4. Confirme a mudanca; 5. Verifique se o nome aparece na conversa.
- gotchas: agentes sem acesso ao inbox podem nao aparecer; usuarios com permissao restrita podem nao conseguir atuar em conversas de terceiros.
- nav_target: `inbox_conversation`

### Resolver conversa
- intent: Como marco conversa como resolvida?; Onde encerro um atendimento?; Como tiro uma conversa da fila aberta?
- onde_fica: Conversas > abrir conversa > botao/status de resolver
- rota: `inbox_conversation` - `/app/accounts/:accountId/conversations/:conversation_id`
- gate: permissoes de conversa: `administrator`, `agent`, `conversation_manage`, `conversation_unassigned_manage`, `conversation_participating_manage`
- pre_requisitos: conversa aberta ou pendente
- passos: 1. Abra a conversa; 2. Revise se nao ha pendencias; 3. Clique para marcar como resolvida; 4. Confirme se a conversa saiu da lista de abertas; 5. Reabra se precisar continuar atendimento.
- gotchas: configuracoes de auto-resolucao podem resolver conversas por inatividade; resolver nao apaga o historico.
- nav_target: `inbox_conversation`

### Adiar conversa
- intent: Como faco snooze de uma conversa?; Onde adio um atendimento?; Quero que a conversa volte depois.; Como removo da fila ate uma data?
- onde_fica: Conversas > abrir conversa > acoes da conversa > Snooze/Adiar
- rota: `inbox_conversation` - `/app/accounts/:accountId/conversations/:conversation_id`
- gate: permissoes de conversa: `administrator`, `agent`, `conversation_manage`, `conversation_unassigned_manage`, `conversation_participating_manage`
- pre_requisitos: conversa existente
- passos: 1. Abra a conversa; 2. Use a acao de adiar/snooze; 3. Escolha um preset ou data/hora; 4. Confirme; 5. Acompanhe quando ela voltar para a fila.
- gotchas: conversa adiada pode sumir da lista principal ate o horario escolhido; use filtros/status se precisar encontra-la antes.
- nav_target: `inbox_conversation`

### Alterar prioridade da conversa
- intent: Como marco uma conversa como urgente?; Onde altero prioridade?; Como tiro prioridade alta de uma conversa?
- onde_fica: Conversas > abrir conversa > painel de acoes > prioridade
- rota: `inbox_conversation` - `/app/accounts/:accountId/conversations/:conversation_id`
- gate: permissoes de conversa: `administrator`, `agent`, `conversation_manage`, `conversation_unassigned_manage`, `conversation_participating_manage`
- pre_requisitos: conversa existente
- passos: 1. Abra a conversa; 2. Localize o campo de prioridade; 3. Selecione a prioridade desejada; 4. Aguarde a confirmacao; 5. Use filtros/ordenacao para priorizar a fila.
- gotchas: prioridade organiza a operacao, mas nao altera sozinho SLA, atribuicao ou automacoes ja configuradas.
- nav_target: `inbox_conversation`

### Aplicar etiquetas na conversa
- intent: Como coloco etiqueta em uma conversa?; Onde removo uma tag do atendimento?; Como organizo conversas por etiquetas?
- onde_fica: Conversas > abrir conversa > painel de acoes > etiquetas
- rota: `inbox_conversation` - `/app/accounts/:accountId/conversations/:conversation_id`
- gate: feature flag `labels`; permissoes de conversa
- pre_requisitos: etiqueta criada em Configuracoes > Etiquetas
- passos: 1. Abra a conversa; 2. Clique em etiquetas/labels no painel lateral; 3. Pesquise a etiqueta; 4. Adicione ou remova; 5. Use a sidebar de etiquetas para consultar depois.
- gotchas: etiquetas ocultas ou especificas de importacao custom podem nao aparecer na sidebar; etiquetas de conversa e contato podem ser usadas em contextos diferentes.
- nav_target: `inbox_conversation`

### Filtrar conversas
- intent: Como filtro conversas?; Onde vejo conversas por canal, time ou etiqueta?; Como encontro uma fila especifica?
- onde_fica: Conversas > Todas; tambem na sidebar em Canais, Times e Etiquetas
- rota: `home` - `/app/accounts/:accountId/dashboard`; relacionados: `inbox_dashboard` - `/app/accounts/:accountId/inbox/:inbox_id`, `label_conversations` - `/app/accounts/:accountId/label/:label`, `team_conversations` - `/app/accounts/:accountId/team/:teamId`
- gate: permissoes de conversa
- pre_requisitos: conversas existentes; filtros/canais/times/etiquetas conforme o caso
- passos: 1. Abra Conversas; 2. Use a sidebar para escolher Todas, Canal, Time ou Etiqueta; 3. Ajuste status e filtros da lista; 4. Abra a conversa desejada; 5. Limpe filtros para voltar a visao geral.
- gotchas: rotas de canal/time/etiqueta exigem parametros reais; se nada aparecer, confira permissao, status da conversa e acesso ao inbox.
- nav_target: `home`

### Usar visoes customizadas de conversas
- intent: Onde ficam as pastas de conversas?; Como abro uma visao salva?; Como uso uma custom view de atendimentos?
- onde_fica: Conversas > Pastas/Visoes customizadas
- rota: `folder_conversations` - `/app/accounts/:accountId/custom_view/:id`
- gate: permissoes de conversa; custom view precisa existir e estar disponivel para o usuario
- pre_requisitos: visao customizada de conversa criada
- passos: 1. Abra Conversas; 2. Expanda Pastas/Visoes customizadas na sidebar; 3. Selecione a visao; 4. Revise os filtros aplicados; 5. Abra os atendimentos listados.
- gotchas: se a custom view foi removida ou nao esta disponivel, a rota redireciona para `home`.
- nav_target: `folder_conversations`

### Ver conversas com mencoes
- intent: Onde vejo conversas em que fui mencionado?; Como encontro minhas mencoes?; Onde estao os atendimentos com @?
- onde_fica: Conversas > Mencoes
- rota: `conversation_mentions` - `/app/accounts/:accountId/mentions/conversations`
- gate: permissoes de conversa
- pre_requisitos: haver mencoes em conversas acessiveis ao usuario
- passos: 1. Abra Conversas; 2. Clique em Mencoes na sidebar; 3. Revise a lista; 4. Abra a conversa; 5. Responda ou acompanhe conforme necessario.
- gotchas: mencoes dependem de acesso a conversa; mencoes antigas podem estar em conversas resolvidas ou filtradas.
- nav_target: `conversation_mentions`

### Ver conversas nao atendidas
- intent: Onde vejo conversas sem atendimento?; Como acho conversas nao atribuidas?; Onde esta a fila de nao atendidas?
- onde_fica: Conversas > Nao atendidas
- rota: `conversation_unattended` - `/app/accounts/:accountId/unattended/conversations`
- gate: permissoes de conversa
- pre_requisitos: conversas abertas sem atendimento/atribuicao conforme a regra da plataforma
- passos: 1. Abra Conversas; 2. Clique em Nao atendidas; 3. Revise a fila; 4. Atribua a um agente/time; 5. Responda ou resolva.
- gotchas: automacoes e regras de autoatribuicao podem tirar conversas dessa fila rapidamente.
- nav_target: `conversation_unattended`

### Criar contato
- intent: Como cadastro um contato?; Onde adiciono um cliente manualmente?; Como salvo nome, email e telefone?
- onde_fica: Contatos > Todos os contatos > Adicionar contato
- rota: `contacts_dashboard_index` - `/app/accounts/:accountId/contacts`
- gate: feature flag `crm`; permissoes `administrator`, `agent`, `contact_manage`
- pre_requisitos: nenhum
- passos: 1. Abra Contatos; 2. Clique em Adicionar contato; 3. Preencha nome e dados de contato; 4. Salve; 5. Abra o detalhe do contato se precisar editar mais campos.
- gotchas: email e telefone podem acusar duplicidade; criar contato nao inicia conversa automaticamente.
- nav_target: `contacts_dashboard_index`

### Criar segmento de contatos
- intent: Como salvo um segmento de contatos?; Onde crio uma lista filtrada?; Como separo contatos por criterios?
- onde_fica: Contatos > Todos os contatos > filtros > criar segmento
- rota: `contacts_dashboard_segments_index` - `/app/accounts/:accountId/contacts/segments/:segmentId`
- gate: feature flag `crm`; permissoes `administrator`, `agent`, `contact_manage`
- pre_requisitos: filtros aplicaveis aos contatos; contatos existentes
- passos: 1. Abra Contatos; 2. Abra filtros; 3. Configure as condicoes; 4. Aplique e salve como segmento; 5. Acesse o segmento pela sidebar.
- gotchas: segmentos dependem da query salva; se atributos ou etiquetas mudarem, o resultado do segmento tambem muda.
- nav_target: `contacts_dashboard_segments_index`

### Aplicar etiquetas em contatos
- intent: Como marco contatos com etiqueta?; Onde vejo contatos por tag?; Como aplico etiqueta em varios contatos?
- onde_fica: Contatos > Todos os contatos; ou Contatos > Marcados com
- rota: `contacts_dashboard_labels_index` - `/app/accounts/:accountId/contacts/labels/:label`
- gate: feature flag `crm`; feature flag `labels`; permissoes `administrator`, `agent`, `contact_manage`
- pre_requisitos: etiqueta criada; contatos existentes
- passos: 1. Abra Contatos; 2. Selecione um ou mais contatos; 3. Use a barra de acoes em massa; 4. Adicione ou remova etiquetas; 5. Abra Marcados com para ver a lista por etiqueta.
- gotchas: a sidebar mostra etiquetas visiveis; etiquetas ocultas criadas por recursos custom podem nao aparecer como filtro visual.
- nav_target: `contacts_dashboard_labels_index`

### Importar contatos por CSV
- intent: Como importo contatos?; Onde subo uma planilha CSV de contatos?; Como faco importacao nativa de contatos?
- onde_fica: Contatos > Todos os contatos > menu de acoes > Importar contatos
- rota: `contacts_dashboard_index` - `/app/accounts/:accountId/contacts`
- gate: feature flag `crm`; permissoes `administrator`, `agent`, `contact_manage`
- pre_requisitos: arquivo CSV no formato esperado; dados minimos de contato
- passos: 1. Abra Contatos; 2. Clique em Importar contatos; 3. Baixe o CSV de exemplo se precisar; 4. Escolha o arquivo CSV; 5. Confirme a importacao e aguarde notificacao por email.
- gotchas: este e o import nativo de contatos por CSV; nao confundir com Importar base de campanha, que e recurso custom controlado por `CAMPAIGN_IMPORT_ENABLED`.
- nav_target: `contacts_dashboard_index`

### Convidar e gerenciar agentes
- intent: Como convido um agente?; Onde vejo usuarios da conta?; Como desativo ou edito um agente?
- onde_fica: Configuracoes > Agentes
- rota: `agent_list` - `/app/accounts/:accountId/settings/agents/list`
- gate: feature flag `agent_management`; papel `administrator`
- pre_requisitos: email do agente; limite/plano permitir novo usuario quando aplicavel
- passos: 1. Abra Configuracoes; 2. Entre em Agentes; 3. Clique para adicionar/editar agente; 4. Informe dados e papel; 5. Salve e acompanhe convite/status.
- gotchas: agente convidado pode precisar aceitar convite antes de operar; acesso a inbox tambem depende de associacao na caixa.
- nav_target: `agent_list`

### Ajustar papel do agente
- intent: Como faco alguem virar administrador?; Onde mudo papel de agente?; Como aplico um papel customizado a um usuario?
- onde_fica: Configuracoes > Agentes > editar agente
- rota: `agent_list` - `/app/accounts/:accountId/settings/agents/list`
- gate: feature flag `agent_management`; papel `administrator`; custom roles exigem `custom_roles`
- pre_requisitos: agente existente; papel customizado criado quando for usar custom role
- passos: 1. Abra Configuracoes > Agentes; 2. Edite o agente; 3. Escolha `administrator`, `agent` ou papel customizado; 4. Salve; 5. Revise acesso a caixas/times se necessario.
- gotchas: papel da conta nao substitui associacao a inbox; custom roles so aparecem em instalacoes Cloud/Enterprise com feature `custom_roles`.
- nav_target: `agent_list`

### Criar papeis customizados
- intent: Como crio um papel customizado?; Onde configuro permissoes granulares?; Como limito acesso de um usuario?
- onde_fica: Configuracoes > Papeis customizados
- rota: `custom_roles_list` - `/app/accounts/:accountId/settings/custom-roles/list`
- gate: feature flag `custom_roles`; instalacao `cloud` ou `enterprise`; papel `administrator`
- pre_requisitos: Enterprise/Cloud habilitado; saber quais permissoes o grupo deve receber
- passos: 1. Abra Configuracoes; 2. Entre em Papeis customizados; 3. Crie ou edite um papel; 4. Marque permissoes como conversa, contato, relatorio ou CRM; 5. Salve e aplique no agente.
- gotchas: a rota nao aparece em instalacao sem suporte Enterprise/Cloud; permissao customizada nao concede automaticamente acesso a todas as caixas.
- nav_target: `custom_roles_list`

### Criar e editar times
- intent: Como crio um time?; Onde adiciono agentes a uma equipe?; Como edito membros de um time?
- onde_fica: Configuracoes > Times
- rota: `settings_teams_new` - `/app/accounts/:accountId/settings/teams/new`
- gate: feature flag `team_management`; papel `administrator`
- pre_requisitos: agentes ativos para adicionar ao time
- passos: 1. Abra Configuracoes > Times; 2. Clique em criar time; 3. Defina nome/descricao; 4. Adicione agentes; 5. Finalize e use o time em atribuicoes/filtros.
- gotchas: times ajudam em atribuicao e filtro, mas agentes ainda precisam ter acesso aos inboxes usados.
- nav_target: `settings_teams_new`

### Criar automacoes
- intent: Como crio uma automacao?; Onde configuro regras automaticas?; Como atribuir, etiquetar ou enviar mensagem automaticamente?
- onde_fica: Configuracoes > Automacao
- rota: `automation_list` - `/app/accounts/:accountId/settings/automation/list`
- gate: feature flag `automations`; papel `administrator`
- pre_requisitos: definir gatilho, condicoes e acoes; labels/times/agentes criados quando usados
- passos: 1. Abra Configuracoes > Automacao; 2. Crie uma regra; 3. Escolha o evento gatilho; 4. Configure condicoes; 5. Escolha acoes e salve.
- gotchas: automacoes podem se sobrepor; revise ordem, condicoes e efeitos como atribuir time, adicionar etiqueta ou enviar webhook.
- nav_target: `automation_list`

### Criar respostas prontas
- intent: Como crio uma resposta pronta?; Onde cadastro um texto padrao?; Como uso slash command no atendimento?
- onde_fica: Configuracoes > Respostas prontas
- rota: `canned_list` - `/app/accounts/:accountId/settings/canned-response/list`
- gate: feature flag `canned_responses`; permissoes `administrator`, `agent` ou permissoes de conversa
- pre_requisitos: texto e shortcode definidos
- passos: 1. Abra Configuracoes > Respostas prontas; 2. Clique em adicionar; 3. Defina shortcode e conteudo; 4. Salve; 5. Na conversa, digite `/` e selecione a resposta.
- gotchas: resposta pronta insere texto no composer; revise antes de enviar; shortcodes devem ser faceis de memorizar.
- nav_target: `canned_list`

### Criar macros
- intent: Como crio uma macro?; Onde salvo acoes repetitivas?; Como executo varias acoes em uma conversa?
- onde_fica: Configuracoes > Macros
- rota: `macros_new` - `/app/accounts/:accountId/settings/macros/new`
- gate: feature flag `macros`; permissoes `administrator`, `agent` ou permissoes de conversa
- pre_requisitos: acoes desejadas disponiveis; labels/times/agentes criados quando usados
- passos: 1. Abra Configuracoes > Macros; 2. Clique em nova macro; 3. Defina nome/visibilidade; 4. Adicione acoes; 5. Salve e execute pela conversa quando necessario.
- gotchas: macros publicas podem ser restritas a administradores; macro nao deve ser usada para contornar permissoes de operacao.
- nav_target: `macros_new`

### Ver relatorios
- intent: Onde vejo relatorios?; Como acompanho volume e desempenho?; Onde vejo relatorio por agente, caixa, time ou etiqueta?
- onde_fica: Relatorios > Visao geral / Conversas / Agentes / Caixas / Times / Etiquetas
- rota: `account_overview_reports` - `/app/accounts/:accountId/reports/overview`; relacionados: `conversation_reports` - `/app/accounts/:accountId/reports/conversation`, `agent_reports_index` - `/app/accounts/:accountId/reports/agents_overview`, `inbox_reports_index` - `/app/accounts/:accountId/reports/inboxes_overview`, `team_reports_index` - `/app/accounts/:accountId/reports/teams_overview`, `label_reports_index` - `/app/accounts/:accountId/reports/labels_overview`
- gate: feature flag `reports`; papel `administrator` ou permissao `report_manage`
- pre_requisitos: conversas e eventos suficientes para gerar metricas
- passos: 1. Abra Relatorios; 2. Escolha Visao geral ou outro recorte; 3. Ajuste periodo/filtros; 4. Compare metricas; 5. Abra detalhes quando a tela oferecer drilldown.
- gotchas: rotas especificas tambem existem, como `conversation_reports`; usuarios sem `report_manage` nao acessam relatorios.
- nav_target: `account_overview_reports`

### Ajustar configuracoes da conta
- intent: Onde altero configuracoes da conta?; Como mudo dados gerais da empresa?; Onde configuro comportamento global?
- onde_fica: Configuracoes > Configuracoes da conta
- rota: `general_settings_index` - `/app/accounts/:accountId/settings/general`
- gate: papel `administrator`
- pre_requisitos: nenhum
- passos: 1. Abra Configuracoes; 2. Entre em Configuracoes da conta; 3. Edite os campos gerais; 4. Ajuste opcoes globais disponiveis; 5. Salve.
- gotchas: configuracoes da conta sao diferentes de preferencias pessoais; perfil/notificacoes ficam no menu do usuario.
- nav_target: `general_settings_index`

### Ajustar perfil e notificacoes
- intent: Onde mudo meu perfil?; Como configuro notificacoes?; Como altero assinatura, idioma ou alertas?
- onde_fica: Menu do usuario/perfil > Configuracoes do perfil
- rota: `profile_settings_index` - `/app/accounts/:accountId/profile/settings`
- gate: papeis `administrator`, `agent`, `custom_role`
- pre_requisitos: usuario autenticado
- passos: 1. Abra o menu do usuario; 2. Entre em perfil/configuracoes; 3. Atualize dados pessoais; 4. Ajuste preferencias de notificacao; 5. Salve.
- gotchas: MFA usa a rota `profile_settings_mfa` e so abre quando MFA esta habilitado globalmente; algumas instalacoes podem bloquear atualizacao de perfil.
- nav_target: `profile_settings_index`

### Criar webhooks
- intent: Como crio um webhook?; Onde configuro callback HTTP?; Como assino eventos da conta?
- onde_fica: Configuracoes > Integracoes > Webhook
- rota: `settings_integrations_webhook` - `/app/accounts/:accountId/settings/integrations/webhook`
- gate: feature flag `integrations`; papel `administrator`
- pre_requisitos: endpoint publico HTTPS; saber quais eventos assinar
- passos: 1. Abra Configuracoes > Integracoes; 2. Entre em Webhook; 3. Clique em adicionar novo webhook; 4. Informe nome, endpoint e eventos; 5. Crie e copie o segredo quando exibido.
- gotchas: endpoints privados, locais ou sem HTTPS podem falhar; copie/guarde o segredo para validar assinaturas.
- nav_target: `settings_integrations_webhook`

### Gerenciar integracoes
- intent: Onde conecto Slack, Linear, Notion ou Shopify?; Como vejo integracoes disponiveis?; Onde configuro aplicativos do dashboard?
- onde_fica: Configuracoes > Integracoes
- rota: `settings_applications` - `/app/accounts/:accountId/settings/integrations`
- gate: feature flag `integrations`; papel `administrator`; algumas integracoes tem flags proprias
- pre_requisitos: credenciais/conta externa quando a integracao exigir OAuth ou token
- passos: 1. Abra Configuracoes > Integracoes; 2. Escolha a integracao; 3. Conecte ou configure hooks; 4. Autorize no provedor externo quando solicitado; 5. Salve e teste.
- gotchas: `linear_integration`, `notion_integration`, `shopify_integration` e apps custom podem ter disponibilidade separada; webhook e dashboard apps ficam dentro da mesma area.
- nav_target: `settings_applications`

### Consultar relatorio de SLA
- intent: Onde vejo SLA?; Como acompanho violacoes de SLA?; Onde consulto conversas com prazo vencido?
- onde_fica: Relatorios > SLA
- rota: `sla_reports` - `/app/accounts/:accountId/reports/sla`
- gate: feature flag `reports`; papel `administrator` ou permissao `report_manage`; feature premium `sla` quando a instalacao exigir
- pre_requisitos: SLA configurado e aplicado a conversas; dados de atendimento no periodo escolhido
- passos: 1. Abra Relatorios; 2. Entre em SLA; 3. Ajuste periodo/filtros; 4. Revise metricas e tabela; 5. Abra a conversa quando precisar investigar.
- gotchas: esta rota e de relatorio; criacao/gestao de politicas SLA pode depender de recursos Enterprise ou customizados fora do fluxo nativo.
- nav_target: `sla_reports`
