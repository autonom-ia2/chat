# Guia da Plataforma Autonom.ia — base de conhecimento (163 fluxos)

> ARQUIVO GERADO por `pnpm guia:build`. Não edite à mão: a rota, o endereço e a
> permissão saem do roteador do painel, e o texto humano fica em
> `lib/operator_guide/porques.md`. Editar aqui é trabalho perdido no próximo build.

Cada bloco é um fluxo: intent (perguntas), onde fica, rota e gate (do código), perfil, pré-requisitos, passos, gotchas, nav_target.

### Ver os Primeiros passos
- intent: Por onde eu comeco?; Onde vejo o que falta configurar na conta?; O que eu preciso fazer para a plataforma funcionar?; Cade a lista de primeiros passos?; Como sei se ja terminei a configuracao?
- onde_fica: Menu lateral > Primeiros passos (e tambem a tela inicial da conta enquanto nao ha conversa aberta)
- rota: `first_steps` - `/app/accounts/:accountId/primeiros-passos`
- gate: papel `administrator`
- pre_requisitos: nenhum
- passos: 1. Abra Primeiros passos no menu lateral; 2. Leia o passo em destaque, que e sempre o primeiro que ainda falta; 3. Clique em Fazer agora para ir direto a tela daquele passo; 4. Volte a lista e siga para o proximo.
- gotchas: cada passo so fica Feito quando o estado real da conta muda, nunca por clique; passos opcionais trazem Deixar para depois e podem ser retomados; o passo em foco mostra os pre-requisitos externos (por exemplo, conta na OpenAI com credito); a lista some do centro da tela quando o essencial termina, mas continua no menu.
- nav_target: `first_steps`

### Criar caixa de entrada
- intent: Como crio uma caixa de entrada?; Onde adiciono um novo canal?; Quero conectar um WhatsApp, email, site ou API.; Como comeco um inbox novo?
- onde_fica: Configuracoes > Caixas de entrada > Nova caixa
- rota: `settings_inbox_new` - `/app/accounts/:accountId/settings/inboxes/new`
- gate: feature flag `inbox_management`; papel `administrator` ou `inbox_manage`
- pre_requisitos: ter credenciais/dados do canal escolhido quando o canal exigir
- passos: 1. Abra Configuracoes; 2. Entre em Caixas de entrada; 3. Clique em adicionar nova caixa; 4. Escolha o tipo de canal; 5. Preencha os dados e avance para agentes/finalizacao.
- gotchas: cada canal pede dados diferentes; canais sociais/email podem exigir autorizacao externa; a etapa final pode mostrar webhook, script ou instrucoes de DNS.
- leitura: caixas
- nav_target: `settings_inbox_new`

### Editar configuracoes da caixa
- intent: Onde altero uma caixa existente?; Como mudo nome, saudacao ou configuracoes do inbox?; Onde vejo as abas de configuracao da caixa?
- onde_fica: Configuracoes > Caixas de entrada > selecionar caixa
- rota: `settings_inbox_show` - `/app/accounts/:accountId/settings/inboxes/:inboxId/:tab?`
- gate: feature flag `inbox_management`; papel `administrator` ou `inbox_view` ou `inbox_manage`
- pre_requisitos: caixa de entrada ja criada
- passos: 1. Abra Configuracoes; 2. Entre em Caixas de entrada; 3. Selecione a caixa; 4. Use as abas de configuracao; 5. Atualize os campos necessarios e salve.
- gotchas: a rota usa `:tab?`; abas como `configuration`, `collaborators`, `business-hours` e `inbox-settings` aparecem conforme o tipo de canal.
- leitura: caixas
- nav_target: `settings_inbox_show`

### Gerenciar agentes da caixa
- intent: Como coloco agentes em uma caixa?; Onde removo um agente do inbox?; Por que um agente nao ve uma caixa?; Como ajusto autoatribuicao da caixa?
- onde_fica: Configuracoes > Caixas de entrada > selecionar caixa > Colaboradores
- rota: `settings_inbox_show` - `/app/accounts/:accountId/settings/inboxes/:inboxId/:tab?`
- gate: feature flag `inbox_management`; papel `administrator` ou `inbox_view` ou `inbox_manage`
- pre_requisitos: caixa criada; agentes convidados/ativos na conta
- passos: 1. Abra a caixa em Configuracoes; 2. Entre na aba Colaboradores; 3. Marque ou desmarque agentes; 4. Ajuste as opcoes de atribuicao quando necessario; 5. Salve.
- gotchas: o agente precisa estar ativo na conta; sem estar associado a caixa, ele pode nao receber/visualizar conversas daquele canal.
- nav_target: `settings_inbox_show`

### Definir horario de atendimento da caixa
- intent: Onde configuro horario comercial?; Como mudo dias e horas de atendimento?; Como configuro disponibilidade da caixa?
- onde_fica: Configuracoes > Caixas de entrada > selecionar caixa > Horario de atendimento
- rota: `settings_inbox_show` - `/app/accounts/:accountId/settings/inboxes/:inboxId/:tab?`
- gate: feature flag `inbox_management`; papel `administrator` ou `inbox_view` ou `inbox_manage`
- pre_requisitos: caixa criada
- passos: 1. Abra a caixa em Configuracoes; 2. Entre na aba Horario de atendimento; 3. Ative/ajuste os dias da semana; 4. Configure faixas de horario; 5. Salve.
- gotchas: mensagens e automacoes podem considerar a disponibilidade da caixa; conta nova nasce no fuso da operacao (America/Sao_Paulo por padrao) e a caixa herda esse fuso ao ser criada; a tela mostra o fuso realmente salvo, inclusive UTC; confira fuso horario e intervalos antes de salvar.
- leitura: horario
- nav_target: `settings_inbox_show`

### Atribuir conversa
- intent: Como atribuo uma conversa a alguem?; Onde passo atendimento para outro agente?; Como atribuo a conversa a um time?
- onde_fica: Conversas > abrir conversa > painel de acoes/atribuicao
- rota: `inbox_conversation` - `/app/accounts/:accountId/conversations/:conversation_id`
- gate: papel `administrator` ou `agent` ou `conversation_manage` ou `conversation_unassigned_manage` ou `conversation_participating_manage`
- pre_requisitos: conversa existente; agente/time disponivel e com acesso ao inbox
- passos: 1. Abra a conversa; 2. Localize o bloco de atribuicao no painel lateral; 3. Escolha agente ou time; 4. Confirme a mudanca; 5. Verifique se o nome aparece na conversa.
- gotchas: agentes sem acesso ao inbox podem nao aparecer; usuarios com permissao restrita podem nao conseguir atuar em conversas de terceiros.
- nav_target: `inbox_conversation`

### Resolver conversa
- intent: Como marco conversa como resolvida?; Onde encerro um atendimento?; Como tiro uma conversa da fila aberta?
- onde_fica: Conversas > abrir conversa > botao/status de resolver
- rota: `inbox_conversation` - `/app/accounts/:accountId/conversations/:conversation_id`
- gate: papel `administrator` ou `agent` ou `conversation_manage` ou `conversation_unassigned_manage` ou `conversation_participating_manage`
- pre_requisitos: conversa aberta ou pendente
- passos: 1. Abra a conversa; 2. Revise se nao ha pendencias; 3. Clique para marcar como resolvida; 4. Confirme se a conversa saiu da lista de abertas; 5. Reabra se precisar continuar atendimento.
- gotchas: configuracoes de auto-resolucao podem resolver conversas por inatividade; resolver nao apaga o historico.
- nav_target: `inbox_conversation`

### Adiar conversa
- intent: Como faco snooze de uma conversa?; Onde adio um atendimento?; Quero que a conversa volte depois.; Como removo da fila ate uma data?
- onde_fica: Conversas > abrir conversa > acoes da conversa > Snooze/Adiar
- rota: `inbox_conversation` - `/app/accounts/:accountId/conversations/:conversation_id`
- gate: papel `administrator` ou `agent` ou `conversation_manage` ou `conversation_unassigned_manage` ou `conversation_participating_manage`
- pre_requisitos: conversa existente
- passos: 1. Abra a conversa; 2. Use a acao de adiar/snooze; 3. Escolha um preset ou data/hora; 4. Confirme; 5. Acompanhe quando ela voltar para a fila.
- gotchas: conversa adiada pode sumir da lista principal ate o horario escolhido; use filtros/status se precisar encontra-la antes.
- nav_target: `inbox_conversation`

### Alterar prioridade da conversa
- intent: Como marco uma conversa como urgente?; Onde altero prioridade?; Como tiro prioridade alta de uma conversa?
- onde_fica: Conversas > abrir conversa > painel de acoes > prioridade
- rota: `inbox_conversation` - `/app/accounts/:accountId/conversations/:conversation_id`
- gate: papel `administrator` ou `agent` ou `conversation_manage` ou `conversation_unassigned_manage` ou `conversation_participating_manage`
- pre_requisitos: conversa existente
- passos: 1. Abra a conversa; 2. Localize o campo de prioridade; 3. Selecione a prioridade desejada; 4. Aguarde a confirmacao; 5. Use filtros/ordenacao para priorizar a fila.
- gotchas: prioridade organiza a operacao, mas nao altera sozinho SLA, atribuicao ou automacoes ja configuradas.
- nav_target: `inbox_conversation`

### Aplicar etiquetas na conversa
- intent: Como coloco etiqueta em uma conversa?; Onde removo uma tag do atendimento?; Como organizo conversas por etiquetas?
- onde_fica: Conversas > abrir conversa > painel de acoes > etiquetas
- rota: `inbox_conversation` - `/app/accounts/:accountId/conversations/:conversation_id`
- gate: papel `administrator` ou `agent` ou `conversation_manage` ou `conversation_unassigned_manage` ou `conversation_participating_manage`
- pre_requisitos: etiqueta criada em Configuracoes > Etiquetas
- passos: 1. Abra a conversa; 2. Clique em etiquetas/labels no painel lateral; 3. Pesquise a etiqueta; 4. Adicione ou remova; 5. Use a sidebar de etiquetas para consultar depois.
- gotchas: etiquetas ocultas ou especificas de importacao custom podem nao aparecer na sidebar; etiquetas de conversa e contato podem ser usadas em contextos diferentes.
- nav_target: `inbox_conversation`

### Filtrar conversas
- intent: Como filtro conversas?; Onde vejo conversas por canal, time ou etiqueta?; Como encontro uma fila especifica?
- onde_fica: Conversas > Todas; tambem na sidebar em Canais, Times e Etiquetas
- rota: `home` - `/app/accounts/:accountId/dashboard`
- gate: papel `administrator` ou `agent` ou `conversation_manage` ou `conversation_unassigned_manage` ou `conversation_participating_manage`
- pre_requisitos: conversas existentes; filtros/canais/times/etiquetas conforme o caso
- passos: 1. Abra Conversas; 2. Use a sidebar para escolher Todas, Canal, Time ou Etiqueta; 3. Ajuste status e filtros da lista; 4. Abra a conversa desejada; 5. Limpe filtros para voltar a visao geral.
- gotchas: rotas de canal/time/etiqueta exigem parametros reais; se nada aparecer, confira permissao, status da conversa e acesso ao inbox.
- nav_target: `home`
- highlight: `conversations-advanced-filter`

### Usar visoes customizadas de conversas
- intent: Onde ficam as pastas de conversas?; Como abro uma visao salva?; Como uso uma custom view de atendimentos?
- onde_fica: Conversas > Pastas/Visoes customizadas
- rota: `folder_conversations` - `/app/accounts/:accountId/custom_view/:id`
- gate: papel `administrator` ou `agent` ou `conversation_manage` ou `conversation_unassigned_manage` ou `conversation_participating_manage`
- pre_requisitos: visao customizada de conversa criada
- passos: 1. Abra Conversas; 2. Expanda Pastas/Visoes customizadas na sidebar; 3. Selecione a visao; 4. Revise os filtros aplicados; 5. Abra os atendimentos listados.
- gotchas: se a custom view foi removida ou nao esta disponivel, a rota redireciona para `home`.
- nav_target: `folder_conversations`

### Ver conversas com mencoes
- intent: Onde vejo conversas em que fui mencionado?; Como encontro minhas mencoes?; Onde estao os atendimentos com @?
- onde_fica: Conversas > Mencoes
- rota: `conversation_mentions` - `/app/accounts/:accountId/mentions/conversations`
- gate: papel `administrator` ou `agent` ou `conversation_manage` ou `conversation_unassigned_manage` ou `conversation_participating_manage`
- pre_requisitos: haver mencoes em conversas acessiveis ao usuario
- passos: 1. Abra Conversas; 2. Clique em Mencoes na sidebar; 3. Revise a lista; 4. Abra a conversa; 5. Responda ou acompanhe conforme necessario.
- gotchas: mencoes dependem de acesso a conversa; mencoes antigas podem estar em conversas resolvidas ou filtradas.
- nav_target: `conversation_mentions`

### Ver conversas nao atendidas
- intent: Onde vejo conversas sem atendimento?; Como acho conversas nao atribuidas?; Onde esta a fila de nao atendidas?
- onde_fica: Conversas > Nao atendidas
- rota: `conversation_unattended` - `/app/accounts/:accountId/unattended/conversations`
- gate: papel `administrator` ou `agent` ou `conversation_manage` ou `conversation_unassigned_manage` ou `conversation_participating_manage`
- pre_requisitos: conversas abertas sem atendimento/atribuicao conforme a regra da plataforma
- passos: 1. Abra Conversas; 2. Clique em Nao atendidas; 3. Revise a fila; 4. Atribua a um agente/time; 5. Responda ou resolva.
- gotchas: automacoes e regras de autoatribuicao podem tirar conversas dessa fila rapidamente.
- nav_target: `conversation_unattended`

### Criar contato
- intent: Como cadastro um contato?; Onde adiciono um cliente manualmente?; Como salvo nome, email e telefone?
- onde_fica: Contatos > Todos os contatos > Adicionar contato
- rota: `contacts_dashboard_index` - `/app/accounts/:accountId/contacts`
- gate: feature flag `crm`; papel `administrator` ou `agent` ou `contact_manage` ou `contact_view`
- pre_requisitos: nenhum
- passos: 1. Abra Contatos; 2. Clique em Adicionar contato; 3. Preencha nome e dados de contato; 4. Salve; 5. Abra o detalhe do contato se precisar editar mais campos.
- gotchas: email e telefone podem acusar duplicidade; criar contato nao inicia conversa automaticamente.
- nav_target: `contacts_dashboard_index`
- highlight: `contacts-more-actions`

### Criar segmento de contatos
- intent: Como salvo um segmento de contatos?; Onde crio uma lista filtrada?; Como separo contatos por criterios?
- onde_fica: Contatos > Todos os contatos > filtros > criar segmento
- rota: `contacts_dashboard_segments_index` - `/app/accounts/:accountId/contacts/segments/:segmentId`
- gate: feature flag `crm`; papel `administrator` ou `agent` ou `contact_manage` ou `contact_view`
- pre_requisitos: filtros aplicaveis aos contatos; contatos existentes
- passos: 1. Abra Contatos; 2. Abra filtros; 3. Configure as condicoes; 4. Aplique e salve como segmento; 5. Acesse o segmento pela sidebar.
- gotchas: segmentos dependem da query salva; se atributos ou etiquetas mudarem, o resultado do segmento tambem muda.
- nav_target: `contacts_dashboard_segments_index`

### Aplicar etiquetas em contatos
- intent: Como marco contatos com etiqueta?; Onde vejo contatos por tag?; Como aplico etiqueta em varios contatos?
- onde_fica: Contatos > Todos os contatos; ou Contatos > Marcados com
- rota: `contacts_dashboard_labels_index` - `/app/accounts/:accountId/contacts/labels/:label`
- gate: feature flag `crm`; papel `administrator` ou `agent` ou `contact_manage` ou `contact_view`
- pre_requisitos: etiqueta criada; contatos existentes
- passos: 1. Abra Contatos; 2. Selecione um ou mais contatos; 3. Use a barra de acoes em massa; 4. Adicione ou remova etiquetas; 5. Abra Marcados com para ver a lista por etiqueta.
- gotchas: a sidebar mostra etiquetas visiveis; etiquetas ocultas criadas por recursos custom podem nao aparecer como filtro visual.
- nav_target: `contacts_dashboard_labels_index`

### Importar contatos por CSV
- intent: Como importo contatos?; Onde subo uma planilha CSV de contatos?; Como faco importacao nativa de contatos?
- onde_fica: Contatos > Todos os contatos > menu de acoes > Importar contatos
- rota: `contacts_dashboard_index` - `/app/accounts/:accountId/contacts`
- gate: feature flag `crm`; papel `administrator` ou `agent` ou `contact_manage` ou `contact_view`
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
- highlight: `settings-add-agent`

### Ajustar papel do agente
- intent: Como faco alguem virar administrador?; Onde mudo papel de agente?; Como aplico um papel customizado a um usuario?
- onde_fica: Configuracoes > Agentes > editar agente
- rota: `agent_list` - `/app/accounts/:accountId/settings/agents/list`
- gate: feature flag `agent_management`; papel `administrator`
- pre_requisitos: agente existente; papel customizado criado quando for usar custom role
- passos: 1. Abra Configuracoes > Agentes; 2. Edite o agente; 3. Escolha `administrator`, `agent` ou papel customizado; 4. Salve; 5. Revise acesso a caixas/times se necessario.
- gotchas: papel da conta nao substitui associacao a inbox; custom roles so aparecem em instalacoes Cloud/Enterprise com feature `custom_roles`.
- nav_target: `agent_list`

### Criar papeis customizados
- intent: Como crio um papel customizado?; Onde configuro permissoes granulares?; Como limito acesso de um usuario?
- onde_fica: Configuracoes > Papeis customizados
- rota: `custom_roles_list` - `/app/accounts/:accountId/settings/custom-roles/list`
- gate: feature flag `custom_roles`; papel `administrator`
- pre_requisitos: Enterprise/Cloud habilitado; saber quais permissoes o grupo deve receber
- passos: 1. Abra Configuracoes; 2. Entre em Papeis customizados; 3. Crie ou edite um papel; 4. Marque permissoes como conversa, contato, relatorio ou CRM; 5. Salve e aplique no agente.
- gotchas: a rota nao aparece em instalacao sem suporte Enterprise/Cloud; permissao customizada nao concede automaticamente acesso a todas as caixas.
- nav_target: `custom_roles_list`
- highlight: `settings-add-role`

### Criar e editar times
- intent: Como crio um time?; Onde adiciono agentes a uma equipe?; Como edito membros de um time?
- onde_fica: Configuracoes > Times
- rota: `settings_teams_new` - `/app/accounts/:accountId/settings/teams/new`
- gate: feature flag `team_management`; papel `administrator`
- pre_requisitos: agentes ativos para adicionar ao time
- passos: 1. Abra Configuracoes > Times; 2. Clique em criar time; 3. Defina nome/descricao; 4. Adicione agentes; 5. Finalize e use o time em atribuicoes/filtros.
- gotchas: times ajudam em atribuicao e filtro, mas agentes ainda precisam ter acesso aos inboxes usados.
- leitura: times
- nav_target: `settings_teams_new`
- highlight: `settings-new-team`

### Criar automacoes
- intent: Como crio uma automacao?; Onde configuro regras automaticas?; Como atribuir, etiquetar ou enviar mensagem automaticamente?
- onde_fica: Configuracoes > Automacao
- rota: `automation_list` - `/app/accounts/:accountId/settings/automation/list`
- gate: feature flag `automations`; papel `administrator` ou `automation_view` ou `automation_manage`
- pre_requisitos: definir gatilho, condicoes e acoes; labels/times/agentes criados quando usados
- passos: 1. Abra Configuracoes > Automacao; 2. Crie uma regra; 3. Escolha o evento gatilho; 4. Configure condicoes; 5. Escolha acoes e salve.
- gotchas: automacoes podem se sobrepor; revise ordem, condicoes e efeitos como atribuir time, adicionar etiqueta ou enviar webhook.
- nav_target: `automation_list`
- highlight: `settings-add-automation`

### Criar respostas prontas
- intent: Como crio uma resposta pronta?; Onde cadastro um texto padrao?; Como uso slash command no atendimento?
- onde_fica: Configuracoes > Respostas prontas
- rota: `canned_list` - `/app/accounts/:accountId/settings/canned-response/list`
- gate: feature flag `canned_responses`; papel `agent` ou `administrator` ou `conversation_manage` ou `conversation_unassigned_manage` ou `conversation_participating_manage` ou `canned_response_manage`
- pre_requisitos: texto e shortcode definidos
- passos: 1. Abra Configuracoes > Respostas prontas; 2. Clique em adicionar; 3. Defina shortcode e conteudo; 4. Salve; 5. Na conversa, digite `/` e selecione a resposta.
- gotchas: resposta pronta insere texto no composer; revise antes de enviar; shortcodes devem ser faceis de memorizar.
- nav_target: `canned_list`
- highlight: `settings-add-canned`

### Criar macros
- intent: Como crio uma macro?; Onde salvo acoes repetitivas?; Como executo varias acoes em uma conversa?
- onde_fica: Configuracoes > Macros
- rota: `macros_new` - `/app/accounts/:accountId/settings/macros/new`
- gate: feature flag `macros`; papel `agent` ou `administrator` ou `conversation_manage` ou `conversation_unassigned_manage` ou `conversation_participating_manage` ou `macro_manage`
- pre_requisitos: acoes desejadas disponiveis; labels/times/agentes criados quando usados
- passos: 1. Abra Configuracoes > Macros; 2. Clique em nova macro; 3. Defina nome/visibilidade; 4. Adicione acoes; 5. Salve e execute pela conversa quando necessario.
- gotchas: macros publicas podem ser restritas a administradores; macro nao deve ser usada para contornar permissoes de operacao.
- nav_target: `macros_new`

### Ver relatorios
- intent: Onde vejo relatorios?; Como acompanho volume e desempenho?; Onde vejo relatorio por agente, caixa, time ou etiqueta?
- onde_fica: Relatorios > Visao geral / Conversas / Agentes / Caixas / Times / Etiquetas
- rota: `account_overview_reports` - `/app/accounts/:accountId/reports/overview`
- gate: feature flag `reports`; papel `administrator` ou `report_manage`
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
- highlight: `settings-account-save`

### Ajustar perfil e notificacoes
- intent: Onde mudo meu perfil?; Como configuro notificacoes?; Como altero assinatura, idioma ou alertas?
- onde_fica: Menu do usuario/perfil > Configuracoes do perfil
- rota: `profile_settings_index` - `/app/accounts/:accountId/profile/settings`
- gate: papel `administrator` ou `agent` ou `custom_role`
- pre_requisitos: usuario autenticado
- passos: 1. Abra o menu do usuario; 2. Entre em perfil/configuracoes; 3. Atualize dados pessoais; 4. Ajuste preferencias de notificacao; 5. Salve.
- gotchas: MFA usa a rota `profile_settings_mfa` e so abre quando MFA esta habilitado globalmente; algumas instalacoes podem bloquear atualizacao de perfil.
- nav_target: `profile_settings_index`
- highlight: `profile-update-basic`

