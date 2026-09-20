# Guia Autonom.ia - KB customizada

> **Registro histórico — desenho da V1, read-only.** Este documento descreve o Guia
> como ele foi desenhado em junho de 2026: só leitura, sem consultar os dados da conta
> e sem executar nada. Esse desenho foi substituído pelas issues #533 (o Guia consulta
> o que a conta tem, com a permissão de quem pergunta) e #536 (o Guia executa ações,
> sempre com confirmação na tela). Fica como registro de decisão — não leia como
> descrição do comportamento atual.


Base custom do fork Autonom.ia/Hub2you. Conteúdo para orientar usuários sobre fluxos que não existem na documentação pública do Chatwoot.

## Route names custom

#### CRM
- `crm_kanban_index`: `/app/accounts/:accountId/crm`
- `crm_calendar_index`: `/app/accounts/:accountId/crm/calendar`
- `crm_dashboard_index`: `/app/accounts/:accountId/crm/dashboard`
- `crm_sla_index`: `/app/accounts/:accountId/crm/sla`
- `crm_campaign_management_index`: `/app/accounts/:accountId/crm/campaign-management`
- `crm_integration_tokens_index`: `/app/accounts/:accountId/crm/settings/integration-tokens`

#### Agentes Autonom.ia
- `autonomia_agents_index`: `/app/accounts/:accountId/agents`
- `autonomia_agents_builder`: `/app/accounts/:accountId/agents/new`
- `autonomia_agent_panel`: `/app/accounts/:accountId/agents/:agentId/:tab(test|knowledge|channels|performance|tune)?`

#### Campanhas
- `campaigns_ongoing_index`: `/app/accounts/:accountId/campaigns/ongoing` -> redireciona para `campaigns_livechat_index`
- `campaigns_one_off_index`: `/app/accounts/:accountId/campaigns/one_off` -> redireciona para `campaigns_sms_index`
- `campaigns_livechat_index`: `/app/accounts/:accountId/campaigns/live_chat`
- `campaigns_sms_index`: `/app/accounts/:accountId/campaigns/sms`
- `campaigns_whatsapp_index`: `/app/accounts/:accountId/campaigns/whatsapp`
- `campaigns_whatsapp_api_index`: `/app/accounts/:accountId/campaigns/whatsapp_api`
- `campaigns_email_sender_index`: `/app/accounts/:accountId/campaigns/email_sender`
- `campaigns_email_index`: `/app/accounts/:accountId/campaigns/email_campaigns`
- `campaigns_email_builder`: `/app/accounts/:accountId/campaigns/email_campaigns/:campaignId/builder`
- `campaigns_email_templates`: `/app/accounts/:accountId/campaigns/email_campaigns/:campaignId/templates`

#### Contatos e importação custom
- `contacts_campaign_imports`: `/app/accounts/:accountId/contacts/campaign-imports`
- `contacts_dashboard_index`: `/app/accounts/:accountId/contacts`
- `contacts_dashboard_segments_index`: `/app/accounts/:accountId/contacts/segments/:segmentId`
- `contacts_dashboard_labels_index`: `/app/accounts/:accountId/contacts/labels/:label`
- `contacts_dashboard_active`: `/app/accounts/:accountId/contacts/active`
- `contacts_edit`: `/app/accounts/:accountId/contacts/:contactId`

#### Booking público
- `public_booking_page` (Rails): `/book/:slug`
- `public_booking_confirm_page` (Rails): `/book/:slug/confirm`

## Fluxos

### Abrir o CRM Kanban e filtrar oportunidades
- intent: "Onde vejo o CRM?"; "Como filtro oportunidades?"; "Como alterno entre Kanban, lista e calendário?"
- onde_fica: Sidebar > CRM > CRM Kanban
- rota: `crm_kanban_index` - `/app/accounts/:accountId/crm`
- gate: `CRM_KANBAN_ENABLED=true`; permissões `administrator`, `agent` ou `crm_view` para custom roles.
- pre_requisitos: ao menos um funil CRM para ver conteúdo; sem funil, a tela mostra estado vazio e botão para criar funil se o usuário puder gerenciar.
- passos: Abra CRM Kanban; selecione o funil; use busca, prioridade e follow-up na barra; abra Filtros para caixa, responsável, time, estágio, valor, card parado e tipo de vínculo; alterne Kanban/Lista/Calendário no seletor superior.
- gotchas: a rota do Calendário é separada, mas o seletor de visualização também existe dentro do Kanban; custom roles sem `crm_view` não veem a entrada; filtros ativos aparecem como chips e podem esconder cards esperados.
- nav_target: `crm_kanban_index`

### Criar funis, estágios e conectar caixas ao CRM
- intent: "Como crio um funil?"; "Como altero os estágios?"; "Como vinculo uma caixa a um funil?"
- onde_fica: Sidebar > CRM > CRM Kanban > Novo funil ou Editar funil; também CRM Kanban > Configurações da caixa
- rota: `crm_kanban_index` - `/app/accounts/:accountId/crm`
- gate: `CRM_KANBAN_ENABLED=true`; permissão de administração CRM (`administrator` ou `crm_admin` para custom roles).
- pre_requisitos: caixas já criadas quando o objetivo for vincular atendimento ao funil.
- passos: Clique em Novo funil; defina nome, descrição e estágios; salve; use Editar funil para ajustar estágios, automações e caixas vinculadas; em Configurações da caixa, escolha comportamento padrão de criação/vínculo.
- gotchas: deletar estágio abre confirmação e pode falhar se houver cards dependentes; caixa vinculada define defaults de cards criados a partir de conversas; arquivar funil não apaga cards.
- nav_target: `crm_kanban_index`

### Criar card ou oportunidade no CRM
- intent: "Como crio uma oportunidade?"; "Como adiciono um card no funil?"; "Como associo contato, caixa e responsável?"
- onde_fica: Sidebar > CRM > CRM Kanban > Novo card
- rota: `crm_kanban_index` - `/app/accounts/:accountId/crm`
- gate: `CRM_KANBAN_ENABLED=true`; permissão `administrator`, `agent` ou `crm_view`; criação depende da permissão operacional do usuário no CRM.
- pre_requisitos: funil e estágio existentes; contato opcional, mas recomendado para histórico e follow-ups.
- passos: Clique em Novo card; preencha título, estágio, valor, prioridade e previsão; busque ou vincule contato; selecione dono, time e caixa quando necessário; salve.
- gotchas: cards sem conversa são "standalone" e podem sumir se o filtro "vinculado" estiver ativo; valores são tratados em centavos no backend e exibidos formatados; a caixa influencia visibilidade para agentes.
- nav_target: `crm_kanban_index`

### Mover card, ganhar, perder ou reabrir oportunidade
- intent: "Como movo uma oportunidade de estágio?"; "Como marco como ganha?"; "Como reabro um negócio perdido?"
- onde_fica: Sidebar > CRM > CRM Kanban > abrir card
- rota: `crm_kanban_index` - `/app/accounts/:accountId/crm`
- gate: `CRM_KANBAN_ENABLED=true`; permissão para mover/editar cards.
- pre_requisitos: card existente em funil ativo.
- passos: Arraste o card entre colunas no Kanban ou abra o drawer; ajuste estágio e responsável; para fechar, use ações de ganhar ou perder; informe valor ganho ou motivo da perda quando solicitado; reabra pelo mesmo drawer quando aplicável.
- gotchas: se o movimento falhar, o front restaura o estado anterior; cards fechados podem aparecer melhor na Lista com filtro de resultado; perder e arquivar não deletam contato nem conversa.
- nav_target: `crm_kanban_index`