### Criar webhooks
- intent: Como crio um webhook?; Onde configuro callback HTTP?; Como assino eventos da conta?
- onde_fica: Configuracoes > Integracoes > Webhook
- rota: `settings_integrations_webhook` - `/app/accounts/:accountId/settings/integrations/webhook`
- gate: feature flag `integrations`; papel `administrator`
- pre_requisitos: endpoint publico HTTPS; saber quais eventos assinar
- passos: 1. Abra Configuracoes > Integracoes; 2. Entre em Webhook; 3. Clique em adicionar novo webhook; 4. Informe nome, endpoint e eventos; 5. Crie e copie o segredo quando exibido.
- gotchas: endpoints privados, locais ou sem HTTPS podem falhar; copie/guarde o segredo para validar assinaturas.
- nav_target: `settings_integrations_webhook`
- highlight: `settings-add-webhook`

### Gerenciar integracoes
- intent: Onde conecto Slack, Linear, Notion ou Shopify?; Como vejo integracoes disponiveis?; Onde configuro aplicativos do dashboard?
- onde_fica: Configuracoes > Integracoes
- rota: `settings_applications` - `/app/accounts/:accountId/settings/integrations`
- gate: feature flag `integrations`; papel `administrator`
- pre_requisitos: credenciais/conta externa quando a integracao exigir OAuth ou token
- passos: 1. Abra Configuracoes > Integracoes; 2. Escolha a integracao; 3. Conecte ou configure hooks; 4. Autorize no provedor externo quando solicitado; 5. Salve e teste.
- gotchas: `linear_integration`, `notion_integration`, `shopify_integration` e apps custom podem ter disponibilidade separada; webhook e dashboard apps ficam dentro da mesma area.
- nav_target: `settings_applications`

### Consultar relatorio de SLA
- intent: Onde vejo SLA?; Como acompanho violacoes de SLA?; Onde consulto conversas com prazo vencido?
- onde_fica: Relatorios > SLA
- rota: `sla_reports` - `/app/accounts/:accountId/reports/sla`
- gate: feature flag `reports`; papel `administrator` ou `report_manage`
- pre_requisitos: SLA configurado e aplicado a conversas; dados de atendimento no periodo escolhido
- passos: 1. Abra Relatorios; 2. Entre em SLA; 3. Ajuste periodo/filtros; 4. Revise metricas e tabela; 5. Abra a conversa quando precisar investigar.
- gotchas: esta rota e de relatorio; criacao/gestao de politicas SLA pode depender de recursos Enterprise ou customizados fora do fluxo nativo.
- nav_target: `sla_reports`
- highlight: `reports-download-sla`

### Abrir o CRM Kanban e filtrar oportunidades
- intent: "Onde vejo o CRM?"; "Como filtro oportunidades?"; "Onde vejo as oportunidades ganhas ou perdidas?"; "Onde vejo o que perdi / o que ganhei?"; "Como alterno entre Kanban, lista e calendário?"
- onde_fica: Sidebar > CRM > CRM Kanban
- rota: `crm_kanban_index` - `/app/accounts/:accountId/crm`
- gate: papel `administrator` ou `agent` ou `crm_view`
- pre_requisitos: ao menos um funil CRM para ver conteúdo; sem funil, a tela mostra estado vazio e botão para criar funil se o usuário puder gerenciar.
- passos: Abra **CRM Kanban**; selecione o funil; use busca, prioridade e follow-up na barra; abra **Filtros** (caixa, responsável, time, estágio, valor, card parado, tipo de vínculo); alterne **Kanban/Lista/Calendário** no seletor superior. Para acompanhar **ganhas/perdidas**: use a visão **Lista** com filtros e veja as métricas de ganhos/perdas no **Dashboard CRM**.
- gotchas: ganhar/perder define o **status** do card (acompanhado no **Dashboard CRM** e na visão **Lista**), diferente do **estágio** do funil; a rota do Calendário é separada, mas o seletor de visualização também existe dentro do Kanban; custom roles sem `crm_view` não veem a entrada; filtros ativos viram chips e podem esconder cards.
- nav_target: `crm_kanban_index`
- highlight: `crm-filters`

### Criar funis, estágios e conectar caixas ao CRM
- intent: "Como crio um funil?"; "Como altero os estágios?"; "Como vinculo uma caixa a um funil?"
- onde_fica: Sidebar > CRM > CRM Kanban > Novo funil ou Editar funil; também CRM Kanban > Configurações da caixa
- rota: `crm_kanban_index` - `/app/accounts/:accountId/crm`
- gate: papel `administrator` ou `agent` ou `crm_view`
- pre_requisitos: caixas já criadas quando o objetivo for vincular atendimento ao funil.
- passos: São duas paradas. 1. Clique em Novo funil, defina nome e estágios e salve — as descrições dos estágios já vêm prontas. 2. Abra Configurar inboxes, ligue o CRM na caixa, escolha o funil e a etapa de entrada e salve; isso já cria o vínculo entre a caixa e o funil, com a criação automática de cards ligada. Não é mais preciso voltar em Editar funil para vincular a caixa.
- gotchas: a criação automática vem marcada na caixa ainda não configurada; trocar o funil da caixa move a criação automática para o funil novo e avisa na tela antes de salvar, e os cards que já existem ficam onde estão; desligar o CRM na caixa para a criação automática; Editar funil > Inbox e automação continua valendo para a caixa que alimenta mais de um funil; deletar estágio abre confirmação e pode falhar se houver cards dependentes; arquivar funil não apaga cards.
- leitura: funis
- nav_target: `crm_kanban_index`
- highlight: `crm-new-pipeline`

### Criar card ou oportunidade no CRM
- intent: "Como crio uma oportunidade?"; "Como adiciono um card no funil?"; "Como associo contato, caixa e responsável?"
- onde_fica: Sidebar > CRM > CRM Kanban > Novo card
- rota: `crm_kanban_index` - `/app/accounts/:accountId/crm`
- gate: papel `administrator` ou `agent` ou `crm_view`
- pre_requisitos: funil e estágio existentes; contato opcional, mas recomendado para histórico e follow-ups.
- passos: Clique em Novo card; preencha título, estágio, valor, prioridade e previsão; busque ou vincule contato; selecione dono, time e caixa quando necessário; salve.
- gotchas: cards sem conversa são "standalone" e podem sumir se o filtro "vinculado" estiver ativo; valores são tratados em centavos no backend e exibidos formatados; a caixa influencia visibilidade para agentes.
- nav_target: `crm_kanban_index`
- highlight: `crm-new-card`

### Mover card, ganhar, perder ou reabrir oportunidade
- intent: "Como movo uma oportunidade de estágio?"; "Como marco como ganha?"; "Como reabro um negócio perdido?"
- onde_fica: Sidebar > CRM > CRM Kanban > abrir card
- rota: `crm_kanban_index` - `/app/accounts/:accountId/crm`
- gate: papel `administrator` ou `agent` ou `crm_view`
- pre_requisitos: card existente em funil ativo.
- passos: Arraste o card entre colunas no Kanban ou abra o drawer; ajuste estágio e responsável; para fechar, use ações de ganhar ou perder; informe valor ganho ou motivo da perda quando solicitado; reabra pelo mesmo drawer quando aplicável.
- gotchas: se o movimento falhar, o front restaura o estado anterior; cards fechados podem aparecer melhor na Lista com filtro de resultado; perder e arquivar não deletam contato nem conversa.
- nav_target: `crm_kanban_index`

### Criar follow-ups e lembretes no CRM
- intent: "Como crio um lembrete?"; "Como programo follow-up de WhatsApp?"; "Como vejo follow-ups atrasados?"
- onde_fica: Sidebar > CRM > CRM Kanban > abrir card > aba Follow-ups; ou CRM > CRM Calendar > clique no dia
- rota: `crm_kanban_index` - `/app/accounts/:accountId/crm`
- gate: papel `administrator` ou `agent` ou `crm_view`
- pre_requisitos: card existente; para follow-up de mensagem, a conversa vinculada precisa existir e a janela/template do canal pode ser exigida.
- passos: Abra o card; entre em Follow-ups; informe título, data/hora e modo de automação; escolha mensagem/template quando houver envio automático; salve; conclua ou cancele pelo card ou calendário.
- gotchas: sem conversa vinculada não há snooze/envio automático; WhatsApp fora da janela pode exigir template; lembretes vencidos aparecem por popup e no filtro de follow-up.
- nav_target: `crm_kanban_index`

### Usar o card CRM a partir de uma conversa
- intent: "Onde está o card CRM desta conversa?"; "Como vinculo atendimento a uma oportunidade?"; "Por que não vejo card no painel da conversa?"
- onde_fica: Conversas > abrir conversa > botão/card CRM no painel lateral; depois CRM > CRM Kanban
- rota: `crm_kanban_index` - `/app/accounts/:accountId/crm`
- gate: papel `administrator` ou `agent` ou `crm_view`
- pre_requisitos: conversa existente; a caixa pode ter auto-criação de card configurada em CRM > Configurações da caixa.
- passos: Abra a conversa; procure o bloco/ação de CRM; crie ou abra o card vinculado; revise contato, responsável e estágio; use o link do card para navegar ao CRM.
- gotchas: se a caixa estiver configurada para não criar card automaticamente, o card não aparece sozinho; em caixas "assigned only", visibilidade pode depender de atribuição/participação; cards standalone não têm conversa para abrir.
- nav_target: `crm_kanban_index`

### Configurar SLA do CRM
- intent: "Onde configuro SLA do CRM?"; "Como defino horários de atendimento?"; "Por que a página de SLA está bloqueada?"
- onde_fica: Sidebar > CRM > CRM SLA
- rota: `crm_sla_index` - `/app/accounts/:accountId/crm/sla`
- gate: papel `administrator` ou `crm_admin`
- pre_requisitos: funis e caixas para associar políticas e agendas.
- passos: Abra CRM SLA; crie/edite políticas de SLA por funil; configure agenda de caixas; salve as janelas de atendimento; volte ao CRM para validar impacto nos cards.
- gotchas: sem feature `sla`, a rota abre paywall e não chama APIs; permissões de relatório não bastam para gerenciar SLA; agenda incorreta gera leitura errada de prazo.
- nav_target: `crm_sla_index`
- highlight: `crm-new-sla`

### Ver dashboard CRM e métricas de funil
- intent: "Onde vejo relatório do CRM?"; "Como acompanho conversão do funil?"; "Como comparo IA e humano?"
- onde_fica: Sidebar > CRM > CRM Dashboard
- rota: `crm_dashboard_index` - `/app/accounts/:accountId/crm/dashboard`
- gate: papel `administrator` ou `agent` ou `crm_view_reports`
- pre_requisitos: ao menos um funil com cards; metas e dados de reuniões aparecem quando houver configuração/dados.
- passos: Abra CRM Dashboard; selecione funil; escolha período; revise KPIs, funil, ganho/perdido, follow-ups, carga por responsável e IA versus humano; use atualizar se dados mudaram.
- gotchas: moedas diferentes não são somadas, são exibidas separadamente; métricas de reunião só carregam com `CRM_CALENDAR_MEETINGS_ENABLED=true`; sem funis a tela fica sem dados.
- nav_target: `crm_dashboard_index`

### Usar calendário CRM e agendar reunião
- intent: "Onde fica o calendário CRM?"; "Como agendo uma reunião no card?"; "Como evitar conflito de agenda?"
- onde_fica: Sidebar > CRM > CRM Calendar; ou CRM Kanban > visualização Calendário
- rota: `crm_calendar_index` - `/app/accounts/:accountId/crm/calendar`
- gate: papel `administrator` ou `agent` ou `crm_view`
- pre_requisitos: caixa de e-mail Google ou Microsoft conectada com calendário ativo; card CRM existente para a reunião.
- passos: Abra CRM Calendar; clique em um dia ou abra um card e escolha agendar reunião; selecione caixa/calendário, data, horário, duração e convidados; confira horários ocupados; confirme.
- gotchas: sem caixa com `calendar_enabled`, o scheduler mostra estado vazio; horários ocupados vêm do free/busy do provedor e podem falhar de forma silenciosa; reuniões arrastadas no calendário não são alteradas sem confirmação, abrem o scheduler de reagendamento.
- nav_target: `crm_calendar_index`

### Configurar link público de agendamento
- intent: "Como crio um link de agenda?"; "Onde configuro /book/:slug?"; "Como cada vendedor tem seu próprio link?"
- onde_fica: Sidebar > CRM > CRM Calendar > Perfis de agendamento
- pre_requisitos: caixa Google/Microsoft com calendário ativo; funil/estágio padrão recomendado; agentes membros da caixa para links por agente.
- passos: Abra CRM Calendar; clique em Perfis de agendamento; habilite o perfil da caixa; defina duração, janela, fuso, dias e horário; escolha modo fixo ou por agente; salve e copie a URL.
- gotchas: no modo por agente, o slug base pode não funcionar e cada agente deve usar seu link individual; a página pública envia e-mail de confirmação antes de criar a reunião; links dependem de `FRONTEND_URL` correto para o e-mail de confirmação.
- nav_target: `crm_calendar_index`

### Sincronizar RSVP, reagendar e registrar no-show
- intent: "Como vejo se o convidado da reunião aceitou ou recusou?"; "Onde vejo o RSVP / confirmação de presença dos convidados da reunião?"; "Como marco no-show (não compareceu)?"; "Como cancelo ou reagendo uma reunião?"; "Status de presença dos convidados da reunião no calendário."
- onde_fica: Sidebar > CRM > CRM Calendar > abrir evento de reunião
- rota: `crm_calendar_index` - `/app/accounts/:accountId/crm/calendar`
- gate: papel `administrator` ou `agent` ou `crm_view`
- pre_requisitos: reunião criada pelo CRM ou pelo link público; calendário conectado ao provedor.
- passos: Abra o evento no calendário; use atualizar RSVP para sincronizar com Google/Microsoft; use Entrar, Abrir card, Reagendar ou Cancelar; após o fim da reunião, marque Realizada ou No-show; adicione notas se realizada.
- gotchas: outcome só aparece depois do horário de término, não durante a reunião; cancelar/reagendar chama o provedor externo e pode falhar por token expirado; resumo por IA depende de `CRM_AI_ENABLED` e credencial configurada.
- nav_target: `crm_calendar_index`

### Criar e verificar identidade de remetente de e-mail
- intent: "Como libero um domínio para disparo?"; "Onde vejo DKIM/SPF/DMARC?"; "Por que não consigo escolher remetente?"
- onde_fica: Sidebar > Campanhas > Campanhas de e-mail > Identidades de remetente
- rota: `campaigns_email_sender_index` - `/app/accounts/:accountId/campaigns/email_sender`
- gate: feature flag `campaigns`; papel `administrator` ou `campaign_view` ou `campaign_manage`
- pre_requisitos: acesso ao DNS do domínio ou caixa webmail conectada para envio direto em baixo volume.
- passos: Abra Identidades de remetente; clique em novo domínio; informe domínio e e-mail opcional; copie os registros DNS; clique em Verificar agora ou aguarde polling; use apenas identidades verificadas na campanha.
- gotchas: domínios pendentes não aparecem como remetente SES; webmail gratuito aparece como opção de envio direto, mas com aviso e limitações; remover identidade em uso retorna erro.
- nav_target: `campaigns_email_sender_index`
- highlight: `campaigns-add-sender`

### Criar campanha de e-mail e importar base
- intent: "Como crio uma campanha de e-mail?"; "Como importo destinatários?"; "Por que o botão de criar está desabilitado?"
- onde_fica: Sidebar > Campanhas > Campanhas de e-mail
- rota: `campaigns_email_index` - `/app/accounts/:accountId/campaigns/email_campaigns`
- gate: feature flag `campaigns`; papel `administrator` ou `campaign_view` ou `campaign_manage`
- pre_requisitos: identidade verificada ou caixa webmail elegível; arquivo CSV/XLSX de destinatários quando houver base externa.
- passos: Clique em Nova campanha; informe nome e remetente; defina nome do remetente, e-mail, reply-to e preheader; anexe CSV/XLSX de base se necessário; salve e abra o editor.
- gotchas: `from_email` precisa pertencer ao domínio SES verificado; envio direto trava o campo "De" com o e-mail da caixa; a importação pode gerar placeholders a partir das colunas da base.
- nav_target: `campaigns_email_index`
- highlight: `campaigns-new-email`

### Montar e-mail com editor, IA e templates
- intent: "Como edito o corpo do e-mail?"; "Onde uso IA para escrever?"; "Como aplicar template?"
- onde_fica: Sidebar > Campanhas > Campanhas de e-mail > Abrir builder
- rota: `campaigns_email_builder` - `/app/accounts/:accountId/campaigns/email_campaigns/:campaignId/builder`
- gate: feature flag `campaigns`; papel `administrator` ou `campaign_view` ou `campaign_manage`
- pre_requisitos: campanha em rascunho; para IA, `CRM_AI_ENABLED=true` e credencial de IA resolvível.
- passos: Abra o builder; escolha IA, galeria de templates ou começar do zero; ajuste assunto no topo; edite blocos e propriedades; use placeholders disponíveis; envie teste e salve.
- gotchas: geração por IA é assíncrona e mostra status `processing/ready/failed`; templates ficam em rota própria `campaigns_email_templates`; enviar teste persiste o corpo antes de disparar.
- nav_target: `campaigns_email_builder`

### Gerenciar destinatários, agendar e enviar campanha de e-mail
- intent: "Como adiciono mais destinatários?"; "Como agendo envio?"; "Quando aparece Enviar agora?"
- onde_fica: Sidebar > Campanhas > Campanhas de e-mail > Gerenciar destinatários
- rota: `campaigns_email_index` - `/app/accounts/:accountId/campaigns/email_campaigns`
- gate: feature flag `campaigns`; papel `administrator` ou `campaign_view` ou `campaign_manage`
- pre_requisitos: campanha em rascunho; corpo HTML salvo para agendar/enviar; destinatários importados.
- passos: Abra Gerenciar destinatários; importe CSV/XLSX adicional se precisar; confira placeholders e validação de template; agende data/hora ou volte ao builder se não houver corpo; na lista, use Enviar agora, Pausar, Retomar ou Cancelar conforme status.
- gotchas: Enviar agora só aparece em rascunho com destinatários e corpo; validação alerta placeholders ausentes ou vazios; a lista faz polling enquanto há campanha `sending`, `scheduled` ou IA processando.
- nav_target: `campaigns_email_index`

### Ver gestão e relatório de campanhas de e-mail
- intent: "Onde vejo a taxa de abertura e de clique das campanhas de e-mail?"; "Onde fica o relatório / métricas das campanhas de e-mail (open rate, click rate)?"; "Como exporto o relatório (CSV) de uma campanha de e-mail?"; "Como comparo o desempenho de campanhas de e-mail?"
- onde_fica: Sidebar > CRM > Gestão de campanhas
- rota: `crm_campaign_management_index` - `/app/accounts/:accountId/crm/campaign-management`
- gate: papel `administrator` ou `campaign_view` ou `campaign_manage`
- pre_requisitos: campanhas de e-mail já enviadas ou com eventos de entrega.
- passos: Abra Gestão de campanhas; filtre por todas ou por uma campanha; revise KPIs de enviado, entregue, abertura aproximada, clique, descadastro, bounce e complaint; ajuste intervalo da linha do tempo; exporte CSV quando uma campanha estiver selecionada.
- gotchas: abertura é aproximada por limitação de tracking; exportar CSV só aparece com campanha específica; esta tela é relatório, não o lugar de editar campanha.
- nav_target: `crm_campaign_management_index`

### Criar campanha WhatsApp API
- intent: "Como disparo campanha pelo WhatsApp API?"; "Onde escolho rótulos de audiência?"; "Como pauso ou cancelo?"
- onde_fica: Sidebar > Campanhas > WhatsApp API
- rota: `campaigns_whatsapp_api_index` - `/app/accounts/:accountId/campaigns/whatsapp_api`
- gate: feature flag `campaigns`; papel `administrator` ou `campaign_view` ou `campaign_manage`
- pre_requisitos: caixa elegível de WhatsApp API; rótulos de contato para audiência; template ou mensagem/mídia.
- passos: Abra WhatsApp API; clique em Nova campanha; selecione caixa; escolha template ou escreva mensagem com variáveis; anexe mídia se precisar; selecione rótulos de audiência; agende e crie.
- gotchas: audiência é por label, não por segmento salvo; uma campanha precisa de mensagem ou mídia; campanhas em `scheduled/running/paused` têm polling e ações de pausar/retomar/cancelar.
- leitura: campanhas
- nav_target: `campaigns_whatsapp_api_index`
- highlight: `campaigns-new-whatsapp`

### Importar base de campanha em Contatos
- intent: "Como importo uma base de campanha?"; "Qual arquivo posso subir?"; "Como divido contatos em lotes?"
- onde_fica: Sidebar > Contatos > Todos os contatos > menu de ações (três pontos) > Importar base
- rota: `contacts_dashboard_index` - `/app/accounts/:accountId/contacts`
- gate: feature flag `crm`; papel `administrator` ou `agent` ou `contact_manage` ou `contact_view`
- pre_requisitos: arquivo CSV ou XLSX com colunas lógicas de nome e telefone; telefones móveis brasileiros; nome da campanha; quantidade de lotes.
- passos: Abra Contatos; clique no menu de ações; escolha Importar base; informe nome da campanha e número de lotes; selecione CSV/XLSX; confirme; acompanhe no histórico.
- gotchas: a UI aceita só `.csv` e `.xlsx`; se houver qualquer linha inválida, nada deve ser importado; fórmulas, telefones fixos, nomes em branco, duplicados no arquivo e limites de tamanho/linhas são rejeitados.
- nav_target: `contacts_dashboard_index`

### Confirmar importação, baixar CSVs e desfazer rótulos
- intent: "Onde vejo histórico de importações?"; "Como confirmo uma base validada?"; "Como removo os rótulos de uma importação?"
- onde_fica: Sidebar > Contatos > Todos os contatos > menu de ações > Histórico; ou URL direta de importações
- rota: `contacts_campaign_imports` - `/app/accounts/:accountId/contacts/campaign-imports`
- gate: feature flag `crm`; papel `administrator` ou `campaign_view` ou `campaign_manage`
- pre_requisitos: importação criada; para desfazer, importação concluída ou concluída com falhas.
- passos: Abra o histórico; aguarde status sair de uploaded/validating/importing; se estiver `ready_to_confirm`, clique Confirmar; baixe CSV de erros, normalizado ou relatório quando disponíveis; em importações concluídas, use Desfazer rótulos.
- gotchas: desfazer remove apenas labels criadas/aplicadas por aquela importação, não deleta contatos; arquivos expiram conforme política de retenção; status em processamento atualiza a cada 5 segundos.
- nav_target: `contacts_campaign_imports`
- highlight: `campaign-imports-back-to-contacts`