### Criar follow-ups e lembretes no CRM
- intent: "Como crio um lembrete?"; "Como programo follow-up de WhatsApp?"; "Como vejo follow-ups atrasados?"
- onde_fica: Sidebar > CRM > CRM Kanban > abrir card > aba Follow-ups; ou CRM > CRM Calendar > clique no dia
- rota: `crm_kanban_index` - `/app/accounts/:accountId/crm`
- gate: `CRM_KANBAN_ENABLED=true`; card editável pelo usuário.
- pre_requisitos: card existente; para follow-up de mensagem, a conversa vinculada precisa existir e a janela/template do canal pode ser exigida.
- passos: Abra o card; entre em Follow-ups; informe título, data/hora e modo de automação; escolha mensagem/template quando houver envio automático; salve; conclua ou cancele pelo card ou calendário.
- gotchas: sem conversa vinculada não há snooze/envio automático; WhatsApp fora da janela pode exigir template; lembretes vencidos aparecem por popup e no filtro de follow-up.
- nav_target: `crm_kanban_index`

### Usar o card CRM a partir de uma conversa
- intent: "Onde está o card CRM desta conversa?"; "Como vinculo atendimento a uma oportunidade?"; "Por que não vejo card no painel da conversa?"
- onde_fica: Conversas > abrir conversa > botão/card CRM no painel lateral; depois CRM > CRM Kanban
- rota: `crm_kanban_index` - `/app/accounts/:accountId/crm`
- gate: `CRM_KANBAN_ENABLED=true`; usuário precisa poder ver a conversa e o CRM.
- pre_requisitos: conversa existente; a caixa pode ter auto-criação de card configurada em CRM > Configurações da caixa.
- passos: Abra a conversa; procure o bloco/ação de CRM; crie ou abra o card vinculado; revise contato, responsável e estágio; use o link do card para navegar ao CRM.
- gotchas: se a caixa estiver configurada para não criar card automaticamente, o card não aparece sozinho; em caixas "assigned only", visibilidade pode depender de atribuição/participação; cards standalone não têm conversa para abrir.
- nav_target: `crm_kanban_index`

### Configurar SLA do CRM
- intent: "Onde configuro SLA do CRM?"; "Como defino horários de atendimento?"; "Por que a página de SLA está bloqueada?"
- onde_fica: Sidebar > CRM > CRM SLA
- rota: `crm_sla_index` - `/app/accounts/:accountId/crm/sla`
- gate: `CRM_KANBAN_ENABLED=true`; `administrator` ou `crm_admin`; feature de conta `sla` precisa estar ativa para renderizar as listas.
- pre_requisitos: funis e caixas para associar políticas e agendas.
- passos: Abra CRM SLA; crie/edite políticas de SLA por funil; configure agenda de caixas; salve as janelas de atendimento; volte ao CRM para validar impacto nos cards.
- gotchas: sem feature `sla`, a rota abre paywall e não chama APIs; permissões de relatório não bastam para gerenciar SLA; agenda incorreta gera leitura errada de prazo.
- nav_target: `crm_sla_index`

### Ver dashboard CRM e métricas de funil
- intent: "Onde vejo relatório do CRM?"; "Como acompanho conversão do funil?"; "Como comparo IA e humano?"
- onde_fica: Sidebar > CRM > CRM Dashboard
- rota: `crm_dashboard_index` - `/app/accounts/:accountId/crm/dashboard`
- gate: `CRM_KANBAN_ENABLED=true`; `administrator`, `agent` ou `crm_view_reports` para custom roles.
- pre_requisitos: ao menos um funil com cards; metas e dados de reuniões aparecem quando houver configuração/dados.
- passos: Abra CRM Dashboard; selecione funil; escolha período; revise KPIs, funil, ganho/perdido, follow-ups, carga por responsável e IA versus humano; use atualizar se dados mudaram.
- gotchas: moedas diferentes não são somadas, são exibidas separadamente; métricas de reunião só carregam com `CRM_CALENDAR_MEETINGS_ENABLED=true`; sem funis a tela fica sem dados.
- nav_target: `crm_dashboard_index`