### Abrir hub de Agentes Autonom.ia
- intent: "Onde ficam meus agentes?"; "Como crio um agente Autonom.ia?"; "Por que não vejo o menu Agentes?"
- onde_fica: Sidebar > Agentes > Meus agentes
- rota: `autonomia_agents_index` - `/app/accounts/:accountId/agents`
- gate: papel `administrator` ou `autonomia_view` ou `autonomia_manage`
- pre_requisitos: conta habilitada pelo gate isolado; credencial de IA quando a liberação for global por conta.
- passos: Abra Agentes; revise os cards existentes; clique em Criar com IA; para abrir um agente existente, clique no card; use a aba Testar como entrada padrão do painel.
- gotchas: o menu Agentes aparece assim que a chave da OpenAI é conectada em Integracoes, sem precisar recarregar a pagina; backend de agentes é admin-only e retorna 404 quando o gate está off; a sidebar também esconde o grupo para não admins; o card mostra apenas `human_card`, não a instrução interna.
- nav_target: `autonomia_agents_index`
- highlight: `agents-create`

### Criar agente externo com base de conhecimento
- intent: "Como crio um agente para atender clientes?"; "Como subo materiais no construtor?"; "Como conecto no fim?"
- onde_fica: Sidebar > Agentes > Construtor de agente
- rota: `autonomia_agents_builder` - `/app/accounts/:accountId/agents/new`
- gate: papel `administrator` ou `autonomia_manage`
- pre_requisitos: tipo de agente escolhido; materiais opcionais em PDF, TXT, MD, JSON, XLSX ou DOCX; caixa elegível se for conectar ao atendimento.
- passos: Escolha atuação Externa e Com conhecimento; selecione o tipo de agente; responda à entrevista do construtor; anexe arquivos ou adicione links no painel de materiais; avance para revisão; teste e conecte uma caixa.
- gotchas: antes da primeira mensagem pode não existir draft agent, então anexos pedem para iniciar a conversa; links colados no chat não viram fonte automaticamente, aparece sugestão para adicionar; a instrução final só existe depois de finalizar/revisar.
- nav_target: `autonomia_agents_builder`

### Criar agente interno ou sem base
- intent: "Como crio um agente interno para a equipe?"; "Como faço sem base de conhecimento?"; "Esse agente responde clientes?"
- onde_fica: Sidebar > Agentes > Construtor de agente
- rota: `autonomia_agents_builder` - `/app/accounts/:accountId/agents/new`
- gate: papel `administrator` ou `autonomia_manage`
- pre_requisitos: definir atuação Interna ou Sem conhecimento na tela inicial.
- passos: Escolha atuação Interna quando o agente for copiloto da equipe; escolha Sem conhecimento se ele deve partir só da conversa guiada; selecione o tipo ou "Outros"; responda ao construtor; finalize para revisar; abra o painel para testar.
- gotchas: agente interno não conecta em caixa e a aba Canais fica oculta/redireciona; atuação `both` não é escolhida no construtor, é ajuste posterior; sem base reduz respostas ancoradas e pode aumentar handoff por falta de conhecimento.
- nav_target: `autonomia_agents_builder`

### Atualizar conhecimento e fontes do agente
- intent: "Como adiciono conhecimento depois de criado?"; "Como reprocesso uma fonte?"; "Como vejo a qualidade da base?"
- onde_fica: Sidebar > Agentes > Meus agentes > abrir agente > Conhecimento
- rota: `autonomia_agent_panel` - `/app/accounts/:accountId/agents/:agentId/:tab(test|knowledge|channels|performance|tune|publish)?`
- gate: papel `administrator` ou `autonomia_view` ou `autonomia_manage`
- pre_requisitos: agente existente; arquivo suportado ou URL para fonte.
- passos: Abra o agente; entre em Conhecimento; arraste arquivos ou clique Adicionar; escolha link ou arquivo; acompanhe status do revisor e barra de confiança; use Reenviar para reprocessar ou remover para excluir fonte.
- gotchas: remover/adicionar fonte recalcula a confiança e pode atualizar a instrução de agentes finalizados; a aba "Mídias para enviar" só aparece quando existir fonte desse tipo; formatos aceitos no diálogo são `.pdf`, `.txt`, `.md`, `.json`, `.xlsx`, `.docx`.
- nav_target: `autonomia_agent_panel`

### Conectar ou desconectar agente de uma caixa
- intent: "Como coloco o agente para atender uma caixa?"; "Por que uma caixa aparece ocupada?"; "Como desconecto um agente?"
- onde_fica: Sidebar > Agentes > Meus agentes > abrir agente > Canais
- rota: `autonomia_agent_panel` - `/app/accounts/:accountId/agents/:agentId/:tab(test|knowledge|channels|performance|tune|publish)?`
- gate: papel `administrator` ou `autonomia_view` ou `autonomia_manage`
- pre_requisitos: agente ativo/finalizado; caixa elegível; cada caixa pode hospedar apenas um agente.
- passos: Abra o agente; entre em Canais; veja caixas conectadas e elegíveis; clique Conectar em uma caixa livre; para remover, use Desconectar na lista de conectadas.
- gotchas: agentes internos não conectam em caixa; caixas ocupadas aparecem sem botão de conectar; mudar um agente com canais conectados para `internal` pode ser rejeitado pelo backend.
- nav_target: `autonomia_agent_panel`

### Testar, acompanhar e ajustar agente
- intent: "Como testo o agente?"; "Como vejo desempenho?"; "Como ajusto tom, handoff ou instrução?"
- onde_fica: Sidebar > Agentes > Meus agentes > abrir agente > Testar, Performance ou Ajustar
- rota: `autonomia_agent_panel` - `/app/accounts/:accountId/agents/:agentId/:tab(test|knowledge|channels|performance|tune|publish)?`
- gate: papel `administrator` ou `autonomia_view` ou `autonomia_manage`
- pre_requisitos: agente existente; para métricas, conversas/respostas já registradas.
- passos: Use Testar para conversar e ver confiança, handoff e fontes usadas; use Performance para período 7d/30d, respostas, handoff e taxa de conhecimento; use Ajustar para saudação, fallback, tom, estratégia de handoff, limiar de confiança e atuação; em modo guiado, use Re-conversar.
- gotchas: testar agente não finalizado mostra aviso; histórico de teste fica em `sessionStorage` por agente; modo manual expõe instrução, mas não permite salvar instrução vazia; Performance pode ficar vazia até o agente operar de verdade.
- nav_target: `autonomia_agent_panel`

### Usar Copiloto Autonom.ia na conversa
- intent: "Como peço ajuda ao copiloto interno?"; "Por que o botão do copiloto não aparece?"; "Como trocar o agente do copiloto?"
- onde_fica: Dashboard de conversas > botão flutuante de Copiloto Autonom.ia ou painel lateral do copiloto
- pre_requisitos: conversa selecionada; ao menos um agente interno/both ativo e finalizado para a conta.
- passos: Abra uma conversa; acione o painel do Copiloto Autonom.ia; escolha o agente se houver mais de um; pergunte em linguagem natural; use a sugestão/resposta no atendimento quando fizer sentido; resete o thread pelo botão de atualizar.
- gotchas: o launcher some quando o painel já está aberto e também se não houver conversa/estado compatível; o thread reseta ao trocar de conversa para evitar vazamento de contexto; este copiloto é independente do Captain e não exige `captain_integration`.
- nav_target: `inbox_conversation`

### Configurar a chave de IA da plataforma
- intent: Onde coloco a chave da OpenAI?; Como habilito a IA do CRM Kanban?; Por que a IA da Autonom.ia nao funciona?; Onde configuro a IA da plataforma?
- onde_fica: Configuracoes > Integracoes > CRM Kanban AI; depois CRM > CRM Kanban > editar funil > IA
- rota: `settings_applications_integration` - `/app/accounts/:accountId/settings/integrations/:integration_id`
- gate: feature flag `integrations`; papel `administrator`
- perfil: `administrator` cadastra ou troca a chave da conta. `agent` nao cadastra chave; diga para pedir a um administrator. Custom role `crm_manage_ai` ou `crm_admin` pode ajustar a IA do funil no CRM quando a rota do CRM estiver liberada, mas nao acessa a tela de Integracoes; se nao puder, diga que a credencial precisa ser configurada por um administrator.
- pre_requisitos: chave OpenAI valida; acesso de administrator; opcionalmente API Base URL quando nao usar `https://api.openai.com`.
- passos: 1. Abra Configuracoes > Integracoes; 2. Entre em CRM Kanban AI; 3. Clique para configurar ou adicionar a integracao; 4. Preencha API Key e, se precisar, API Base URL: conectar ja liga a IA, nao existe mais caixa Enable CRM Kanban AI no formulario; 5. Salve e depois abra CRM Kanban para configurar a IA por funil.
- gotchas: depois de conectar, a tela da integracao mostra "Conectado e funcionando"; se mostrar "Conectado, mas desligado", a conta ficou com a IA desligada e e preciso desconectar e conectar de novo; chave recusada costuma ser chave errada, revogada ou conta OpenAI sem credito; a integracao generica `openai` nao e a mesma coisa que `crm_kanban_ai`; se ja existir um hook `crm_kanban_ai` vazio ou desativado, ele impede o fallback para a chave global de sistema; a chave global de fallback e configuracao de super-admin, nao da conta; a tela de IA do funil ajusta criterios/auto-move/follow-up, mas nao cria a credencial.
- nav_target: `settings_applications_integration` com `integration_id=crm_kanban_ai`

### Primeiros passos numa conta nova
- intent: O que configurar primeiro numa conta nova?; Qual checklist inicial da plataforma?; Como comecar o onboarding?; Depois de criar a conta, para onde vou?
- onde_fica: Onboarding inicial da conta; depois Sidebar > Configuracoes e Sidebar > CRM
- rota: `onboarding_account_details` - `/app/accounts/:accountId/onboarding`
- gate: papel `administrator` ou `agent` ou `custom_role`
- perfil: `administrator` faz o checklist completo. `agent` e custom roles nao criam caixas, agentes, times ou configuracoes da conta; diga que eles podem ajustar perfil/notificacoes e pedir ao administrator para concluir o onboarding. Custom roles com permissoes operacionais podem usar as telas liberadas depois que a conta estiver configurada.
- pre_requisitos: nenhum; para conectar canais, ter credenciais do canal escolhido.
- passos: 1. Complete os dados da conta, idioma, fuso e site no onboarding; 2. Crie a primeira caixa de entrada; 3. Convide agentes e associe-os a caixa; 4. Configure horario de atendimento e mensagens basicas da caixa; 5. Crie times ou filas se a operacao tiver mais de uma equipe; 6. Configure a chave de IA/CRM se a conta usar Kanban ou agentes Autonom.ia.
- gotchas: sem agentes vinculados a caixa, usuarios podem nao ver conversas do canal; horario de atendimento fica dentro da caixa, nao nas configuracoes gerais; agents/custom roles veem menos itens na sidebar porque a navegacao respeita permissoes reais.
- nav_target: `settings_inbox_new`

### Visao geral dos canais
- intent: Qual canal devo conectar?; Como conecto WhatsApp, Instagram ou email?; Onde crio live-chat do site?; Como comeco com Telegram ou API?
- onde_fica: Configuracoes > Caixas de entrada > Nova caixa
- rota: `settings_inbox_new` - `/app/accounts/:accountId/settings/inboxes/new`
- gate: feature flag `inbox_management`; papel `administrator` ou `inbox_manage`
- perfil: `administrator` cria canais e conclui o wizard. `agent` e custom roles nao criam caixas; diga para pedir a um administrator e, se ja houver caixa criada, orientar apenas como acessar conversas permitidas.
- pre_requisitos: credenciais do provedor escolhido; para WhatsApp API, numero em formato `55DDNNNNNNNNN`; para Instagram, conta/authorization da Meta; para email, conta Google/Microsoft ou endereco para encaminhamento; para site, dominio do site; para Telegram, token do bot; para API, webhook opcional.
- passos: 1. Abra Nova caixa e escolha o canal; 2. Para WhatsApp oficial, escolha Cloud/Twilio e siga a autorizacao ou configuracao manual; 3. Para WhatsApp API, informe modo humano ou IA, nome da caixa e telefone; 4. Para Instagram, autorize o perfil; para email, escolha Google, Microsoft ou encaminhamento; 5. Para site, Telegram ou API, preencha os campos do canal; 6. Adicione agentes e finalize o wizard.
- gotchas: `settings_inboxes_page_channel` precisa do `sub_page` correto; WhatsApp API nesta fork e o conector WAHA, nao a campanha WhatsApp API; Instagram fica desabilitado se o app id nao estiver configurado; email via Google/Microsoft pode exigir credenciais OAuth; o passo de agentes usa `settings_inboxes_add_agents` e o final usa `settings_inbox_finish`.
- nav_target: `settings_inbox_new`

### Usar o proprio Guia Autonom.ia
- intent: O que o Guia faz?; Voce consegue me levar para uma tela?; O Guia pode configurar por mim?; Como pergunto onde fica uma funcao?
- onde_fica: Widget/atalho global do Guia dentro do dashboard, quando habilitado
- perfil: `administrator`, `agent` e custom roles podem perguntar ao Guia quando o recurso estiver habilitado para a conta. Se o usuario pedir uma tela bloqueada para o perfil dele, diga que o perfil atual nao tem acesso, explique o motivo e ofereca caminho alternativo ou orientacao para acionar um administrator.
- pre_requisitos: usuario autenticado em uma conta ativa; Guia habilitado para a conta.
- passos: 1. Pergunte em linguagem natural onde fica ou como fazer algo; 2. O Guia identifica seu perfil e as flags da conta; 3. Ele responde com o caminho no menu e os pre-requisitos; 4. Quando houver uma rota permitida, ele pode abrir a tela certa; 5. Para acoes sensiveis, ele orienta os passos, mas nao executa por voce.
- gotchas: o Guia e read-only: nao cria, edita, envia, apaga, integra ou desfaz nada; ele nao deve revelar segredos nem burlar permissoes; rotas com parametros, como `:inboxId` ou `:agentId`, precisam de um item real escolhido antes da navegacao; se uma feature estiver desligada, o Guia deve explicar o gate em vez de prometer a tela.
- nav_target: —

### Escalar para suporte humano
- intent: Quando devo falar com suporte humano?; Como abro um chamado?; Onde contato o suporte?; O Guia nao resolveu, o que faco?
- onde_fica: Menu do perfil/avatar > Contate o suporte, quando o item estiver disponivel; em white-label/custom branded, usar o canal de suporte definido pela operacao Autonom.ia
- perfil: `administrator`, `agent` e custom roles podem escalar quando o item estiver visivel. Se o item nao aparecer, diga que o atalho de suporte nao esta habilitado para esta instalacao/perfil e oriente usar o canal humano contratado ou pedir ao administrator/super-admin da plataforma.
- pre_requisitos: usuario logado; widget de suporte instalado e configurado, ou canal externo de suporte informado pela operacao.
- passos: 1. Tente primeiro pedir ao Guia o caminho, gate ou erro observado; 2. Escale se houver bloqueio de permissao, instabilidade, credencial externa, dado divergente ou erro que o Guia nao consegue resolver; 3. Abra o menu do perfil/avatar; 4. Clique em Contate o suporte se aparecer; 5. Informe conta, tela, horario aproximado, mensagem de erro e o que estava tentando fazer.
- gotchas: o Guia nao abre chamado por conta propria; em white-label o item nativo de suporte pode ficar escondido mesmo com a feature ligada; nao envie senhas, tokens, chaves OpenAI, credenciais de S3/SMTP ou dados sensiveis em texto aberto.
- nav_target: —

### Gerenciar Central de Ajuda
- intent: Onde fica a Central de Ajuda?; Como crio artigo ou categoria?; Como mudo idioma do portal?; Onde configuro portal de help center?
- onde_fica: Sidebar > Central de Ajuda > Artigos, Categorias, Idiomas ou Configuracoes
- rota: `portals_index` - `/app/accounts/:accountId/portals/:navigationPath`
- gate: feature flag `help_center`; papel `administrator` ou `knowledge_base_manage`
- perfil: `administrator`, `agent` ou custom role com `knowledge_base_manage` acessam as rotas de conteudo liberadas pela meta; criar o primeiro portal (`portals_new`) exige `administrator` ou custom role com `knowledge_base_manage`. Se o perfil nao puder, diga que a Central de Ajuda nao esta liberada para aquele usuario e oriente pedir permissao `knowledge_base_manage` ou acesso de administrador.
- pre_requisitos: para editar conteudo, portal existente; para publicar em varios idiomas, locales adicionados ao portal
- passos: 1. Abra Central de Ajuda na sidebar; 2. Entre em Artigos para listar, criar, editar, publicar ou filtrar por status; 3. Use Categorias para organizar artigos; 4. Use Idiomas para gerenciar locales do portal; 5. Use Configuracoes para nome, slug, dominio/widget e ajustes do portal.
- gotchas: se nao houver portal, a tela redireciona para `portals_new`; agentes sem permissao de criacao podem precisar de um admin para criar o primeiro portal; a sidebar usa `portals_index` com `navigationPath`, mas a tela final cai nas rotas `portals_*`; dominio customizado/SSL so faz polling em Cloud.
- nav_target: `portals_index`

### Gerenciar catalogo de etiquetas
- intent: Onde crio uma etiqueta nova?; Como edito cor ou nome de uma label?; Como escondo etiqueta da sidebar?; Onde apago uma etiqueta?
- onde_fica: Sidebar > Configuracoes > Etiquetas
- rota: `labels_list` - `/app/accounts/:accountId/settings/labels/list`
- gate: feature flag `labels`; papel `administrator` ou `label_manage`
- perfil: somente `administrator`. Se o perfil nao puder, diga que ele pode aplicar etiquetas onde tiver acesso, mas criar/editar/excluir o catalogo de etiquetas exige administrador.
- pre_requisitos: nenhum
- passos: 1. Abra Configuracoes; 2. Entre em Etiquetas; 3. Clique em adicionar etiqueta ou edite uma existente; 4. Preencha nome, descricao, cor e a opcao de exibir na sidebar; 5. Salve ou confirme a exclusao quando necessario.
- gotchas: esta tela gerencia o catalogo, diferente de aplicar etiqueta em conversa/contato; o nome e salvo em lowercase; a opcao `show_on_sidebar` controla se aparece na sidebar; etiquetas ocultas ainda podem existir e ser usadas por fluxos customizados.
- nav_target: `labels_list`
- highlight: `settings-add-label`

### Gerenciar atributos customizados
- intent: Onde crio campo customizado?; Como adiciono atributo de contato?; Como adiciono atributo de conversa?; Como edito lista de opcoes de um atributo?
- onde_fica: Sidebar > Configuracoes > Atributos customizados
- rota: `attributes_list` - `/app/accounts/:accountId/settings/custom-attributes/list`
- gate: feature flag `custom_attributes`; papel `administrator` ou `attribute_manage`
- perfil: somente `administrator`. Se o perfil nao puder, diga que ele pode ver/preencher atributos nas telas onde tiver acesso, mas criar/editar/excluir atributos customizados exige administrador.
- pre_requisitos: definir se o atributo e de conversa ou contato antes de criar
- passos: 1. Abra Configuracoes > Atributos customizados; 2. Escolha a aba Conversa ou Contato; 3. Clique para adicionar atributo; 4. Informe nome, chave, descricao e tipo; 5. Para tipo lista, cadastre as opcoes; para texto, use regex se precisar validar; 6. Salve.
- gotchas: tipos disponiveis: texto, numero, link, data, lista e checkbox; a chave nao pode conter espacos; depois de criado, a chave e o tipo ficam travados para edicao; atributos usados no pre-chat ou como obrigatorios aparecem com badges.
- nav_target: `attributes_list`
- highlight: `settings-add-attribute`

### Configurar CSAT da caixa
- intent: Como ativo pesquisa de satisfacao?; Onde configuro CSAT?; Como escolho quando enviar avaliacao?; Como configuro CSAT no WhatsApp?
- onde_fica: Sidebar > Configuracoes > Caixas de entrada > selecionar caixa > CSAT
- rota: `settings_inbox_show` - `/app/accounts/:accountId/settings/inboxes/:inboxId/:tab?`
- gate: feature flag `inbox_management`; papel `administrator` ou `inbox_view` ou `inbox_manage`
- perfil: somente `administrator`. Se o perfil nao puder, diga que configurar CSAT e uma configuracao de caixa e precisa de administrador; o usuario pode apenas consultar relatorios se tiver `report_manage`.
- pre_requisitos: caixa de entrada existente; etiquetas criadas se a regra de envio for baseada em labels
- passos: 1. Abra a caixa em Configuracoes; 2. Entre na aba CSAT; 3. Ative a pesquisa; 4. Defina tipo de exibicao/mensagem ou template, conforme o canal; 5. Configure a regra por etiquetas; 6. Salve.
- gotchas: CSAT e enviado uma vez por conversa; em canais WhatsApp a tela cria/atualiza template dedicado e mostra status de aprovacao; alterar template existente pode pedir confirmacao; se a regra por label nao bater, a pesquisa nao dispara.
- nav_target: `settings_inbox_show`

### Configurar widget do site
- intent: Como configuro o live-chat do site?; Onde altero cor e texto do widget?; Como ativo formulario pre-chat?; Onde pego o script do widget?
- onde_fica: Sidebar > Configuracoes > Caixas de entrada > caixa de website/live-chat
- rota: `settings_inbox_show` - `/app/accounts/:accountId/settings/inboxes/:inboxId/:tab?`
- gate: feature flag `inbox_management`; papel `administrator` ou `inbox_view` ou `inbox_manage`
- perfil: somente `administrator`. Se o perfil nao puder, diga que editar widget, pre-chat, disponibilidade e dominio permitido exige administrador da conta.
- pre_requisitos: caixa do tipo Website/live-chat ja criada; para criar uma nova, use `settings_inbox_new`
- passos: 1. Abra Configuracoes > Caixas de entrada e selecione a caixa de website; 2. Em Configuracoes, ajuste nome, titulo, tagline, cor, posicao/tipo do bubble, saudacao e recursos do widget; 3. Em Pre-chat, habilite o formulario e escolha campos; 4. Em Horario de atendimento, configure disponibilidade; 5. Em Configuracao, revise HMAC, dominios permitidos e acesso mobile quando aplicavel.
- gotchas: as abas de widget so aparecem para caixas web widget; restringir dominios bloqueia embeds fora da lista; mobile apps podem precisar da opcao de webview; o script aparece no final da criacao e tambem no preview/configuracao da caixa.
- nav_target: `settings_inbox_show`