### Usar calendário CRM e agendar reunião
- intent: "Onde fica o calendário CRM?"; "Como agendo uma reunião no card?"; "Como evitar conflito de agenda?"
- onde_fica: Sidebar > CRM > CRM Calendar; ou CRM Kanban > visualização Calendário
- rota: `crm_calendar_index` - `/app/accounts/:accountId/crm/calendar`
- gate: rota exige `CRM_KANBAN_ENABLED=true`; agendamento, free/busy e scheduler exigem `CRM_CALENDAR_MEETINGS_ENABLED=true`.
- pre_requisitos: caixa de e-mail Google ou Microsoft conectada com calendário ativo; card CRM existente para a reunião.
- passos: Abra CRM Calendar; clique em um dia ou abra um card e escolha agendar reunião; selecione caixa/calendário, data, horário, duração e convidados; confira horários ocupados; confirme.
- gotchas: sem caixa com `calendar_enabled`, o scheduler mostra estado vazio; horários ocupados vêm do free/busy do provedor e podem falhar de forma silenciosa; reuniões arrastadas no calendário não são alteradas sem confirmação, abrem o scheduler de reagendamento.
- nav_target: `crm_calendar_index`

### Configurar link público de agendamento
- intent: "Como crio um link de agenda?"; "Onde configuro /book/:slug?"; "Como cada vendedor tem seu próprio link?"
- onde_fica: Sidebar > CRM > CRM Calendar > Perfis de agendamento
- rota: `public_booking_page` (Rails) - `/book/:slug`
- gate: configuração interna exige `CRM_KANBAN_ENABLED=true`, `CRM_CALENDAR_MEETINGS_ENABLED=true` e permissão de admin CRM; página pública exige perfil/link ativo.
- pre_requisitos: caixa Google/Microsoft com calendário ativo; funil/estágio padrão recomendado; agentes membros da caixa para links por agente.
- passos: Abra CRM Calendar; clique em Perfis de agendamento; habilite o perfil da caixa; defina duração, janela, fuso, dias e horário; escolha modo fixo ou por agente; salve e copie a URL.
- gotchas: no modo por agente, o slug base pode não funcionar e cada agente deve usar seu link individual; a página pública envia e-mail de confirmação antes de criar a reunião; links dependem de `FRONTEND_URL` correto para o e-mail de confirmação.
- nav_target: `crm_calendar_index`

### Sincronizar RSVP, reagendar e registrar no-show
- intent: "Como vejo se o convidado aceitou?"; "Como marco no-show?"; "Como cancelo ou reagendo uma reunião?"
- onde_fica: Sidebar > CRM > CRM Calendar > abrir evento de reunião
- rota: `crm_calendar_index` - `/app/accounts/:accountId/crm/calendar`
- gate: `CRM_KANBAN_ENABLED=true`; `CRM_CALENDAR_MEETINGS_ENABLED=true`; usuário precisa ver o card/reunião.
- pre_requisitos: reunião criada pelo CRM ou pelo link público; calendário conectado ao provedor.
- passos: Abra o evento no calendário; use atualizar RSVP para sincronizar com Google/Microsoft; use Entrar, Abrir card, Reagendar ou Cancelar; após o fim da reunião, marque Realizada ou No-show; adicione notas se realizada.
- gotchas: outcome só aparece depois do horário de término, não durante a reunião; cancelar/reagendar chama o provedor externo e pode falhar por token expirado; resumo por IA depende de `CRM_AI_ENABLED` e credencial configurada.
- nav_target: `crm_calendar_index`

### Criar e verificar identidade de remetente de e-mail
- intent: "Como libero um domínio para disparo?"; "Onde vejo DKIM/SPF/DMARC?"; "Por que não consigo escolher remetente?"
- onde_fica: Sidebar > Campanhas > Campanhas de e-mail > Identidades de remetente
- rota: `campaigns_email_sender_index` - `/app/accounts/:accountId/campaigns/email_sender`
- gate: feature `campaigns`; permissão `administrator`; `CRM_KANBAN_ENABLED=true`; `EMAIL_CAMPAIGN_ENABLED=true`.
- pre_requisitos: acesso ao DNS do domínio ou caixa webmail conectada para envio direto em baixo volume.
- passos: Abra Identidades de remetente; clique em novo domínio; informe domínio e e-mail opcional; copie os registros DNS; clique em Verificar agora ou aguarde polling; use apenas identidades verificadas na campanha.
- gotchas: domínios pendentes não aparecem como remetente SES; webmail gratuito aparece como opção de envio direto, mas com aviso e limitações; remover identidade em uso retorna erro.
- nav_target: `campaigns_email_sender_index`