### Gerenciar agent bots nativos
- intent: Onde crio um bot nativo?; Como conecto um bot webhook/API?; Como ligo um bot a uma caixa?; Onde configuro Dialogflow?
- onde_fica: Sidebar > Configuracoes > Agent Bots; para conectar na caixa: Configuracoes > Caixas de entrada > selecionar caixa > Bot Configuration
- rota: `agent_bots` - `/app/accounts/:accountId/settings/agent-bots`
- gate: feature flag `agent_bots`; papel `administrator`
- perfil: somente `administrator`. Se o perfil nao puder, diga que bots e conexao de bots por caixa sao configuracoes administrativas.
- pre_requisitos: endpoint HTTPS do bot webhook/API; caixa criada para conectar o bot; credenciais JSON e Project ID se for Dialogflow
- passos: 1. Abra Agent Bots; 2. Crie ou edite um bot com nome, descricao, avatar e webhook URL; 3. Copie o access token e secret quando forem exibidos; 4. Abra a caixa desejada e entre em Bot Configuration; 5. Selecione o bot e salve; 6. Para Dialogflow, va em Aplicacoes > Dialogflow e conecte a uma caixa.
- gotchas: nesta fork, `agent_bots` cria bot do tipo webhook; Dialogflow nao e criado nessa tela, e sim em Integracoes; bots `system_bot` aparecem na lista mas nao podem ser editados/excluidos; desconectar bot da caixa nao apaga o bot do catalogo.
- nav_target: `agent_bots`
- highlight: `settings-add-bot`

### Usar busca global
- intent: Como busco uma conversa?; Onde procuro mensagens antigas?; Como acho contato pela busca?; Como encontro artigo da Central de Ajuda?
- onde_fica: Barra superior/sidebar > campo de busca ou atalho Cmd/Ctrl+K
- rota: `search` - `/app/accounts/:accountId/search/:tab?`
- gate: papel `agent` ou `administrator` ou `conversation_manage` ou `conversation_unassigned_manage` ou `conversation_participating_manage` ou `contact_manage` ou `knowledge_base_manage`
- perfil: `administrator` e `agent` podem buscar conforme acesso; custom role com `conversation_manage`, `conversation_unassigned_manage` ou `conversation_participating_manage` ve conversas/mensagens; custom role com `contact_manage` ve contatos; custom role com `knowledge_base_manage` ve artigos. Se o perfil nao puder, explique que a busca so mostra tipos de resultado permitidos ao usuario.
- pre_requisitos: existir dado acessivel ao usuario; para artigos, Central de Ajuda habilitada
- passos: 1. Abra a busca global pela sidebar ou atalho; 2. Digite o termo e pressione enter; 3. Use as abas Tudo, Contatos, Conversas, Mensagens e Artigos conforme aparecerem; 4. Use Ver mais ou Carregar mais quando houver muitos resultados; 5. Abra o item encontrado para navegar ao detalhe.
- gotchas: a aba Tudo mostra apenas alguns resultados por tipo; filtros avancados de data, remetente e inbox so entram no payload quando `advanced_search` esta ativo; resultados seguem permissao e acesso a inbox/contato/artigo.
- nav_target: `search`
- highlight: `global-search`

### Configurar seguranca da conta e do usuario
- intent: Onde configuro SSO/SAML?; Como ativo MFA?; Onde troco minha senha?; Por que nao vejo seguranca?
- onde_fica: SAML: Sidebar > Configuracoes > Seguranca; senha/MFA: menu de perfil > Configuracoes do perfil
- rota: `security_settings_index` - `/app/accounts/:accountId/settings/security`
- gate: feature flag `saml`; papel `administrator`
- perfil: SAML exige `administrator`; senha e MFA ficam disponiveis para `administrator`, `agent` e `custom_role` no perfil proprio. Se o perfil nao puder acessar SAML, diga que SSO e configuracao administrativa; se MFA/senha nao aparecer, orientar a abrir configuracoes do proprio perfil.
- pre_requisitos: para SAML, dados do IdP: SSO URL, certificado e Entity ID; para MFA, aplicativo autenticador; para senha, senha atual
- passos: 1. Para SAML, abra Configuracoes > Seguranca; 2. Ative SAML e preencha SSO URL, IdP Entity ID e certificado; 3. Confira fingerprint, SP Entity ID e mapeamento de atributos; 4. Para senha, abra Perfil > Configuracoes e use Trocar senha; 5. Para MFA, use Gerenciar 2FA, leia o QR Code, valide o codigo e guarde os codigos de backup.
- gotchas: se `saml` estiver desabilitado ou a instalacao nao for Cloud/Enterprise, a rota pode nao aparecer ou mostrar bloqueio; se login SAML nao estiver em `allowedLoginMethods`, a tela mostra mensagem de desabilitado; `profile_settings_mfa` redireciona para perfil quando MFA global esta desligado.
- nav_target: `security_settings_index`

### Consultar logs de auditoria
- intent: Onde vejo log de auditoria?; Como descubro quem alterou algo?; Onde vejo atividades administrativas?; Tem historico com IP?
- onde_fica: Sidebar > Configuracoes > Logs de auditoria
- rota: `auditlogs_list` - `/app/accounts/:accountId/settings/audit-logs/list`
- gate: feature flag `audit_logs`; papel `administrator`
- perfil: somente `administrator`. Se o perfil nao puder, diga que logs de auditoria sao restritos a administradores.
- pre_requisitos: feature habilitada na conta/plano; haver eventos auditaveis
- passos: 1. Abra Configuracoes; 2. Entre em Logs de auditoria; 3. Revise atividade, horario e IP; 4. Navegue pelas paginas no rodape; 5. Use o texto do evento para identificar agente, recurso e alteracao.
- gotchas: a tela nao tem busca/filtro avancado neste componente; os textos sao gerados por chaves de traducao a partir do payload; se a feature estiver desativada, pode aparecer paywall/bloqueio ou a entrada sumir.
- nav_target: `auditlogs_list`

### Gerenciar aplicacoes e dashboard apps
- intent: Onde configuro integracoes?; Como crio app no painel da conversa?; Como conecto Dialogflow, Slack ou webhook?; O que sao dashboard apps?
- onde_fica: Sidebar > Configuracoes > Integracoes; para apps embutidos: Integracoes > Dashboard Apps
- rota: `settings_applications` - `/app/accounts/:accountId/settings/integrations`
- gate: feature flag `integrations`; papel `administrator`
- perfil: somente `administrator`. Se o perfil nao puder, diga que integrar aplicativos, webhooks e dashboard apps exige administrador.
- pre_requisitos: credenciais da integracao ou URL do app; para dashboard app, titulo e URL valida; para Dialogflow, Project ID, JSON de credenciais e caixa de entrada
- passos: 1. Abra Configuracoes > Integracoes; 2. Pesquise a aplicacao desejada; 3. Clique em configurar; 4. Para hooks, preencha credenciais e selecione a caixa quando a integracao for por inbox; 5. Para Dashboard Apps, abra a area propria e cadastre titulo e URL; 6. Salve e teste no contexto da conversa/caixa.
- gotchas: Dashboard App usa conteudo do tipo `frame` com URL valida; Dialogflow e uma integracao por inbox, nao um `agent_bot`; algumas integracoes so aparecem como ativas se houver credencial global ou feature habilitada; remover hook desconecta a integracao.
- nav_target: `settings_applications`

### Ver plano e cobranca
- intent: Onde vejo meu plano?; Como abro cobranca?; Onde compro creditos?; Esta instalacao tem billing?
- onde_fica: Sidebar > Configuracoes > Billing/Cobranca
- rota: `billing_settings_index` - `/app/accounts/:accountId/settings/billing`
- gate: papel `administrator`
- perfil: somente `administrator`. Se o perfil nao puder, diga que plano e cobranca sao restritos a administradores.
- pre_requisitos: conta Cloud com dados de assinatura em `custom_attributes`; para comprar creditos, plano diferente de Hacker
- passos: 1. Abra Configuracoes > Billing; 2. Revise plano atual, quantidade de assentos e renovacao; 3. Use Gerenciar assinatura para abrir o portal de cobranca; 4. Revise creditos/limites do Captain quando aparecerem; 5. Use comprar creditos se o plano permitir.
- gotchas: no fork self-hosted/white-label, considerar nao-aplicavel se `isOnChatwootCloud` for falso; quando nao ha billing plan, a tela tenta atualizar uma vez e pode mostrar mensagem de ausencia de billing; compra de creditos nao aparece no plano Hacker.
- nav_target: `billing_settings_index`

### Configurar IA do CRM por funil
- intent: "Como ligo a IA de um funil?"; "Onde configuro auto follow-up do CRM?"; "Como a IA decide mover cards de etapa?"; "Como ativo deteccao de callback?"
- onde_fica: Sidebar > CRM > CRM Kanban > selecionar funil > Editar funil > IA do funil
- rota: `crm_kanban_index` - `/app/accounts/:accountId/crm`
- gate: papel `administrator` ou `agent` ou `crm_view`
- perfil: `administrator`, `agent` sem custom role, ou custom role com `crm_manage_ai`/`crm_admin`; se o perfil nao puder, diga que ele pode visualizar o CRM quando tiver acesso, mas precisa de permissao de IA do CRM para alterar essas configuracoes.
- pre_requisitos: funil ja criado; etapas do funil definidas; para auto-move, criterios de IA por etapa bem descritos.
- passos: 1. Abra CRM Kanban; 2. Selecione o funil; 3. Clique em Editar funil; 4. No bloco IA do funil, habilite IA, auto-move, callback e/ou follow-up automatico; 5. Preencha criterios por etapa, handoff e horarios de envio; 6. Clique em Salvar IA ou Salvar funil.
- gotchas: o painel so aparece ao editar um funil existente; auto-move depende de criterios por etapa; callback tem modos "so lembrar", "enviar mensagem" ou "ambos"; follow-up automatico envia mensagens, entao deve ser ligado com cuidado.
- nav_target: `crm_kanban_index`

### Usar sugestoes e resumo por IA no card do CRM
- intent: "Como peco para a IA analisar um card?"; "Onde aceito a etapa sugerida pela IA?"; "Como vejo resumo da conversa no card?"
- onde_fica: Sidebar > CRM > CRM Kanban > abrir card > paineis de IA no drawer do card
- rota: `crm_kanban_index` - `/app/accounts/:accountId/crm`
- gate: papel `administrator` ou `agent` ou `crm_view`
- perfil: `administrator`, `agent` sem custom role, ou custom role com `crm_manage_ai`/`crm_admin` para analisar, aceitar, dispensar e atualizar resumo; custom role apenas com `crm_view` pode ser orientada a visualizar o card, mas nao a executar acoes de IA.
- pre_requisitos: card existente; para resumo, card precisa estar vinculado a uma conversa visivel ao usuario.
- passos: 1. Abra o card; 2. Veja o painel Sugestao de estagio; 3. Clique em Analisar agora quando quiser reavaliar; 4. Aceite para mover o card ou dispense a sugestao; 5. No painel Resumo da conversa por IA, use Atualizar quando precisar regenerar.
- gotchas: se a IA ficar abaixo do limiar, a tela mostra que nao encontrou etapa adequada; resumo nao aparece para card sem conversa; aceitar sugestao move o card de etapa.
- nav_target: `crm_kanban_index`

### Conectar ou autorizar calendario em uma caixa de e-mail
- intent: "Como libero agenda Google no CRM?"; "Como autorizo calendario da Microsoft?"; "Por que nao aparece caixa para agendar reuniao?"; "Como reconecto calendario de uma inbox?"
- onde_fica: Configuracoes > Caixas de entrada > Nova caixa > Email > Google ou Microsoft; para revisar caixa existente: Configuracoes > Caixas de entrada > selecionar caixa
- rota: `settings_inboxes_page_channel` - `/app/accounts/:accountId/settings/inboxes/new/:sub_page`
- gate: feature flag `inbox_management`; papel `administrator` ou `inbox_manage`
- perfil: `administrator`; se o perfil nao puder, diga que conexao OAuth de e-mail/calendario e acao administrativa e peca a um administrador da conta para conectar ou reautorizar a caixa.
- pre_requisitos: credenciais OAuth Google ou Microsoft configuradas para a conta ou globalmente; permissao no provedor para consentir acesso de e-mail e calendario.
- passos: 1. Abra Nova caixa e escolha Email; 2. Escolha Google ou Microsoft; 3. Entre com a conta de e-mail que sera a caixa; 4. Aceite as permissoes solicitadas, incluindo calendario; 5. Ao voltar, confirme que a caixa aparece no CRM Calendar e nos perfis de agendamento.
- gotchas: `calendar_enabled` e `calendar_scope_granted` so ficam ativos se o provedor devolver escopo de calendario; caixas Google/Microsoft conectadas antes da flag podem precisar reautorizar; entrar com o mesmo e-mail no fluxo OAuth atualiza a caixa existente em vez de criar outra; provedores "outros" por IMAP/SMTP nao habilitam calendario.
- nav_target: `settings_inboxes_page_channel`

### Configurar pagina de agendamento em caixa compartilhada e links por agente
- intent: "Como varios vendedores usam o mesmo e-mail para agenda?"; "Como gero um link de agendamento para cada agente?"; "O que significa caixa compartilhada no booking?"
- onde_fica: Sidebar > CRM > CRM Calendar > Pagina de agendamento
- rota: `crm_calendar_index` - `/app/accounts/:accountId/crm/calendar`
- gate: papel `administrator` ou `agent` ou `crm_view`
- perfil: `administrator`; se o perfil nao puder, diga que a API de perfis de agendamento e administrativa. Custom role com `crm_manage_pipelines` pode ver controles de CRM, mas deve pedir a um administrador para salvar/gerar links de booking.
- pre_requisitos: caixa de e-mail Google/Microsoft conectada com calendario; agentes adicionados como membros da caixa; funil/etapa padrao recomendados para criar o lead corretamente.
- passos: 1. Abra CRM Calendar; 2. Clique em Pagina de agendamento; 3. Habilite a pagina da caixa; 4. Em Atribuicao, escolha Por agente (links individuais); 5. Marque Caixa compartilhada quando varios agentes usam o mesmo e-mail; 6. Salve e copie o link de cada agente.
- gotchas: em modo por agente, compartilhe os links individuais, nao o slug base; agente sem acesso a caixa nao e elegivel; com `calendar_shared`, disponibilidade e calculada pelos compromissos CRM do agente, nao pelo free/busy agregado da caixa compartilhada.
- nav_target: `crm_calendar_index`
- highlight: `crm-booking-page`

### Gerenciar tokens de integracao do CRM
- intent: "Onde crio token para integrar o CRM?"; "Como gero token para n8n?"; "Como revogo ou rotaciono um token do CRM?"
- onde_fica: URL direta de CRM Settings > Integration tokens; tambem acessivel pelo guia de n8n em Configuracoes > Integracoes > n8n (Conexoes do CRM)
- rota: `crm_integration_tokens_index` - `/app/accounts/:accountId/crm/settings/integration-tokens`
- gate: papel `administrator` ou `crm_admin`
- perfil: `administrator` ou custom role com `crm_admin`; agentes comuns, agentes sem custom role e custom roles sem `crm_admin` nao podem gerenciar tokens. Diga que tokens sao credenciais administrativas e devem ser criados por admin/CRM admin.
- pre_requisitos: saber o nome da integracao e os escopos minimos necessarios (`crm_view`, `crm_manage_cards`, `crm_move_cards`, `crm_manage_pipelines`, `crm_manage_ai`, `crm_view_reports`, `crm_admin`).
- passos: 1. Abra a pagina de tokens; 2. Informe um nome identificavel; 3. Marque somente os escopos necessarios; 4. Crie o token; 5. Copie o segredo exibido uma unica vez; 6. Use Rotacionar ou Revogar quando precisar trocar ou encerrar o acesso.
- gotchas: o segredo nao e mostrado de novo depois de dispensado; rotacionar revoga o token anterior imediatamente; revogar remove o acesso na hora; para n8n, a tela mostra o header `api_access_token`.
- nav_target: `crm_integration_tokens_index`
- highlight: `crm-new-token`

### Configurar integracao CRM com n8n
- intent: "Como conecto o CRM ao n8n?"; "Quais eventos do CRM posso enviar por webhook?"; "Onde configuro automacao externa para cards?"
- onde_fica: Configuracoes > Integracoes > n8n (Conexoes do CRM)
- rota: `settings_integrations_crm_n8n` - `/app/accounts/:accountId/settings/integrations/crm_n8n`
- gate: feature flag `integrations`; papel `administrator`
- perfil: `administrator`; se o perfil nao puder, diga que a tela de integracoes e webhooks e administrativa. Custom role `crm_admin` pode acessar tokens pela rota do CRM, mas nao substitui o acesso administrativo a Configuracoes > Integracoes.
- pre_requisitos: endpoint HTTPS publico do n8n; token de CRM com escopos adequados; decidir quais eventos assinar.
- passos: 1. Abra n8n (Conexoes do CRM); 2. Clique para criar token de API do CRM; 3. Copie o token no n8n usando o header `api_access_token`; 4. Volte e crie um webhook; 5. Marque eventos como `crm.card.created`, `crm.card.moved`, `crm.card.won`, `crm.card.lost`, `crm.card.reopened` ou `crm.card.archived`.
- gotchas: n8n local ou URL privada pode ser bloqueado por protecao SSRF; eventos de CRM so aparecem no webhook quando `CRM_KANBAN_ENABLED=true`; token e webhook sao duas partes separadas da integracao.
- nav_target: `settings_integrations_crm_n8n`
- highlight: `crm-n8n-token`

### Configurar CRM por caixa de entrada
- intent: "Como faco conversas virarem cards automaticamente?"; "Como defino funil padrao por inbox?"; "Como restringo cards da caixa para o agente atribuido?"
- onde_fica: Sidebar > CRM > CRM Kanban > Configuracoes de inbox
- rota: `crm_kanban_index` - `/app/accounts/:accountId/crm`
- gate: papel `administrator` ou `agent` ou `crm_view`
- perfil: `administrator`, `agent` sem custom role, ou custom role com `crm_manage_pipelines`/`crm_admin`; se o perfil nao puder, diga que ele precisa de permissao para gerenciar funis/configuracoes do CRM.
- pre_requisitos: caixas de entrada criadas; funil e etapas existentes quando quiser definir padrao.
- passos: 1. Abra CRM Kanban; 2. Clique em Configuracoes de inbox; 3. Ative CRM na caixa desejada; 4. Escolha visibilidade entre todos os cards da inbox ou apenas atribuidos; 5. Defina funil/etapa padrao; 6. Marque Criar card automaticamente e clique em Salvar no cartao daquela caixa; o cartao mostra "Salvo" quando gravou; 7. Repita nas outras caixas e clique em Concluir. Cada caixa salva separada: o rodape avisa quantas caixas tem alteracao nao salva, e fechar descarta o que nao foi salvo.
- gotchas: se CRM ativo for desligado, a criacao automatica tambem e desligada; `assigned_only` muda a visibilidade de agentes; funil/etapa padrao precisam pertencer a mesma conta.
- nav_target: `crm_kanban_index`
- highlight: `crm-configure-inboxes`

### Criar automacoes por etapa do funil
- intent: "Como automatizo uma etapa do CRM?"; "Como criar follow-up ao mover card?"; "Como atribuir responsavel automaticamente quando entrar numa etapa?"
- onde_fica: Sidebar > CRM > CRM Kanban > Editar funil > etapa > icone de automacoes
- rota: `crm_kanban_index` - `/app/accounts/:accountId/crm`
- gate: papel `administrator` ou `agent` ou `crm_view`
- perfil: `administrator`, `agent` sem custom role, ou custom role com `crm_manage_pipelines`/`crm_admin`; se o perfil nao puder, diga que automacoes de etapa fazem parte da gestao de funis.
- pre_requisitos: funil salvo; etapa existente; agentes disponiveis quando a acao for atribuir responsavel.
- passos: 1. Abra Editar funil; 2. Na etapa desejada, clique no icone de automacoes; 3. Crie uma regra e escolha gatilho de entrada ou saida; 4. Adicione passos como Criar follow-up, Atribuir responsavel ou Mover estagio; 5. Defina atraso e parametros; 6. Salve a regra.
- gotchas: automacoes so aparecem para etapas ja salvas; regras podem encadear movimentos, entao evite loops; follow-ups criados pela automacao aparecem no card e no calendario.
- nav_target: `crm_kanban_index`

### Salvar e compartilhar visoes da lista do CRM
- intent: "Como salvo uma visualizacao do CRM?"; "Como compartilhar filtros e colunas da lista?"; "Onde aplico uma visao salva?"
- onde_fica: Sidebar > CRM > CRM Kanban > alternar para Lista > botao de visoes salvas
- rota: `crm_kanban_index` - `/app/accounts/:accountId/crm`
- gate: papel `administrator` ou `agent` ou `crm_view`
- perfil: `administrator`, `agent` ou custom role com `crm_view`; se o perfil nao puder, diga que ele precisa ao menos de acesso de visualizacao do CRM. Somente dono da visao ou administrador edita/exclui uma visao existente.
- pre_requisitos: funil selecionado; modo Lista aberto; filtros, colunas, ordenacao, agrupamento ou densidade ajustados.
- passos: 1. Abra o CRM em modo Lista; 2. Ajuste filtros, colunas e ordenacao; 3. Clique no botao de visoes salvas; 4. Crie uma nova visao; 5. Escolha visibilidade privada, time ou conta; 6. Aplique a visao quando quiser restaurar a configuracao.
- gotchas: visoes privadas aparecem so para o dono; visoes de time/conta aparecem para outros usuarios com acesso ao CRM; a visao salva captura configuracao da lista, nao altera cards.
- nav_target: `crm_kanban_index`

### Ordenar e filtrar status da lista de conversas
- intent: Como ordeno minhas conversas?; Onde mudo a ordem da lista?; Como mostro só conversas resolvidas/pendentes/adiadas?; Como vejo conversas por prioridade ou não lidas?
- onde_fica: Conversas > cabeçalho da lista > botão de ordenação (ícone de setas)
- rota: `home` - `/app/accounts/:accountId/dashboard`
- gate: papel `administrator` ou `agent` ou `conversation_manage` ou `conversation_unassigned_manage` ou `conversation_participating_manage`
- pre_requisitos: estar na lista de conversas (sem filtro avançado/pasta ativos)
- passos: 1. Abra Conversas; 2. Clique no botão de ordenação (ícone de setas) no topo da lista; 3. Em Status escolha Abertas, Resolvidas, Pendentes, Adiadas ou Todas; 4. Em Ordenar por escolha por última atividade, criação, prioridade, não lidas ou tempo de espera; 5. A preferência fica salva para as próximas visitas.
- gotchas: o botão de ordenação só aparece na visão padrão da lista — quando há filtro avançado ou pasta aplicada ele some; a escolha de status/ordem é salva nas preferências do usuário (uiSettings) e não é um filtro avançado.
- nav_target: `home`
- highlight: `conversations-sort-status`