### Criar campanha de e-mail e importar base
- intent: "Como crio uma campanha de e-mail?"; "Como importo destinatários?"; "Por que o botão de criar está desabilitado?"
- onde_fica: Sidebar > Campanhas > Campanhas de e-mail
- rota: `campaigns_email_index` - `/app/accounts/:accountId/campaigns/email_campaigns`
- gate: feature `campaigns`; permissão `administrator`; `CRM_KANBAN_ENABLED=true`; `EMAIL_CAMPAIGN_ENABLED=true`.
- pre_requisitos: identidade verificada ou caixa webmail elegível; arquivo CSV/XLSX de destinatários quando houver base externa.
- passos: Clique em Nova campanha; informe nome e remetente; defina nome do remetente, e-mail, reply-to e preheader; anexe CSV/XLSX de base se necessário; salve e abra o editor.
- gotchas: `from_email` precisa pertencer ao domínio SES verificado; envio direto trava o campo "De" com o e-mail da caixa; a importação pode gerar placeholders a partir das colunas da base.
- nav_target: `campaigns_email_index`

### Montar e-mail com editor, IA e templates
- intent: "Como edito o corpo do e-mail?"; "Onde uso IA para escrever?"; "Como aplicar template?"
- onde_fica: Sidebar > Campanhas > Campanhas de e-mail > Abrir builder
- rota: `campaigns_email_builder` - `/app/accounts/:accountId/campaigns/email_campaigns/:campaignId/builder`
- gate: feature `campaigns`; permissão `administrator`; `CRM_KANBAN_ENABLED=true`; `EMAIL_CAMPAIGN_ENABLED=true`.
- pre_requisitos: campanha em rascunho; para IA, `CRM_AI_ENABLED=true` e credencial de IA resolvível.
- passos: Abra o builder; escolha IA, galeria de templates ou começar do zero; ajuste assunto no topo; edite blocos e propriedades; use placeholders disponíveis; envie teste e salve.
- gotchas: geração por IA é assíncrona e mostra status `processing/ready/failed`; templates ficam em rota própria `campaigns_email_templates`; enviar teste persiste o corpo antes de disparar.
- nav_target: `campaigns_email_builder`

### Gerenciar destinatários, agendar e enviar campanha de e-mail
- intent: "Como adiciono mais destinatários?"; "Como agendo envio?"; "Quando aparece Enviar agora?"
- onde_fica: Sidebar > Campanhas > Campanhas de e-mail > Gerenciar destinatários
- rota: `campaigns_email_index` - `/app/accounts/:accountId/campaigns/email_campaigns`
- gate: feature `campaigns`; permissão `administrator`; `CRM_KANBAN_ENABLED=true`; `EMAIL_CAMPAIGN_ENABLED=true`.
- pre_requisitos: campanha em rascunho; corpo HTML salvo para agendar/enviar; destinatários importados.
- passos: Abra Gerenciar destinatários; importe CSV/XLSX adicional se precisar; confira placeholders e validação de template; agende data/hora ou volte ao builder se não houver corpo; na lista, use Enviar agora, Pausar, Retomar ou Cancelar conforme status.
- gotchas: Enviar agora só aparece em rascunho com destinatários e corpo; validação alerta placeholders ausentes ou vazios; a lista faz polling enquanto há campanha `sending`, `scheduled` ou IA processando.
- nav_target: `campaigns_email_index`