### Iniciar nova conversa
- intent: Como começo uma nova conversa?; Onde envio a primeira mensagem para um contato?; Como crio um atendimento do zero?; Como mando mensagem proativa por WhatsApp/e-mail?
- onde_fica: Sidebar (canto superior) > botão de nova conversa (ícone de caneta)
- rota: `home` - `/app/accounts/:accountId/dashboard`
- gate: papel `administrator` ou `agent` ou `conversation_manage` ou `conversation_unassigned_manage` ou `conversation_participating_manage`
- pre_requisitos: existir ao menos uma caixa de entrada que permita criar conversa; contato existente ou criar um novo no fluxo
- passos: 1. Clique no botão de nova conversa (ícone de caneta) no topo da sidebar; 2. Selecione a caixa de entrada; 3. Escolha ou crie o contato; 4. Para WhatsApp/e-mail escolha o template/opções; 5. Escreva a mensagem e envie para abrir a conversa.
- gotchas: canais que exigem janela/template (WhatsApp API) podem limitar o envio livre; a caixa precisa suportar criação de conversa; o contato precisa ter o identificador correto (telefone/e-mail) do canal escolhido.
- nav_target: `home`
- highlight: `conversations-compose-new`

### Filtrar contatos
- intent: Como filtro contatos?; Onde aplico condições por atributo ou etiqueta?; Como busco contatos por critérios avançados?
- onde_fica: Contatos > Todos os contatos > botão de filtros (ícone de funil) no cabeçalho
- rota: `contacts_dashboard_index` - `/app/accounts/:accountId/contacts`
- gate: feature flag `crm`; papel `administrator` ou `agent` ou `contact_manage` ou `contact_view`
- pre_requisitos: contatos existentes; atributos/etiquetas para usar como condição
- passos: 1. Abra Contatos; 2. Clique no ícone de filtros (funil) no cabeçalho; 3. Adicione condições por atributo, etiqueta ou padrão; 4. Aplique o filtro; 5. Opcionalmente salve como segmento.
- gotchas: o botão de filtros não aparece nas visões Marcados com (etiqueta) nem Ativos; um ponto colorido no ícone indica que há filtros aplicados.
- nav_target: `contacts_dashboard_index`
- highlight: `contacts-open-filter`

### Ordenar lista de contatos
- intent: Como ordeno os contatos?; Onde mudo a ordem da lista de contatos?; Como classifico por nome ou data de criação?
- onde_fica: Contatos > Todos os contatos > botão de ordenação (ícone de setas) no cabeçalho
- rota: `contacts_dashboard_index` - `/app/accounts/:accountId/contacts`
- gate: feature flag `crm`; papel `administrator` ou `agent` ou `contact_manage` ou `contact_view`
- pre_requisitos: nenhum
- passos: 1. Abra Contatos; 2. Clique no ícone de ordenação (setas) no cabeçalho; 3. Escolha o campo em Classificar por; 4. Escolha Crescente ou Decrescente em Ordenação; 5. A lista é reordenada automaticamente.
- gotchas: a preferência de ordenação fica salva nas configurações de interface (contacts_sort_by) e é aplicada também em segmentos e busca.
- nav_target: `contacts_dashboard_index`
- highlight: `contacts-sort-menu`

### Ver histórico de importações de campanha
- intent: Onde vejo o histórico de bases importadas?; Como acompanho o status das importações de campanha?; Onde fica a lista de importações?
- onde_fica: Contatos > Todos os contatos > menu de ações (três pontos) > Histórico de bases
- rota: `contacts_campaign_imports` - `/app/accounts/:accountId/contacts/campaign-imports`
- gate: feature flag `crm`; papel `administrator` ou `campaign_view` ou `campaign_manage`
- pre_requisitos: pelo menos uma importação de base criada
- passos: 1. Abra Contatos; 2. Clique no menu de ações (três pontos); 3. Escolha Histórico de bases; 4. Acompanhe o status, baixe CSVs e use as ações da linha.
- gotchas: a página só abre com CAMPAIGN_IMPORT_ENABLED=true e papel administrador, caso contrário redireciona para Contatos; status em processamento atualiza a cada 5 segundos.
- nav_target: `contacts_campaign_imports`
- highlight: `campaign-imports-history-title`

### Trocar a senha no perfil
- intent: Como troco minha senha?; Onde mudo a senha da minha conta?; Como atualizo a senha de acesso?; Esqueci minha senha, mudo aqui?
- onde_fica: Menu do usuario/perfil > Configuracoes do perfil > Senha
- rota: `profile_settings_index` - `/app/accounts/:accountId/profile/settings`
- gate: papel `administrator` ou `agent` ou `custom_role`
- pre_requisitos: saber a senha atual; nova senha com pelo menos 6 caracteres
- passos: 1. Abra Configuracoes do perfil; 2. Va ate a secao Senha; 3. Informe a senha atual; 4. Digite e confirme a nova senha; 5. Clique em Mudar Senha.
- gotchas: a troca de senha so existe quando a atualizacao de perfil esta liberada; senha e confirmacao precisam coincidir e ter no minimo 6 caracteres; esqueci-a-senha (reset por e-mail) e um fluxo de login separado, nao esta nesta tela.
- nav_target: `profile_settings_index`
- highlight: `profile-change-password`

### Copiar ou reiniciar o token de acesso da API
- intent: Onde pego meu token de acesso?; Como copio a chave de API do usuario?; Como reinicio/rotaciono meu access token?; Onde fica o token pessoal de API?
- onde_fica: Menu do usuario/perfil > Configuracoes do perfil > Token de acesso
- rota: `profile_settings_index` - `/app/accounts/:accountId/profile/settings`
- gate: papel `administrator` ou `agent` ou `custom_role`
- pre_requisitos: usuario autenticado
- passos: 1. Abra Configuracoes do perfil; 2. Role ate a secao Token de acesso; 3. Use o icone de olho para revelar o token; 4. Clique em Copiar para usar em integracoes; 5. Use Reiniciar para gerar um novo token quando precisar revogar o atual.
- gotchas: este token e pessoal do usuario, diferente dos tokens de integracao do CRM; reiniciar invalida o token anterior imediatamente e quebra integracoes que o usavam.
- nav_target: `profile_settings_index`
- highlight: `profile-copy-access-token`

### Baixar relatório de agentes
- intent: Como baixo o relatório de agentes?; Onde exporto o desempenho por agente?; Como gero o CSV de agentes?; Onde fica o download do relatório de agentes?
- onde_fica: Relatorios > Agentes
- rota: `agent_reports_index` - `/app/accounts/:accountId/reports/agents_overview`
- gate: feature flag `reports`; papel `administrator` ou `report_manage`
- pre_requisitos: conversas atribuídas a agentes no período escolhido
- passos: 1. Abra Relatorios; 2. Entre em Agentes; 3. Ajuste o período/filtros; 4. Clique em Baixar relatórios de agentes; 5. Abra o arquivo gerado.
- gotchas: o download usa o período/filtros ativos na tela; usuários sem `report_manage` não acessam.
- nav_target: `agent_reports_index`
- highlight: `reports-download-agents`

### Baixar relatório de caixas
- intent: Como baixo o relatório por caixa de entrada?; Onde exporto o desempenho das caixas?; Como gero o CSV de caixas?; Onde fica o download do relatório de caixas?
- onde_fica: Relatorios > Caixas
- rota: `inbox_reports_index` - `/app/accounts/:accountId/reports/inboxes_overview`
- gate: feature flag `reports`; papel `administrator` ou `report_manage`
- pre_requisitos: conversas nas caixas no período escolhido
- passos: 1. Abra Relatorios; 2. Entre em Caixas; 3. Ajuste o período/filtros; 4. Clique em Baixar relatórios de entrada; 5. Abra o arquivo gerado.
- gotchas: o rótulo no botão é 'Baixar relatórios de entrada'; o download respeita o período ativo.
- nav_target: `inbox_reports_index`
- highlight: `reports-download-inboxes`

### Baixar relatório de times
- intent: Como baixo o relatório por time?; Onde exporto o desempenho dos times?; Como gero o CSV de times?; Onde fica o download do relatório de times?
- onde_fica: Relatorios > Times
- rota: `team_reports_index` - `/app/accounts/:accountId/reports/teams_overview`
- gate: feature flag `reports`; papel `administrator` ou `report_manage`
- pre_requisitos: times criados e conversas atribuídas no período
- passos: 1. Abra Relatorios; 2. Entre em Times; 3. Ajuste o período/filtros; 4. Clique em Baixar relatórios de time; 5. Abra o arquivo gerado.
- gotchas: o download respeita o período/filtros ativos na tela.
- nav_target: `team_reports_index`
- highlight: `reports-download-teams`

### Baixar relatório de etiquetas
- intent: Como baixo o relatório por etiqueta?; Onde exporto o desempenho das etiquetas?; Como gero o CSV de etiquetas?; Onde fica o download do relatório de etiquetas?
- onde_fica: Relatorios > Etiquetas
- rota: `label_reports_index` - `/app/accounts/:accountId/reports/labels_overview`
- gate: feature flag `reports`; papel `administrator` ou `report_manage`
- pre_requisitos: etiquetas aplicadas a conversas no período
- passos: 1. Abra Relatorios; 2. Entre em Etiquetas; 3. Ajuste o período/filtros; 4. Clique em Baixar relatórios de etiquetas; 5. Abra o arquivo gerado.
- gotchas: o download respeita o período/filtros ativos na tela.
- nav_target: `label_reports_index`
- highlight: `reports-download-labels`

### Baixar relatório de CSAT
- intent: Onde vejo a satisfação do cliente (CSAT)?; Como exporto as respostas de CSAT?; Como baixo o relatório de CSAT?; Onde acompanho avaliações dos clientes?
- onde_fica: Relatorios > CSAT
- rota: `csat_reports` - `/app/accounts/:accountId/reports/csat`
- gate: feature flag `reports`; papel `administrator` ou `report_manage`
- pre_requisitos: pesquisa de CSAT habilitada e respostas coletadas no período
- passos: 1. Abra Relatorios; 2. Entre em CSAT; 3. Ajuste o período/filtros; 4. Revise as métricas e respostas; 5. Clique em Baixar relatórios de CSAT para exportar.
- gotchas: o botão de download usa o rótulo 'Baixar relatórios de CSAT'; sem respostas no período a tela fica vazia.
- nav_target: `csat_reports`
- highlight: `reports-download-csat`

### Criar campanha SMS
- intent: Como crio uma campanha de SMS?; Onde disparo SMS em massa?; Como agendo um envio de SMS?; Onde fica campanhas SMS?
- onde_fica: Sidebar > Campanhas > Campanhas SMS
- rota: `campaigns_sms_index` - `/app/accounts/:accountId/campaigns/sms`
- gate: feature flag `campaigns`; papel `administrator` ou `campaign_view` ou `campaign_manage`
- pre_requisitos: caixa de SMS conectada; audiência (rótulos/contatos); mensagem do SMS
- passos: 1. Abra Campanhas > Campanhas SMS; 2. Clique em Criar campanha; 3. Selecione a caixa de SMS; 4. Escreva a mensagem; 5. Defina audiência e agendamento; 6. Crie a campanha.
- gotchas: o botão 'Criar campanha' fica no cabeçalho da página (CampaignLayout); a criação abre um diálogo; sem caixa de SMS conectada não há opções de envio.
- nav_target: `campaigns_sms_index`
- highlight: `campaigns-new-sms`

### Criar campanha de chat ao vivo
- intent: Como crio uma campanha de chat ao vivo?; Como disparo mensagem proativa no widget?; Onde configuro campanha de live chat?; Como abordo visitantes automaticamente?
- onde_fica: Sidebar > Campanhas > Campanhas de chat ao vivo
- rota: `campaigns_livechat_index` - `/app/accounts/:accountId/campaigns/live_chat`
- gate: feature flag `campaigns`; papel `administrator` ou `campaign_view` ou `campaign_manage`
- pre_requisitos: caixa de site/widget de chat ao vivo conectada
- passos: 1. Abra Campanhas > Campanhas de chat ao vivo; 2. Clique em Criar campanha; 3. Selecione a caixa de site; 4. Defina título, mensagem e regra de URL/tempo; 5. Crie a campanha.
- gotchas: campanhas de chat ao vivo são contínuas (ongoing) e dependem do widget; o botão 'Criar campanha' fica no cabeçalho e abre um diálogo.
- nav_target: `campaigns_livechat_index`
- highlight: `campaigns-new-livechat`

### Criar campanha WhatsApp Oficial
- intent: Como crio campanha no WhatsApp oficial?; Onde disparo mensagem em massa pelo WhatsApp?; Como uso template oficial em campanha?; Qual a diferença para WhatsApp API?
- onde_fica: Sidebar > Campanhas > Campanhas WhatsApp Oficial
- rota: `campaigns_whatsapp_index` - `/app/accounts/:accountId/campaigns/whatsapp`
- gate: feature flag `whatsapp_campaign`; papel `administrator` ou `campaign_view` ou `campaign_manage`
- pre_requisitos: caixa de WhatsApp oficial conectada; template/audiência
- passos: 1. Abra Campanhas > Campanhas WhatsApp Oficial; 2. Clique em Criar campanha; 3. Selecione a caixa de WhatsApp; 4. Escolha template ou mensagem; 5. Defina audiência e agendamento; 6. Crie.
- gotchas: esta é a tela 'WhatsApp Oficial' (whatsapp_campaigns), diferente de 'WhatsApp API' (campaigns_whatsapp_api_index); só aparece com a feature flag whatsapp_campaigns ativa.
- nav_target: `campaigns_whatsapp_index`
- highlight: `campaigns-new-whatsapp-official`

### Usar e filtrar o calendário CRM por tipo de evento
- intent: Como filtro o calendário por tipo?; Como mostro só reuniões / só follow-ups no calendário?; Como escondo os eventos externos do calendário?; O que são os chips Lembretes, WhatsApp, Previsões, Reuniões e Externos?
- onde_fica: Sidebar > CRM > Calendário (ou CRM Kanban > visualização Calendário) > chips de tipo no cabeçalho do calendário
- rota: `crm_calendar_index` - `/app/accounts/:accountId/crm/calendar`
- gate: papel `administrator` ou `agent` ou `crm_view`
- pre_requisitos: ao menos um funil; para ver reuniões/externos, caixa Google ou Microsoft com calendário ativo.
- passos: 1. Abra o Calendário do CRM; 2. No cabeçalho, use os chips de tipo (Lembretes, WhatsApp, Previsões, Reuniões, Externos) para ligar/desligar cada camada; 3. Alterne a visão em Mês/Semana/Dia/Agenda; 4. Use Hoje e as setas para navegar; 5. Ajuste o escopo entre Meus e Todos.
- gotchas: os chips são toggles independentes e ficam coloridos quando ativos; Externos aparece em estilo apagado/itálico e é só leitura; sem caixa com calendário conectado, Reuniões e Externos ficam vazios; o escopo Meus/Todos altera quais follow-ups aparecem.
- nav_target: `crm_calendar_index`

### Conectar WhatsApp Oficial (Cloud API)
- intent: Como conecto o WhatsApp Oficial?; Como crio uma caixa do WhatsApp oficial (Cloud API/Meta)?; Quero atender no WhatsApp oficial; Onde ligo o WhatsApp Business API oficial?
- onde_fica: Configurações > Caixas de entrada > Nova caixa > WhatsApp Oficial
- rota: `settings_inbox_new` - `/app/accounts/:accountId/settings/inboxes/new`
- gate: feature flag `inbox_management`; papel `administrator` ou `inbox_manage`
- pre_requisitos: ter os dados/credenciais do canal escolhido
- passos: Vá em Configurações > Caixas de entrada > Nova caixa; escolha WhatsApp Oficial; faça o login/autorização da Meta (Embedded Signup) ou informe os dados da Cloud API; selecione o número aprovado; atribua agentes e finalize.
- gotchas: WhatsApp Oficial (Cloud API da Meta) é DIFERENTE do WhatsApp API por QR Code: o oficial usa número aprovado pela Meta e exige templates aprovados para mensagens fora da janela de 24h.
- nav_target: `settings_inbox_new`
- highlight: `channel-whatsapp-oficial`

### Conectar WhatsApp por QR Code (WhatsApp API)
- intent: Como conecto o WhatsApp lendo um QR Code?; Como uso o WhatsApp API (não oficial)?; Conectar número de WhatsApp escaneando QR; WhatsApp via WAHA
- onde_fica: Configurações > Caixas de entrada > Nova caixa > WhatsApp API
- rota: `settings_inbox_new` - `/app/accounts/:accountId/settings/inboxes/new`
- gate: feature flag `inbox_management`; papel `administrator` ou `inbox_manage`
- pre_requisitos: ter os dados/credenciais do canal escolhido
- passos: Vá em Configurações > Caixas de entrada > Nova caixa; escolha WhatsApp API; informe modo/nome/número e crie a caixa; na tela de conexão aparece o QR Code; no celular abra WhatsApp > Aparelhos conectados > Conectar aparelho e escaneie; aguarde conectar e finalize.
- gotchas: WhatsApp API por QR Code é DIFERENTE do WhatsApp Oficial: usa o número direto via QR (sem aprovação da Meta); o QR aparece na tela de conexão DEPOIS de criar a caixa (não no clique do tile); o WhatsApp dá cerca de 2 minutos e meio para ler (a tela mostra o tempo restante); se expirar, a tela mostra "O QR Code expirou" e o botão Gerar novo QR Code, sem recriar a caixa; leia pelo próprio WhatsApp (Aparelhos conectados), não pela câmera do celular; pode desconectar se o aparelho/sessão cair; se o tile não aparecer, o canal pode não estar habilitado nesta instalação.
- nav_target: `settings_inbox_new`
- highlight: `channel-whatsapp-api`

### Conectar caixa de e-mail
- intent: Como conecto um e-mail?; Como integro Gmail/Outlook?; Quero atender por e-mail; Conectar caixa de e-mail (IMAP/SMTP)
- onde_fica: Configurações > Caixas de entrada > Nova caixa > E-mail
- rota: `settings_inbox_new` - `/app/accounts/:accountId/settings/inboxes/new`
- gate: feature flag `inbox_management`; papel `administrator` ou `inbox_manage`
- pre_requisitos: ter os dados/credenciais do canal escolhido
- passos: Vá em Configurações > Caixas de entrada > Nova caixa; escolha E-mail; conecte via Gmail/Microsoft (OAuth) ou informe IMAP/SMTP; valide o envio/recebimento; atribua agentes e finalize.
- gotchas: Para Google/Microsoft pode ser preciso reautorizar para conceder o escopo; verifique IMAP/SMTP e a identidade de remetente para o envio sair correto.
- nav_target: `settings_inbox_new`
- highlight: `channel-email`

### Conectar Instagram
- intent: Como conecto o Instagram?; Quero atender DMs do Instagram; Conectar conta do Instagram
- onde_fica: Configurações > Caixas de entrada > Nova caixa > Instagram
- rota: `settings_inbox_new` - `/app/accounts/:accountId/settings/inboxes/new`
- gate: feature flag `inbox_management`; papel `administrator` ou `inbox_manage`
- pre_requisitos: ter os dados/credenciais do canal escolhido
- passos: Vá em Configurações > Caixas de entrada > Nova caixa; escolha Instagram; faça login e autorize a conta do Instagram (vinculada a uma página/Meta); selecione a conta; atribua agentes e finalize.
- gotchas: A conta do Instagram precisa ser profissional e vinculada à Meta; mensagens dependem das permissões concedidas na autorização.
- nav_target: `settings_inbox_new`
- highlight: `channel-instagram`

### Conectar página do Facebook
- intent: Como conecto o Facebook/Messenger?; Quero atender mensagens da página do Facebook; Conectar página do Facebook
- onde_fica: Configurações > Caixas de entrada > Nova caixa > Facebook
- rota: `settings_inbox_new` - `/app/accounts/:accountId/settings/inboxes/new`
- gate: feature flag `inbox_management`; papel `administrator` ou `inbox_manage`
- pre_requisitos: ter os dados/credenciais do canal escolhido
- passos: Vá em Configurações > Caixas de entrada > Nova caixa; escolha Facebook; faça login e autorize; selecione a página do Facebook; atribua agentes e finalize.
- gotchas: É preciso ser administrador da página no Facebook e conceder as permissões de mensagens na autorização da Meta.
- nav_target: `settings_inbox_new`
- highlight: `channel-facebook`

### Criar canal de chat ao vivo no site
- intent: Como coloco o chat ao vivo no meu site?; Como crio um widget de site?; Conectar canal de website/live-chat
- onde_fica: Configurações > Caixas de entrada > Nova caixa > Site
- rota: `settings_inbox_new` - `/app/accounts/:accountId/settings/inboxes/new`
- gate: feature flag `inbox_management`; papel `administrator` ou `inbox_manage`
- pre_requisitos: ter os dados/credenciais do canal escolhido
- passos: Vá em Configurações > Caixas de entrada > Nova caixa; escolha Site; preencha nome e domínio do widget; ajuste cor/saudação; atribua agentes; finalize e copie o script para colar no seu site.
- gotchas: O widget só aparece depois de colar o script no site; a última etapa mostra o código de instalação.
- nav_target: `settings_inbox_new`
- highlight: `channel-website`

### Conectar canal de SMS
- intent: Como conecto SMS?; Quero atender por SMS; Conectar SMS com Twilio ou Bandwidth
- onde_fica: Configurações > Caixas de entrada > Nova caixa > SMS
- rota: `settings_inbox_new` - `/app/accounts/:accountId/settings/inboxes/new`
- gate: feature flag `inbox_management`; papel `administrator` ou `inbox_manage`
- pre_requisitos: ter os dados/credenciais do canal escolhido
- passos: Vá em Configurações > Caixas de entrada > Nova caixa; escolha SMS; selecione o provedor (Twilio ou Bandwidth) e informe as credenciais/número; atribua agentes e finalize.
- gotchas: Exige conta no provedor (Twilio/Bandwidth) com número habilitado para SMS.
- nav_target: `settings_inbox_new`
- highlight: `channel-sms`

### Conectar canal do Telegram
- intent: Como conecto o Telegram?; Quero atender pelo Telegram; Conectar bot do Telegram
- onde_fica: Configurações > Caixas de entrada > Nova caixa > Telegram
- rota: `settings_inbox_new` - `/app/accounts/:accountId/settings/inboxes/new`
- gate: feature flag `inbox_management`; papel `administrator` ou `inbox_manage`
- pre_requisitos: ter os dados/credenciais do canal escolhido
- passos: No Telegram crie um bot com o BotFather e copie o token; vá em Configurações > Caixas de entrada > Nova caixa; escolha Telegram; cole o token do bot; atribua agentes e finalize.
- gotchas: O token vem do BotFather; sem o token correto o canal não conecta.
- nav_target: `settings_inbox_new`
- highlight: `channel-telegram`

### Criar canal personalizado via API
- intent: Como crio um canal pela API?; Conectar canal personalizado; Quero integrar um canal próprio via API
- onde_fica: Configurações > Caixas de entrada > Nova caixa > API
- rota: `settings_inbox_new` - `/app/accounts/:accountId/settings/inboxes/new`
- gate: feature flag `inbox_management`; papel `administrator` ou `inbox_manage`
- pre_requisitos: ter os dados/credenciais do canal escolhido
- passos: Vá em Configurações > Caixas de entrada > Nova caixa; escolha API; informe nome e (opcional) webhook; finalize; use as credenciais/endpoints para integrar seu canal.
- gotchas: O canal API é genérico: você envia/recebe mensagens pelos endpoints; precisa de desenvolvimento do seu lado.
- nav_target: `settings_inbox_new`
- highlight: `channel-api`

### Diagnosticar conexão de canal (WhatsApp / e-mail / Instagram não conecta ou não recebe)
- intent: Por que meu WhatsApp não conecta?; Por que não estou recebendo mensagens?; Minha caixa de e-mail parou de receber; Por que o Instagram não recebe mensagens?; Meu canal caiu ou desconectou; Diagnosticar conexão da caixa de entrada
- onde_fica: Configurações > Caixas de entrada
- rota: `settings_inbox_new` - `/app/accounts/:accountId/settings/inboxes/new`
- gate: feature flag `inbox_management`; papel `administrator` ou `inbox_manage`
- passos: O Guia lê o estado real das suas caixas e aponta o que está faltando (autorização expirada, credenciais incompletas, IMAP/SMTP desligado, caixa sem agente etc.). Siga o conserto indicado para a caixa citada, nas Configurações daquela caixa de entrada.
- gotchas: o status em tempo real do WhatsApp API (QR Code) só aparece na tela de Conexão da caixa; reconectar/reautorizar é sempre feito pelo administrador.
- diagnostic: `channel`
- nav_target: `—`
- highlight: `—`

### Diagnosticar notificações (não estou recebendo notificações)
- intent: Por que não recebo notificações?; Não chega notificação no navegador; Parei de receber e-mails de notificação; Não sou avisado de novas conversas; Diagnosticar notificações
- onde_fica: Perfil > Configurações de notificação
- rota: `profile_settings_index` - `/app/accounts/:accountId/profile/settings`
- gate: papel `administrator` ou `agent` ou `custom_role`
- passos: O Guia verifica suas preferências de notificação (push e e-mail), se há inscrição de push registrada no navegador e se o seu e-mail está confirmado, e indica exatamente o que ativar em Perfil > Configurações de notificação.
- gotchas: o push do navegador exige permitir as notificações no navegador; e-mails de notificação só são enviados depois de confirmar o e-mail do usuário.
- diagnostic: `notifications`
- nav_target: `profile_settings_index`
- highlight: `profile-update-basic`

### Diagnosticar IA / agente (a IA não responde nas conversas)
- intent: Por que a IA não responde?; Meu agente de IA não está respondendo; Por que o agente automático não atende os clientes?; O bot parou de responder; Diagnosticar agente de IA
- onde_fica: Agentes de IA (Autonom.ia)
- rota: `autonomia_agents_index` - `/app/accounts/:accountId/agents`
- gate: papel `administrator` ou `autonomia_view` ou `autonomia_manage`
- passos: O Guia confere se os Agentes de IA estão habilitados na conta, se há chave de IA configurada, se existe um agente habilitado e ativo apto a atender o cliente (atuação Externo/Ambos) e se ele está conectado a uma caixa de entrada — e aponta o que falta.
- gotchas: um agente interno (copiloto) nunca fala com o cliente, só ajuda o atendente; cada caixa de entrada só aceita um bot.
- diagnostic: `ai_agent`
- nav_target: `autonomia_agents_index`
- highlight: `—`

### Diagnosticar atribuição (conversas não são atribuídas a ninguém)
- intent: Por que as conversas não são atribuídas?; As conversas ficam sem responsável; A atribuição automática não está funcionando; Ninguém recebe as novas conversas; Diagnosticar roteamento de conversas
- onde_fica: Configurações > Caixas de entrada > Colaboradores / Atribuição automática
- rota: `settings_inbox_new` - `/app/accounts/:accountId/settings/inboxes/new`
- gate: feature flag `inbox_management`; papel `administrator` ou `inbox_manage`
- passos: O Guia verifica, por caixa, se a atribuição automática está ligada, se há agentes vinculados, se algum agente está online, se há limite por agente e se o horário de funcionamento está fora do expediente — e aponta o que ajustar nas Configurações da caixa.
- gotchas: a atribuição automática só envia conversas para agentes 'Online'; fora do horário comercial a atribuição cai ou zera.
- diagnostic: `routing`
- nav_target: `—`
- highlight: `—`

### Diagnosticar calendário/reuniões (não consigo agendar)
- intent: Por que não consigo agendar reunião?; O calendário não conecta; Os horários disponíveis não aparecem; Falha ao criar reunião; Diagnosticar calendário ou reuniões
- onde_fica: Configurações > Caixas de entrada (e-mail Google/Microsoft)
- rota: `settings_inbox_new` - `/app/accounts/:accountId/settings/inboxes/new`
- gate: feature flag `inbox_management`; papel `administrator` ou `inbox_manage`
- passos: O Guia confere se o recurso de reuniões está ativo na instalação, se há caixa de e-mail Google/Microsoft conectada por OAuth, se o calendário foi autorizado (escopo) e se os tokens de acesso estão presentes — e indica o que reconectar.
- gotchas: só e-mail conectado via 'Entrar com Google/Microsoft' oferece calendário (IMAP/SMTP comum não); ativar o recurso na instalação é ajuste de servidor (administrador da plataforma).
- diagnostic: `calendar`
- nav_target: `—`
- highlight: `—`

### Ver o volume e os tempos de atendimento da conta
- intent: Quantas conversas entraram neste mês?; Nosso tempo de primeira resposta está piorando?; Quanto tempo o cliente espera entre respostas?; Quantas conversas foram resolvidas no período?; Como exporto esses números para planilha?
- onde_fica: Relatórios > Conversas
- rota: `conversation_reports` - `/app/accounts/:accountId/reports/conversation`
- gate: feature flag `reports`; papel `administrator` ou `report_manage`
- pre_requisitos: nenhum, mas só aparecem números se houver conversas no período escolhido
- passos: 1. Abra Relatórios > Conversas; 2. Escolha o período no seletor de datas; 3. Ligue Horários de funcionamento se quiser descontar o tempo fora do expediente; 4. Compare os gráficos de conversas, mensagens, tempo de primeira resposta, tempo de resolução e tempo de espera do cliente; 5. Clique em Baixar relatórios de conversas para gerar o arquivo CSV.
- gotchas: o filtro Agrupar por só aparece quando o período tem 30 dias ou mais, abaixo disso tudo é mostrado por dia; clicar numa barra abre a lista de conversas daquela barra, mas só para administrador e só em barra com valor maior que zero; tempo de primeira resposta e tempo de resolução são médias apenas das conversas que tiveram resposta ou resolução, por isso somam menos que o total de conversas; com Horários de funcionamento ligado, o arquivo baixado vem com nome terminando em business-hours.
- nav_target: `conversation_reports`

### Abrir o desempenho de um agente por dentro
- intent: Por que o tempo de resposta desse agente subiu?; Quantas conversas essa pessoa resolveu no mês?; Em que dias ela atendeu mais?; Quais conversas entraram naquele pico do gráfico?; Como baixo isso em planilha?
- onde_fica: Relatórios > Agentes > clicar no nome do agente
- rota: `agent_reports_show` - `/app/accounts/:accountId/reports/agents/:id`
- gate: feature flag `reports`; papel `administrator` ou `report_manage`
- pre_requisitos: o agente precisa existir e ter conversas atribuídas no período
- passos: 1. Abra Relatórios > Agentes; 2. Clique no nome da pessoa na tabela; 3. Ajuste o período e, se quiser, ligue Horários de funcionamento; 4. Clique numa barra para ver as conversas daquele dia; 5. Use a seta de voltar para retornar à lista.
- gotchas: o relatório de agente não tem gráfico de mensagens recebidas, porque mensagem do cliente não é atribuída a um agente; o botão de baixar gera o arquivo de todos os agentes do período, não apenas o da pessoa aberta na tela; trocar de agente pelo filtro do topo recarrega a tela inteira; ver as conversas por trás de uma barra é restrito a administrador.
- nav_target: `agent_reports_show`

### Abrir o desempenho de um canal por dentro
- intent: O WhatsApp está demorando mais que o site para responder?; Quantas mensagens esse canal recebeu na semana?; Em que dia esse canal teve mais conversa?; Quais conversas geraram aquele pico?
- onde_fica: Relatórios > Caixa de Entrada > clicar no nome da caixa
- rota: `inbox_reports_show` - `/app/accounts/:accountId/reports/inboxes/:id`
- gate: feature flag `reports`; papel `administrator` ou `report_manage`
- pre_requisitos: a caixa de entrada precisa existir e ter conversas no período
- passos: 1. Abra Relatórios > Caixa de Entrada; 2. Clique no nome do canal na tabela; 3. Ajuste o período e, se quiser, ligue Horários de funcionamento; 4. Clique numa barra para ver as conversas daquele dia; 5. Use a seta de voltar para retornar à lista.
- gotchas: o botão de baixar traz o arquivo de todas as caixas do período, não só a que está na tela; o filtro do topo troca de canal e recarrega tudo; os tempos médios consideram apenas conversas que tiveram primeira resposta ou resolução; abrir as conversas de uma barra é permitido apenas a administrador.
- nav_target: `inbox_reports_show`

### Abrir o desempenho de um time por dentro
- intent: O time de suporte está resolvendo mais rápido que o comercial?; Quantas conversas esse time atendeu no mês?; O tempo de espera do cliente nesse time caiu?; Quais conversas estão por trás desse número?
- onde_fica: Relatórios > Time > clicar no nome do time
- rota: `team_reports_show` - `/app/accounts/:accountId/reports/teams/:id`
- gate: feature flag `reports`; papel `administrator` ou `report_manage`
- pre_requisitos: o time precisa existir e ter conversas atribuídas a ele no período
- passos: 1. Abra Relatórios > Time; 2. Clique no nome do time na tabela; 3. Ajuste o período e, se quiser, ligue Horários de funcionamento; 4. Clique numa barra para ver as conversas daquele dia; 5. Use a seta de voltar para retornar à lista.
- gotchas: só entram conversas atribuídas ao time, então atendimento feito pela mesma pessoa fora do time não aparece aqui; o botão de baixar gera o arquivo de todos os times do período; trocar de time pelo filtro do topo substitui toda a tela; ver as conversas de uma barra é restrito a administrador.
- nav_target: `team_reports_show`

### Abrir o desempenho de uma etiqueta por dentro
- intent: Quantas conversas tiveram essa etiqueta no mês?; Reclamações estão crescendo?; Conversas com essa etiqueta demoram mais para resolver?; Quais conversas receberam essa etiqueta naquele dia?
- onde_fica: Relatórios > Etiquetas > clicar no nome da etiqueta
- rota: `label_reports_show` - `/app/accounts/:accountId/reports/labels/:id`
- gate: feature flag `reports`; papel `administrator` ou `report_manage`
- pre_requisitos: a etiqueta precisa estar criada e aplicada em conversas do período
- passos: 1. Abra Relatórios > Etiquetas; 2. Clique no nome da etiqueta na tabela; 3. Ajuste o período e, se quiser, ligue Horários de funcionamento; 4. Clique numa barra para ver as conversas daquele dia; 5. Use a seta de voltar para retornar à lista.
- gotchas: etiqueta criada mas nunca aplicada abre a tela zerada, e isso não é erro; o botão de baixar gera o arquivo de todas as etiquetas do período; trocar de etiqueta pelo filtro do topo recarrega a tela inteira; só administrador abre a lista de conversas por trás de uma barra.
- nav_target: `label_reports_show`

### Medir o quanto o robô resolve sozinho
- intent: Quantas conversas o robô atendeu sem passar para ninguém?; Qual a taxa de transferência para os atendentes?; O robô está resolvendo mais do que no mês passado?; Quantas respostas o robô enviou?
- onde_fica: Relatórios > Robôs
- rota: `bot_reports` - `/app/accounts/:accountId/reports/bot`
- gate: feature flag `reports`; papel `administrator` ou `report_manage`
- pre_requisitos: ter conversas atendidas por robô no período
- passos: 1. Abra Relatórios > Robôs; 2. Escolha o período; 3. Leia os quadros de conversas, total de respostas, taxa de resolução e taxa de entrega; 4. Acompanhe a evolução nos gráficos de resolução e de transferências; 5. Clique numa barra para ver as conversas daquele dia.
- gotchas: esta tela não tem o botão Horários de funcionamento, tudo é contado no dia inteiro, diferente das demais; também não tem botão de baixar, os números ficam só na tela; taxa de resolução e taxa de entrega aparecem como dois tracinhos quando o valor é zero; os quadros do topo usam o período inteiro e ignoram o agrupamento por semana ou mês, que vale só para os gráficos; taxa de entrega alta significa que o robô passou muita conversa para gente, o que costuma ser sinal de fluxo incompleto.
- nav_target: `bot_reports`

### Escolher como as conversas são distribuídas
- intent: Onde eu configuro a distribuição automática de conversas?; Como escolher entre política de atribuição e capacidade do agente?; Onde fica a configuração de passagem da IA para uma pessoa?; Por que só aparece um card nessa tela?
- onde_fica: Configurações > Atribuição de Agentes
- rota: `assignment_policy_index` - `/app/accounts/:accountId/settings/assignment-policy/index`
- gate: feature flag `assignment_v2`; papel `administrator`
- pre_requisitos: ser administrador da conta
- passos: 1. Abra Configurações > Atribuição de Agentes; 2. Leia os cards e decida o que quer ajustar; 3. Clique em Política de atribuição para a ordem do rodízio, em Capacidade do agente para limitar quantas conversas cada pessoa aguenta, ou em Handoff da IA para a passagem da IA para uma pessoa.
- gotchas: a tela mostra de um a três cards conforme o que a conta tem liberado; Política de atribuição aparece sempre, Capacidade do agente só com atribuição avançada, e Handoff da IA só com o CRM e a IA do CRM ligados; card que sumiu é liberação de recurso, não erro.
- nav_target: `assignment_policy_index`

### Ver e organizar as políticas de atribuição
- intent: Quais políticas de atribuição já existem?; Quais caixas de entrada estão em cada política?; Como apago uma política que não uso mais?; Onde crio uma política nova?
- onde_fica: Configurações > Atribuição de Agentes > Política de atribuição
- rota: `agent_assignment_policy_index` - `/app/accounts/:accountId/settings/assignment-policy/assignment`
- gate: feature flag `assignment_v2`; papel `administrator`
- pre_requisitos: ser administrador da conta
- passos: 1. Abra Configurações > Atribuição de Agentes e clique em Política de atribuição; 2. Confira a ordem, a prioridade e as caixas de cada política; 3. Use Nova política para criar, Alterar para editar ou o botão de excluir para remover.
- gotchas: cada caixa de entrada fica em uma política só, então a mesma caixa nunca aparece em duas linhas; excluir pede confirmação e não tem volta, e as caixas daquela política ficam sem regra de distribuição; conta nova mostra a lista vazia, o que é normal.
- nav_target: `agent_assignment_policy_index`

### Criar uma regra nova de distribuição de conversas
- intent: Como crio uma política de atribuição do zero?; Qual a diferença entre rodízio e equilibrado?; Como evito que um agente receba conversa demais?; Por que o modo Equilibrado está bloqueado?
- onde_fica: Configurações > Atribuição de Agentes > Política de atribuição > Nova política
- rota: `agent_assignment_policy_create` - `/app/accounts/:accountId/settings/assignment-policy/assignment/create`
- gate: feature flag `assignment_v2`; papel `administrator`
- pre_requisitos: ser administrador da conta
- passos: 1. Clique em Nova política; 2. Preencha nome e descrição; 3. Escolha a ordem de atribuição e a prioridade; 4. Ajuste a distribuição justa e o descarte de conversas inativas; 5. Clique em Criar política.
- gotchas: nome e descrição são obrigatórios e o botão fica travado sem os dois; a política nasce com rodízio, 100 conversas por hora por agente e descarte de conversas paradas há mais de 7 dias; Equilibrado exige o plano com atribuição avançada; não dá para escolher as caixas de entrada aqui, só depois de salvar, na tela de edição, para onde o sistema leva sozinho.
- nav_target: `agent_assignment_policy_create`

### Ajustar uma política existente e ligar as caixas de entrada
- intent: Como coloco uma caixa de entrada nessa política?; Como mudo o limite de conversas por agente?; Como tiro uma caixa de entrada da política?; Por que a caixa saiu da outra política quando eu vinculei aqui?
- onde_fica: Configurações > Atribuição de Agentes > Política de atribuição > Alterar
- rota: `agent_assignment_policy_edit` - `/app/accounts/:accountId/settings/assignment-policy/assignment/edit/:id`
- gate: feature flag `assignment_v2`; papel `administrator`
- pre_requisitos: ter uma política de atribuição já criada
- passos: 1. Na lista, clique em Alterar na política desejada; 2. Ajuste ordem, prioridade, distribuição justa e descarte de inativas; 3. Clique em Atualizar política para gravar esses campos; 4. Em Caixas de entrada adicionadas, vincule e desvincule as caixas.
- gotchas: esta é a única tela com a seção de caixas de entrada, e já vem preenchida com a política existente; uma caixa só pode estar em uma política, e vincular aqui desvincula da anterior, com aviso antes; vincular e desvincular caixa vale na hora, enquanto os demais campos só valem depois do botão Atualizar política; o intervalo de conversas inativas aceita de 1 hora a 999 dias, e em branco desliga o descarte.
- nav_target: `agent_assignment_policy_edit`

### Ver quanto cada pessoa aguenta de conversa
- intent: Onde defino o limite de conversas por agente?; Quais políticas de capacidade já existem?; Quem está em cada política de capacidade?; Como apago uma política de capacidade?
- onde_fica: Configurações > Atribuição de Agentes > Capacidade do agente
- rota: `agent_capacity_policy_index` - `/app/accounts/:accountId/settings/assignment-policy/capacity`
- gate: feature flag `advanced_assignment`; papel `administrator`
- pre_requisitos: ter atribuição avançada liberada no plano e ser administrador
- passos: 1. Abra Configurações > Atribuição de Agentes e clique em Capacidade do agente; 2. Confira os agentes e os limites de cada política; 3. Use Nova política para criar, Alterar para editar ou o botão de excluir para remover.
- gotchas: a capacidade só muda a distribuição de verdade quando a política de atribuição da caixa está no modo Equilibrado, que também depende do plano; cada agente pertence a uma única política de capacidade; excluir pede confirmação e não tem volta.
- nav_target: `agent_capacity_policy_index`

### Criar uma regra de limite de conversas
- intent: Como crio uma política de capacidade?; Como limito o número máximo de conversas por caixa?; Quais conversas não devem contar no limite do agente?; Onde adiciono os agentes nessa política?
- onde_fica: Configurações > Atribuição de Agentes > Capacidade do agente > Nova política
- rota: `agent_capacity_policy_create` - `/app/accounts/:accountId/settings/assignment-policy/capacity/create`
- gate: feature flag `advanced_assignment`; papel `administrator`
- pre_requisitos: ter atribuição avançada liberada no plano
- passos: 1. Clique em Nova política; 2. Preencha nome e descrição; 3. Defina as regras de exclusão, escolhendo as etiquetas e o tempo que não contam na capacidade; 4. Clique em Criar política.
- gotchas: a política nasce sem ninguém dentro, porque as seções de limite por caixa e de agentes só existem na tela de edição, para onde o sistema leva ao salvar; as etiquetas de exclusão precisam já existir na conta para poderem ser escolhidas.
- nav_target: `agent_capacity_policy_create`

### Colocar agentes e limites numa política de capacidade
- intent: Como adiciono agentes a uma política de capacidade?; Como defino o máximo de conversas por caixa de entrada?; Como mudo a capacidade de uma pessoa específica?; Por que o agente saiu da outra política de capacidade?
- onde_fica: Configurações > Atribuição de Agentes > Capacidade do agente > Alterar
- rota: `agent_capacity_policy_edit` - `/app/accounts/:accountId/settings/assignment-policy/capacity/edit/:id`
- gate: feature flag `advanced_assignment`; papel `administrator`
- pre_requisitos: ter uma política de capacidade criada e os agentes cadastrados na conta
- passos: 1. Na lista, clique em Alterar na política desejada; 2. Em limites por caixa de entrada, escolha a caixa e o máximo de conversas; 3. Em agentes atribuídos, use Adicionar agente; 4. Ajuste nome, descrição e regras de exclusão e clique em Atualizar política.
- gotchas: todo agente entra com capacidade 20 por padrão, então ajuste se o time não for homogêneo; um agente só pode estar em uma política de capacidade, e vincular aqui tira ele da anterior; mexer em agente e em limite por caixa vale na hora, enquanto nome, descrição e exclusões só valem depois do botão Atualizar política.
- nav_target: `agent_capacity_policy_edit`

### Escolher o funil para configurar a passagem da IA
- intent: Onde configuro a IA passando o atendimento para uma pessoa?; Em quais funis o handoff já está ligado?; Por que essa tela não aparece para mim?; Como reviso a passagem da IA de um funil específico?
- onde_fica: Configurações > Handoff da IA (CRM)
- rota: `crm_handoff_settings_index` - `/app/accounts/:accountId/settings/assignment-policy/handoff`
- gate: feature flag `crm`; papel `administrator` ou `crm_manage_ai`
- pre_requisitos: CRM Kanban e IA do CRM ligados, pelo menos um funil criado, e permissão de administrador
- passos: 1. Abra Configurações > Handoff da IA (CRM); 2. Veja na etiqueta de cada funil se está ligado e em qual fluxo; 3. Clique no funil que quer configurar.
- gotchas: aqui nada é configurado, é só a lista de escolha; a etiqueta reflete o padrão do funil, não as personalizações por etapa; com o CRM ou a IA do CRM desligados a plataforma devolve você à tela inicial sem avisar; sem funil criado a lista fica vazia.
- nav_target: `crm_handoff_settings_index`