### Ver gestão e relatório de campanhas de e-mail
- intent: "Onde vejo abertura e clique?"; "Como exporto relatório de campanha?"; "Como comparo campanhas de e-mail?"
- onde_fica: Sidebar > CRM > Gestão de campanhas
- rota: `crm_campaign_management_index` - `/app/accounts/:accountId/crm/campaign-management`
- gate: `CRM_KANBAN_ENABLED=true`; `EMAIL_CAMPAIGN_ENABLED=true`; permissão `administrator`, `agent` ou `crm_view_reports` para custom roles.
- pre_requisitos: campanhas de e-mail já enviadas ou com eventos de entrega.
- passos: Abra Gestão de campanhas; filtre por todas ou por uma campanha; revise KPIs de enviado, entregue, abertura aproximada, clique, descadastro, bounce e complaint; ajuste intervalo da linha do tempo; exporte CSV quando uma campanha estiver selecionada.
- gotchas: abertura é aproximada por limitação de tracking; exportar CSV só aparece com campanha específica; esta tela é relatório, não o lugar de editar campanha.
- nav_target: `crm_campaign_management_index`

### Criar campanha WhatsApp API
- intent: "Como disparo campanha pelo WhatsApp API?"; "Onde escolho rótulos de audiência?"; "Como pauso ou cancelo?"
- onde_fica: Sidebar > Campanhas > WhatsApp API
- rota: `campaigns_whatsapp_api_index` - `/app/accounts/:accountId/campaigns/whatsapp_api`
- gate: feature `campaigns`; permissão `administrator`; `WHATSAPP_API_CAMPAIGNS_ENABLED=true`.
- pre_requisitos: caixa elegível de WhatsApp API; rótulos de contato para audiência; template ou mensagem/mídia.
- passos: Abra WhatsApp API; clique em Nova campanha; selecione caixa; escolha template ou escreva mensagem com variáveis; anexe mídia se precisar; selecione rótulos de audiência; agende e crie.
- gotchas: audiência é por label, não por segmento salvo; uma campanha precisa de mensagem ou mídia; campanhas em `scheduled/running/paused` têm polling e ações de pausar/retomar/cancelar.
- nav_target: `campaigns_whatsapp_api_index`

### Importar base de campanha em Contatos
- intent: "Como importo uma base de campanha?"; "Qual arquivo posso subir?"; "Como divido contatos em lotes?"
- onde_fica: Sidebar > Contatos > Todos os contatos > menu de ações (três pontos) > Importar base
- rota: `contacts_dashboard_index` - `/app/accounts/:accountId/contacts`
- gate: feature `crm`; permissão `administrator`; `CAMPAIGN_IMPORT_ENABLED=true`.
- pre_requisitos: arquivo CSV ou XLSX com colunas lógicas de nome e telefone; telefones móveis brasileiros; nome da campanha; quantidade de lotes.
- passos: Abra Contatos; clique no menu de ações; escolha Importar base; informe nome da campanha e número de lotes; selecione CSV/XLSX; confirme; acompanhe no histórico.
- gotchas: a UI aceita só `.csv` e `.xlsx`; se houver qualquer linha inválida, nada deve ser importado; fórmulas, telefones fixos, nomes em branco, duplicados no arquivo e limites de tamanho/linhas são rejeitados.
- nav_target: `contacts_dashboard_index`

### Confirmar importação, baixar CSVs e desfazer rótulos
- intent: "Onde vejo histórico de importações?"; "Como confirmo uma base validada?"; "Como removo os rótulos de uma importação?"
- onde_fica: Sidebar > Contatos > Todos os contatos > menu de ações > Histórico; ou URL direta de importações
- rota: `contacts_campaign_imports` - `/app/accounts/:accountId/contacts/campaign-imports`
- gate: feature `crm`; permissão `administrator`; `CAMPAIGN_IMPORT_ENABLED=true`.
- pre_requisitos: importação criada; para desfazer, importação concluída ou concluída com falhas.
- passos: Abra o histórico; aguarde status sair de uploaded/validating/importing; se estiver `ready_to_confirm`, clique Confirmar; baixe CSV de erros, normalizado ou relatório quando disponíveis; em importações concluídas, use Desfazer rótulos.
- gotchas: desfazer remove apenas labels criadas/aplicadas por aquela importação, não deleta contatos; arquivos expiram conforme política de retenção; status em processamento atualiza a cada 5 segundos.
- nav_target: `contacts_campaign_imports`