### Definir quando e para quem a IA passa a conversa
- intent: Como faço a IA chamar um humano no meio do atendimento?; Qual a diferença entre transferir direto e por convite?; O que acontece se ninguém pegar a conversa?; Como coloco uma regra diferente só em uma etapa do funil?; Como escolho quem recebe a conversa?
- onde_fica: Configurações > Handoff da IA (CRM) > nome do funil
- rota: `crm_handoff_settings_edit` - `/app/accounts/:accountId/settings/assignment-policy/handoff/:pipelineId`
- gate: feature flag `crm`; papel `administrator` ou `crm_manage_ai`
- pre_requisitos: um funil com etapas criadas, caixas vinculadas ao funil e agentes cadastrados
- passos: 1. Escolha o funil no seletor do topo; 2. No padrão do funil, ligue a passagem para humano e escreva quando transferir; 3. Escolha direto ou convite e o destino; 4. Defina o tempo de espera e o que fazer se ninguém pegar; 5. Nas personalizações por etapa, deixe em Padrão o que herda e personalize onde a regra é diferente; 6. Salve.
- gotchas: a passagem só acontece de verdade quando o funil está configurado E a caixa tem atendente como membro: caixa sem membro deixa a promessa de que alguém vai assumir sem ninguém para atribuir, e nada na tela avisa isso; salvar grava o padrão e todas as etapas de uma vez, inclusive etapa que você deixou pela metade; etapa marcada como Padrão herda e ignora o que estiver preenchido nela; no rodízio a equipe sai da caixa em que a conversa chegou; direto atribui na hora, a IA para de responder e só entrega para quem está online, enquanto convite notifica e a IA continua atendendo até alguém pegar; o tempo de espera padrão é 15 minutos, re-notificar avisa até 8 vezes e escalar exige escolher a pessoa.
- nav_target: `crm_handoff_settings_edit`

### Fechar conversas paradas e exigir campos na resolução
- intent: Como fecho automaticamente conversa que ficou parada?; Como obrigo o agente a preencher campos antes de resolver?; Dá para avisar o cliente quando a conversa fecha sozinha?; Como marco com etiqueta as conversas fechadas automaticamente?
- onde_fica: Configurações > Fluxo de Conversa
- rota: `conversation_workflow_index` - `/app/accounts/:accountId/settings/conversation-workflow`
- gate: papel `administrator`
- pre_requisitos: ser administrador; para os campos obrigatórios, ter atributos personalizados de conversa já criados
- passos: 1. Abra Configurações > Fluxo de Conversa; 2. Na resolução automática, defina a inatividade, a mensagem enviada ao cliente e a etiqueta aplicada; 3. Salve; 4. Em atributos obrigatórios, adicione os campos que o agente precisa preencher antes de resolver.
- gotchas: as duas seções são independentes e cada uma depende de estar liberada na conta; a duração da resolução automática aceita de 10 minutos a 999 dias; a opção de pular conversas aguardando resposta do agente evita fechar quem está esperando você; só dá para exigir atributo de conversa que já existe, então crie o atributo antes.
- nav_target: `conversation_workflow_index`

### Acompanhar quanto a IA está custando
- intent: Quanto gastei de IA esse mês?; Qual recurso de IA consome mais?; Como exporto o relatório de uso da IA?; Por que os valores apareceram em dólar?; Dá para ver o que foi conversado com a IA?
- onde_fica: CRM > Gestão de IA
- rota: `crm_ai_usage_index` - `/app/accounts/:accountId/crm/ai-usage`
- gate: papel `administrator` ou `agent` ou `crm_view_reports`
- pre_requisitos: CRM e IA do CRM ligados, e permissão de ver relatórios do CRM
- passos: 1. Abra CRM > Gestão de IA; 2. Escolha o período entre hoje, semana e mês; 3. Leia os indicadores de gasto, usos, economia e custo médio; 4. Confira o gasto por recurso e o histórico; 5. Use baixar relatório para exportar o período.
- gotchas: a tela é só de leitura, não limita gasto nem desliga IA; só existem os três períodos fixos, sem intervalo personalizado; os valores vêm em dólar e são convertidos, e quando a cotação está indisponível a tela avisa e mostra em dólar; o conteúdo das conversas com a IA nunca aparece aqui, só quantidade e custo.
- nav_target: `crm_ai_usage_index`

### Ver o plano contratado e quanto está sendo cobrado
- intent: Qual plano eu contratei?; Quanto eu pago por mês?; Quando vence a próxima cobrança?; O que compõe o valor da minha assinatura?; Minha assinatura está ativa?
- onde_fica: Financeiro > Assinatura
- rota: `autonomia_financial_subscription` - `/app/accounts/:accountId/financial/subscription`
- gate: papel `administrator`
- pre_requisitos: ser administrador da conta e ter um checkout já concluído
- passos: 1. Abra Financeiro > Assinatura; 2. Leia os cartões de status, total mensal, total anual e próximo vencimento; 3. Confira o plano, o ciclo e a quantidade no resumo; 4. Desça até a composição da cobrança para ver item a item o que soma no total.
- gotchas: a tela é só de leitura, não existe botão para cancelar, trocar de plano ou pagar por aqui; o menu Financeiro só aparece para administrador; sem assinatura a tela diz que nenhuma foi encontrada; o próximo vencimento vem do fim do período atual ou do fim do teste, e não é data de boleto.
- nav_target: `autonomia_financial_subscription`

### Conferir faturas emitidas e o que já foi pago
- intent: Tenho alguma fatura em aberto?; Onde baixo o documento da fatura?; Quando essa fatura venceu?; Meu pagamento foi registrado?; Quanto eu já paguei até agora?
- onde_fica: Financeiro > Faturas
- rota: `autonomia_financial_invoices` - `/app/accounts/:accountId/financial/invoices`
- gate: papel `administrator`
- pre_requisitos: ser administrador da conta
- passos: 1. Abra Financeiro > Faturas; 2. Veja no topo o total em aberto, quantas estão pagas e quantos pagamentos existem; 3. Na tabela, olhe valor, status, vencimento e data de pagamento; 4. Use abrir fatura para ver o documento da cobrança; 5. Desça até pagamentos para conferir origem e data de cada um.
- gotchas: a tela não cobra, não paga e não emite fatura, só mostra o que o sistema de cobrança registrou; o link de abrir fatura só existe quando a cobrança tem documento; o total em aberto soma pendentes e vencidas juntas, sem separar; a origem mostra o meio de pagamento e cai para manual quando o pagamento foi lançado à mão.
- nav_target: `autonomia_financial_invoices`

### Conectar pelo QR Code o WhatsApp que criaram para você
- intent: Meu WhatsApp está conectado?; Como leio o QR Code para conectar?; Por que parei de receber mensagens?; Como reconecto meu número?; Onde vejo o status da minha conexão?
- onde_fica: menu do seu perfil > Status Conexão
- rota: `autonomia_invite_connection` - `/app/accounts/:accountId/autonomia/invite-connection`
- gate: papel `administrator` ou `agent` ou `custom_role`
- pre_requisitos: existir uma caixa de entrada criada por convite vinculada ao seu usuário, e estar com o celular em mãos
- passos: 1. Abra o menu do seu perfil e clique em Status Conexão; 2. Veja a etiqueta de status ao lado do número; 3. Estando desconectado, gere um novo QR Code; 4. No celular, abra o WhatsApp em aparelhos conectados e toque em conectar um aparelho; 5. Aponte para o código e espere virar conectado.
- gotchas: o item de menu só aparece para quem tem caixa criada por convite; leia o código pelo próprio WhatsApp, não pela câmera do celular; o QR expira em cerca de dois minutos e meio, então gere com o celular já na mão; a tela se atualiza sozinha, sem precisar recarregar; o número precisa ser o mesmo da caixa de entrada, ler com outro celular não conecta a caixa certa.
- nav_target: `autonomia_invite_connection`

### Procurar empresas por região e transformar em contato ou card
- intent: Como acho empresas de um segmento na minha cidade?; Como priorizo quem ligar primeiro?; Como viro esse lead em contato?; Dá para criar card no CRM a partir da busca?
- onde_fica: Prospecção > Buscar leads
- rota: `autonomia_prospecting_search` - `/app/accounts/:accountId/autonomia/prospecting/search`
- gate: papel `administrator` ou `prospecting_view` ou `prospecting_manage`
- pre_requisitos: módulo de Prospecção habilitado e a chave de busca configurada em Configurações > Prospecção
- passos: 1. Abra Prospecção > Buscar leads e clique em nova busca; 2. Escreva o segmento e a localização e escolha uma sugestão; 3. Defina a área, o limite e a forma de pesquisa; 4. Busque e ordene por maior prioridade; 5. Abra os detalhes de um lead para ver reputação e fatores de atenção; 6. Use criar contato, criar card, ou selecione vários e aplique em lote.
- gotchas: sem a chave de busca configurada as sugestões não aparecem e a busca não devolve empresas; o mapa usa uma segunda chave e, sem ela, a busca funciona mas o mapa não abre; criar card exige um funil ativo configurado; a conta tem limite diário e mensal, e a busca para ao bater o limite; excluir uma busca do histórico não apaga os leads já salvos.
- nav_target: `autonomia_prospecting_search`

### Juntar leads em listas e preparar um público de campanha
- intent: Como separo os leads por praça ou campanha?; Como adiciono leads a uma lista?; Como uso esses leads numa campanha?; Quantos leads da lista estão prontos para campanha?
- onde_fica: Prospecção > Listas
- rota: `autonomia_prospecting_lists` - `/app/accounts/:accountId/autonomia/prospecting/lists`
- gate: papel `administrator` ou `prospecting_view` ou `prospecting_manage`
- pre_requisitos: já ter leads salvos por uma busca de prospecção
- passos: 1. Abra Prospecção > Listas e crie uma nova lista; 2. Dê um nome de campanha, praça ou segmento; 3. Selecione a lista para ver os leads e os números de prontos, contatos, CRM e bloqueados; 4. Busque e adicione leads; 5. Em campanha, dê nome ao público e crie o público.
- gotchas: criar o público só gera o segmento por etiqueta, nada é disparado automaticamente e a campanha continua sendo você quem dispara; lead bloqueado por status ou consentimento entra na conta de bloqueados e fica de fora do público; a busca de leads disponíveis só mostra quem ainda não está na lista; remover um lead da lista não apaga o lead nem o contato criado a partir dele.
- nav_target: `autonomia_prospecting_lists`

### Ajustar chaves, limites e critérios de score da prospecção
- intent: Onde coloco a chave do Google?; Por que o mapa não aparece na busca?; Como mudo o funil padrão dos cards?; Como limito quantas buscas podem ser feitas por dia?; Como mudo o peso do score dos leads?
- onde_fica: Configurações > Prospecção
- rota: `settings_prospecting_index` - `/app/accounts/:accountId/settings/prospecting`
- gate: papel `administrator` ou `prospecting_manage`
- pre_requisitos: ser administrador ou ter a permissão de gerenciar prospecção
- passos: 1. Abra Configurações > Prospecção; 2. Na aba geral, cole a chave de busca de locais e a chave de exibição do mapa; 3. Defina o funil e a etapa padrão usados ao criar cards; 4. Ajuste limite por busca, cache e limites diário e mensal; 5. Na aba score, escolha um perfil ou mude para customizado para editar os pesos; 6. Salve.
- gotchas: são duas chaves com funções diferentes, uma alimenta a busca e as sugestões, a outra só desenha o mapa; chave já gravada não é exibida de volta, e preencher o campo substitui a anterior; os pesos do score só ficam editáveis no modo customizado; a forma de pesquisa muda o sentido do score, priorizando quem tem lacunas no perfil ou quem já é mais estruturado.
- nav_target: `autonomia_prospecting_settings`

### Entrar na área de Cotação da corretora
- intent: Onde fica a parte de seguros?; Como abro a cotação?; Por que o menu Cotação não aparece para mim?; O que existe dentro de Cotação?
- onde_fica: Cotação
- rota: `autonomia_insurance` - `/app/accounts/:accountId/autonomia/insurance`
- gate: papel `administrator` ou `insurance_view` ou `insurance_manage`
- pre_requisitos: módulo de Cotação habilitado para a conta
- passos: 1. Clique em Cotação na barra lateral; 2. Você cai direto em Conexões; 3. Use as abas do topo para alternar entre Conexões e Agente.
- gotchas: Cotação não é uma tela própria, é a porta de entrada que leva sempre para Conexões; o módulo depende de duas chaves ligadas, a da instalação e a da conta, e com qualquer uma desligada o item some do menu; só existem essas duas abas.
- nav_target: `autonomia_insurance`

### Ligar a conta da corretora e ver o que dá para cotar
- intent: Como conecto a corretora?; Por que a cotação não está funcionando?; Quais produtos a minha conta cota hoje?; Por que uma seguradora não está cotando?; A senha fica guardada onde?
- onde_fica: Cotação > Conexões
- rota: `autonomia_insurance_connections` - `/app/accounts/:accountId/autonomia/insurance/connections`
- gate: papel `administrator` ou `insurance_view` ou `insurance_manage`
- pre_requisitos: usuário e senha da corretora no portal, e o módulo de Cotação habilitado
- passos: 1. Abra Cotação > Conexões; 2. Preencha usuário e senha e conecte; 3. Espere o estado chegar em conectado; 4. Leia o veredito do topo, que diz quantos produtos estão prontos para cotar; 5. Confira produto a produto quantas seguradoras respondem; 6. Atualize os produtos quando a corretora habilitar algo novo.
- gotchas: credencial recusada quer dizer que o portal negou o acesso, e o conserto é lá, não aqui; a verificação da sessão é periódica, então a tela mostra a última checagem e não o estado deste segundo; atualizar produtos leva cerca de meio minuto e a tela se atualiza sozinha; ramo que a corretora não tem habilitado no portal não aparece na lista; seguradora com credencial recusada simplesmente não cota, e o cliente nunca vê esse aviso.
- nav_target: `autonomia_insurance_connections`

### Criar o agente que cota com o cliente no WhatsApp
- intent: Como crio o agente de cotação?; Dá para mudar o nome e o tom do agente?; O agente já sabe cotar sozinho?; Posso ter mais de um agente de cotação?; Onde edito o agente depois de criado?
- onde_fica: Cotação > Agente
- rota: `autonomia_insurance_agent` - `/app/accounts/:accountId/autonomia/insurance/agent`
- gate: papel `administrator` ou `insurance_view` ou `insurance_manage`
- pre_requisitos: conexão com a seguradora já funcionando e permissão de gerenciar o módulo de Cotação
- passos: 1. Abra Cotação > Agente; 2. Clique em configurar e criar; 3. Informe o nome do agente e o nome da corretora; 4. Escreva o horário em que a sua equipe assume; 5. Escolha o comportamento, consultivo ou objetivo; 6. Crie o agente e siga editando em Meus agentes.
- gotchas: é um agente de cotação por conta, e se já existir a tela mostra o que existe em vez de criar outro; nome do agente e da corretora são obrigatórios; o horário precisa ser texto simples de dias e horas; a jornada de cotação, os formulários e as regras de segurança são mantidos pela plataforma e não se editam aqui, você muda identidade, horário e comportamento; nos dois comportamentos o agente responde cobertura consultando as condições gerais, nunca de memória.
- nav_target: `autonomia_insurance_agent`

### Ligar a verificação em duas etapas da sua conta
- intent: Como ativo a verificação em duas etapas?; Onde configuro o segundo fator do meu usuário?; O que acontece se eu perder o celular com o aplicativo?; Onde pego novos códigos de recuperação?; Como desligo a verificação em duas etapas?
- onde_fica: Menu do usuário > Configurações do perfil > Autenticação em Dois Fatores
- rota: `profile_settings_mfa` - `/app/accounts/:accountId/profile/mfa`
- gate: papel `administrator` ou `agent` ou `custom_role`
- pre_requisitos: um aplicativo autenticador no celular, e a senha atual, que é exigida para desligar
- passos: 1. Abra Configurações do perfil; 2. Em Autenticação em Dois Fatores, clique em gerenciar; 3. Habilite a verificação; 4. Leia o QR Code no aplicativo, ou copie a chave se não conseguir escanear; 5. Digite o código de 6 dígitos e confirme; 6. Guarde os códigos de recuperação e finalize.
- gotchas: os códigos de recuperação só aparecem uma vez, logo depois da verificação, e cada um serve para um único uso; perdendo o celular, entrar com um código de recuperação é a única saída sem ajuda externa, e perdendo o celular e os códigos só o suporte resolve; gerar novos códigos invalida todos os antigos na hora; para desligar, a plataforma pede a senha mais um código; se a verificação estiver desligada na instalação inteira, a tela nem abre.
- nav_target: `profile_settings_mfa`

### Ver o histórico de chamadas e ouvir gravações
- intent: Onde vejo as ligações que entraram?; Como acho as chamadas perdidas?; Onde ouço a gravação de uma ligação?; Como vejo as chamadas de um agente específico?; Por que a tela de chamadas está vazia?
- onde_fica: Chamadas
- rota: `calls_dashboard_index` - `/app/accounts/:accountId/calls`
- gate: papel `agent` ou `administrator` ou `conversation_manage` ou `conversation_unassigned_manage` ou `conversation_participating_manage`
- pre_requisitos: recurso de voz liberado na conta e uma caixa de entrada com voz habilitada
- passos: 1. Abra Chamadas; 2. Use os atalhos de perdidas e sem resposta para ir ao que precisa de retorno; 3. Escolha entre recebidas, efetuadas ou em andamento; 4. Filtre por caixa de entrada, e por agente se você for administrador; 5. Ouça a gravação na linha da chamada, quando existir; 6. Clique no número da conversa para abrir o atendimento ligado a ela.
- gotchas: sem canal de voz configurado a tela mostra o convite para configurar, e não uma lista vazia; quem não é administrador vê apenas as próprias chamadas, por isso o filtro de agente nem aparece; perdidas é chamada que entrou e ninguém atendeu, sem resposta é chamada que você fez e não atenderam; gravação só aparece se o provedor gravou aquela chamada; os filtros ficam no endereço da página, então o link copiado reabre a mesma visão.
- nav_target: `calls_dashboard_index`

### Ver quem está no site neste momento
- intent: Quem está no meu site agora?; O que significa a lista Ativo em Contatos?; Por que meus contatos de WhatsApp não aparecem em Ativo?; Como falo com quem está navegando agora?
- onde_fica: Contatos > Ativo
- rota: `contacts_dashboard_active` - `/app/accounts/:accountId/contacts/active`
- gate: feature flag `crm`; papel `administrator` ou `agent` ou `contact_manage` ou `contact_view`
- pre_requisitos: canal de chat ao vivo instalado no site, que é o que informa presença
- passos: 1. Abra Contatos; 2. Clique em Ativo; 3. Confira quem está presente agora; 4. Abra o contato para ver a ficha ou iniciar uma conversa; 5. Volte a todos os contatos quando quiser a base inteira.
- gotchas: presença é medida em segundos, não em dias, então a lista muda sozinha o tempo todo e o contato sai dela pouco depois de fechar a página; quem fala por WhatsApp ou e-mail não aparece aqui mesmo tendo conversado há pouco, porque não há sessão aberta no site; lista vazia quase sempre significa ninguém no site, não erro; o botão de filtros do cabeçalho não funciona nesta visão.
- nav_target: `contacts_dashboard_active`

### Abrir a ficha de um contato e juntar cadastros repetidos
- intent: Onde edito os dados de um cliente?; Como vejo todas as conversas que já tive com esta pessoa?; Como junto dois cadastros do mesmo cliente?; Onde bloqueio um contato?; Onde anoto informações sobre o cliente?
- onde_fica: Contatos > clicar no contato
- rota: `contacts_edit` - `/app/accounts/:accountId/contacts/:contactId`
- gate: feature flag `crm`; papel `administrator` ou `agent` ou `contact_manage` ou `contact_view`
- pre_requisitos: contato já cadastrado
- passos: 1. Abra Contatos e clique no contato; 2. Ajuste os dados à esquerda e salve; 3. Use as abas de atributos, histórico, notas, mídia e mesclar; 4. Em histórico, veja as conversas anteriores; 5. Em notas, registre o que a equipe precisa saber; 6. Para juntar cadastros repetidos, abra mesclar, escolha o contato principal e confirme.
- gotchas: ao mesclar, o contato principal é o que sobrevive e o outro é excluído, com os dados do principal prevalecendo em caso de conflito, e não há desfazer; excluir contato é permanente; bloquear não apaga o contato, só impede novo contato; e-mail ou telefone repetido é recusado por já pertencer a outro cadastro; abrindo a ficha a partir de um segmento ou de uma etiqueta, a tela é a mesma e o voltar devolve para aquela lista.
- nav_target: `contacts_edit`

### Cadastrar empresas e achar a que você procura
- intent: Onde cadastro uma empresa?; Como agrupo os contatos de uma mesma empresa?; Onde busco uma empresa pelo nome ou domínio?; Por que não vejo Empresas no menu?
- onde_fica: Empresas
- rota: `companies_dashboard_index` - `/app/accounts/:accountId/companies`
- gate: feature flag `companies`; papel `administrator` ou `agent`
- pre_requisitos: recurso de Empresas liberado na conta
- passos: 1. Abra Empresas; 2. Busque pelo nome ou domínio; 3. Ajuste a ordenação; 4. Clique em adicionar empresa e preencha os dados; 5. Ao salvar, a plataforma abre a ficha da empresa criada.
- gotchas: Empresas é liberado por conta, então pode simplesmente não aparecer no menu; criar a empresa não vincula contato nenhum, o vínculo é feito dentro da ficha ou pelo campo empresa do contato; busca e ordenação ficam no endereço da página, então dá para compartilhar o link já filtrado.
- nav_target: `companies_dashboard_index`

### Ver a empresa por dentro e vincular os contatos dela
- intent: Como vinculo um contato a uma empresa?; Onde vejo as conversas dos contatos de uma empresa?; Como tiro um contato de uma empresa?; O que acontece com os contatos se eu excluir a empresa?
- onde_fica: Empresas > clicar na empresa
- rota: `companies_dashboard_show` - `/app/accounts/:accountId/companies/:companyId`
- gate: feature flag `companies`; papel `administrator` ou `agent`
- pre_requisitos: empresa cadastrada e contatos existentes para vincular
- passos: 1. Abra Empresas e clique na empresa; 2. Ajuste nome, domínio, descrição e avatar e atualize; 3. Use as abas de histórico, notas e contatos; 4. Em contatos, adicione pesquisando e confirmando o vínculo; 5. Use remover para desvincular.
- gotchas: vincular um contato que já pertence a outra empresa é reatribuição, não cópia, e a tela avisa a qual empresa ele está ligado hoje; histórico e notas vêm dos contatos vinculados, então empresa sem contato aparece vazia; excluir a empresa é irreversível e desvincula todos os contatos, mas os contatos continuam na conta.
- nav_target: `companies_dashboard_show`