### Abrir hub de Agentes Autonom.ia
- intent: "Onde ficam meus agentes?"; "Como crio um agente Autonom.ia?"; "Por que não vejo o menu Agentes?"
- onde_fica: Sidebar > Agentes > Meus agentes
- rota: `autonomia_agents_index` - `/app/accounts/:accountId/agents`
- gate: `AUTONOMIA_AGENTS_ENABLED=true`; conta com `autonomia_agents_enabled=true`; permissão `administrator`.
- pre_requisitos: conta habilitada pelo gate isolado; credencial de IA quando a liberação for global por conta.
- passos: Abra Agentes; revise os cards existentes; clique em Criar com IA; para abrir um agente existente, clique no card; use a aba Testar como entrada padrão do painel.
- gotchas: backend de agentes é admin-only e retorna 404 quando o gate está off; a sidebar também esconde o grupo para não admins; o card mostra apenas `human_card`, não a instrução interna.
- nav_target: `autonomia_agents_index`

### Criar agente externo com base de conhecimento
- intent: "Como crio um agente para atender clientes?"; "Como subo materiais no construtor?"; "Como conecto no fim?"
- onde_fica: Sidebar > Agentes > Construtor de agente
- rota: `autonomia_agents_builder` - `/app/accounts/:accountId/agents/new`
- gate: `AUTONOMIA_AGENTS_ENABLED=true`; conta habilitada; permissão `administrator`.
- pre_requisitos: tipo de agente escolhido; materiais opcionais em PDF, TXT, MD, JSON, XLSX ou DOCX; caixa elegível se for conectar ao atendimento.
- passos: Escolha atuação Externa e Com conhecimento; selecione o tipo de agente; responda à entrevista do construtor; anexe arquivos ou adicione links no painel de materiais; avance para revisão; teste e conecte uma caixa.
- gotchas: antes da primeira mensagem pode não existir draft agent, então anexos pedem para iniciar a conversa; links colados no chat não viram fonte automaticamente, aparece sugestão para adicionar; a instrução final só existe depois de finalizar/revisar.
- nav_target: `autonomia_agents_builder`

### Criar agente interno ou sem base
- intent: "Como crio um agente interno para a equipe?"; "Como faço sem base de conhecimento?"; "Esse agente responde clientes?"
- onde_fica: Sidebar > Agentes > Construtor de agente
- rota: `autonomia_agents_builder` - `/app/accounts/:accountId/agents/new`
- gate: `AUTONOMIA_AGENTS_ENABLED=true`; conta habilitada; permissão `administrator`.
- pre_requisitos: definir atuação Interna ou Sem conhecimento na tela inicial.
- passos: Escolha atuação Interna quando o agente for copiloto da equipe; escolha Sem conhecimento se ele deve partir só da conversa guiada; selecione o tipo ou "Outros"; responda ao construtor; finalize para revisar; abra o painel para testar.
- gotchas: agente interno não conecta em caixa e a aba Canais fica oculta/redireciona; atuação `both` não é escolhida no construtor, é ajuste posterior; sem base reduz respostas ancoradas e pode aumentar handoff por falta de conhecimento.
- nav_target: `autonomia_agents_builder`

### Atualizar conhecimento e fontes do agente
- intent: "Como adiciono conhecimento depois de criado?"; "Como reprocesso uma fonte?"; "Como vejo a qualidade da base?"
- onde_fica: Sidebar > Agentes > Meus agentes > abrir agente > Conhecimento
- rota: `autonomia_agent_panel` - `/app/accounts/:accountId/agents/:agentId/knowledge`
- gate: `AUTONOMIA_AGENTS_ENABLED=true`; conta habilitada; permissão `administrator`.
- pre_requisitos: agente existente; arquivo suportado ou URL para fonte.
- passos: Abra o agente; entre em Conhecimento; arraste arquivos ou clique Adicionar; escolha link ou arquivo; acompanhe status do revisor e barra de confiança; use Reenviar para reprocessar ou remover para excluir fonte.
- gotchas: remover/adicionar fonte recalcula a confiança e pode atualizar a instrução de agentes finalizados; a aba "Mídias para enviar" só aparece quando existir fonte desse tipo; formatos aceitos no diálogo são `.pdf`, `.txt`, `.md`, `.json`, `.xlsx`, `.docx`.
- nav_target: `autonomia_agent_panel`