### Abrir a Central de Ajuda no portal certo
- intent: Onde fica a Central de Ajuda?; Por que abriu outro portal?; Como troco de portal?; Sumiu a Central de Ajuda do menu, e agora?
- onde_fica: Central de Ajuda
- rota: `portals_index` - `/app/accounts/:accountId/portals/:navigationPath`
- gate: feature flag `help_center`; papel `administrator` ou `knowledge_base_manage`
- pre_requisitos: recurso de Central de Ajuda liberado na conta, e permissão de gerenciar base de conhecimento
- passos: 1. Clique em Central de Ajuda e escolha artigos, categorias, localidades ou configurações; 2. a tela abre o último portal e idioma que você usou; 3. se o portal lembrado não existir mais, ela abre o primeiro portal da conta.
- gotchas: não é uma tela de verdade, é um redirecionamento, por isso o endereço muda sozinho; sem nenhum portal criado, ela leva direto à criação; a lembrança do último portal é de cada usuário, então dois colegas podem abrir portais diferentes pelo mesmo item do menu.
- nav_target: `portals_index`

### Criar o portal da central de ajuda
- intent: Como crio uma central de ajuda?; O que é portal?; O que preencho para criar o portal?; Onde escolho o endereço do portal?
- onde_fica: Central de Ajuda > Criar portal
- rota: `portals_new` - `/app/accounts/:accountId/portals/new`
- gate: feature flag `help_center`; papel `administrator` ou `knowledge_base_manage`
- pre_requisitos: permissão de gerenciar base de conhecimento
- passos: 1. Clique em criar portal; 2. preencha o nome; 3. confira o endereço, preenchido sozinho a partir do nome; 4. crie; 5. o portal abre já na lista de artigos.
- gotchas: só existem dois campos aqui, e logo, cor, domínio e integrações ficam para depois, em configurações; o endereço só aceita letras, números e hífen; o portal nasce com inglês como idioma padrão, então adicione o português antes de escrever; mudar o endereço depois muda o link público.
- nav_target: `portals_new`

### Ajustar aparência, domínio e integrações do portal
- intent: Como coloco meu domínio na central de ajuda?; Onde troco o logo e a cor?; Como ligo o chat ao vivo no portal?; Como coloco a medição de acesso?; Como excluo um portal?
- onde_fica: Central de Ajuda > Configurações
- rota: `portals_settings_index` - `/app/accounts/:accountId/portals/:portalSlug/settings`
- gate: feature flag `help_center`; papel `administrator` ou `agent` ou `knowledge_base_manage` ou `knowledge_base_view`
- pre_requisitos: portal criado, e acesso ao painel de DNS para usar domínio próprio
- passos: 1. Abra configurações e use as abas de geral, domínio, tema e integrações; 2. em geral ajuste logo, nome, textos e cor; 3. em domínio cadastre o seu endereço e aponte o registro indicado; 4. em tema escolha o leiaute e os links sociais; 5. em integrações ligue o chat ao vivo e as ferramentas de medição.
- gotchas: trocar o endereço recarrega a tela no link novo e os antigos deixam de funcionar; excluir o portal pede o nome na confirmação e é permanente; sendo o último portal, a tela volta para a criação; dá para enviar as instruções de DNS por e-mail para quem cuida do site; campo de integração em branco desliga aquela integração.
- nav_target: `portals_settings_index`

### Cuidar dos idiomas do portal
- intent: Como coloco a central de ajuda em português?; Como adiciono outro idioma?; O que é idioma em rascunho?; Como escolho o que aparece na página inicial do portal?
- onde_fica: Central de Ajuda > Localidades
- rota: `portals_locales_index` - `/app/accounts/:accountId/portals/:portalSlug/locales`
- gate: feature flag `help_center`; papel `administrator` ou `agent` ou `knowledge_base_manage` ou `knowledge_base_view`
- pre_requisitos: portal criado
- passos: 1. Abra localidades e veja o cartão de cada idioma; 2. adicione um idioma novo, escolhendo se entra publicado ou em rascunho; 3. use o menu do cartão para tornar padrão, publicar ou mover para rascunho; 4. localize o conteúdo daquele idioma; 5. escolha as categorias e artigos em destaque na página inicial.
- gotchas: idioma em rascunho não aparece para o visitante, e serve para montar o conteúdo antes de abrir; o idioma padrão é o que abre para quem entra e não pode ir para rascunho; campo em branco herda o valor do idioma padrão; artigos e categorias são por idioma, e escrever em português não gera as versões nos outros.
- nav_target: `portals_locales_index`

### Ver, filtrar e organizar os artigos do portal
- intent: Onde vejo todos os artigos?; Como acho um artigo específico?; Como publico vários artigos de uma vez?; Como mudo a ordem dos artigos dentro da categoria?; Onde estão meus rascunhos?
- onde_fica: Central de Ajuda > Artigos
- rota: `portals_articles_index` - `/app/accounts/:accountId/portals/:portalSlug/:locale/:categorySlug?/articles/:tab?`
- gate: feature flag `help_center`; papel `administrator` ou `agent` ou `knowledge_base_manage` ou `knowledge_base_view`
- pre_requisitos: portal criado com pelo menos um idioma
- passos: 1. Abra artigos; 2. escolha a aba de todos, meus, rascunho, publicado ou arquivado; 3. ajuste idioma e categoria; 4. busque pelo texto; 5. marque artigos para publicar, arquivar, mover de categoria ou excluir em lote.
- gotchas: trocar o idioma limpa o filtro de categoria; arrastar para reordenar só existe dentro de uma categoria, e não funciona com busca ativa; a ação em lote pula artigos publicados que têm edições não publicadas e avisa quantos ignorou, menos quando a ação é publicar; excluir em lote é definitivo.
- nav_target: `portals_articles_index`

### Escrever um artigo do zero
- intent: Como crio um artigo?; Em que categoria o artigo entra?; Como mudo o autor do artigo?; Escrevi o texto e não salvou, por quê?
- onde_fica: Central de Ajuda > Artigos > Novo artigo
- rota: `portals_articles_new` - `/app/accounts/:accountId/portals/:portalSlug/:locale/:categorySlug?/articles/new`
- gate: feature flag `help_center`; papel `administrator` ou `agent` ou `knowledge_base_manage` ou `knowledge_base_view`
- pre_requisitos: portal com o idioma escolhido e pelo menos uma categoria nesse idioma
- passos: 1. Clique em novo artigo; 2. escreva o título e clique fora do campo, o que cria o artigo como rascunho; 3. ajuste autor e categoria; 4. escreva o conteúdo; 5. a tela passa sozinha para a edição do artigo criado.
- gotchas: nada é salvo enquanto o título estiver vazio, porque é ele que cria o artigo; entrando pela categoria, o artigo já nasce nela, senão cai na primeira da lista; o salvamento automático do conteúdo só começa depois que o artigo existe; havendo arquivo subindo, a criação espera terminar.
- nav_target: `portals_articles_new`

### Editar, revisar e publicar um artigo
- intent: Editei o artigo e o site não mudou, por quê?; Como publico as alterações?; Como volto atrás numa edição?; Onde coloco título e descrição para busca?; Como vejo o artigo como o cliente vê?
- onde_fica: Central de Ajuda > Artigos > clicar no artigo
- rota: `portals_articles_edit` - `/app/accounts/:accountId/portals/:portalSlug/:locale/:categorySlug?/articles/:tab?/edit/:articleSlug`
- gate: feature flag `help_center`; papel `administrator` ou `agent` ou `knowledge_base_manage` ou `knowledge_base_view`
- pre_requisitos: artigo já criado
- passos: 1. Abra o artigo pela lista; 2. edite título e conteúdo, que salvam sozinhos; 3. pré-visualize para ver a página pública; 4. use o menu de status para publicar, voltar a rascunho ou arquivar; 5. em artigo publicado, publique as alterações, compare com o que está no ar ou descarte a edição.
- gotchas: em artigo já publicado a edição fica guardada e não vai ao ar até você publicar as alterações, e é por isso que o site continua mostrando o texto antigo; mudar o status com alterações pendentes pergunta antes se aplica ou descarta; publicar fica bloqueado enquanto um salvamento ou envio de arquivo está em andamento; título e descrição para busca ficam no painel de propriedades, não no corpo do texto.
- nav_target: `portals_articles_edit`

### Criar e ordenar as categorias do portal
- intent: Como agrupo os artigos por assunto?; Como crio uma categoria?; Como mudo a ordem das categorias no site?; Como renomeio ou excluo uma categoria?
- onde_fica: Central de Ajuda > Categorias
- rota: `portals_categories_index` - `/app/accounts/:accountId/portals/:portalSlug/:locale/categories`
- gate: feature flag `help_center`; papel `administrator` ou `agent` ou `knowledge_base_manage` ou `knowledge_base_view`
- pre_requisitos: portal criado com o idioma desejado
- passos: 1. Abra categorias e escolha o idioma; 2. crie a categoria com nome, endereço, descrição e ícone; 3. arraste os cartões para definir a ordem no portal público; 4. clique numa categoria para ver e reordenar os artigos dela.
- gotchas: categoria é por idioma, e criar em português não cria a equivalente nos outros; o endereço da categoria entra no link público; arrastar para reordenar não funciona com busca ativa; excluir pelo menu do cartão apaga na hora, sem tela de confirmação.
- nav_target: `portals_categories_index`

### Levar as conversas para o Slack
- intent: Como coloco as conversas no Slack?; Dá para responder o cliente de dentro do Slack?; Por que não acho o Slack nas integrações?; Conectei o Slack e nada chega, o que falta?
- onde_fica: Configurações > Integrações > Slack
- rota: `settings_integrations_slack` - `/app/accounts/:accountId/settings/integrations/slack`
- gate: feature flag `integrations`; papel `administrator`
- pre_requisitos: ser administrador, e a credencial do Slack configurada pelo time da plataforma, senão o cartão nem aparece
- passos: 1. Abra Configurações > Integrações; 2. Clique no cartão do Slack e conecte; 3. Autorize no seu espaço do Slack; 4. Escolha o canal; 5. Escolha entre sincronização nos dois sentidos e somente alertas.
- gotchas: autorizar não basta, a integração fica inativa até você escolher um canal; para canal privado, adicione o aplicativo ao canal no Slack antes; na sincronização nos dois sentidos tudo que a equipe escrever na conversa do Slack vai para o cliente, e só vira nota interna com o prefixo note:; a resposta só sai com o nome do agente se o e-mail dele no Slack for o mesmo da plataforma; quando a conexão expira, a saída é excluir e conectar de novo.
- nav_target: `settings_integrations_slack`

### Conectar o Linear para abrir tarefas da conversa
- intent: Onde conecto o Linear?; Como abro uma tarefa a partir de uma conversa?; O Linear não aparece nas integrações, por quê?; Como desconecto o Linear?
- onde_fica: Configurações > Integrações > Linear
- rota: `settings_integrations_linear` - `/app/accounts/:accountId/settings/integrations/linear`
- gate: papel `administrator`
- pre_requisitos: ser administrador, recurso liberado na conta e credencial configurada pelo time da plataforma
- passos: 1. Abra Configurações > Integrações; 2. Clique no cartão do Linear; 3. Conecte; 4. Autorize dentro do Linear; 5. Confirme que a tela mostra conectado.
- gotchas: são duas condições somadas para o cartão existir, recurso na conta e credencial da plataforma, e faltando uma não há nada a fazer pelo painel; a conta aceita uma conexão só; depois de conectado, o uso acontece dentro da conversa, não nesta tela; desconectar derruba os vínculos existentes.
- nav_target: `settings_integrations_linear`

### Conectar o Notion
- intent: Como conecto o Notion?; Onde autorizo meu espaço do Notion?; Não encontro o Notion nas integrações; Como removo o acesso?
- onde_fica: Configurações > Integrações > Notion
- rota: `settings_integrations_notion` - `/app/accounts/:accountId/settings/integrations/notion`
- gate: papel `administrator`
- pre_requisitos: ser administrador, recurso liberado na conta e credencial configurada pelo time da plataforma
- passos: 1. Abra Configurações > Integrações; 2. Clique no cartão do Notion; 3. Conecte; 4. Escolha o espaço de trabalho e autorize; 5. Confirme que aparece conectado.
- gotchas: mesmo padrão do Linear, e se faltar recurso ou credencial o cartão some da lista; a conexão é da conta inteira, não por caixa de entrada; excluir remove o acesso ao espaço e derruba o que dependia dele.
- nav_target: `settings_integrations_notion`

### Conectar a loja Shopify
- intent: Como conecto minha loja Shopify?; Qual endereço eu coloco para conectar a loja?; Deu erro ao voltar da Shopify, e agora?; Por que a Shopify não aparece nas integrações?
- onde_fica: Configurações > Integrações > Shopify
- rota: `settings_integrations_shopify` - `/app/accounts/:accountId/settings/integrations/shopify`
- gate: feature flag `integrations`; papel `administrator`
- pre_requisitos: ser administrador, a integração ligada na instalação e liberada na conta, e o endereço da loja no formato sualoja.myshopify.com
- passos: 1. Abra Configurações > Integrações; 2. Clique no cartão da Shopify; 3. Conecte; 4. Digite o endereço da loja; 5. Conclua a autorização e volte.
- gotchas: o campo só aceita endereço terminado em myshopify.com, e o domínio próprio da loja é recusado, mesmo sendo o que seus clientes usam; são três condições para o cartão aparecer, e sem elas o endereço direto dá página não encontrada; se a volta trouxer erro, a tela avisa e basta repetir.
- nav_target: `settings_integrations_shopify`

### Mostrar um sistema seu dentro da conversa
- intent: Como mostro os dados do meu sistema dentro da conversa?; Onde cadastro um aplicativo no painel?; Dá para ver a apólice do cliente sem sair do atendimento?; Cadastrei o aplicativo e ele abre em branco, por quê?
- onde_fica: Configurações > Integrações > Painel de Aplicativos
- rota: `settings_integrations_dashboard_apps` - `/app/accounts/:accountId/settings/integrations/dashboard_apps`
- gate: feature flag `integrations`; papel `administrator`
- pre_requisitos: ser administrador e ter uma página publicada que possa ser aberta dentro de outra
- passos: 1. Abra Configurações > Integrações; 2. Entre em Painel de Aplicativos; 3. Adicione um aplicativo; 4. Preencha o nome e o endereço da sua página; 5. Salve e confira numa conversa.
- gotchas: nome e endereço válido são obrigatórios; a plataforma entrega o contexto da conversa à sua página por um aviso de janela, e se a sua página não escutar esse aviso ela abre em branco, parecendo quebrada, embora o cadastro esteja certo; excluir tira o aplicativo de todas as conversas na hora.
- nav_target: `settings_integrations_dashboard_apps`

### Ver os modelos de mensagem do WhatsApp
- intent: Onde vejo os modelos do WhatsApp?; Como crio um modelo novo?; Meu modelo foi aprovado mas não aparece aqui, por quê?; Como vejo o modelo antes de usar numa campanha?
- onde_fica: Configurações > Modelos
- rota: `settings_templates` - `/app/accounts/:accountId/settings/templates`
- gate: papel `administrator`
- pre_requisitos: pelo menos uma caixa de WhatsApp conectada, e os modelos já existindo no provedor
- passos: 1. Abra Configurações > Modelos; 2. Sincronize os modelos; 3. Filtre por caixa, idioma e tipo; 4. Busque pelo nome ou pelo texto; 5. Abra o modelo para ver status, categoria e caixas.
- gotchas: esta tela só exibe, porque criar e editar modelo é sempre no provedor, e não há botão de criar aqui; sincronizar fica desligado sem nenhuma caixa de WhatsApp; a sincronização leva alguns minutos e a tela mostra a hora da última tentativa; respondendo só parte das caixas, aparece aviso de sincronização parcial e a lista fica incompleta; modelo ainda não enviado para aprovação não serve para campanha.
- nav_target: `settings_templates`

### Trazer contatos e conversas de outra ferramenta
- intent: Como trago meus contatos da ferramenta antiga?; Dá para importar o histórico de conversas?; De quais sistemas eu consigo importar?; Posso rodar duas importações ao mesmo tempo?
- onde_fica: Configurações > Dados > Importar
- rota: `settings_data_imports` - `/app/accounts/:accountId/settings/data`
- gate: feature flag `data_import`; papel `administrator`
- pre_requisitos: ser administrador, recurso liberado na conta, e a chave de acesso do sistema de origem
- passos: 1. Abra Configurações > Dados; 2. Clique em importar; 3. Escolha a fonte; 4. Dê um nome que você reconheça depois; 5. Cole a chave e, quando for o caso, o domínio; 6. Marque contatos, conversas ou os dois e importe.
- gotchas: as fontes são apenas as duas listadas, e não existe envio de planilha nesta tela, porque o CSV de contatos fica em Contatos; a chave é testada antes e o botão só libera quando ela é aceita, então chave errada trava aqui e não no meio da carga; só uma importação roda por vez; a aba de exportar existe mas ainda não está disponível.
- nav_target: `settings_data_imports`

### Acompanhar uma importação e ver o que ficou de fora
- intent: Como sei se a importação terminou?; Quantos contatos entraram de verdade?; O que deu erro na importação?; Por que alguns registros foram ignorados?
- onde_fica: Configurações > Dados > clicar na importação
- rota: `settings_data_import_show` - `/app/accounts/:accountId/settings/data/:dataImportId`
- gate: feature flag `data_import`; papel `administrator`
- pre_requisitos: uma importação já iniciada
- passos: 1. Abra Configurações > Dados; 2. Clique na importação; 3. Leia os totais e o progresso; 4. Abra as seções de erros e de ignorados; 5. Baixe o arquivo de cada uma para conferir linha a linha; 6. Se precisar, tente novamente ou cancele.
- gotchas: registro ignorado não é erro, é linha que a plataforma decidiu não trazer, e o motivo está no arquivo; as seções abrem sozinhas quando há algo dentro; a tela se atualiza enquanto a importação roda e para quando termina; cancelar encerra e não volta sozinha.
- nav_target: `settings_data_import_show`

### Escolher um modelo pronto de e-mail
- intent: Onde estão os modelos prontos de e-mail?; Como aplico um modelo na minha campanha?; Dá para ver o modelo antes de usar?; Usar um modelo apaga o que eu já escrevi?
- onde_fica: Campanhas > Campanhas de e-mail > abrir a campanha > galeria de modelos
- rota: `campaigns_email_templates` - `/app/accounts/:accountId/campaigns/email_campaigns/:campaignId/templates`
- gate: feature flag `campaigns`; papel `administrator` ou `campaign_view` ou `campaign_manage`
- pre_requisitos: campanhas de e-mail liberadas na conta, uma campanha já criada e permissão de gerenciar campanhas
- passos: 1. Abra Campanhas > Campanhas de e-mail; 2. Abra a campanha no editor; 3. Vá para a galeria de modelos; 4. Filtre pela categoria; 5. Pré-visualize e use o modelo.
- gotchas: usar o modelo substitui o conteúdo atual da campanha, então quem já escreveu perde o que estava lá; sem permissão de gerenciar campanhas sobra só a pré-visualização; as miniaturas carregam conforme você rola; se o modelo não tiver conteúdo editável, a tela avisa e nada é aplicado.
- nav_target: `campaigns_email_templates`

### Ver o resultado de uma campanha de WhatsApp
- intent: Quantas pessoas receberam a campanha?; Quantos leram a mensagem?; Por que alguns contatos foram ignorados?; A campanha já terminou de enviar?; Como vejo contato por contato o que aconteceu?
- onde_fica: Campanhas > WhatsApp Oficial > Ver análises
- rota: `campaigns_whatsapp_analytics` - `/app/accounts/:accountId/campaigns/whatsapp/:campaignId/analytics`
- gate: feature flag `whatsapp_campaign`; papel `administrator` ou `campaign_view` ou `campaign_manage`
- pre_requisitos: uma campanha de WhatsApp Oficial já enviada ou em envio
- passos: 1. Abra Campanhas > WhatsApp Oficial; 2. Clique em ver análises; 3. Leia os números de público, enviadas, entregues, lidas, falhas e ignoradas; 4. Use as abas de status para filtrar; 5. Navegue pela lista para ver contato por contato.
- gotchas: entregues já inclui as lidas, então somar os dois conta o mesmo contato duas vezes; enviadas quer dizer aceita para entrega, não entregue no celular; ignoradas são contatos descartados antes do envio, quase sempre telefone ausente ou inválido, e é o número que vale olhar para limpar a base; campanhas enviadas antes desta tela existir aparecem sem dado, e isso não é erro.
- nav_target: `campaigns_whatsapp_analytics`

### Como o cliente recebe os valores da cotação
- intent: Como o cliente recebe os preços?; O agente manda os valores conforme as seguradoras respondem?; O cliente recebe link ou arquivo?; Como envio a proposta de uma seguradora só?; E se uma seguradora não responder?; Quanto tempo demora a cotação?
- onde_fica: acontece na conversa do WhatsApp, não numa tela do painel
- rota: `autonomia_insurance_agent` - `/app/accounts/:accountId/autonomia/insurance/agent`
- gate: papel `administrator` ou `insurance_view` ou `insurance_manage`
- pre_requisitos: agente de cotação criado e conexão com a seguradora funcionando
- passos: 1. O cliente pede a cotação pelo WhatsApp e responde o que o agente perguntar; 2. A cotação fecha quando todas as seguradoras tiveram desfecho; 3. O comparativo chega como arquivo PDF na conversa, com o que respondeu; 4. Se o cliente pedir uma seguradora, ele recebe o documento daquela seguradora; 5. A equipe assume a conversa no horário configurado.
- gotchas: os valores não saem conforme cada seguradora responde, o comparativo chega quando a cotação inteira termina, o que costuma levar de 1 a 2 minutos, e passando disso sai um aviso de espera escrito pelo agente, nunca uma lista de preços solta; o que vai ao cliente é o arquivo, nunca o link do portal, porque aquele endereço abre sem senha e traz o nome do segurado, e quando o arquivo falha nada é enviado no lugar; a proposta de uma seguradora é outro documento, gerado pela própria seguradora com o mesmo preço informado, e pedir duas seguradoras gera dois arquivos sem abrir cotação nova; seguradora que recusou não é anunciada ao cliente, e se ele perguntar o motivo sai por categoria, como veículo ou região, nunca o texto do portal; problema de credencial da corretora nunca chega ao cliente, ele aparece em Cotação > Conexões; na cotação de empresa o condutor deixa de ser opcional, precisa ser pessoa física com CPF e vínculo real, e a razão social não é perguntada, o sistema busca pelo CNPJ.
- nav_target: `autonomia_insurance_agent`