### Conectar ou desconectar agente de uma caixa
- intent: "Como coloco o agente para atender uma caixa?"; "Por que uma caixa aparece ocupada?"; "Como desconecto um agente?"
- onde_fica: Sidebar > Agentes > Meus agentes > abrir agente > Canais
- rota: `autonomia_agent_panel` - `/app/accounts/:accountId/agents/:agentId/channels`
- gate: `AUTONOMIA_AGENTS_ENABLED=true`; conta habilitada; permissão `administrator`; agente precisa ser `external` ou `both`.
- pre_requisitos: agente ativo/finalizado; caixa elegível; cada caixa pode hospedar apenas um agente.
- passos: Abra o agente; entre em Canais; veja caixas conectadas e elegíveis; clique Conectar em uma caixa livre; para remover, use Desconectar na lista de conectadas.
- gotchas: agentes internos não conectam em caixa; caixas ocupadas aparecem sem botão de conectar; mudar um agente com canais conectados para `internal` pode ser rejeitado pelo backend.
- nav_target: `autonomia_agent_panel`

### Testar, acompanhar e ajustar agente
- intent: "Como testo o agente?"; "Como vejo desempenho?"; "Como ajusto tom, handoff ou instrução?"
- onde_fica: Sidebar > Agentes > Meus agentes > abrir agente > Testar, Performance ou Ajustar
- rota: `autonomia_agent_panel` - `/app/accounts/:accountId/agents/:agentId/:tab(test|performance|tune)`
- gate: `AUTONOMIA_AGENTS_ENABLED=true`; conta habilitada; permissão `administrator`.
- pre_requisitos: agente existente; para métricas, conversas/respostas já registradas.
- passos: Use Testar para conversar e ver confiança, handoff e fontes usadas; use Performance para período 7d/30d, respostas, handoff e taxa de conhecimento; use Ajustar para saudação, fallback, tom, estratégia de handoff, limiar de confiança e atuação; em modo guiado, use Re-conversar.
- gotchas: testar agente não finalizado mostra aviso; histórico de teste fica em `sessionStorage` por agente; modo manual expõe instrução, mas não permite salvar instrução vazia; Performance pode ficar vazia até o agente operar de verdade.
- nav_target: `autonomia_agent_panel`

### Usar Copiloto Autonom.ia na conversa
- intent: "Como peço ajuda ao copiloto interno?"; "Por que o botão do copiloto não aparece?"; "Como trocar o agente do copiloto?"
- onde_fica: Dashboard de conversas > botão flutuante de Copiloto Autonom.ia ou painel lateral do copiloto
- rota: usa rotas de conversa existentes; APIs em `/app/accounts/:accountId` com endpoints `autonomia/conversations/:conversation_id/copilot/agents` e `/chat`
- gate: `CRM_KANBAN_ENABLED=true`; `CRM_COPILOT_ENABLED=true`; usuário precisa poder ver a conversa; agentes listados precisam ter atuação `internal` ou `both`, status `active` e instrução presente.
- pre_requisitos: conversa selecionada; ao menos um agente interno/both ativo e finalizado para a conta.
- passos: Abra uma conversa; acione o painel do Copiloto Autonom.ia; escolha o agente se houver mais de um; pergunte em linguagem natural; use a sugestão/resposta no atendimento quando fizer sentido; resete o thread pelo botão de atualizar.
- gotchas: o launcher some quando o painel já está aberto e também se não houver conversa/estado compatível; o thread reseta ao trocar de conversa para evitar vazamento de contexto; este copiloto é independente do Captain e não exige `captain_integration`.
- nav_target: `inbox_conversation`
