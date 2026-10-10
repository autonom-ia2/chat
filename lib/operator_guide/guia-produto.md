# Guia da Plataforma Autonom.ia — base de conhecimento (202 fluxos)

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
- passos: 1. Abra Primeiros passos no menu lateral; 2. Leia o painel Seu proximo passo, que e sempre o primeiro que ainda falta; 3. Assista ao video curto ao lado, quando houver; 4. Clique no botao azul do painel (o nome dele e a acao do passo, por exemplo Conectar a chave) para ir direto a tela daquele passo; 5. Volte a lista e siga para o proximo.
- gotchas: cada passo so fica Feito quando o estado real da conta muda, nunca por clique; os passos ficam em tres etapas (Ligar a plataforma, Organizar as vendas, Crescer); passos opcionais trazem Pular por enquanto; o painel mostra os pre-requisitos externos (por exemplo, conta na OpenAI com credito) e o tempo estimado; passo que depende de outro mostra Precisa antes, sem bloquear; clicar num passo da lista abre ele no painel; Preciso de ajuda abre o Guia; a lista some do centro da tela quando o essencial termina, mas continua no menu.
- nav_target: `first_steps`

### Criar caixa de entrada
- intent: Como crio uma caixa de entrada?; Onde adiciono um novo canal?; Quero conectar um WhatsApp, email, site ou API.; Como comeco um inbox novo?
- onde_fica: Configuracoes > Caixas de entrada > Nova caixa
- rota: `settings_inbox_new` - `/app/accounts/:accountId/settings/inboxes/new`
- gate: feature flag `inbox_management`; papel `administrator` ou `inbox_manage`
- cobre: settings_inbox_list, settings_inbox_finish, settings_inboxes_add_agents
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

### Ligar o rodízio para cada conversa nova ganhar um responsável
- intent: Quero que cada lead chegue com um responsável; Como distribuo as conversas entre o time?; Liga o rodízio na caixa Comercial; Por que os leads ficam sem responsável?; Por que o card do CRM está sem dono?
- onde_fica: Configurações > Caixas de entrada > selecionar caixa > Colaboradores > Atribuição automática (pela API: PATCH inboxes/:id com enable_auto_assignment). Na conta com atribuição avançada, a regra vem de Configurações > Atribuição de Agentes > Política de atribuição, vinculada à caixa.
- rota: `settings_inbox_show` - `/app/accounts/:accountId/settings/inboxes/:inboxId/:tab?`
- gate: feature flag `inbox_management`; papel `administrator` ou `inbox_view` ou `inbox_manage`
- pre_requisitos: administrador; a caixa com as pessoas certas como agentes (o rodízio só escolhe entre os agentes da caixa)
- passos: 1. Leia a caixa e os agentes dela e confira se quem deve receber está lá; 2. Ligue a Atribuição automática da caixa; 3. Na conta com atribuição avançada, confira se a caixa está numa política de atribuição e, se não estiver, vincule a uma (ou crie uma em rodízio); 4. Diga à pessoa quem vai entrar no rodízio e o aviso de quem está online.
- gotchas: o rodízio só entrega para quem está online naquele momento; sem atribuição avançada ele só age quando a conversa nasce ou é reaberta, então a conversa que chega com todo mundo offline (um e-mail à noite) fica sem responsável para sempre, até alguém atribuir à mão; com atribuição avançada a plataforma tenta de novo a cada 30 minutos para as conversas abertas e sem responsável, então a da noite ganha dono quando alguém entra online (conversa parada há mais de 7 dias fica de fora, por padrão); o card do CRM herda o responsável da conversa: se o card nasce antes da atribuição, ganha o dono quando a conversa é atribuída; o card que o card automático da caixa criou acompanha cada troca de responsável da conversa, e o criado de outro jeito (automação, Kanban) só recebe o dono quando está sem dono; conversa que já tem responsável não entra no rodízio.
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
- pre_requisitos: conversa existente; agente/time disponivel e com acesso a caixa de entrada
- passos: 1. Abra a conversa; 2. Localize o bloco de atribuicao no painel lateral; 3. Escolha agente ou time; 4. Confirme a mudanca; 5. Verifique se o nome aparece na conversa.
- gotchas: agentes sem acesso a caixa de entrada podem nao aparecer; usuarios com permissao restrita podem nao conseguir atuar em conversas de terceiros.
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
- onde_fica: Conversas > abrir conversa > acoes da conversa > Adiar
- rota: `inbox_conversation` - `/app/accounts/:accountId/conversations/:conversation_id`
- gate: papel `administrator` ou `agent` ou `conversation_manage` ou `conversation_unassigned_manage` ou `conversation_participating_manage`
- pre_requisitos: conversa existente
- passos: 1. Abra a conversa; 2. Use a acao de adiar; 3. Escolha um preset ou data/hora; 4. Confirme; 5. Acompanhe quando ela voltar para a fila.
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
- passos: 1. Abra a conversa; 2. Clique em etiquetas no painel lateral; 3. Pesquise a etiqueta; 4. Adicione ou remova; 5. Use a sidebar de etiquetas para consultar depois.
- gotchas: etiquetas ocultas ou especificas de importacao custom podem nao aparecer na sidebar; etiquetas de conversa e contato podem ser usadas em contextos diferentes.
- nav_target: `inbox_conversation`

### Filtrar conversas
- intent: Como filtro conversas?; Onde vejo conversas por canal, time ou etiqueta?; Como encontro uma fila especifica?
- onde_fica: Conversas > Todas; tambem na sidebar em Canais, Times e Etiquetas
- rota: `home` - `/app/accounts/:accountId/dashboard`
- gate: papel `administrator` ou `agent` ou `conversation_manage` ou `conversation_unassigned_manage` ou `conversation_participating_manage`
- cobre: inbox_view, inbox_view_conversation, inbox_dashboard, conversation_through_inbox, label_conversations, conversations_through_label, team_conversations, conversations_through_team, conversations_through_folders, conversation_participating, conversation_through_participating
- pre_requisitos: conversas existentes; filtros/canais/times/etiquetas conforme o caso
- passos: 1. Abra Conversas; 2. Use a sidebar para escolher Todas, Canal, Time ou Etiqueta; 3. Ajuste status e filtros da lista; 4. Abra a conversa desejada; 5. Limpe filtros para voltar a visao geral.
- gotchas: rotas de canal/time/etiqueta exigem parametros reais; se nada aparecer, confira permissao, status da conversa e acesso a caixa de entrada.
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
- cobre: conversation_through_mentions
- pre_requisitos: haver mencoes em conversas acessiveis ao usuario
- passos: 1. Abra Conversas; 2. Clique em Mencoes na sidebar; 3. Revise a lista; 4. Abra a conversa; 5. Responda ou acompanhe conforme necessario.
- gotchas: mencoes dependem de acesso a conversa; mencoes antigas podem estar em conversas resolvidas ou filtradas.
- nav_target: `conversation_mentions`

### Ver conversas nao atendidas
- intent: Onde vejo conversas sem atendimento?; Como acho conversas nao atribuidas?; Onde esta a fila de nao atendidas?
- onde_fica: Conversas > Nao atendidas
- rota: `conversation_unattended` - `/app/accounts/:accountId/unattended/conversations`
- gate: papel `administrator` ou `agent` ou `conversation_manage` ou `conversation_unassigned_manage` ou `conversation_participating_manage`
- cobre: conversation_through_unattended
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

### Importar contatos com colunas, atributos e empresas
- intent: Como importo uma planilha de contatos com empresa?; As colunas extras da planilha viram atributos do contato?; Por que a importação pediu para escolher as colunas?; Como importo contatos de um Excel?
- onde_fica: Contatos > Todos os contatos > menu de ações (três pontos) > Importar contatos (com a jornada de campanhas ligada)
- rota: `contacts_import_journey` - `/app/accounts/:accountId/contacts/import`
- gate: feature flag `crm`; papel `administrator` ou `contact_manage`
- pre_requisitos: administrador ou função com gestão de contatos; planilha CSV ou Excel (.xlsx) até 10 MB com celular ou e-mail em cada linha
- passos: 1. Abra Contatos; 2. No menu de três pontos, clique em Importar contatos; 3. Escolha a planilha; 4. Confira as Colunas encontradas e use Trocar se alguma estiver errada (ou Não tem); 5. Veja quais Outras colunas viram atributos do contato e quais são atributos novos; 6. Confira contatos prontos, linhas com problema e o bloco Empresas (Criar e ligar); 7. Clique em Importar e veja o resumo.
- gotchas: com a jornada de campanhas desligada o menu abre a importação nativa do Chatwoot; quando o sistema não tem certeza das colunas, pede a escolha antes de seguir; contato que já existe (celular com ou sem o 9, ou e-mail) só ganha o que falta e não perde valores de atributos; contato que já tem outra empresa mantém a dele; atributos novos são criados como texto com o nome da coluna; nada entra na base antes de clicar em Importar; essa importação não vira público nem aparece em Campanhas.
- nav_target: `contacts_import_journey`

### Convidar e gerenciar agentes
- intent: Como convido um agente?; Onde vejo usuarios da conta?; Como desativo ou edito um agente?
- onde_fica: Configuracoes > Agentes
- rota: `agent_list` - `/app/accounts/:accountId/settings/agents/list`
- gate: feature flag `agent_management`; papel `administrator`
- pre_requisitos: email do agente; limite/plano permitir novo usuario quando aplicavel
- passos: 1. Abra Configuracoes; 2. Entre em Agentes; 3. Clique para adicionar/editar agente; 4. Informe dados e papel; 5. Salve e acompanhe convite/status.
- gotchas: agente convidado pode precisar aceitar convite antes de operar; o acesso a uma caixa de entrada tambem depende de estar associado a ela.
- nav_target: `agent_list`
- highlight: `settings-add-agent`

### Ajustar papel do agente
- intent: Como faco alguem virar administrador?; Onde mudo papel de agente?; Como aplico um papel customizado a um usuario?
- onde_fica: Configuracoes > Agentes > editar agente
- rota: `agent_list` - `/app/accounts/:accountId/settings/agents/list`
- gate: feature flag `agent_management`; papel `administrator`
- pre_requisitos: agente existente; papel customizado criado quando for usar custom role
- passos: 1. Abra Configuracoes > Agentes; 2. Edite o agente; 3. Escolha `administrator`, `agent` ou papel customizado; 4. Salve; 5. Revise acesso a caixas/times se necessario.
- gotchas: papel da conta nao substitui associacao a caixa de entrada; custom roles so aparecem em instalacoes Cloud/Enterprise com feature `custom_roles`.
- nav_target: `agent_list`

### Criar funcoes personalizadas
- intent: Como crio um papel customizado?; Como crio uma funcao personalizada?; Onde configuro permissoes granulares?; Como limito acesso de um usuario?; Como duplico uma funcao?; Como aplico um modelo de perfil a uma funcao?
- onde_fica: Configuracoes > Funcoes Personalizadas
- rota: `custom_roles_list` - `/app/accounts/:accountId/settings/custom-roles/list`
- gate: feature flag `custom_roles`; papel `administrator`
- cobre: custom_roles_new, custom_roles_edit
- pre_requisitos: Enterprise/Cloud habilitado; saber o que o grupo deve ver e fazer
- passos: 1. Abra Configuracoes > Funcoes Personalizadas; 2. Clique em Nova funcao; 3. Escolha o perfil mais parecido (ou Comecar do zero) e clique em Continuar; 4. De um nome e abra so os grupos que quer mudar, escolhendo Sem acesso, Ver ou Editar em cada area; 5. Confira o painel Esta pessoa podera e clique em Criar funcao; 6. Atribua aos agentes na janela seguinte ou depois em Configuracoes > Agentes.
- gotchas: a rota nao aparece em instalacao sem suporte Enterprise/Cloud; Editar ja inclui Ver; o que nao for liberado some do menu da pessoa; opcoes sensiveis pedem confirmacao; com Acesso total ao CRM as opcoes que ele inclui ficam travadas; enviar leads da Prospeccao para campanha exige Campanhas em Editar; administrador nao recebe funcao personalizada; permissao customizada nao concede automaticamente acesso a todas as caixas.
- nav_target: `custom_roles_list`
- highlight: `settings-add-role`

### Montar as permissoes de uma funcao personalizada
- intent: Crie uma funcao so leitura; Quero que o time de marketing veja tudo da caixa X; Crie uma funcao para quem so ve relatorios; Que permissoes uso para uma funcao?; Como dou acesso a uma caixa especifica?
- onde_fica: Configuracoes > Funcoes Personalizadas > Nova funcao (pela API: POST /api/v1/accounts/:account_id/custom_roles)
- rota: `custom_roles_new` - `/app/accounts/:accountId/settings/custom-roles/new`
- gate: feature flag `custom_roles`; papel `administrator`
- pre_requisitos: administrador; saber o que o grupo deve ver e fazer; as pessoas ja cadastradas como agentes
- passos: 0. Antes de perguntar qualquer coisa, leia o time e as pessoas citadas e a caixa do pedido, e proponha com nomes reais o que vai fazer, por exemplo "crio a funcao Marketing com conversas, contatos e relatorios e deixo a Carla so na caixa Marketing; ela vai poder responder. Sigo?" — diga o que fica diferente do pedido (ela vai poder responder; a caixa sai da participacao, nao da funcao) e espere o sim antes de fazer; 1. Consulte formato_da_acao da criacao de funcao e traduza o pedido em areas e niveis usando so os valores de `permissions` que ele trouxer; 2. Mande nome, descricao e a lista `permissions` ja no POST, num passo so (nao crie a funcao vazia para preencher depois); 3. Mande so a chave mais alta de cada area (_manage ja inclui _view); 4. Se o pedido cita uma caixa, a funcao nao resolve isso: inclua a pessoa como agente daquela caixa em Configuracoes > Caixas de entrada > (caixa) > Agentes, e tire das caixas que ela nao deve ver; 5. Atribua a funcao a pessoa em Configuracoes > Agentes; 6. Diga ao usuario, em uma frase, o que ficou diferente do pedido e por que.
- gotchas: PRIMEIRO, o que mais confunde: Nenhuma chave escolhe caixa: a pessoa so ve conversas das caixas em que e agente, e conversation_manage quer dizer todas as conversas dessas caixas. Nao existe conversa so leitura: quem ve as conversas de uma caixa tambem responde nelas. Para "so leitura" de uma caixa, o mais proximo e conversation_manage com a pessoa agente so daquela caixa, mais contact_view, report_manage e o que mais for de leitura; avise que ela ainda consegue responder. Inbox_view NAO e o mais proximo de "ver tudo da caixa": ela so mostra a tela de configuracao, nenhuma conversa. Se a pessoa proibiu mexer nos membros, diga que sem isso a funcao nao restringe a caixa nem mostra as conversas dela, e mesmo assim proponha o mais proximo com os nomes reais (por a pessoa so na caixa pedida) perguntando se ela abre essa excecao — so dizer que nao da deixa a pessoa sem caminho. A lista de chaves validas vem de formato_da_acao, que le o codigo; nao use lista de memoria. O que o nome da chave nao diz: _view e ver e _manage e editar (ja inclui ver); conversas tem tres niveis: nenhuma chave, so as proprias (conversation_participating_manage e/ou conversation_unassigned_manage, a fila de nao atribuidas) ou todas (conversation_manage); report_manage e so leitura de relatorios; sem canned_response_manage a pessoa so usa respostas prontas; crm_admin liga todas as de CRM; prospecting_view_all_searches mostra as buscas de todos; inbox_view e inbox_manage sao so a tela de configuracao das caixas. Time (Configuracoes > Times) agrupa pessoas para atribuicao e filtro; nao e funcao e nao da permissao. Administrador ignora funcao personalizada.
- diagnostic: se a plataforma recusar com "chaves desconhecidas" (em ingles, "unknown keys"), a mensagem lista as chaves invalidas e as validas; troque pela chave valida mais proxima e mande de novo, sem oferecer suporte. Uma funcao que ficou com permissions vazio deixa a pessoa sem menu; corrija com PATCH na mesma funcao em vez de criar outra.
- nav_target: `custom_roles_new`

### Criar e editar times
- intent: Como crio um time?; Onde adiciono agentes a uma equipe?; Como edito membros de um time?
- onde_fica: Configuracoes > Times
- rota: `settings_teams_new` - `/app/accounts/:accountId/settings/teams/new`
- gate: feature flag `team_management`; papel `administrator`
- cobre: settings_teams_list, settings_teams_finish, settings_teams_add_agents, settings_teams_edit, settings_teams_edit_members, settings_teams_edit_finish
- pre_requisitos: agentes ativos para adicionar ao time
- passos: 1. Abra Configuracoes > Times; 2. Clique em criar time; 3. Defina nome/descricao; 4. Adicione agentes; 5. Finalize e use o time em atribuicoes/filtros.
- gotchas: times ajudam em atribuicao e filtro, mas agentes ainda precisam ter acesso as caixas de entrada usadas.
- leitura: times
- nav_target: `settings_teams_new`
- highlight: `settings-new-team`

### Criar automacoes no modo manual
- intent: Onde fica o formulario completo de automacao?; Como edito uma automacao campo a campo?; Como atribuir, etiquetar ou enviar mensagem automaticamente pelo formulario?
- onde_fica: Menu lateral > Automacoes > abra uma automacao > Editar no modo manual (o formulario completo de antes; saiu das Configuracoes)
- rota: `automation_list` - `/app/accounts/:accountId/settings/automation/list`
- gate: feature flag `automations`; papel `administrator` ou `automation_view` ou `automation_manage`
- pre_requisitos: definir gatilho, condicoes e acoes; etiquetas/times/agentes criados quando usados
- passos: 1. Abra Automacoes no menu lateral; 2. Abra a automacao e clique em Editar no modo manual, ou em Nova automacao > Prefiro montar no modo manual; 3. Escolha o evento gatilho; 4. Configure condicoes; 5. Escolha acoes e salve.
- gotchas: o modo manual e para quem prefere o formulario; a forma recomendada de criar e conversando na tela Automacoes; automacoes podem se sobrepor; revise ordem, condicoes e efeitos como atribuir time, adicionar etiqueta ou enviar webhook.
- nav_target: `automation_list`
- highlight: `settings-add-automation`

### Usar um Decisor na automacao
- intent: Como faco a automacao so seguir quando o e-mail for lead?; Quero que a automacao entenda o que o cliente escreveu antes de agir.; Como separo formulario do site de newsletter?; Como ensino a automacao a decidir se e lead?; Tem caso esperando eu decidir?; Como corrijo o que o Decisor decidiu?; Quando o card entrar em Proposta, so seguir se for empresa grande?; Quando a conversa for resolvida, avisar se o cliente saiu insatisfeito?; O WhatsApp que fala de sinistro vai direto para a caixa de sinistros?
- onde_fica: Menu lateral > Automacoes > abra a automacao (o passo aparece no resumo como "Pergunta ao Decisor <nome>: segue se a resposta for ..."; em Editar no modo manual o passo e mantido ao salvar, mas o formulario nao oferece adiciona-lo — quem adiciona e o Guia, conversando nessa tela) e CRM > Editar funil > etapa > Automacoes desta etapa (o mesmo passo); os Decisores da conta ficam em `autonomia/decisores`
- rota: `automacoes_lista` - `/app/accounts/:accountId/automacoes`
- gate: feature flag `automations`; papel `administrator` ou `automation_view` ou `automation_manage`
- cobre: automacoes_nova, automacoes_editar
- pre_requisitos: ter `automation_manage` (ou ser administrador) para criar, testar e ligar; para gravar campos (nome, telefone, empresa) a conta precisa de chave de IA configurada, e essa extracao gasta a chave da conta; atributo personalizado de contato usado como destino precisa existir antes
- passos: 1. Proponha o Decisor com nomes reais da conta: a pergunta, de 2 a 8 respostas com chave curta e descricao do que conta como cada uma (ex.: `sim` = pede cotacao ou informacao de seguro; `nao` = newsletter, fornecedor, aviso automatico), instrucoes, certeza minima (padrao 0,80) e `leituras` — o que ele le, da lista fechada: `mensagens_recentes` (as ultimas do cliente, qualquer canal; e o padrao), `mensagens_com_respostas` (cliente e equipe), `ultima_mensagem` (a que disparou; em regra de conversa, a ultima recebida do cliente), `conversa` (canal, caixa, etiquetas, atributos, status), `contato` (nome e atributos), `card` (titulo, etapa, funil, valor, metadados), `empresa` (nome e atributos); 2. Antes de salvar, teste a pergunta em itens reais com `classificar_com_jev` (le os registros com `ler_da_conta` e manda os ids); 3. Crie com `POST autonomia/decisores`; se for gravar dados, inclua `campos` com chave, descricao e destino; 4. TESTE antes de ligar: `POST autonomia/decisores/:id/teste` com `inbox_id` da caixa (ou `conversation_ids`), ate 10 conversas; mostre a pessoa a resposta, a certeza, as duvidas e os campos que seriam gravados — o teste nao grava nada; 5. Para cada acerto ou erro que a pessoa apontar, confirme com `POST autonomia/decisores/:id/exemplos` (`conversation_id`, `resposta`); ajuste instrucoes ou descricoes e teste de novo; 6. Monte a automacao DESLIGADA com o passo antes dos passos que so devem rodar naquele caso — na regra (`POST automation_rules` com `active: false`): `{action_name: "perguntar_ao_decisor", action_params: [decisor_id, "chave_que_segue"]}`; na etapa do funil (`POST crm/stages/:stage_id/stage_automations` com `enabled: false`): `{action_type: "perguntar_ao_decisor", action_config: {decisor_id, chave_que_segue}}`; 7. So ligue (`active: true` / `enabled: true`) depois que a pessoa aprovar o resultado do teste — ligar automacao com Decisor passa por propor_acao e a pessoa confirma na tela.
- gotchas: o Decisor serve a qualquer gatilho: mensagem criada em qualquer canal (WhatsApp, e-mail, Instagram, site), conversa criada, aberta ou resolvida, e card entrando ou saindo de uma etapa do funil — ele e uma pergunta, a automacao e quem diz quando perguntar; exemplos de composicao: (a) regra "mensagem criada" na caixa do WhatsApp -> Decisor "fala de sinistro?" (le `mensagens_recentes`) -> segue em `sim` -> atribuir a caixa/time de sinistros e etiquetar `sinistro`; (b) etapa Proposta, ao entrar -> Decisor "e empresa grande?" (le `card`, `empresa`, `contato`) -> segue em `sim` -> atribuir responsavel senior e criar retorno; na regra de conversa (criada, aberta ou resolvida) nao ha mensagem que disparou: o Decisor le ate a ultima mensagem RECEBIDA do cliente (`ultima_mensagem` e essa), as respostas da equipe depois dela ficam de fora, e a decisao e guardada por essa mensagem — a conversa resolvida, reaberta e resolvida de novo sem mensagem nova do cliente reaproveita a primeira decisao e NAO roda os passos de novo; por isso nao proponha Decisor em "conversa resolvida" para julgar o encerramento (ex.: "o cliente saiu insatisfeito?"): diga a pessoa que isso ainda nao funciona bem e prefira "mensagem criada"; o que o Decisor le tem de existir no gatilho: na etapa do funil nao ha mensagem que disparou, entao `ultima_mensagem` e recusado ali (use `mensagens_recentes`, que le a conversa em atendimento do card, se houver); o Decisor nunca le e-mail nem telefone do contato, nem quando o nome do contato e o proprio e-mail ou o telefone (em qualquer formato), nem atributo personalizado cujo valor seja um e-mail ou um telefone; o Decisor so responde uma das chaves que ele tem: os passos DEPOIS de "Perguntar ao Decisor" so rodam quando a resposta e a chave combinada com certeza igual ou maior que a minima; outra resposta para a automacao ali; para tratar cada resposta de um jeito, crie uma automacao por resposta com o mesmo Decisor — a decisao e guardada por mensagem (ou por card e entrada na etapa) e a conta paga uma pergunta so; a automacao com Decisor nasce DESLIGADA e so liga depois que a pessoa aprova o teste, nunca antes — criar ligada, ligar ou por o Decisor numa automacao ligada nao tem desfazer e pede confirmacao; o Decisor nao combina com condicao "atributo alterado"; na duvida (certeza abaixo da minima) o Guia decide sozinho so quando o caso deixa claro e o caso vira exemplo "decidido pelo Guia"; se nao estiver claro, o caso fica esperando uma pessoa por 2 dias (`GET autonomia/decisores/:id/decisoes?status=esperando_pessoa`) e vence depois disso sem retomar a automacao, para nao mover card ou mandar mensagem fora de hora; resolver um caso (`POST autonomia/decisoes/:id/resolver` com `resposta`) vira exemplo e, se for a resposta que segue e estiver no prazo, retoma a automacao (todas as que esperavam aquela decisao, cada uma so se ainda vale: as condicoes da regra, ou o card ainda na etapa) e pode mandar mensagem ou mover card — confirme com a pessoa antes; corrigir uma decisao ja tomada conta como correcao e nao refaz a automacao; por padrao os campos so PREENCHEM o que esta vazio (o nome que e so o e-mail ou o telefone conta como vazio) e, para mudar valor que ja existe, o campo precisa de trocar: true (abaixo); destinos aceitos para os campos: contato.nome, contato.telefone, contato.email, contato.cargo (o Cargo da ficha), contato.biografia (a Biografia da ficha), empresa.nome, card.titulo, card.descricao e contato.atributo:<chave> de atributo de contato que ja existe; cada campo pode ter trocar: true — use quando a pessoa pedir para MUDAR ou ATUALIZAR o valor (ex.: 'mude o nome do contato com o do e-mail'); sem trocar o campo so preenche o que esta vazio; o e-mail do contato nunca e trocado; empresa com trocar renomeia a empresa so daquele contato, e se ela tiver outros contatos o contato passa para a empresa do nome novo; campo de card so grava quando ha card (se o passo seguinte da regra for criar card, ele grava logo depois); o telefone e completado com o codigo do pais da conta e, se ja for de outro contato, vai para a biografia; o campo que nao grava fica na decisao com o motivo; as mensagens lidas sao as ultimas 5 (e o assunto do e-mail); sem nada para ler no que o Decisor declara (conversa so de audio ou imagem, card vazio) ele nao pergunta e nao segue (status `sem_conteudo`); cada conta tem limite mensal de perguntas ao Decisor e, acima dele, os passos seguintes nao rodam (status `sem_cota`); regra em "mensagem criada" sem filtro de caixa pergunta a cada mensagem — filtre pela caixa certa; `classificar_com_jev` so estima (escolha e certeza por item) e nao grava nada: agir em cima do resultado passa pelo desfazer ou pela confirmacao de sempre.
- nav_target: `automacoes_lista`

### Montar automacoes compostas (um pedido, varias regras)
- intent: Quero uma automacao que faca varias coisas; Se em 15 minutos ninguem atender, avisa alguem; Como evito que a automacao entre em loop ou mande mensagem repetida?; Como identifico cliente querendo cancelar ou pedindo reembolso?; Como mando alerta para o responsavel da equipe?; Quando a conversa for resolvida, manda a transcricao por e-mail
- onde_fica: Menu lateral > Automacoes (cada regra e uma linha da lista)
- rota: `automacoes_lista` - `/app/accounts/:accountId/automacoes`
- gate: feature flag `automations`; papel `administrator` ou `automation_view` ou `automation_manage`
- cobre: automacoes_nova, automacoes_editar
- pre_requisitos: etiquetas, times e agentes que as regras usam ja criados; recurso de atraso ligado na conta para "se em N minutos ainda"; transcricao por e-mail habilitada na conta para mandar transcricao; a URL do sistema externo para webhook.
- passos: 1. Quebre o pedido em regras: uma por momento — agora, daqui a N minutos, ao resolver —, e cada uma com o seu evento; 2. Crie antes o que falta (time, etiqueta) e pergunte o que so a pessoa sabe: a URL do webhook, quem recebe o alerta, o texto da mensagem se ela nao deu; 3. Monte cada acao e condicao pelo formato_da_acao de POST automation_rules, pedindo o ramo com `campo` ("actions.send_email_to_team", "conditions.status") — e la que diz o que o motor le; 4. Regra que reage a mensagem: evento message_created com message_type igual a incoming (so mensagem do cliente); 5. Idempotencia por etiqueta: a regra que trata o caso tem a condicao "labels nao contem X" e a acao "adicionar X" — depois da primeira vez ela nao dispara de novo para o mesmo caso, sem mensagem repetida ao cliente nem e-mail duplicado; 6. "Se em N minutos ainda...": outra regra, evento message_created de mensagem do cliente, com execution_delay N e as condicoes que precisam continuar valendo (status open, assignee_id sem ninguem, a etiqueta do caso); na hora de rodar a plataforma reconfere tudo e desiste se alguem da equipe respondeu; 7. "Quando resolver...": regra em conversation_resolved com a condicao da etiqueta do caso; 8. Nao pare para perguntar o que tem padrao sensato (nome, prazo, texto que ela deu, quem entra no time novo): faca e diga o que escolheu; crie direto o que tem volta (time, etiqueta, Decisor) e proponha a primeira regra na mesma resposta; a regra com acao sem volta (mensagem, e-mail, webhook, transcricao) vai por propor_acao mesmo desligada, uma por resposta — a confirmacao e a pessoa vendo a regra; na resposta, liste as regras do plano e o que cada uma faz.
- gotchas: intencao do cliente (quer cancelar, pediu reembolso, esta insatisfeito) NUNCA vira lista de palavras em content: palavra solta pega "nao quero cancelar" e perde "vou desistir"; quem entende a intencao e o Decisor, como passo da regra (veja usar_decisor_na_automacao) — sem ele, dispare o resto do fluxo pela etiqueta do caso que a equipe poe na conversa (evento conversation_updated, labels contem o caso e nao contem a marca de ja tratado); o que a propria automacao faz (mensagem, etiqueta, atribuicao) nao dispara outra regra, entao uma regra nao encadeia outra por etiqueta — o loop vem de reagir a mensagem da equipe (outgoing) ou de duas regras que se desfazem; regra com atraso so arma quando chega o evento com as condicoes ja valendo, e o atraso de mensagem conta desde a primeira mensagem do cliente ainda sem resposta; o webhook manda o pacote padrao da conversa (contato, numero da conversa, caixa e canal, mensagens, etiquetas, status) com event automation_event.<evento> — nao da para escolher campos nem escrever o texto do aviso; e-mail para o time vai para todos os agentes do time, e time nao tem lider: para alertar UMA pessoa use nota privada mencionando ela ([@Nome](mention://user/ID/Nome)), que notifica so ela, ou atribua a conversa a ela; automacao nao tem condicao de horario — "fora do horario" e o horario de atendimento da caixa (working_hours e out_of_office_message), que responde sozinho fora do expediente; message_created vale para toda caixa: restrinja por inbox_id quando o pedido for de um canal; etiqueta vai pelo titulo exato gravado na conta (Risco de cancelamento -> risco_de_cancelamento).
- nav_target: `automacoes_lista`

### Ver, ligar e desligar automacoes
- intent: Quais automacoes eu tenho?; Onde vejo minhas automacoes?; Como desligo uma automacao?; Como ligo de novo uma automacao parada?; Qual automacao o Guia criou?
- onde_fica: Menu lateral > Automacoes
- rota: `automacoes_lista` - `/app/accounts/:accountId/automacoes`
- gate: feature flag `automations`; papel `administrator` ou `automation_view` ou `automation_manage`
- pre_requisitos: nenhum para ver; ligar, desligar e criar exigem administrador ou funcao com Automacoes em Editar
- passos: 1. Abra Automacoes no menu lateral; 2. Leia cada automacao, escrita como frase (Quando... se... faz...); 3. Use o interruptor da linha para ligar ou desligar; 4. Clique na frase para abrir, testar ou ajustar.
- gotchas: a automacao desligada nao faz nada ate alguem ligar; o selo Criada pelo Guia aparece nas automacoes que o Guia criou para a propria pessoa nos ultimos 5 dias; lista vazia mostra tres modelos prontos para comecar; a automacao por etapa do funil do CRM e outra coisa e fica em Editar funil.
- nav_target: `automacoes_lista`

### Criar ou ajustar uma automacao conversando com o Guia
- intent: Quero criar uma automacao; Me ajuda a montar uma regra automatica; Quando chegar mensagem X quero que aconteca Y; Como testo uma automacao antes de ligar?; Liga esta automacao; Muda esta automacao
- onde_fica: Menu lateral > Automacoes > Nova automacao (ou clique numa automacao da lista)
- rota: `automacoes_nova` - `/app/accounts/:accountId/automacoes/nova`
- gate: feature flag `automations`; papel `administrator` ou `automation_manage`
- cobre: automacoes_editar
- pre_requisitos: administrador para o Guia criar ou mudar; etiquetas, times, agentes, funis e etapas usados ja precisam existir
- passos: 1. Abra Automacoes > Nova automacao; 2. Conte com suas palavras o que deve acontecer, ou escolha um modelo pronto; 3. O Guia cria a automacao e a tela passa a mostrar o resumo Quando > Se > Entao; 4. Clique em Testar com casos reais para ver o que ela faria nas conversas recentes; 5. Clique em Ligar automacao quando estiver como voce quer.
- gotchas: nesta tela a automacao nasce DESLIGADA — ao criar, mande active false e diga que ela so comeca a valer quando a pessoa clicar em Ligar; so ligue (PATCH com active true) quando a pessoa pedir com todas as letras; o registro aberto na tela chega no contexto como id=N e e a automacao que a pessoa esta vendo, entao "esta", "ela" e "essa regra" falam dela; ajuste com PATCH automation_rules/:id na mesma automacao em vez de criar outra; o teste com casos reais nao envia nem muda nada e deixa de fora a condicao que depende de um campo mudar; Editar no modo manual abre a mesma automacao no formulario completo. Comece pronto: se a pessoa nao ditou o texto da mensagem, escreva um curto e cordial, ja crie a automacao desligada com ele e mostre o texto na resposta — ela troca conversando; nao pergunte o texto antes de criar.
- nav_target: `automacoes_nova`

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
- cobre: macros_edit
- pre_requisitos: acoes desejadas disponiveis; etiquetas/times/agentes criados quando usados
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
- cobre: settings_home
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
- cobre: profile_settings
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
- passos: Abra **CRM Kanban**; selecione o funil; use **Buscar por nome** para localizar o negócio, contato ou empresa; abra **Mais filtros** para empresa, etiquetas, status, prioridade, atenção da IA, responsável, time, caixa de entrada, campanha, valor e retornos; alterne **Kanban/Lista/Calendário** no seletor superior. Para acompanhar **ganhas/perdidas**: use a visão **Lista** com filtros e veja as métricas de ganhos/perdas no **Dashboard CRM**.
- gotchas: ganhar/perder define o **status** do card (acompanhado no **Dashboard CRM** e na visão **Lista**), diferente da **etapa** do funil; a rota do Calendário é separada, mas o seletor de visualização também existe dentro do Kanban; custom roles sem `crm_view` não veem a entrada; filtros ativos viram chips removíveis e podem esconder cards; Encontrar com IA está desabilitado, aguardando uma integração específica; para mudar a etapa, arraste o card ou abra **Resumo > Etapa**; o botão Mover não aparece na face do card; no card, empresa aparece em destaque, pessoa abaixo e negócio em texto secundário; sem empresa, a pessoa aparece em destaque; cards da Prospecção preservam a empresa do negócio mesmo quando compartilham um contato.
- nav_target: `crm_kanban_index`
- highlight: `crm-filters`

### Criar funis, estágios e conectar caixas ao CRM
- intent: "Como crio um funil?"; "Como altero os estágios?"; "Como vinculo uma caixa a um funil?"
- onde_fica: Sidebar > CRM > Kanban > Criar funil (ao lado do seletor); para editar o atual, Configurar > Editar funil; também Configurar > Configurar caixas de entrada
- rota: `crm_kanban_index` - `/app/accounts/:accountId/crm`
- gate: papel `administrator` ou `agent` ou `crm_view`
- pre_requisitos: caixas de entrada já criadas quando o objetivo for vincular atendimento ao funil.
- passos: No editor, defina o nome e abra uma etapa para editar sua descrição. Para mudar a ordem, arraste pelos pontinhos da lista ou use as setas nas opções da etapa; o número indica a posição atual. Melhorar com IA compara as demais etapas e apresenta uma sugestão: Usar esta descrição aplica, Manter minha descrição descarta. Concluir etapa volta à lista; Salvar funil persiste. Lembretes e retornos reúne os retornos e o envio opcional por IA. Mais ajustes reúne descrição geral, meta mensal, Resultados dos anúncios e, no fim, Caixas de entrada. Adicione cada caixa de entrada e escolha a etapa de entrada. Para um funil novo, salve primeiro. Também é possível abrir Configurar caixas de entrada, ligar o CRM na caixa de entrada, escolher o funil e a etapa de entrada e salvar.
- gotchas: sugestões da IA não são aplicadas nem movem cards automaticamente; os recursos de IA do funil vêm incluídos e a reavaliação padrão é de 7 dias, respeitando os gates globais; o retorno automático existente conserva sua ativação e agenda; Google Ads exige importação agendada do feed e Meta exige integração e atribuição do anúncio — ligar a opção no funil não comprova recebimento externo; vendas de anúncios usam o status ganho do card, não a coluna Fechamento; a criação automática vem marcada na caixa ainda não configurada; trocar o funil da caixa move a criação automática para o funil novo e avisa na tela antes de salvar, e os cards que já existem ficam onde estão; desligar o CRM na caixa para a criação automática; Editar funil > Mais ajustes > Caixas de entrada continua valendo para a caixa que alimenta mais de um funil; excluir uma etapa abre confirmação e pode falhar se houver cards dependentes; arquivar funil não apaga cards.
- leitura: funis
- nav_target: `crm_kanban_index`
- highlight: `crm-new-pipeline`

### Criar card ou oportunidade no CRM
- intent: "Como crio uma oportunidade?"; "Como adiciono um card no funil?"; "Como associo contato, caixa e responsável?"
- onde_fica: Sidebar > CRM > CRM Kanban > Nova oportunidade
- rota: `crm_kanban_index` - `/app/accounts/:accountId/crm`
- gate: papel `administrator` ou `agent` ou `crm_view`
- pre_requisitos: CRM habilitado e permissão de criar oportunidades; funil e etapa disponíveis. Contato e empresa são opcionais.
- passos: Clique em **Nova oportunidade**; em Relacionamento, use um contato existente, **Criar novo** ou **Continuar sem vínculo**. Para contato novo, a empresa pode ficar ausente, ser escolhida ou criada. Preencha título, funil, etapa, valor e responsável; abra **Mais opções da oportunidade** para os dados adicionais; confira o resumo do rodapé e clique em **Criar oportunidade**.
- gotchas: os cadastros são compartilhados com Relacionamentos, não cópias; reutilizar existente não altera a pessoa ou empresa; identidade/domínio repetidos pedem escolha explícita, nomes iguais não causam fusão; erro de gravação conserva o preenchimento; repetir a mesma solicitação recupera a oportunidade confirmada. Cards sem conversa podem ser ocultados pelo filtro vinculado; a caixa influencia a visibilidade para agentes.
- nav_target: `crm_kanban_index`
- highlight: `crm-new-card`

### Criar uma oportunidade pela ficha do contato
- intent: "Como crio uma oportunidade para este contato?"; "Como levo o contato de Relacionamentos para o CRM?"
- onde_fica: Sidebar > Relacionamentos > Contatos > abrir contato > Nova oportunidade
- rota: `contacts_edit` - `/app/accounts/:accountId/contacts/:contactId`
- gate: feature flag `crm`; papel `administrator` ou `agent` ou `contact_manage` ou `contact_view`
- pre_requisitos: navegação de Relacionamentos e CRM habilitados; permissão de visualizar CRM e gerenciar oportunidades; acesso ao contato; funil com etapa disponível.
- passos: Na ficha do contato, clique em **Nova oportunidade**. O CRM abre em outra aba com a pessoa e sua empresa cadastrada selecionadas. Preencha os dados comerciais e confirme **Criar oportunidade**. O card criado abre com o mesmo contato vinculado. **Voltar ao contato** retorna à ficha; se houver dados comerciais não salvos, confirme o descarte ou continue editando.
- gotchas: a aba original e seu preenchimento não salvo permanecem abertos. A oportunidade usa o cadastro salvo, não alterações ainda não confirmadas na ficha. Abrir o formulário não cria nenhum registro. Contato indisponível mostra erro e permite tentar novamente ou cancelar, sem virar card avulso silenciosamente. Usuário somente leitura não vê a ação. Sem funil/etapa, selecione ou crie um disponível conforme suas permissões.
- nav_target: `contacts_edit`

### Consultar oportunidades na ficha do contato
- intent: "Quais oportunidades este contato tem?"; "Como vejo os negócios ganhos ou perdidos deste contato?"
- onde_fica: Relacionamentos > Contatos > abrir contato > Acompanhamento > Oportunidades
- rota: `contacts_edit` - `/app/accounts/:accountId/contacts/:contactId`
- gate: feature flag `crm`; papel `administrator` ou `agent` ou `contact_manage` ou `contact_view`
- pre_requisitos: Relacionamentos e CRM habilitados; permissão de visualizar CRM e acesso ao contato. Cada oportunidade respeita também sua visibilidade no CRM.
- passos: Abra **Oportunidades** no painel Acompanhamento. A lista reúne as negociações do mesmo contato em todos os funis. Use a busca pelo título e **Situação**; avance por **Próxima** quando houver mais resultados. Clique numa oportunidade para abrir seu card no CRM em outra aba. Use **Atualizar oportunidades** ou retorne à ficha para buscar o estado atual.
- gotchas: por padrão, arquivadas ficam fora; escolha **Arquivado** ou **Todas as situações** para consultá-las. O total considera apenas registros que você pode acessar e os filtros da consulta. A lista não cria nem altera dados. A ficha e seu preenchimento permanecem abertos. Os filtros desta lista não mudam os filtros do Kanban; as moedas aparecem por oportunidade e não são somadas ou convertidas.
- nav_target: `contacts_edit`

### Marcar contato como cliente
- intent: "Como marco que este contato já é cliente?"; "Desde quando ele é cliente?"; "Por que este lead virou cliente?"
- onde_fica: Relacionamentos > Contatos > abrir contato > seção **Cliente**, abaixo de **Atualizar contato**
- rota: `contacts_edit` - `/app/accounts/:accountId/contacts/:contactId`
- gate: feature flag `crm`; papel `administrator` ou `agent` ou `contact_manage` ou `contact_view`
- pre_requisitos: acesso para editar o contato.
- passos: O contato vira cliente sozinho quando um card dele é ganho num funil que conta como venda. Para quem comprou de outro jeito, clique em **Marcar como cliente** e confirme em **Sim, marcar**. Para desfazer um engano, **Não é cliente** e **Sim, tirar**.
- gotchas: o selo **Cliente desde** guarda a primeira venda e aparece também no painel da conversa; ganhar de novo não muda a data. Resolver um card de funil que não é de venda não promove. Desfazer volta o contato para lead e não mexe em cards nem conversas.
- nav_target: `contacts_edit`

### Mover card, ganhar, perder ou reabrir oportunidade
- intent: "Como movo uma oportunidade de estágio?"; "Como marco como ganha?"; "Como reabro um negócio perdido?"
- onde_fica: Sidebar > CRM > CRM Kanban > abrir card
- rota: `crm_kanban_index` - `/app/accounts/:accountId/crm`
- gate: papel `administrator` ou `agent` ou `crm_view`
- pre_requisitos: card existente em funil ativo.
- passos: Arraste o card entre colunas no Kanban ou abra o drawer; ajuste etapa e responsável; para fechar, use ações de ganhar ou perder; informe valor ganho ou motivo da perda quando solicitado; reabra pelo mesmo drawer quando aplicável.
- gotchas: se o movimento falhar, o front restaura o estado anterior; cards fechados podem aparecer melhor na Lista com filtro de resultado; perder e arquivar não deletam contato nem conversa; em funil com "Fechar com sucesso aqui conta como venda" desligado (Editar funil), os botões fecham como Resolvido/Cancelado (ou o nome que o funil der), não somam em vendas nem avisam anúncios.
- nav_target: `crm_kanban_index`

### Criar follow-ups e lembretes no CRM
- intent: "Como crio um lembrete?"; "Como programo follow-up de WhatsApp?"; "Como vejo follow-ups atrasados?"
- onde_fica: Sidebar > CRM > CRM Kanban > abrir card > aba Retornos; ou CRM > Calendário > clique no dia
- rota: `crm_kanban_index` - `/app/accounts/:accountId/crm`
- gate: papel `administrator` ou `agent` ou `crm_view`
- pre_requisitos: card existente; para retorno com mensagem, a conversa vinculada precisa existir e a janela/template do canal pode ser exigida.
- passos: Abra o card; entre em Retornos; informe título, data/hora e modo de automação; escolha mensagem/template quando houver envio automático; crie o retorno; conclua ou cancele pelo card ou calendário. Consulte Histórico para acompanhar as atividades e tentativas registradas.
- gotchas: sem conversa vinculada não há adiar/envio automático; WhatsApp fora da janela pode exigir template; lembretes vencidos aparecem por popup e no filtro de retorno; envio automático para contato que não quer receber mensagens ativas é cancelado sem virar atraso, e o Histórico mostra Retorno cancelado com o motivo.
- nav_target: `crm_kanban_index`

### Usar o card CRM a partir de uma conversa
- intent: "Onde está o card CRM desta conversa?"; "Como vinculo atendimento a uma oportunidade?"; "Por que não vejo card no painel da conversa?"
- onde_fica: Conversas > abrir conversa > botão/card CRM no painel lateral; depois CRM > CRM Kanban
- rota: `crm_kanban_index` - `/app/accounts/:accountId/crm`
- gate: papel `administrator` ou `agent` ou `crm_view`
- pre_requisitos: conversa existente; a caixa pode ter auto-criação de card configurada em CRM > Configurações da caixa.
- passos: Abra a conversa; procure o bloco/ação de CRM; crie ou abra o card vinculado; revise contato, responsável e etapa; use o link do card para navegar ao CRM.
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
- passos: Abra CRM Dashboard; selecione funil; escolha período; revise KPIs, funil, ganho/perdido, retornos, carga por responsável e IA versus humano; use atualizar se dados mudaram.
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
- onde_fica: Sidebar > CRM > CRM Calendar > Agendamento
- pre_requisitos: caixa Google/Microsoft com calendário ativo; funil/etapa padrão recomendado; agentes membros da caixa para links por agente.
- passos: Abra CRM Calendar; clique em Agendamento; habilite o perfil da caixa; defina duração, janela, fuso, dias e horário; escolha modo fixo ou por agente; salve e copie a URL.
- gotchas: no modo por agente, o slug base pode não funcionar e cada agente deve usar seu link individual; a página pública envia e-mail de confirmação antes de criar a reunião; links dependem de `FRONTEND_URL` correto para o e-mail de confirmação.
- nav_target: `crm_calendar_index`

### Criar e publicar a página de agendamento
- intent: Como crio uma página para o cliente marcar horário?; Onde fica o link de agendamento sem Google ou Microsoft?; Como mando o link ou o QR code de agendamento?; Como pauso a página de agendamento?; Por que não consigo publicar a página?; Como escolho para qual funil vai quem marcar?
- onde_fica: Configurações > Agendamento
- rota: `settings_booking` - `/app/accounts/:accountId/settings/booking`
- gate: papel `administrator` ou `agendamento_view` ou `agendamento_manage`
- perfil: criar, editar, publicar, pausar e excluir exige administrador ou função com Agendamento em Editar; com Agendamento em Ver a pessoa vê as páginas, a prévia e o link (copiar, QR code, abrir), mas não vê Criar página, Editar, Pausar, Publicar, Excluir nem Alterar. Agente sem função e função sem o módulo Agendamento não veem o item no menu.
- pre_requisitos: agendamento de reuniões ligado na instalação e a opção Agendamento WhatsApp-first ligada na conta pelo suporte; função com Agendamento (Ver ou Editar) para quem não é administrador; para Google Meet ou Teams, uma caixa de e-mail do Google ou Microsoft com agenda já conectada.
- passos: 1. Abra Configurações > Agendamento e clique em Criar página; 2. Escolha um modelo (Conversa de vendas, Consulta ou atendimento, Visita ou Começar do zero); 3. Em Conte, confira o nome que o cliente vê, quanto tempo dura e toque em quem atende; 4. Em Onde acontece, escolha um ou mais locais (Vídeo no WhatsApp, Ligação no WhatsApp, Meu link com o endereço completo, No local com o endereço); 5. Em Dias e horas, toque nos dias e escolha Das, Até, Avisar com e Intervalo; 6. Em Cara, envie logo e foto, escolha a cor e escreva a frase de boas-vindas, e clique em Ver como fica; 7. Na prévia, confira a frase do funil e use Alterar se quiser outro funil ou etapa; 8. Clique em Publicar e use Copiar link, QR code ou Abrir.
- gotchas: escolher o modelo já cria a página pausada, com nome, duração, local e horários preenchidos; cada Continuar salva o passo, e voltar não perde o que foi digitado; Google Meet e Teams só aparecem com caixa de e-mail com agenda conectada, e uma página usa uma caixa só, então Meet e Teams não vão juntos; Publicar pode voltar com o que falta (quem atende, onde acontece, dias de atendimento), e Resolver leva ao passo certo; duas ou mais pessoas em quem atende criam um link individual para cada uma; página com um link por pessoa: divulgue o link de cada pessoa — o cartão, a prévia e a tela de leitura mostram Um link para cada pessoa, com Copiar link, QR code e Abrir em cada linha, porque o endereço da página sozinho não marca horário; logo e foto só PNG, JPEG ou WebP até 2 MB; a cor sai de opções prontas; excluir não funciona com reunião marcada no futuro, e nesse caso a saída é pausar; aviso de atenção no cartão quer dizer que quem atende não pode receber reuniões, e a página se comporta como pausada até trocar a pessoa; os avisos por WhatsApp ao cliente ainda não estão nesta tela; desligar a opção da conta tira a tela e a gaveta antiga do Kanban continua como antes.
- nav_target: `settings_booking`

### Quem pode o quê no Agendamento
- intent: Quem pode criar a página de agendamento?; Como deixo alguém só ver as páginas de agendamento?; Por que o atendente não vê Configurações > Agendamento?; Qual função dá acesso ao Agendamento?
- onde_fica: Configurações > Funções personalizadas > módulo Agendamento (Sem acesso, Ver, Editar); a tela fica em Configurações > Agendamento
- rota: `settings_booking` - `/app/accounts/:accountId/settings/booking`
- gate: papel `administrator` ou `agendamento_view` ou `agendamento_manage`
- perfil: administrador faz tudo; função com Agendamento em Editar cria, edita, publica, pausa e exclui páginas e escolhe modelo, marca, locais, horários, funil e quem atende; função com Agendamento em Ver vê as páginas, a prévia e o link, sem botão de mudar; agente sem função e função sem o módulo não veem a tela e a API responde 401.
- pre_requisitos: opção Agendamento WhatsApp-first ligada na conta; só o administrador cria e muda funções.
- passos: 1. Abra Configurações > Funções personalizadas; 2. Crie ou edite a função; 3. Na linha Agendamento, escolha Ver ou Editar; 4. Salve a função e atribua à pessoa em Configurações > Agentes.
- gotchas: Editar já inclui Ver; para publicar, a página precisa de quem atende, de um lugar, de pelo menos um dia de atendimento e de um funil para onde vai quem marcar, e o que faltar aparece com Resolver (o do funil abre o Alterar na própria prévia); página desligada com algo faltando aparece como Rascunho no cartão; Agendamento não dá acesso a conectar caixas de e-mail ou WhatsApp, usuários, funções, integrações nem faturamento, que continuam do administrador; escolher uma caixa já conectada para Meet ou Teams não é conectar caixa; quem atende precisa ser pessoa da conta e, se tiver função, com acesso ao CRM; a gaveta antiga de página de agendamento no Kanban continua só do administrador.
- nav_target: `settings_booking`

### Sincronizar RSVP, reagendar e registrar no-show
- intent: "Como vejo se o convidado da reunião aceitou ou recusou?"; "Onde vejo o RSVP / confirmação de presença dos convidados da reunião?"; "Como marco no-show (não compareceu)?"; "Como cancelo ou reagendo uma reunião?"; "Status de presença dos convidados da reunião no calendário."
- onde_fica: Sidebar > CRM > CRM Calendar > abrir evento de reunião
- rota: `crm_calendar_index` - `/app/accounts/:accountId/crm/calendar`
- gate: papel `administrator` ou `agent` ou `crm_view`
- pre_requisitos: reunião criada pelo CRM ou pelo link público; calendário conectado ao provedor.
- passos: Abra o evento no calendário; use atualizar RSVP para sincronizar com Google/Microsoft; use Entrar, Abrir card, Reagendar ou Cancelar; após o fim da reunião, marque Realizada ou No-show; adicione notas se realizada.
- gotchas: outcome só aparece depois do horário de término, não durante a reunião; cancelar/reagendar chama o provedor externo e pode falhar por token expirado; resumo por IA depende de `CRM_AI_ENABLED` e credencial configurada.
- nav_target: `crm_calendar_index`

### Ver todas as campanhas em uma lista
- intent: Onde vejo todas as minhas campanhas?; Onde ficam as campanhas de WhatsApp, e-mail e SMS juntas?; Como filtro as campanhas por canal ou situação?; Qual é o próximo envio agendado?; Onde está a tela Campanha?
- onde_fica: Menu lateral > Campanhas > Campanha
- rota: `campaigns_journey_index` - `/app/accounts/:accountId/campaigns/all`
- gate: feature flag `campaigns`; papel `administrator` ou `campaign_view` ou `campaign_manage`
- pre_requisitos: nova jornada de campanhas ligada na instalação (CAMPAIGN_JOURNEY_ENABLED); pelo menos um canal de campanha conectado (domínio de envio verificado ou caixa de webmail aceita no envio direto, WhatsApp Oficial pela Cloud API, WhatsApp API marcada para campanha, caixa de SMS ou chat do site).
- passos: 1. Abra Campanhas > Campanha no menu lateral; 2. Veja no topo o próximo envio, quantas estão em preparação, quantas saíram nos últimos 30 dias e quantas ficam sempre ativas; 3. Use os botões de canal para ver só um canal; 4. Use Filtrar por situação e a busca para achar uma campanha; 5. Clique em Abrir para ver o Resultado da campanha (E-mail, WhatsApp Oficial, WhatsApp API ou SMS); Chat ao vivo abre a tela dele; 6. Nas linhas de e-mail, o botão de três pontos tem as ações da campanha (editar rascunho, pausar, retomar, duplicar, salvar como modelo, cancelar e excluir rascunho).
- gotchas: a lista mostra todas as campanhas que existem, mesmo de um canal desconectado depois; o filtro mostra os canais conectados e os que ainda têm campanhas; Nova campanha só oferece canais conectados; campanhas de WhatsApp enviadas pelo Twilio não entram como SMS; Chat ao vivo é a mensagem automática do site e aparece como Sempre ativa, sem data; os endereços antigos das listas de E-mails, WhatsApp Oficial, WhatsApp API, SMS e Chat ao vivo abrem esta lista já filtrada pelo canal, e Abrir em cada linha leva ao Resultado da campanha (Chat ao vivo abre a tela dele, onde se edita e pausa); com a jornada desligada o menu volta a mostrar E-mails, WhatsApp Oficial, WhatsApp API, Chat ao vivo e SMS e este endereço leva para as telas antigas.
- nav_target: `campaigns_journey_index`

### Criar campanha escolhendo o canal
- intent: Como crio uma campanha nova?; Onde escolho se a campanha vai por e-mail, WhatsApp ou SMS?; Por que um canal não aparece em Nova campanha?; Como faço uma mensagem automática no site?
- onde_fica: Menu lateral > Campanhas > Campanha > Nova campanha
- rota: `campaigns_journey_index` - `/app/accounts/:accountId/campaigns/all`
- gate: feature flag `campaigns`; papel `administrator` ou `campaign_view` ou `campaign_manage`
- pre_requisitos: permissão para gerenciar campanhas (administrador ou função com campaign_manage); canal conectado.
- passos: 1. Abra Campanhas > Campanha; 2. Clique em Nova campanha; 3. Escolha o canal na lista (só aparecem os conectados); 4. Preencha o formulário do canal, o mesmo de antes; 5. Salve; a campanha entra na lista.
- gotchas: canal que não aparece não está conectado: conecte a caixa em Configurações > Caixas de entrada (para WhatsApp API, marque a caixa para campanhas; para WhatsApp Oficial, a conta precisa do recurso de campanhas de WhatsApp e da caixa pela Cloud API; para e-mail, é preciso domínio de envio verificado ou caixa de webmail como Gmail ou Outlook, uma caixa de domínio próprio sem domínio verificado não basta); sem nenhum canal conectado, o botão mostra o atalho Conectar um canal; quem só tem campaign_view vê a lista mas não o botão; com a importação de base ligada, Nova campanha abre os três passos (Público, Mensagem, Revisar); sem ela, cada canal abre o formulário que já existia.
- nav_target: `campaigns_journey_index`

### Ver os públicos de campanha
- intent: Onde ficam as planilhas que subi para campanhas?; Onde vejo meus públicos?; Como subo uma lista de pessoas para uma campanha?; Onde foi parar a Base Campanha?; Por onde dá para falar com as pessoas de um público?
- onde_fica: Menu lateral > Campanhas > Público
- rota: `campaigns_journey_audiences` - `/app/accounts/:accountId/campaigns/audiences`
- gate: feature flag `campaigns`; papel `administrator` ou `campaign_view` ou `campaign_manage`
- pre_requisitos: nova jornada de campanhas ligada (CAMPAIGN_JOURNEY_ENABLED) e importação de base ligada (CAMPAIGN_IMPORT_ENABLED); para criar, administrador ou função com campaign_manage.
- passos: 1. Abra Campanhas > Público; 2. Veja cada público com nome, selos de canal (E-mail e WhatsApp com a contagem), pessoas e data; 3. Clique no nome para abrir o painel com pessoas, empresas, outras colunas guardadas, quem não recebe, campanhas que usaram e Ver contatos e empresas; 4. Para subir uma planilha nova, clique em Novo público; 5. Em um público salvo, clique em Usar em nova campanha para abrir a campanha com ele escolhido; 6. Excluir público apaga só a lista; 7. Detalhes abre o histórico da importação com os arquivos.
- gotchas: com a jornada ligada, Base Campanha e Histórico de bases saem do menu de três pontos de Contatos e moram aqui; públicos antigos aparecem com o nome da campanha e sem selos de canal, que só são calculados nas importações novas; excluir não apaga contatos, empresas, conversas nem resultados; público usado por campanha que ainda não terminou não pode ser excluído e a tela diz quais campanhas o usam; quem só tem campaign_view vê a lista sem os botões de criar, usar e excluir; com CAMPAIGN_IMPORT_ENABLED desligado o item Público some do menu e o endereço leva para Campanha.
- nav_target: `campaigns_journey_audiences`

### Criar um público com uma planilha
- intent: Como crio um público?; Como subo a planilha de uma campanha?; Por que preciso escolher as colunas?; O que quer dizer linhas com problema?; Como desligo o e-mail ou o WhatsApp de um público?; O público vai criar empresas?
- onde_fica: Menu lateral > Campanhas > Público > Novo público (ou, numa campanha nova sem público, Criar público)
- rota: `campaigns_journey_audience_new` - `/app/accounts/:accountId/campaigns/audiences/new`
- gate: feature flag `campaigns`; papel `administrator` ou `campaign_manage`
- pre_requisitos: jornada de campanhas e importação de base ligadas (CAMPAIGN_JOURNEY_ENABLED e CAMPAIGN_IMPORT_ENABLED); administrador ou função com campaign_manage.
- passos: 1. Dê um nome ao público e escolha a planilha (CSV ou Excel); 2. Clique em Ler planilha e espere a leitura; 3. Em Colunas encontradas, confira qual coluna é nome, celular, e-mail e empresa; se a tela pedir, escolha cada uma (ou Não tem) e clique em Usar estas colunas; 4. Veja os canais (E-mail e WhatsApp com a contagem) e desligue o que o público não deve usar; 5. Confira quantos estão prontos, quantos têm problema (com o motivo de cada linha, sem o nome) e quantos não recebem (recusaram mensagens, descadastrados ou e-mail que voltou); baixe as linhas com problema se quiser corrigir; 6. Em Empresas, deixe Criar e ligar ligado para criar e ligar as empresas da planilha, ou desligue; 7. Clique em Salvar público.
- gotchas: nada entra nos contatos antes de Salvar público; sair antes não cria contato, empresa nem lista; é preciso ter coluna de celular ou de e-mail; canal sem dado aparece desligado com sem dados e não liga; as outras colunas ficam guardadas para usar na mensagem; o bloco Empresas só aparece com Empresas ligada na conta e coluna de empresa; contato que já tem outra empresa continua com a dele (mantida); se veio de uma campanha, o aviso no topo diz qual e, depois de salvar, Voltar para a campanha abre o passo 1 com o público escolhido; não dá para desligar um canal que uma campanha agendada ainda usa.
- nav_target: `campaigns_journey_audience_new`

### Guardar a identidade visual dos e-mails
- intent: Onde coloco a logo e as cores da minha marca nos e-mails?; Como faço os e-mails terem a cara da minha empresa?; Onde fica a Identidade visual?; Como troco a identidade padrão?; Como arquivo ou trago de volta uma identidade?
- onde_fica: Menu lateral > Campanhas > Campanha > aba Identidade visual
- rota: `campaigns_journey_brand_kits` - `/app/accounts/:accountId/campaigns/identity`
- gate: feature flag `campaigns`; papel `administrator` ou `campaign_view` ou `campaign_manage`
- pre_requisitos: jornada de campanhas e campanhas de e-mail ligadas (CAMPAIGN_JOURNEY_ENABLED, EMAIL_CAMPAIGN_ENABLED) e identidade visual ligada (BRAND_KITS_ENABLED, ligada por padrão); e-mail conectado (domínio verificado ou caixa de webmail aceita no envio direto); para ver, campaign_view; para criar, alterar, tornar padrão e arquivar, administrador ou função com campaign_manage.
- passos: 1. Abra Campanhas > Campanha e clique na aba Identidade visual; 2. Sem nenhuma identidade, clique em Usar o meu site; 3. Cada cartão mostra a logo na faixa do topo, o nome, Padrão na que os e-mails novos usam, o site, as fontes e as cores; 4. Clique em Alterar para mudar logo, cores, fontes, redes e rodapé; 5. No botão de três pontos, Tornar padrão faz os e-mails novos saírem com ela; Arquivar tira da lista (pede confirmação no próprio cartão); 6. Arquivadas: Ver mostra as arquivadas, com Restaurar.
- gotchas: a aba só aparece com e-mail conectado; a padrão não pode ser arquivada antes de outra virar padrão; arquivar não muda e-mails já feitos; a primeira identidade vira padrão sozinha; cada identidade guarda duas versões de cores, fundo claro (recomendada para e-mail) e fundo escuro (igual ao site), e cada e-mail escolhe uma; o rodapé do e-mail é sempre o do sistema, com o descadastro: a identidade só preenche a linha de empresa, endereço e site e as redes; com BRAND_KITS_ENABLED desligada a aba some e a IA volta a escolher as cores.
- nav_target: `campaigns_journey_brand_kits`

### Criar a identidade visual a partir do site
- intent: Como crio uma identidade visual?; Como pego a logo e as cores do meu site?; Por que o e-mail sai com fundo claro se o meu site é escuro?; Por que aparece Arial em vez da minha fonte?; Por que a logo não aparece na faixa do topo?
- onde_fica: Menu lateral > Campanhas > Campanha > Identidade visual > Nova identidade (ou Usar o meu site)
- rota: `campaigns_journey_brand_kit_new` - `/app/accounts/:accountId/campaigns/identity/new`
- gate: feature flag `campaigns`; papel `administrator` ou `campaign_manage`
- pre_requisitos: identidade visual ligada (BRAND_KITS_ENABLED) e e-mail conectado; administrador ou função com campaign_manage; site público com página inicial em HTML.
- passos: 1. Cole o endereço do site e clique em Ler o site; 2. Espere a leitura (logo, cores, fontes, redes e rodapé) e clique em Conferir; 3. Parte 1: escolha a logo (do topo do site, ícone ou Enviar outra); em Cores do e-mail, veja Fundo claro e Fundo escuro e use Alterar em cada cor (Botões e destaques, Detalhes, Texto, Texto suave, Fundo, Faixa do topo); Voltar às cores sugeridas desfaz; troque as fontes de títulos e de texto se quiser; a prévia ao lado muda na hora e Ver com Arial mostra como fica sem a fonte; 4. Continuar; 5. Parte 2: dê o nome, confira as redes (Alterar, Tirar, Adicionar rede) e o rodapé (empresa, site, endereço); 6. Salvar.
- gotchas: nada é salvo antes de Salvar; a logo escolhida só é baixada ao salvar e precisa ser PNG, JPEG, WebP ou GIF (SVG fica de fora); logo branca precisa de faixa do topo escura, e a tela avisa quando a faixa está clara; fonte fora do Google Fonts não carrega no e-mail; mesmo com a fonte do site, alguns programas de e-mail mostram Arial; site sem endereço deixa o campo vazio com um convite para escrever; até algumas leituras por hora e uma por vez na conta.
- nav_target: `campaigns_journey_brand_kit_new`

### Alterar uma identidade visual
- intent: Como mudo a cor do botão dos e-mails?; Como troco a logo da identidade?; Como mudo as redes que aparecem no rodapé?; Como deixo os e-mails com fundo escuro?
- onde_fica: Menu lateral > Campanhas > Campanha > Identidade visual > Alterar (no cartão)
- rota: `campaigns_journey_brand_kit_edit` - `/app/accounts/:accountId/campaigns/identity/:kitId`
- gate: feature flag `campaigns`; papel `administrator` ou `campaign_manage`
- pre_requisitos: identidade visual ligada; administrador ou função com campaign_manage.
- passos: 1. No cartão da identidade, clique em Alterar; 2. Na aba Logo, cores e fontes, troque a logo, escolha Fundo claro ou Fundo escuro para ver e mudar cada versão, e troque as fontes; 3. Na aba Redes e rodapé, mude o nome, as redes e a linha do rodapé; 4. Salvar.
- gotchas: as mudanças valem para os e-mails criados depois; e-mails já feitos guardam o que tinham; a versão de cores (clara ou escura) de cada e-mail é escolhida em Criar com IA.
- nav_target: `campaigns_journey_brand_kit_edit`

### Usar a identidade visual num e-mail criado com IA
- intent: Como faço o e-mail da IA sair com a minha marca?; Como uso outra identidade num e-mail?; Como uso o site de outra marca só neste e-mail?; Posso pedir no próprio texto para usar a identidade de um site?; Por que o e-mail diz Confira antes de enviar?; Por que a geração falhou com um problema que impede o envio?
- onde_fica: editor do e-mail > Criar com IA > Identidade (e, no editor, o painel Identidade deste e-mail)
- rota: `campaigns_email_builder` - `/app/accounts/:accountId/campaigns/email_campaigns/:campaignId/builder`
- gate: feature flag `campaigns`; papel `administrator` ou `campaign_view` ou `campaign_manage`
- pre_requisitos: identidade visual ligada; IA de e-mail configurada; para gerar, administrador ou função com campaign_manage.
- passos: 1. Em Criar com IA, a identidade padrão já vem escolhida; 2. Clique em Trocar para escolher outra, Usar outro site ou Ver todas as identidades (abre em outra aba, o e-mail fica aberto); 3. Em Usar outro site, cole o endereço, clique em Ler o site e espere a leitura; marque Salvar como identidade se quiser guardar o site na lista; 4. Escolha Fundo claro (recomendado) ou Fundo escuro; 5. Escreva o briefing e clique em Gerar; 6. No editor, o painel Identidade deste e-mail mostra qual foi usada; Trocar abre o Criar com IA de novo para refazer o e-mail com outra identidade. 7. Também dá para pedir no próprio texto do Criar com IA ou do Ajustar com IA (ex.: "use a identidade do site https://aurora.com.br"): a IA lê o pedido, lê o site e usa a logo, as cores e as fontes dele só neste e-mail; uma frase diz "Usei a identidade de aurora.com.br, como você pediu." com o botão Salvar como identidade.
- gotchas: sem marcar Salvar como identidade, o site vale só para este e-mail e a logo dele fica guardada com a campanha; marcado, o site vira uma identidade ao clicar em Gerar, com o nome do site (se o nome já existe na lista, ganha um número, como Aurora 2), não vira padrão (a não ser que seja a primeira) e um aviso diz se deu certo, se salvou sem a logo ou se não deu para salvar (nesse caso o e-mail usa o site mesmo assim); a IA usa as cores, as fontes e a logo da identidade e não inventa outro rodapé; depois de gerar, o sistema confere contraste, tamanho dos botões, descrição das imagens, placeholders, tamanho e rodapé; se algo falha, pede uma correção à IA; segundo rodapé, placeholder que a campanha não preenche ou e-mail claramente maior que o limite do Gmail fazem a geração falhar; o resto aparece em Confira antes de enviar, inclusive e-mail perto do limite do Gmail e menos de 3 assuntos sugeridos; o tamanho é uma estimativa feita pelo MJML; em Nova campanha, a linha Identidade (Trocar, Gerenciar) escolhe a identidade antes de abrir o editor; o Resultado da campanha mostra qual identidade o e-mail usou. Site pedido no próprio texto: vale só para este e-mail e vence a identidade escolhida; "layout" ou "cara" do site quer dizer cores, fontes e logo — a estrutura continua nos blocos do editor; no Ajustar com IA, trocar a identidade conta como o pedido (textos, imagens e links ficam); no Ajustar com IA, a identidade da campanha só muda quando você clica em Aplicar (Descartar não muda nada, e Desfazer logo depois volta o e-mail e a identidade de antes); site que não abre, endereço interno ou endereço privado não é lido (e os sites lidos assim não contam no limite de 10 leituras por hora da tela Identidade visual; têm um limite próprio de 30 por hora), e a frase diz "Não consegui ler aurora.com.br. Usei a identidade padrão."; endereço citado só como link ou página do produto não troca a identidade.
- nav_target: `campaigns_email_builder`

### Criar campanha de WhatsApp Oficial em três passos
- intent: Como crio uma campanha de WhatsApp para uma planilha?; Como escolho o público da campanha?; De onde vem cada parte da mensagem do modelo?; Por que um canal aparece indisponível?; Como agendo o envio?; Por que algumas pessoas ficam de fora?
- onde_fica: Menu lateral > Campanhas > Campanha > Nova campanha (ou Público > Usar em nova campanha)
- rota: `campaigns_journey_new` - `/app/accounts/:accountId/campaigns/new`
- gate: feature flag `campaigns`; papel `administrator` ou `campaign_manage`
- pre_requisitos: jornada de campanhas e importação de base ligadas; administrador ou função com campaign_manage; um público salvo com celular; caixa WhatsApp pela Cloud API com modelo aprovado.
- passos: 1. Passo Público: escolha um público salvo (os selos mostram e-mail e WhatsApp com a contagem); sem público, clique em Criar público e volte com ele já escolhido; 2. Passo Mensagem: escolha WhatsApp Oficial, dê o nome da campanha, escolha a caixa e o modelo aprovado; 3. Em De onde vem cada parte da mensagem, ligue cada variável (do texto, do cabeçalho e do link do botão) a um dado do contato, a uma coluna do público ou a um texto fixo (as sugestões vêm marcadas como Sugerido); 4. Se a tela disser que pessoas ficam de fora, escreva um texto para quando faltar o dado ou aceite; 5. Passo Revisar: confira, escolha Agora ou data e hora (no fuso da conta) e confirme o envio para o número de pessoas mostrado.
- gotchas: canal que o público não tem aparece indisponível com o motivo (sem celular ou sem e-mail); WhatsApp API (texto com fichas do contato e do público, modelo salvo e anexo) e E-mail (remetente e caixa das respostas, depois o editor de sempre; volte à Nova campanha para revisar, enviar teste para você e agendar) também correm aqui; SMS (caixa de SMS, texto com fichas, contador de partes e prévia) também corre aqui e precisa do selo SMS ligado no público; Chat ao vivo não usa público e tem atalho no passo Público; o rascunho fica salvo neste navegador enquanto você cria o público; quem recusou mensagens fica fora de Vão receber; quem responder ganha a marca Campanha: nome no card do CRM; a campanha envia para todo o público no horário escolhido, sem etapas.
- nav_target: `campaigns_journey_new`

### Criar a mensagem automática do Chat ao vivo
- intent: Como faço uma mensagem automática no meu site?; Como mostro uma mensagem para quem visita uma página?; Onde crio campanha do chat ao vivo?; Como faço a mensagem aparecer só em horário de atendimento?
- onde_fica: Menu lateral > Campanhas > Campanha > Nova campanha > atalho "Quer uma mensagem automática no seu site, sem lista?"
- rota: `campaigns_journey_live_chat_new` - `/app/accounts/:accountId/campaigns/live-chat/new`
- gate: feature flag `campaigns`; papel `administrator` ou `campaign_manage`
- pre_requisitos: jornada de campanhas ligada (CAMPAIGN_JOURNEY_ENABLED); chat do site conectado; administrador ou função com campaign_manage.
- passos: 1. Em Quando aparece, escolha o site, escreva o endereço completo da página (começando com https://), os segundos na página e, se quiser, ligue Só em horário de atendimento; 2. Em Mensagem, dê o nome, escolha quem fala (um agente ou o robô) e escreva o texto, conferindo a prévia; 3. Em Ativar, confira o resumo e clique em Ativar.
- gotchas: não usa público nem lista de pessoas: aparece para quem visita a página; fica na lista Campanha com o selo Sempre ativa; quem conversar por ela ganha a marca "Campanha: <nome da campanha>" no card do CRM; o endereço precisa ser completo.
- nav_target: `campaigns_journey_live_chat_new`

### Editar ou pausar a mensagem do Chat ao vivo
- intent: Como pauso a mensagem automática do site?; Como mudo o texto da mensagem do chat ao vivo?; Como ligo de novo uma mensagem pausada?
- onde_fica: Menu lateral > Campanhas > Campanha > filtro Chat ao vivo > Abrir
- rota: `campaigns_journey_live_chat_edit` - `/app/accounts/:accountId/campaigns/live-chat/:campaignId`
- gate: feature flag `campaigns`; papel `administrator` ou `campaign_manage`
- pre_requisitos: jornada de campanhas ligada; administrador ou função com campaign_manage.
- passos: 1. Na lista Campanha, filtre por Chat ao vivo e clique em Abrir na mensagem; 2. Mude o que precisar em Quando aparece e Mensagem; 3. Em Ativar, clique em Salvar alterações, ou em Pausar (ou Ligar de novo).
- gotchas: o selo no topo mostra Sempre ativa ou Pausada; pausar não apaga a mensagem nem as marcas já dadas.
- nav_target: `campaigns_journey_live_chat_edit`

### Criar e verificar identidade de remetente de e-mail
- intent: "Como libero um domínio para disparo?"; "Onde vejo DKIM/SPF/DMARC?"; "Por que não consigo escolher remetente?"
- onde_fica: Sidebar > Campanhas > E-mails > Identidades de remetente
- rota: `campaigns_email_sender_index` - `/app/accounts/:accountId/campaigns/email_sender`
- gate: feature flag `campaigns`; papel `administrator` ou `campaign_view` ou `campaign_manage`
- pre_requisitos: acesso ao DNS do domínio ou caixa webmail conectada para envio direto em baixo volume.
- passos: Abra Identidades de remetente; clique em novo domínio; informe domínio e e-mail opcional; copie os registros DNS; clique em Verificar agora ou aguarde polling; use apenas identidades verificadas na campanha.
- gotchas: domínios pendentes não aparecem como remetente SES; webmail gratuito aparece como opção de envio direto, mas com aviso e limitações; remover identidade em uso retorna erro.
- nav_target: `campaigns_email_sender_index`
- highlight: `campaigns-add-sender`

### Criar campanha de e-mail e importar base
- intent: "Como crio uma campanha de e-mail?"; "Como importo destinatários?"; "Por que o botão de criar está desabilitado?"
- onde_fica: Sidebar > Campanhas > E-mails
- rota: `campaigns_email_index` - `/app/accounts/:accountId/campaigns/email_campaigns`
- gate: feature flag `campaigns`; papel `administrator` ou `campaign_view` ou `campaign_manage`
- pre_requisitos: identidade verificada ou caixa webmail elegível; arquivo CSV/XLSX de destinatários quando houver base externa.
- passos: Clique em Nova campanha; informe nome e remetente; defina nome do remetente, e-mail, reply-to e texto de prévia; anexe CSV/XLSX de base se necessário; salve e abra o editor.
- gotchas: `from_email` precisa pertencer ao domínio SES verificado; envio direto trava o campo "De" com o e-mail da caixa de entrada; a importação pode gerar campos de personalização a partir das colunas da base.
- nav_target: `campaigns_email_index`
- highlight: `campaigns-new-email`

### Montar e-mail com editor, IA e templates
- intent: "Como edito o corpo do e-mail?"; "Onde uso IA para escrever?"; "Como aplicar template?"; "Como peço para a IA mudar só uma parte do e-mail?"
- onde_fica: Sidebar > Campanhas > E-mails > Editor
- rota: `campaigns_email_builder` - `/app/accounts/:accountId/campaigns/email_campaigns/:campaignId/builder`
- gate: feature flag `campaigns`; papel `administrator` ou `campaign_view` ou `campaign_manage`
- pre_requisitos: campanha em rascunho; para IA, `CRM_AI_ENABLED=true` e credencial de IA resolvível.
- passos: Abra o editor; escolha IA, Biblioteca de modelos ou começar do zero; ajuste assunto e prévia do assunto no topo; edite blocos e propriedades; use Personalizar para inserir os campos disponíveis; com o e-mail já montado, clique em Ajustar com IA, escreva o que quer mudar (ex.: "deixe o botão verde") e confira o antes e depois: Aplicar troca o e-mail, Descartar mantém como estava, e Desfazer volta logo depois de aplicar; envie teste, salve e abra Revisar envio.
- gotchas: geração por IA é assíncrona e mostra status `processing/ready/failed`; o botão diz Criar com IA com o editor vazio e Ajustar com IA quando já há conteúdo — desmarcar "Mudar só o que eu pedir" cria um e-mail novo do zero; o ajuste muda só o pedido, nunca o rodapé de descadastro, e não aplica nada sem a pessoa ver a prévia; se a mudança deixaria o e-mail difícil de ler ou não dá para fazer num e-mail, a tela diz o motivo em uma frase; templates ficam em rota própria `campaigns_email_templates`; enviar teste persiste o corpo antes de enviar.
- nav_target: `campaigns_email_builder`

### Gerenciar destinatários, agendar e enviar campanha de e-mail
- intent: "Como adiciono mais destinatários?"; "Como agendo envio?"; "Onde fica o botão Disparar?"
- onde_fica: Sidebar > Campanhas > E-mails > Gerenciar destinatários
- rota: `campaigns_email_index` - `/app/accounts/:accountId/campaigns/email_campaigns`
- gate: feature flag `campaigns`; papel `administrator` ou `campaign_view` ou `campaign_manage`
- pre_requisitos: campanha em rascunho; corpo HTML salvo para agendar/enviar; destinatários importados.
- passos: Abra Destinatários; importe CSV/XLSX adicional se precisar; confira campos e validação; na lista, clique em Enviar; a revisão mostra o que falta, remetente, público e exclusões; escolha enviar agora ou data/hora e confirme na etapa final. Pausar, Retomar e Cancelar ficam nas ações da campanha.
- gotchas: Enviar aparece nos rascunhos de quem pode gerenciar, inclusive quando falta conteúdo, e abre a revisão sem enviar; o botão final só libera quando os requisitos atuais do servidor estiverem atendidos; falha permanente, spam e descadastro continuam excluídos; validação alerta campos de personalização ausentes ou vazios; a lista faz polling enquanto há campanha `sending`, `scheduled` ou IA processando; destinatário cujo e-mail é de um contato que não quer receber mensagens ativas não recebe e aparece como Descadastrado; o descadastro de e-mail, pelo link ou pelo provedor, marca a recusa nos contatos com aquele e-mail.
- nav_target: `campaigns_email_index`

### Ver a gestão de campanhas
- intent: Como vão as campanhas no geral?; Quantas campanhas enviei no mês?; Quantas pessoas responderam às campanhas?; Quantas campanhas viraram negócio no CRM?; Como comparo campanhas de canais diferentes?; "Onde vejo a taxa de abertura e de clique das campanhas de e-mail?"; "Onde fica o relatório / métricas das campanhas de e-mail (open rate, click rate)?"; "Como exporto o relatório (CSV) de uma campanha de e-mail?"; "Como comparo o desempenho de campanhas de e-mail?"
- onde_fica: Sidebar > Campanhas > Gestão de campanhas (último item do grupo, depois de SMS)
- rota: `crm_campaign_management_index` - `/app/accounts/:accountId/campaigns/management`
- gate: papel `administrator` ou `campaign_view` ou `campaign_manage`
- pre_requisitos: campanhas de e-mail já enviadas ou com eventos de entrega. Com a nova jornada ligada (CAMPAIGN_JOURNEY_ENABLED), vale para campanhas de E-mail, WhatsApp Oficial, WhatsApp API e SMS.
- passos: Com a nova jornada ligada: 1. Abra Gestão de campanhas; 2. Escolha o período (7, 30 ou 90 dias) e o canal (só os conectados); 3. Leia os totais: campanhas enviadas, pessoas alcançadas, responderam, viraram negócio no CRM e saúde do e-mail; 4. Compare as campanhas na tabela (data, enviadas, entregues, engajamento, responderam e taxa; no filtro E-mail também cliques, bounce permanente e descadastros); 5. Clique numa campanha para abrir o Resultado dela. Com a jornada desligada: Abra Gestão de campanhas; filtre por todas ou por uma campanha; revise KPIs de enviado, entregue, abertura aproximada, clique, descadastro, bounce e complaint; ajuste intervalo da linha do tempo; exporte CSV quando uma campanha estiver selecionada.
- gotchas: com a jornada ligada, o detalhe de uma campanha (gráfico, cliques por link, tabela por pessoa, exportação, saúde) fica no Resultado dela, e links antigos com uma campanha de e-mail escolhida abrem esse Resultado; viraram negócio conta os cards do CRM ligados a uma conversa marcada pela campanha, e ganhos é a parte já ganha; pessoas alcançadas soma as entregues, e no WhatsApp API, que não confirma entrega, as enviadas; abertura é aproximada por limitação de tracking; exportar CSV só aparece com campanha específica; esta tela é relatório, não o lugar de editar campanha.
- nav_target: `crm_campaign_management_index`

### Ver o resultado de uma campanha
- intent: Como foi esta campanha?; Quantas pessoas receberam, leram e responderam?; Quem respondeu a campanha?; Por que uma mensagem falhou?; Onde vejo a taxa de abertura e de clique de um e-mail?; Como baixo o resultado por pessoa?; Como pauso, retomo, cancelo ou duplico uma campanha de e-mail?; Onde vejo no CRM quem veio da campanha?
- onde_fica: Menu lateral > Campanhas > Campanha > Abrir (ou Gestão de campanhas > clicar na campanha)
- rota: `campaigns_journey_result` - `/app/accounts/:accountId/campaigns/results/:channel/:campaignId`
- gate: feature flag `campaigns`; papel `administrator` ou `campaign_view` ou `campaign_manage`
- pre_requisitos: nova jornada de campanhas ligada (CAMPAIGN_JOURNEY_ENABLED); campanha de E-mail, WhatsApp Oficial, WhatsApp API ou SMS; permissão de ver campanhas (campaign_view); para baixar o resultado e usar as ações, gerenciar campanhas (campaign_manage); no e-mail, relatórios de e-mail ligados.
- passos: 1. Abra Campanhas > Campanha e clique em Abrir na campanha; 2. Leia os números do topo (WhatsApp e SMS: Público, Enviadas, Entregues, Lidas no WhatsApp Oficial, Responderam, Falharam e Puladas; E-mail: Público elegível, Enviados, Entregues, Abriram, Clicaram, Responderam, Descadastros, Bounce permanente, Temporários, Reclamações e Desconhecidos); 3. A linha abaixo dos números mostra a conta que fecha com o público; 4. Em Pessoas, use as abas de situação para filtrar e Abrir conversa em quem respondeu; 5. Clique em Baixar resultado para o arquivo da aba escolhida; 6. Em Ver no CRM, abra o CRM filtrado por esta campanha; 7. No e-mail, use o gráfico, os cliques por link, a saúde do envio (reavaliar, retomar, problemas), a tabela de destinatários com filtros e exportação e as ações do topo.
- gotchas: enquanto a campanha envia, a faixa amarela aparece e os números se atualizam sozinhos a cada 15 segundos; Enviadas já inclui as entregues e lidas, e Entregues já inclui as lidas; Responderam conta quem mandou mensagem até 72 horas depois do envio e ganhou a marca Campanha: nome no CRM; Abrir conversa só aparece para conversa que você pode ver; o arquivo baixado mostra o nome com a inicial do sobrenome e o telefone ou e-mail mascarado; WhatsApp API não recebe confirmação de entrega nem de leitura, por isso não tem Entregues nem Lidas; SMS só mostra números quando o SMS passa a registrar cada envio por pessoa, antes disso a tela avisa; Chat ao vivo não tem resultado por pessoa; quem só tem campaign_view vê tudo, mas não baixa nem usa as ações.
- nav_target: `campaigns_journey_result`

### Criar e compartilhar Links e QR codes
- intent: Como crio um QR code para o WhatsApp da loja?; Onde crio um link rastreável de vendedor?; Como identifico as conversas que vêm da bio?; Onde baixo o QR code de uma origem?; Como ligo o botão de WhatsApp da minha landing page ao CRM?; O que colo nos Parâmetros de URL do anúncio da Meta?; Como vejo quais campanhas da Meta trouxeram conversas e vendas pelo site?; Por que o lead da landing page chegou sem origem?
- onde_fica: Menu lateral > Campanhas > Links e QR codes, depois de E-mails e antes de Modelos WhatsApp
- rota: `campaigns_tracked_links_index` - `/app/accounts/:accountId/campaigns/links`
- gate: papel `administrator` ou `campaign_view` ou `campaign_manage`
- pre_requisitos: CRM habilitado; acesso às campanhas; caixa de WhatsApp conectada; permissão de gerenciar campanhas para criar, editar o site do botão ou excluir. No uso de site, alguém que mexa no código da página para enviar o aviso de clique.
- passos: 1. Abra Links e QR codes e clique em Nova origem; 2. Em Onde você vai usar, escolha QR code ou link direto (loja, vendedor, bio, impresso) ou Botão de site ou landing page; 3. No QR ou link: informe o nome da origem, o WhatsApp de destino e a mensagem opcional, confira a prévia e crie; depois copie o link, baixe o QR ou veja o material; 4. No site: informe o nome da origem, o WhatsApp de destino e, em Site onde fica o botão, cole o endereço da página como aparece no navegador (pode ser o link inteiro; usamos só o site, até 5, um por linha) e crie; 5. Na origem do site, copie o Texto para os anúncios da Meta e cole em Parâmetros de URL de cada anúncio; 6. Passe ao desenvolvedor o Endereço de aviso e o código da origem (em Para o desenvolvedor); 7. Confira o Último aviso recebido (verde nas últimas 24 horas, âmbar se mais antigo, cinza se nunca chegou) e acompanhe, no painel da origem selecionada, os Resultados por campanha (cliques, conversas, ganhos e valor).
- gotchas: link e QR usam a mesma URL rastreável; o cliente pode editar a mensagem antes de enviar; o QR só é gerado depois de criar; a origem de site não tem QR nem mensagem pré-preenchida, quem monta a mensagem é a página, com o código do clique; o tipo de uso não muda depois de criar; só os sites informados em Site onde fica o botão conseguem avisar cliques (trava contra cliques inventados), e sem nenhum site nada é registrado; anúncio sem o texto de parâmetros ainda aparece como Meta pago, mas sem campanha, conjunto e anúncio; se o cliente apagar o código da mensagem, a conversa só é ligada quando houve exatamente um clique nos 10 minutos anteriores naquela caixa; Último aviso cinza ou âmbar indica que a página não está avisando; excluir inutiliza o link, o QR ou o aviso do site já divulgados; não é necessário habilitar campanhas de e-mail; Gestão de campanhas mantém apenas os relatórios de e-mail; para devolver vendas do site à Meta, preencha o Pixel do site na seção Meta Ads da edição do funil; no card, Conversão Meta Ads mostra o que foi enviado e, quando aparece Não enviado, o motivo (por exemplo, o site não mandou os dados do anúncio porque o cliente não aceitou cookies, falta o Pixel no funil ou passou de 7 dias).
- leitura: campanhas
- nav_target: `campaigns_tracked_links_index`

### Mostrar os nomes das campanhas da Meta no CRM
- intent: Por que a origem do lead aparece com um número em vez do nome da campanha?; Como faço o CRM mostrar o nome da campanha, do conjunto e do anúncio da Meta?; Onde colo o token da Meta para ler os anúncios?; O que é o aviso Precisa de atenção em Nomes das campanhas da Meta?; Como removo a conexão com a Meta?
- onde_fica: Menu lateral > Campanhas > Links e QR codes > bloco Nomes das campanhas da Meta, abaixo da lista de origens
- rota: `campaigns_tracked_links_index` - `/app/accounts/:accountId/campaigns/links`
- gate: papel `administrator` ou `campaign_view` ou `campaign_manage`
- pre_requisitos: ser administrador da conta; acesso ao Gerenciador de Negócios da Meta com um usuário do sistema que enxergue a conta de anúncios.
- passos: 1. Em Links e QR codes, no bloco Nomes das campanhas da Meta, clique em Conectar; 2. No Gerenciador de Negócios, abra Configurações do negócio > Usuários > Usuários do sistema (crie um, se não houver); 3. Em Atribuir ativos, dê ao usuário acesso à conta de anúncios; 4. Clique em Gerar novo token, escolha o app, marque a permissão ads_read e, na validade, escolha Nunca; 5. Copie o token, cole no campo Token de acesso e clique em Testar e salvar; 6. Com o bloco em Conectado, os toques novos e os dos últimos 90 dias passam a mostrar os nomes em alguns minutos.
- gotchas: só administradores veem e editam o bloco; o token é testado antes de salvar e não aparece de novo; sem ads_read o token é recusado com essa explicação; se o usuário do sistema não tiver a conta de anúncios atribuída (Atribuir ativos), o teste passa e o bloco fica Conectado, mas os números continuam no lugar dos nomes — confira esse passo primeiro; se aparecer o aviso de criptografia do servidor não configurada, o token não pode ser guardado e o caso é do suporte; Precisa de atenção quer dizer que a Meta passou a recusar o token salvo (expirou ou perdeu acesso), e a resposta da Meta aparece no bloco; Trocar token ou Conectar de novo substitui o salvo; Remover apaga o token, mas os nomes já resolvidos continuam; enquanto não houver nome, o CRM mostra ID com o começo e o fim do número, e o número inteiro ao passar o mouse; renomear a campanha na Meta só aparece quando o nome guardado vence (7 dias); o filtro de campanha do CRM continua pelo identificador, não pelo nome.
- leitura: campanhas
- nav_target: `campaigns_tracked_links_index`

### Conectar os anúncios da Meta em Anúncios da Meta
- intent: Como conecto meus anúncios da Meta ao Chat2You?; Como compartilho a conta de anúncios com a Hub2You?; Qual conta de anúncios e qual Pixel escolher?; Como faço a Meta receber as minhas vendas?; Como a Meta entende as etapas do meu funil?; Meus anúncios levam para o WhatsApp e para o site, o que marco?; O que quer dizer A Meta ainda está liberando?
- onde_fica: Menu lateral > Campanhas > Anúncios da Meta
- rota: `campaigns_meta_ads_index` - `/app/accounts/:accountId/campaigns/meta-ads`
- gate: feature flag `meta_ads_hub`; papel `administrator`
- pre_requisitos: ser administrador da conta; a página aparece quando Anúncios da Meta está ligado para a conta; para compartilhar sem token, a conta precisa de um WhatsApp oficial conectado à Meta.
- passos: 1. Em Anúncios da Meta, clique em Conectar a Meta; 2. Em Compartilhar com a Hub2You, siga os três passos no Gerenciador de Negócios (Parceiros > Adicionar > Conceder a um parceiro acesso aos seus ativos, cole o código mostrado e marque a conta de anúncios com Ver desempenho e o Pixel; Abrir a Meta já abre a tela de Parceiros da empresa certa) e clique em Já compartilhei — ou use Colar token; 3. Escolha a conta de anúncios (a mais usada vem marcada) e o Pixel do site, e clique em Usar esta conta; 4. Marque para onde os anúncios levam: Direto para o WhatsApp, Para uma página do site, ou os dois, e clique em Continuar; se marcou o site, use Enviar por WhatsApp para mandar a quem cuida do site a página com o código pronto, e Testar agora para confirmar o clique; 5. Em Avisar a Meta sobre o seu funil, confira cada funil ligado ao WhatsApp, revise o que cada etapa significa para a Meta (a IA sugere quando nenhuma etapa tem) e clique em Gravar no funil.
- gotchas: o passo 2 diz por onde a conta é lida (pela parceira ou pela sua chave de acesso) e Trocar volta ao passo 1 — recarregar a página não troca o caminho escolhido; se a escolha da conta falhar, o motivo fica escrito embaixo do botão; a conexão só fica pronta depois que o Chat2You lê a conta de anúncios de verdade (nome, gasto dos últimos 30 dias e Pixel); A Meta ainda está liberando aparece logo depois de compartilhar e some em alguns minutos — clique em Usar esta conta de novo; a conta de anúncios precisa ser do mesmo portfólio da Meta do WhatsApp da conta: de outro portfólio, ou com um número de WhatsApp registrado no portfólio de um revendedor, use Colar token; uma conta de anúncios fica ligada a uma conta do Chat2You só; o passo 4 mostra só os funis ligados a um WhatsApp oficial e grava no próprio funil o mesmo que Editar funil (Como a Meta entende esta etapa e o envio de venda e mudança de etapa); a perda e o dataset continuam como estavam, e o Pixel escolhido só entra no funil que não tem um; Parar de avisar desliga só aquele funil e guarda as escolhas; número de WhatsApp fora de qualquer funil aparece em aviso, porque os clientes dele não chegam à Meta; para anúncios que levam ao site, as páginas são ligadas em Links e QR codes e o texto de Parâmetros de URL é copiado aqui; com Anúncios da Meta ligado, o bloco antigo Nomes das campanhas da Meta sai de Links e QR codes e vira um atalho para esta página; o card do CRM mostra Ver anúncio com a miniatura quando a Meta entrega a prévia do anúncio.
- leitura: campanhas
- nav_target: `campaigns_meta_ads_index`

### Usar o painel de Anúncios da Meta e o que fazer hoje
- intent: Quanto custou cada venda dos meus anúncios?; O que eu faço hoje com os meus anúncios?; Onde vejo as propostas que vieram de anúncio?; Qual anúncio está vendendo e qual não está?; Quanto tempo minha equipe demora para responder quem veio do anúncio?; Por que o número de conversas da Meta é diferente do da plataforma?; Como marco que já fiz a ação do dia?
- onde_fica: Menu lateral > Campanhas > Anúncios da Meta > aba Resultado
- rota: `campaigns_meta_ads_index` - `/app/accounts/:accountId/campaigns/meta-ads`
- gate: feature flag `meta_ads_hub`; papel `administrator`
- pre_requisitos: ser administrador da conta; a conta de anúncios conectada em Anúncios da Meta.
- passos: 1. Na aba Resultado, escolha o período: 7 ou 30 dias; 2. Leia O que fazer hoje: até 3 ações, da mais importante para a menos, cada uma com o porquê; 3. Clique no botão da ação para ir ao trabalho (as propostas paradas, as conversas mais demoradas, o passo 3 da conexão, o anúncio por dentro ou o anúncio no Gerenciador da Meta); 4. Depois de fazer, clique em Feito: a ação fica marcada Feita; se não for fazer, clique em Dispensar e ela sai até amanhã; 5. No caminho do dinheiro, clique em Conversas, Propostas ou Vendas para abrir a lista daquela etapa, com Abrir conversa e Abrir no CRM em cada linha; 6. Confira em Quanto confiar nos números o número da Meta ao lado do nosso.
- gotchas: as ações são decididas pelos números, e a IA só escreve o texto (com o selo Escrito pela IA); sem IA ligada, o texto vem pela regra, com os mesmos números; abrir uma ação não conta como feita, só o Feito conta; na ação que pede para não mexer no anúncio por causa do preço da concorrência, o botão Entendi já é o Feito; dispensada não volta no mesmo dia, e a vaga vai para a próxima ação; a lista das conversas mais demoradas é sempre dos últimos 30 dias, mesmo com o painel em 7; aumentar orçamento é feito no Gerenciador da Meta, a plataforma só lê os anúncios; o Tempo de resposta é a mediana (metade foi respondida em até esse tempo) e conta resposta de pessoas e de agentes; a comparação com a Meta vai até ontem, porque o gasto de hoje ainda está mudando; a lista da etapa mostra até 50 linhas, e o Kanban filtrado por anúncio ainda não existe.
- leitura: campanhas
- nav_target: `campaigns_meta_ads_index`

### Ver todas as origens de um contato no CRM
- intent: O que é o +2 ao lado da origem no card do CRM?; Como vejo todas as campanhas que trouxeram este contato?; Onde vejo o primeiro e o último anúncio que o cliente clicou?; Por que a origem mostra ID e um número?
- onde_fica: Menu lateral > CRM > CRM Kanban > botão +N ao lado da origem no card; ou abrir o card > bloco de vínculos > Origens do contato
- rota: `crm_kanban_index` - `/app/accounts/:accountId/crm`
- gate: papel `administrator` ou `agent` ou `crm_view`
- pre_requisitos: card com conversa que veio de anúncio, link rastreado ou landing page; para ver nomes no lugar de números, a conexão em Links e QR codes > Nomes das campanhas da Meta.
- passos: 1. No Kanban, clique no +N ao lado da origem do card (o card não abre); 2. Leia a lista do primeiro ao último toque, com data, origem, campanha, conjunto, anúncio e o link do post ou da página; 3. Feche com Esc ou clicando fora; 4. No card aberto, a mesma lista aparece em Origens do contato quando houve mais de um toque.
- gotchas: guarda no máximo 20 toques; com um toque só, o card mostra a origem e a campanha como antes; no clique para WhatsApp sem nome resolvido, o anúncio é o título do anúncio; ID 1202…0416 aparece quando a Meta mandou só o número, e o número inteiro fica ao passar o mouse; o link abre em outra aba.
- nav_target: `crm_kanban_index`

### Criar campanha WhatsApp API
- intent: "Como disparo campanha pelo WhatsApp API?"; "Onde escolho rótulos de audiência?"; "Como pauso ou cancelo?"
- onde_fica: Sidebar > Campanhas > WhatsApp API
- rota: `campaigns_whatsapp_api_index` - `/app/accounts/:accountId/campaigns/whatsapp_api`
- gate: feature flag `campaigns`; papel `administrator` ou `campaign_view` ou `campaign_manage`
- pre_requisitos: caixa elegível de WhatsApp API; rótulos de contato para audiência; template ou mensagem/mídia.
- passos: Abra WhatsApp API; clique em Nova campanha; selecione caixa; escolha template ou escreva mensagem com variáveis; anexe mídia se precisar; selecione rótulos de audiência; agende e crie.
- gotchas: audiência é por label, não por segmento salvo; uma campanha precisa de mensagem ou mídia; campanhas em `scheduled/running/paused` têm polling e ações de pausar/retomar/cancelar; contato que não quer receber mensagens ativas é conferido antes de cada mensagem, mesmo com a campanha enviando, e vira cancelado, não falha; a coluna Envios mostra Recusaram mensagens ativas com a contagem; lead descartado na Prospecção com a campanha em andamento sai dos destinatários pendentes, também como cancelado, e aparece em Descartados na Prospecção com a contagem.
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
- gotchas: desfazer remove apenas etiquetas criadas/aplicadas por aquela importação, não deleta contatos; arquivos expiram conforme política de retenção; status em processamento atualiza a cada 5 segundos.
- nav_target: `contacts_campaign_imports`
- highlight: `campaign-imports-back-to-contacts`

### Abrir hub de Agentes de IA
- intent: "Onde ficam meus agentes?"; "Como crio um agente de IA?"; "Por que não vejo o menu Agentes?"
- onde_fica: Sidebar > Agentes de IA > Meus agentes
- rota: `autonomia_agents_index` - `/app/accounts/:accountId/agents`
- gate: papel `administrator` ou `autonomia_view` ou `autonomia_manage`
- pre_requisitos: conta habilitada pelo gate isolado; credencial de IA quando a liberação for global por conta.
- passos: Abra Agentes; revise os cards existentes; clique em Criar com IA; para abrir um agente existente, clique no card; use a aba Testar como entrada padrão do painel.
- gotchas: o menu Agentes aparece assim que a chave da OpenAI é conectada em Integracoes, sem precisar recarregar a pagina; backend de agentes é admin-only e retorna 404 quando o gate está off; a sidebar também esconde o grupo para não admins; o card mostra apenas `human_card`, não a instrução interna.
- nav_target: `autonomia_agents_index`
- highlight: `agents-create`

### Criar agente externo com base de conhecimento
- intent: "Como crio um agente para atender clientes?"; "Como subo materiais no construtor?"; "Como conecto no fim?"
- onde_fica: Sidebar > Agentes de IA > Construtor de agentes
- rota: `autonomia_agents_builder` - `/app/accounts/:accountId/agents/new`
- gate: papel `administrator` ou `autonomia_manage`
- pre_requisitos: tipo de agente escolhido; materiais opcionais em PDF, TXT, MD, JSON, XLSX ou DOCX; caixa elegível se for conectar ao atendimento.
- passos: Escolha atuação Externa e Com conhecimento; selecione o tipo de agente; responda à entrevista do construtor; anexe arquivos ou adicione links no painel de materiais; avance para revisão; teste e conecte uma caixa.
- gotchas: antes da primeira mensagem pode não existir draft agent, então anexos pedem para iniciar a conversa; links colados no chat não viram fonte automaticamente, aparece sugestão para adicionar; a instrução final só existe depois de finalizar/revisar.
- nav_target: `autonomia_agents_builder`

### Criar agente interno ou sem base
- intent: "Como crio um agente interno para a equipe?"; "Como faço sem base de conhecimento?"; "Esse agente responde clientes?"
- onde_fica: Sidebar > Agentes de IA > Construtor de agentes
- rota: `autonomia_agents_builder` - `/app/accounts/:accountId/agents/new`
- gate: papel `administrator` ou `autonomia_manage`
- pre_requisitos: definir atuação Interna ou Sem conhecimento na tela inicial.
- passos: Escolha atuação Interna quando o agente for copiloto da equipe; escolha Sem conhecimento se ele deve partir só da conversa guiada; selecione o tipo ou "Outros"; responda ao construtor; finalize para revisar; abra o painel para testar.
- gotchas: agente interno não se conecta a caixa de entrada e a aba Canais fica oculta/redireciona; atuação `both` não é escolhida no construtor, é ajuste posterior; sem base reduz respostas ancoradas e pode aumentar as transferências para humano por falta de conhecimento.
- nav_target: `autonomia_agents_builder`

### Atualizar conhecimento e fontes do agente
- intent: "Como adiciono conhecimento depois de criado?"; "Como reprocesso uma fonte?"; "Como vejo a qualidade da base?"
- onde_fica: Sidebar > Agentes de IA > Meus agentes > abrir agente > Conhecimento
- rota: `autonomia_agent_panel` - `/app/accounts/:accountId/agents/:agentId/:tab(test|knowledge|channels|performance|tune|publish)?`
- gate: papel `administrator` ou `autonomia_view` ou `autonomia_manage`
- pre_requisitos: agente existente; arquivo suportado ou URL para fonte.
- passos: Abra o agente; entre em Conhecimento; arraste arquivos ou clique Adicionar; escolha link ou arquivo; acompanhe status do revisor e barra de confiança; use Reenviar para reprocessar ou remover para excluir fonte.
- gotchas: remover/adicionar fonte recalcula a confiança e pode atualizar a instrução de agentes finalizados; a aba "Mídias para enviar" só aparece quando existir fonte desse tipo; formatos aceitos no diálogo são `.pdf`, `.txt`, `.md`, `.json`, `.xlsx`, `.docx`.
- nav_target: `autonomia_agent_panel`

### Conectar ou desconectar agente de uma caixa
- intent: "Como coloco o agente para atender uma caixa?"; "Por que uma caixa aparece ocupada?"; "Como desconecto um agente?"
- onde_fica: Sidebar > Agentes de IA > Meus agentes > abrir agente > Canais
- rota: `autonomia_agent_panel` - `/app/accounts/:accountId/agents/:agentId/:tab(test|knowledge|channels|performance|tune|publish)?`
- gate: papel `administrator` ou `autonomia_view` ou `autonomia_manage`
- pre_requisitos: agente ativo/finalizado; caixa elegível; cada caixa pode hospedar apenas um agente.
- passos: Abra o agente; entre em Canais; veja caixas conectadas e elegíveis; clique Conectar em uma caixa livre; para remover, use Desconectar na lista de conectadas.
- gotchas: agentes internos não conectam em caixa; caixas ocupadas aparecem sem botão de conectar; mudar um agente com canais conectados para `internal` pode ser rejeitado pelo backend.
- nav_target: `autonomia_agent_panel`

### Testar, acompanhar e ajustar agente
- intent: "Como testo o agente?"; "Como vejo desempenho?"; "Como ajusto tom, handoff ou instrução?"
- onde_fica: Sidebar > Agentes de IA > Meus agentes > abrir agente > Testar, Desempenho ou Ajustar
- rota: `autonomia_agent_panel` - `/app/accounts/:accountId/agents/:agentId/:tab(test|knowledge|channels|performance|tune|publish)?`
- gate: papel `administrator` ou `autonomia_view` ou `autonomia_manage`
- pre_requisitos: agente existente; para métricas, conversas/respostas já registradas.
- passos: Use Testar para conversar e ver confiança, transferência para humano e fontes usadas; use Desempenho para período 7d/30d, respostas, transferências e taxa de conhecimento; use Ajustar para primeira mensagem, mensagem quando não souber responder, tom, quando transferir para um humano, limite de confiança e atuação; em modo guiado, use Ajustar com IA.
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
- intent: Onde coloco a chave da OpenAI?; Como habilito a IA do CRM Kanban?; Por que a IA nao funciona nesta conta?; Onde configuro a IA da plataforma?
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
- perfil: `administrator` faz o checklist completo. `agent` sem funcao personalizada nao cria caixas, agentes, times nem configuracoes da conta; diga que ele pode ajustar perfil/notificacoes e pedir ao administrator para concluir o onboarding. Funcao personalizada muda parte disso: `inbox_manage` cria caixa, `autonomia_manage` cria agente de IA. Nao diga a essas pessoas que so administrador faz — mostre a tela e deixe a permissao real decidir. Time e configuracoes gerais da conta continuam so do administrator.
- pre_requisitos: nenhum; para conectar canais, ter credenciais do canal escolhido.
- passos: 1. Complete os dados da conta, idioma, fuso e site no onboarding; 2. Crie a primeira caixa de entrada; 3. Convide agentes e associe-os a caixa; 4. Configure horario de atendimento e mensagens basicas da caixa; 5. Crie times ou filas se a operacao tiver mais de uma equipe; 6. Configure a chave de IA/CRM se a conta usar Kanban ou agentes de IA.
- gotchas: sem agentes vinculados a caixa, usuarios podem nao ver conversas do canal; horario de atendimento fica dentro da caixa, nao nas configuracoes gerais; agents/custom roles veem menos itens na sidebar porque a navegacao respeita permissoes reais.
- nav_target: `settings_inbox_new`

### Visao geral dos canais
- intent: Qual canal devo conectar?; Como conecto WhatsApp, Instagram ou email?; Onde crio live-chat do site?; Como comeco com Telegram ou API?
- onde_fica: Configuracoes > Caixas de entrada > Nova caixa
- rota: `settings_inbox_new` - `/app/accounts/:accountId/settings/inboxes/new`
- gate: feature flag `inbox_management`; papel `administrator` ou `inbox_manage`
- perfil: `administrator` cria canais e conclui o wizard. Funcao personalizada com `inbox_manage` tambem cria: as telas do wizard aceitam `administrator` ou `inbox_manage`. `agent` sem essa funcao nao cria; diga para pedir a um administrator e, se ja houver caixa criada, orientar apenas como acessar conversas permitidas. O Guia nao monta a criacao para quem nao e administrator, mas isso e limite dele, nao da pessoa: ofereca o caminho na tela.
- pre_requisitos: credenciais do provedor escolhido; para WhatsApp API, numero em formato `55DDNNNNNNNNN`; para Instagram, conta/authorization da Meta; para email, conta Google/Microsoft ou endereco para encaminhamento; para site, dominio do site; para Telegram, token do bot; para API, webhook opcional.
- passos: 1. Abra Nova caixa e escolha o canal; 2. Para WhatsApp oficial, escolha Cloud/Twilio e siga a autorizacao ou configuracao manual; 3. Para WhatsApp API, informe modo humano ou IA, nome da caixa e telefone; 4. Para Instagram, autorize o perfil; para email, escolha Google, Microsoft ou encaminhamento; 5. Para site, Telegram ou API, preencha os campos do canal; 6. Adicione agentes e finalize o wizard.
- gotchas: `settings_inboxes_page_channel` precisa do `sub_page` correto; WhatsApp API nesta fork e o conector WAHA, nao a campanha WhatsApp API; Instagram fica desabilitado se o app id nao estiver configurado; email via Google/Microsoft pode exigir credenciais OAuth; o passo de agentes usa `settings_inboxes_add_agents` e o final usa `settings_inbox_finish`.
- nav_target: `settings_inbox_new`

### Usar o proprio Guia da Plataforma
- intent: O que o Guia faz?; Voce consegue me levar para uma tela?; O Guia pode configurar por mim?; Como pergunto onde fica uma funcao?; Onde vejo minhas conversas anteriores com o Guia?; Como apago uma conversa com o Guia?
- onde_fica: Barra lateral > botao Pergunte ao Guia, no pe da barra, acima da foto do perfil (com a barra recolhida, so o icone de interrogacao); no celular, bolinha azul no canto inferior direito; quando habilitado
- perfil: `administrator`, `agent` e custom roles podem perguntar ao Guia quando o recurso estiver habilitado para a conta. Se o usuario pedir uma tela bloqueada para o perfil dele, diga que o perfil atual nao tem acesso, explique o motivo e ofereca caminho alternativo ou orientacao para acionar um administrator.
- pre_requisitos: usuario autenticado em uma conta ativa; Guia habilitado para a conta.
- passos: 1. Pergunte em linguagem natural onde fica ou como fazer algo; 2. O Guia identifica seu perfil e as flags da conta; 3. Ele responde com o caminho no menu e os pre-requisitos, consultando os dados da sua conta quando a pergunta for sobre o que voce tem; 4. Quando houver uma rota permitida, ele pode abrir a tela certa; 5. Se voce for administrador e pedir para ele fazer algo, ele monta o pedido e mostra o que vai acontecer: nada acontece ate voce confirmar na tela.
- gotchas: o Guia le e executa sempre com a permissao de quem falou com ele, nunca alem dela; nenhuma acao acontece sem a confirmacao na tela; o Guia so executa para quem e administrador da conta, e isso e limite dele, nao veredito sobre a pessoa: quem tem funcao personalizada costuma poder fazer a mesma coisa clicando, entao para os demais perfis ele explica e leva ate a tela, onde a permissao real decide; alterar ou apagar registro existente exige saber qual registro e: ele le a conta, acha o registro pelo nome e propoe com o id que a leitura trouxe, e pergunta qual quando ha mais de um; ele nao deve revelar segredos nem burlar permissoes; rotas com parametros, como `:inboxId` ou `:agentId`, levam ao item real que ele leu da conta; se uma feature estiver desligada, o Guia deve explicar o gate em vez de prometer a tela.; a conversa com o Guia fica guardada: ao abrir o painel ele volta na ultima conversa, mesmo depois de recarregar a pagina; Nova conversa comeca outra sem apagar a anterior; o botao de relogio no topo do painel abre o Historico, com a aba Conversas (as anteriores, para continuar ou apagar pela lixeira) e a aba Feito pelo Guia (o que ele mudou na conta, com o desfazer de 5 dias); as conversas ficam guardadas sem prazo, ate a pessoa apagar; apagar uma conversa nao tem desfazer, por isso a tela pede confirmacao; cada pessoa ve so as proprias conversas, nem o administrador ve as dos outros; numa conversa reaberta, foto e arquivo aparecem so pelo nome (o arquivo some em 1 dia) e a mensagem de voz aparece como o texto falado
- nav_target: —

### Escalar para suporte humano
- intent: Quando devo falar com suporte humano?; Como abro um chamado?; Onde contato o suporte?; O Guia nao resolveu, o que faco?
- onde_fica: Menu do perfil/avatar > Contate o suporte, quando o item estiver disponivel; em white-label/custom branded, usar o canal de suporte definido por quem mantem a instalacao
- perfil: `administrator`, `agent` e custom roles podem escalar quando o item estiver visivel. Se o item nao aparecer, diga que o atalho de suporte nao esta habilitado para esta instalacao/perfil e oriente usar o canal humano contratado ou pedir ao administrator/super-admin da plataforma.
- pre_requisitos: usuario logado; widget de suporte instalado e configurado, ou canal externo de suporte informado pela operacao.
- passos: 1. Tente primeiro pedir ao Guia o caminho, o gate ou o erro observado; 2. Antes de abrir chamado, peca ao Guia olhar: dado que parece divergente e credencial mal configurada ele le direto da conta, e para administrador ainda prepara a correcao para voce confirmar na tela; 3. Escale quando o Guia realmente nao conseguir: instabilidade da plataforma, erro que se repete depois da correcao, falha dentro do servico externo em si, ou bloqueio que so quem mantem a instalacao resolve; 4. Abra o menu do perfil/avatar; 5. Clique em Contate o suporte se aparecer; 6. Informe conta, tela, horario aproximado, mensagem de erro e o que estava tentando fazer.
- gotchas: o Guia nao abre chamado por conta propria; em white-label o item nativo de suporte pode ficar escondido mesmo com a feature ligada; nao envie senhas, tokens, chaves OpenAI, credenciais de S3/SMTP ou dados sensiveis em texto aberto.
- nav_target: —

### Ler a Central de Ajuda
- intent: Onde fica a Central de Ajuda?; Tem um manual da plataforma?; Onde aprendo a usar a plataforma?; Como acho um artigo de ajuda?; Onde fica a documentacao?; Como aumento a letra da Central de Ajuda?; Como pergunto ao Guia pela Central?; Onde vejo os videos de ajuda?; Onde continuo os primeiros passos?; Onde acho ajuda quando algo nao funcionou?; Onde vejo os artigos de um assunto?; Onde vejo os videos de um assunto?; Como sei quais artigos ja li?; Como continuo de onde parei num assunto?; O que e a Melhor resposta da busca da Central?; Por que nao apareceu a Melhor resposta?
- onde_fica: Menu lateral > Central de Ajuda (tambem no menu da sua foto > Central de Ajuda)
- rota: `central_de_ajuda` - `/app/accounts/:accountId/central-de-ajuda`
- gate: papel `administrator` ou `agent` ou `custom_role`
- cobre: central_de_ajuda_artigo, central_de_ajuda_assunto
- pre_requisitos: nenhum
- passos: 1. Abra Central de Ajuda no menu lateral; 2. Escreva na busca o que voce quer fazer ou o problema que tem, com as suas palavras (quando voce para de digitar, os artigos aparecem, com a Melhor resposta no topo e com destaque; Enter abre a Melhor resposta ou, sem ela, o primeiro da lista), ou escreva a duvida e clique em Perguntar ao Guia, ao lado da busca; 3. Para os pedidos comuns, use um atalho de Mais procurados, logo abaixo da busca; 4. Em Continue de onde parou, veja o proximo passo que falta na configuracao e clique em Assistir ou Ler o passo a passo; 5. Se algo deu errado, procure o caso em Algo nao funcionou?; 6. Em Por assunto, clique no assunto para abrir a pagina dele, com os artigos em ordem, o video de cada um e o que voce ja viu; 7. Na pagina do assunto, clique em Continuar para abrir o primeiro artigo que falta ver (Comecar quando nao viu nenhum, Rever do inicio quando viu todos), ou em Abrir com o nome do assunto para ir direto a tela dele; 8. Clique no artigo e use Me leve ate la para abrir a tela certa com o botao destacado; 9. Use A- e A+ para mudar o tamanho da letra.
- gotchas: cada pessoa ve so os artigos dos recursos que a conta tem, e artigo de configuracao aparece so para administrador; atalho ou assunto sem artigo visivel para a conta nao aparece; a Melhor resposta e escolhida por IA entre os artigos que a pessoa pode ler e entende o pedido em linguagem natural, enquanto a lista abaixo continua sendo a busca por palavras; a Melhor resposta some quando a busca nao tem certeza do artigo (o mais provavel vai entao para o topo da lista, sem destaque), quando nenhum artigo responde, quando o texto tem menos de tres letras ou quando a busca demora ou falha, e nesses casos a lista por palavras continua valendo; Perguntar ao Guia manda ao Guia o texto da busca, e com a busca vazia so abre o painel; Continue de onde parou mostra o primeiro passo pendente cujo artigo a conta enxerga, e some quando nao falta passo (todos feitos ou pulados), quando o que falta depende de um recurso que a conta nao tem, ou quando a lista de passos nao carrega; o link Ver todos os passos, que abre a tela Primeiros passos, aparece so para administrador; cada assunto mostra quantos artigos tem e, quando ha, quantos videos, e o video fica dentro do artigo; a pagina do assunto marca Visto em cada artigo que a pessoa ja abriu, guardado no usuario dela e valendo em todos os aparelhos; o botao Abrir com o nome do assunto some quando nenhuma tela do assunto existe para a conta; Perguntar ao Guia, no rodape da pagina do assunto, so abre o painel do Guia e aparece so quando o Guia esta disponivel; no topo do artigo, o nome do assunto leva de volta a pagina dele; o botao Me leve ate la some quando a tela nao existe para a conta; a letra escolhida vale em todos os aparelhos; os artigos sao da plataforma e ninguem edita pelo painel; logo depois de uma atualizacao da plataforma, a Central pode levar alguns minutos para mostrar o texto novo.
- nav_target: `central_de_ajuda`

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
- pre_requisitos: caixa de entrada existente; etiquetas criadas se a regra de envio for baseada em etiquetas
- passos: 1. Abra a caixa em Configuracoes; 2. Entre na aba CSAT; 3. Ative a pesquisa; 4. Defina tipo de exibicao/mensagem ou template, conforme o canal; 5. Configure a regra por etiquetas; 6. Salve.
- gotchas: CSAT e enviado uma vez por conversa; em canais WhatsApp a tela cria/atualiza template dedicado e mostra status de aprovacao; alterar template existente pode pedir confirmacao; se a regra por etiqueta nao bater, a pesquisa nao e enviada.
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
- gotchas: a aba Tudo mostra apenas alguns resultados por tipo; filtros avancados de data, remetente e caixa de entrada so entram no payload quando `advanced_search` esta ativo; resultados seguem permissao e acesso a caixa de entrada/contato/artigo.
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
- passos: 1. Abra Configuracoes > Integracoes; 2. Pesquise a aplicacao desejada; 3. Clique em configurar; 4. Para hooks, preencha credenciais e selecione a caixa de entrada quando a integracao for por caixa de entrada; 5. Para Dashboard Apps, abra a area propria e cadastre titulo e URL; 6. Salve e teste no contexto da conversa/caixa.
- gotchas: Dashboard App usa conteudo do tipo `frame` com URL valida; Dialogflow e uma integracao por caixa de entrada, nao um `agent_bot`; algumas integracoes so aparecem como ativas se houver credencial global ou feature habilitada; remover hook desconecta a integracao.
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
- passos: 1. Abra CRM Kanban; 2. Selecione o funil; 3. Clique em Editar funil; 4. No bloco IA do funil, habilite IA, auto-move, callback e/ou retorno automatico; 5. Preencha criterios por etapa, transferencia para humano e horarios de envio; 6. Clique em Salvar IA ou Salvar funil.
- gotchas: o painel so aparece ao editar um funil existente; auto-move depende de criterios por etapa; callback tem modos "so lembrar", "enviar mensagem" ou "ambos"; o retorno automatico envia mensagens, entao deve ser ligado com cuidado; contato marcado como quem nao quer receber mensagens ativas nao recebe retorno automatico: o card mostra Parado a pedido do cliente.
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
- onde_fica: Sidebar > CRM > CRM Calendar > Agendamento
- rota: `crm_calendar_index` - `/app/accounts/:accountId/crm/calendar`
- gate: papel `administrator` ou `agent` ou `crm_view`
- perfil: `administrator`; se o perfil nao puder, diga que a API de perfis de agendamento e administrativa. Custom role com `crm_manage_pipelines` pode ver controles de CRM, mas deve pedir a um administrador para salvar/gerar links de booking.
- pre_requisitos: caixa de e-mail Google/Microsoft conectada com calendario; agentes adicionados como membros da caixa; funil/etapa padrao recomendados para criar o lead corretamente.
- passos: 1. Abra CRM Calendar; 2. Clique em Agendamento; 3. Habilite a pagina da caixa; 4. Em Atribuicao, escolha Por agente (links individuais); 5. Marque Caixa compartilhada quando varios agentes usam o mesmo e-mail; 6. Salve e copie o link de cada agente.
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
- passos: 1. Abra n8n (Conexoes do CRM); 2. Clique para criar token de API do CRM; 3. Copie o token no n8n usando o header `api_access_token`; 4. Volte e crie um webhook; 5. Marque eventos como `crm.card.created`, `crm.card.moved`, `crm.card.won`, `crm.card.lost`, `crm.card.resolved`, `crm.card.cancelled`, `crm.card.reopened` ou `crm.card.archived`.
- gotchas: n8n local ou URL privada pode ser bloqueado por protecao SSRF; eventos de CRM so aparecem no webhook quando `CRM_KANBAN_ENABLED=true`; token e webhook sao duas partes separadas da integracao.
- nav_target: `settings_integrations_crm_n8n`
- highlight: `crm-n8n-token`

### Configurar CRM por caixa de entrada
- intent: "Como faco conversas virarem cards automaticamente?"; "Como defino funil padrao por inbox?"; "Como restringo cards da caixa para o agente atribuido?"
- onde_fica: Sidebar > CRM > CRM Kanban > Configurar caixas de entrada
- rota: `crm_kanban_index` - `/app/accounts/:accountId/crm`
- gate: papel `administrator` ou `agent` ou `crm_view`
- perfil: `administrator`, `agent` sem custom role, ou custom role com `crm_manage_pipelines`/`crm_admin`; se o perfil nao puder, diga que ele precisa de permissao para gerenciar funis/configuracoes do CRM.
- pre_requisitos: caixas de entrada criadas; funil e etapas existentes quando quiser definir padrao.
- passos: 1. Abra CRM Kanban; 2. Clique em Configurar caixas de entrada; 3. Ative CRM na caixa de entrada desejada; 4. Escolha visibilidade entre todos os cards da caixa de entrada ou apenas atribuidos; 5. Defina funil/etapa padrao; 6. Marque Criar card automaticamente e clique em Salvar no cartao daquela caixa; o cartao mostra "Salvo" quando gravou; 7. Repita nas outras caixas e clique em Concluir. Cada caixa salva separada: o rodape avisa quantas caixas tem alteracao nao salva, e fechar descarta o que nao foi salvo.
- gotchas: card automatico cria card para todo e-mail, inclusive os que nao sao lead (newsletter, fornecedor, aviso de sistema): numa caixa de e-mail que recebe de tudo, o funil se enche de card que nao e venda; nesse caso o caminho e desligar o card automatico da caixa e criar o card por automacao com uma condicao que separe o que e lead (por exemplo, o remetente do formulario do site); se CRM ativo for desligado, a criacao automatica tambem e desligada; `assigned_only` muda a visibilidade de agentes; funil/etapa padrao precisam pertencer a mesma conta.
- nav_target: `crm_kanban_index`
- highlight: `crm-configure-inboxes`

### Criar automacoes por etapa do funil
- intent: "Como automatizo uma etapa do CRM?"; "Como criar follow-up ao mover card?"; "Como atribuir responsavel automaticamente quando entrar numa etapa?"
- onde_fica: Sidebar > CRM > CRM Kanban > Configurar > Editar funil > status > Automacoes deste status
- rota: `crm_kanban_index` - `/app/accounts/:accountId/crm`
- gate: papel `administrator` ou `agent` ou `crm_view`
- perfil: `administrator`, `agent` sem custom role, ou custom role com `crm_manage_pipelines`/`crm_admin`; se o perfil nao puder, diga que automacoes de etapa fazem parte da gestao de funis.
- pre_requisitos: funil salvo; etapa existente; agentes disponiveis quando a acao for atribuir responsavel.
- passos: 1. Abra Editar funil; 2. Na etapa desejada, abra Automacoes desta etapa; 3. Crie uma regra e escolha gatilho de entrada ou saida; 4. Adicione passos como Criar retorno, Atribuir responsavel, Mover etapa ou Perguntar ao Decisor (os passos depois dele so rodam se ele responder a chave combinada; veja usar_decisor_na_automacao); 5. Defina atraso e parametros; 6. Salve a regra.
- gotchas: automacoes so aparecem para etapas ja salvas; regras podem encadear movimentos, entao evite loops; retornos criados pela automacao aparecem no card e no calendario.
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

### Exportar a lista do CRM para Excel
- intent: "Como exporto o CRM para Excel?"; "Como baixo uma planilha dos cards?"; "Da para exportar o funil em CSV?"; "Como tiro os leads do CRM para uma planilha?"
- onde_fica: Sidebar > CRM > CRM Kanban > alternar para Lista > botao Exportar, ao lado de Novo card
- rota: `crm_kanban_index` - `/app/accounts/:accountId/crm`
- gate: papel `administrator` ou `agent` ou `crm_view`
- perfil: `administrator` ou custom role com `crm_export` (ou `crm_admin`). Agente sem funcao personalizada NAO exporta, mesmo vendo o CRM: a planilha leva nome, telefone e e-mail dos contatos. Se o perfil nao puder, diga que falta a permissao Exportar a lista do CRM para Excel e que um administrador pode concede-la na funcao personalizada.
- pre_requisitos: CRM habilitado; funil selecionado; modo Lista aberto.
- passos: 1. Abra o CRM e troque para Lista; 2. Escolha o funil, a aba de resultado, a busca, os filtros e a ordenacao que quer levar; 3. Clique em Exportar; 4. O navegador baixa um arquivo .xlsx que abre no Excel ou no Google Planilhas.
- gotchas: so existe na Lista, nao no Kanban nem no Calendario; a planilha segue exatamente o recorte da Lista (funil, aba de resultado, busca, filtros e ordenacao) e traz todos os cards, nao so os carregados na tela; cards e campos que a pessoa nao ve na tela tambem nao saem no arquivo; o formato e Excel (.xlsx), nao CSV.
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
- cobre: campaigns_one_off_index
- pre_requisitos: caixa de SMS conectada; audiência (rótulos/contatos); mensagem do SMS
- passos: 1. Abra Campanhas > Campanhas SMS; 2. Clique em Criar campanha; 3. Selecione a caixa de SMS; 4. Escreva a mensagem; 5. Defina audiência e agendamento; 6. Crie a campanha.
- gotchas: o botão 'Criar campanha' fica no cabeçalho da página (CampaignLayout); a criação abre um diálogo; sem caixa de SMS conectada não há opções de envio; contato marcado como quem não quer receber mensagens ativas é pulado no envio.
- nav_target: `campaigns_sms_index`
- highlight: `campaigns-new-sms`

### Criar campanha de chat ao vivo
- intent: Como crio uma campanha de chat ao vivo?; Como disparo mensagem proativa no widget?; Onde configuro campanha de live chat?; Como abordo visitantes automaticamente?
- onde_fica: Sidebar > Campanhas > Campanhas de chat ao vivo
- rota: `campaigns_livechat_index` - `/app/accounts/:accountId/campaigns/live_chat`
- gate: feature flag `campaigns`; papel `administrator` ou `campaign_view` ou `campaign_manage`
- cobre: campaigns_ongoing_index
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
- gotchas: esta é a tela 'WhatsApp Oficial' (whatsapp_campaigns), diferente de 'WhatsApp API' (campaigns_whatsapp_api_index); só aparece com a feature flag whatsapp_campaigns ativa; contato marcado como quem não quer receber mensagens ativas é pulado no envio.
- nav_target: `campaigns_whatsapp_index`
- highlight: `campaigns-new-whatsapp-official`

### Usar e filtrar o calendário CRM por tipo de evento
- intent: Como filtro o calendário por tipo?; Como mostro só reuniões / só follow-ups no calendário?; Como escondo os eventos externos do calendário?; O que são os chips Lembretes, WhatsApp, Previsões, Reuniões e Externos?
- onde_fica: Sidebar > CRM > Calendário (ou CRM Kanban > visualização Calendário) > chips de tipo no cabeçalho do calendário
- rota: `crm_calendar_index` - `/app/accounts/:accountId/crm/calendar`
- gate: papel `administrator` ou `agent` ou `crm_view`
- pre_requisitos: ao menos um funil; para ver reuniões/externos, caixa Google ou Microsoft com calendário ativo.
- passos: 1. Abra o Calendário do CRM; 2. No cabeçalho, use os chips de tipo (Lembretes, WhatsApp, Previsões, Reuniões, Externos) para ligar/desligar cada camada; 3. Alterne a visão em Mês/Semana/Dia/Agenda; 4. Use Hoje e as setas para navegar; 5. Ajuste o escopo entre Meus e Todos.
- gotchas: os chips são toggles independentes e ficam coloridos quando ativos; Externos aparece em estilo apagado/itálico e é só leitura; sem caixa com calendário conectado, Reuniões e Externos ficam vazios; o escopo Meus/Todos altera quais retornos aparecem.
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
- gotchas: WhatsApp API por QR Code é DIFERENTE do WhatsApp Oficial: usa o número direto via QR (sem aprovação da Meta); números brasileiros enviados com ou sem o 9º dígito são resolvidos automaticamente para o chat correto quando o App de números brasileiros está habilitado no WAHA; cada contato usa uma conversa contínua nesta caixa e, se o cliente voltar depois de uma resolução, a mesma conversa é reaberta; o QR aparece na tela de conexão DEPOIS de criar a caixa (não no clique do tile); o WhatsApp dá cerca de 2 minutos e meio para ler (a tela mostra o tempo restante); se expirar, a tela mostra "O QR Code expirou" e o botão Gerar novo QR Code, sem recriar a caixa; leia pelo próprio WhatsApp (Aparelhos conectados), não pela câmera do celular; pode desconectar se o aparelho/sessão cair; se o tile não aparecer, o canal pode não estar habilitado nesta instalação.
- nav_target: `settings_inbox_new`
- highlight: `channel-whatsapp-api`

### Conectar o WhatsApp API na caixa oficial
- intent: Como respondo o cliente depois de 24 horas sem modelo?; Quero ligar o WhatsApp API na minha caixa oficial; Onde fica a aba WhatsApp API da caixa?; O que quer dizer WhatsApp API na bolha da mensagem?; O que é WhatsApp API plano B?; O WhatsApp API da caixa desconectou, como reconecto?; Como desligo o envio pelo WhatsApp API?
- onde_fica: Configurações > Caixas de entrada > selecionar a caixa de WhatsApp Oficial > aba WhatsApp API
- rota: `settings_inbox_show` - `/app/accounts/:accountId/settings/inboxes/:inboxId/:tab?`
- gate: feature flag `inbox_management`; papel `administrator` ou `inbox_view` ou `inbox_manage`
- perfil: `administrator`, ou função personalizada com `inbox_manage`. Sem isso, diga que conectar, ajustar e desconectar o WhatsApp API da caixa fica com quem administra as caixas; quem atende só vê o resultado na conversa.
- pre_requisitos: caixa de WhatsApp Oficial conectada pela Meta; o celular com o WhatsApp Business do mesmo número na mão; a aba só aparece nas contas em que o recurso foi liberado
- passos: 1. Abra a caixa de WhatsApp Oficial em Configurações > Caixas de entrada; 2. Entre na aba WhatsApp API e clique em Conectar WhatsApp API; 3. No celular deste número, abra o WhatsApp Business, vá em Configurações > Dispositivos conectados > Conectar dispositivo e leia o QR Code (ou clique em Prefiro usar um código e, no celular, toque em Conectar com número de telefone e digite o código); 4. Espere a tela confirmar que é o mesmo número da caixa oficial; 5. Em Antes de ligar, marque o aceite do risco; 6. Confira o Envio automático (já vem ligado); 7. Em Quem pode enviar depois de 24 horas, deixe ligados só Atendentes, Robôs, Automações ou Campanhas que devem usar esse caminho; 8. Ajuste Mensagens por minuto pelo WhatsApp API (de 1 a 120; vem 20).
- gotchas: o WhatsApp API não é canal oficial da Meta e o número oficial pode sofrer restrição ou banimento, por isso nada sai por ele antes do aceite do risco; é a mesma caixa e a mesma conversa, sem segunda caixa nem bolha repetida; dentro de 24 horas a mensagem sai pelo WhatsApp Oficial, depois de 24 horas sai pelo WhatsApp API; modelo aprovado sempre sai pelo oficial; botões, listas, carrossel e formulários nunca saem pelo WhatsApp API; com a aba conectada, o campo de resposta não trava mais depois de 24 horas; a bolha mostra WhatsApp API quando saiu por esse caminho e WhatsApp API · plano B quando a Meta recusou porque a janela tinha fechado e a mensagem foi reenviada com segurança; contato só com o código da Meta, sem telefone na ficha, nunca usa o WhatsApp API e continua precisando de modelo depois de 24 horas; se o celular conectado for outro número, a tela avisa e nada sai por ele: desconecte e conecte o celular certo; origem desligada em Quem pode enviar falha depois de 24 horas como antes; o que passa do limite por minuto espera a vez em vez de sair em rajada; se o celular desconectar, os administradores recebem aviso urgente do Guia e, até reconectar com Gerar novo QR Code, respostas depois de 24 horas voltam a precisar de modelo aprovado; falha com Confira no celular antes de reenviar quer dizer que não deu para saber se saiu, então olhe o celular antes de mandar de novo; desligar o Envio automático pausa sem desconectar; Desconectar WhatsApp API tira o aparelho do celular e a caixa volta a pedir modelo depois de 24 horas.
- nav_target: `settings_inbox_show`

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
- pre_requisitos: perfil profissional do Instagram; acesso ao perfil para autorizar no Instagram Login; permissão de gerenciar caixas de entrada. Este fluxo de Instagram Login não exige Página do Facebook.
- passos: Vá em Configurações > Caixas de entrada > Nova caixa e escolha Instagram. Com preparação assistida habilitada na conta, informe o @, busque e selecione o perfil conferindo foto, @ e nome; envie convite somente quando a tela oferecer essa ação. Se estiver pendente, no navegador de um computador entre com o @ exato, abra Apps e sites > Convites do testador, localize o nome do aplicativo exibido e clique em Aceitar; o link Abrir Apps e sites leva a https://www.instagram.com/accounts/manage_access/. Volte e clique em Já aceitei — verificar. Com Convite aceito, clique em Continuar com Instagram e autorize o mesmo perfil. Com preparação assistida desligada na conta, siga diretamente o Instagram Login. Atribua agentes e finalize o assistente.
- gotchas: Preparação assistida ligada depende da disponibilidade da instalação; se indisponível, peça suporte e nova verificação, sem pular para OAuth direto. A habilitação não concede canal, plano, limite de caixas ou permissões. Convite aceito não comprova propriedade do perfil, não conclui a conexão e não substitui OAuth ou App Review. Não detectamos qual perfil está aberto no Instagram: confira o @ na outra aba. Nunca peça senha, cookie ou token ao usuário. Erro ou timeout não significa convite ausente; após envio incerto, verifique antes de tentar novamente. O gestor de sessão usa uma máquina dedicada da operação; não abre Chrome no computador do cliente. Trocar perfil ou voltar não remove testador. Reautorizar uma caixa existente preserva a mesma caixa e perfil e continua disponível, respeitando suas permissões; não serve para criar outra caixa ou trocar de perfil. Mensagens dependem das permissões concedidas e do funcionamento da integração.
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
- onde_fica: Sidebar > Agentes de IA
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
- cobre: agent_reports
- pre_requisitos: o agente precisa existir e ter conversas atribuídas no período
- passos: 1. Abra Relatórios > Agentes; 2. Clique no nome da pessoa na tabela; 3. Ajuste o período e, se quiser, ligue Horários de funcionamento; 4. Clique numa barra para ver as conversas daquele dia; 5. Use a seta de voltar para retornar à lista.
- gotchas: o relatório de agente não tem gráfico de mensagens recebidas, porque mensagem do cliente não é atribuída a um agente; o botão de baixar gera o arquivo de todos os agentes do período, não apenas o da pessoa aberta na tela; trocar de agente pelo filtro do topo recarrega a tela inteira; ver as conversas por trás de uma barra é restrito a administrador.
- nav_target: `agent_reports_show`

### Abrir o desempenho de um canal por dentro
- intent: O WhatsApp está demorando mais que o site para responder?; Quantas mensagens esse canal recebeu na semana?; Em que dia esse canal teve mais conversa?; Quais conversas geraram aquele pico?
- onde_fica: Relatórios > Caixa de Entrada > clicar no nome da caixa
- rota: `inbox_reports_show` - `/app/accounts/:accountId/reports/inboxes/:id`
- gate: feature flag `reports`; papel `administrator` ou `report_manage`
- cobre: inbox_reports
- pre_requisitos: a caixa de entrada precisa existir e ter conversas no período
- passos: 1. Abra Relatórios > Caixa de Entrada; 2. Clique no nome do canal na tabela; 3. Ajuste o período e, se quiser, ligue Horários de funcionamento; 4. Clique numa barra para ver as conversas daquele dia; 5. Use a seta de voltar para retornar à lista.
- gotchas: o botão de baixar traz o arquivo de todas as caixas do período, não só a que está na tela; o filtro do topo troca de canal e recarrega tudo; os tempos médios consideram apenas conversas que tiveram primeira resposta ou resolução; abrir as conversas de uma barra é permitido apenas a administrador.
- nav_target: `inbox_reports_show`

### Abrir o desempenho de um time por dentro
- intent: O time de suporte está resolvendo mais rápido que o comercial?; Quantas conversas esse time atendeu no mês?; O tempo de espera do cliente nesse time caiu?; Quais conversas estão por trás desse número?
- onde_fica: Relatórios > Time > clicar no nome do time
- rota: `team_reports_show` - `/app/accounts/:accountId/reports/teams/:id`
- gate: feature flag `reports`; papel `administrator` ou `report_manage`
- cobre: team_reports
- pre_requisitos: o time precisa existir e ter conversas atribuídas a ele no período
- passos: 1. Abra Relatórios > Time; 2. Clique no nome do time na tabela; 3. Ajuste o período e, se quiser, ligue Horários de funcionamento; 4. Clique numa barra para ver as conversas daquele dia; 5. Use a seta de voltar para retornar à lista.
- gotchas: só entram conversas atribuídas ao time, então atendimento feito pela mesma pessoa fora do time não aparece aqui; o botão de baixar gera o arquivo de todos os times do período; trocar de time pelo filtro do topo substitui toda a tela; ver as conversas de uma barra é restrito a administrador.
- nav_target: `team_reports_show`

### Abrir o desempenho de uma etiqueta por dentro
- intent: Quantas conversas tiveram essa etiqueta no mês?; Reclamações estão crescendo?; Conversas com essa etiqueta demoram mais para resolver?; Quais conversas receberam essa etiqueta naquele dia?
- onde_fica: Relatórios > Etiquetas > clicar no nome da etiqueta
- rota: `label_reports_show` - `/app/accounts/:accountId/reports/labels/:id`
- gate: feature flag `reports`; papel `administrator` ou `report_manage`
- cobre: label_reports
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
- passos: 1. Abra Configurações > Atribuição de Agentes; 2. Leia os cards e decida o que quer ajustar; 3. Clique em Política de atribuição para a ordem do rodízio, em Capacidade do agente para limitar quantas conversas cada pessoa aguenta, ou em Transferir para humano (CRM) para a transferência da IA para uma pessoa.
- gotchas: a tela mostra de um a três cards conforme o que a conta tem liberado; Política de atribuição aparece sempre, Capacidade do agente só com atribuição avançada, e Transferir para humano (CRM) só com o CRM e a IA do CRM ligados; card que sumiu é liberação de recurso, não erro.
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
- onde_fica: Configurações > Transferir para humano (CRM)
- rota: `crm_handoff_settings_index` - `/app/accounts/:accountId/settings/assignment-policy/handoff`
- gate: feature flag `crm`; papel `administrator` ou `crm_manage_ai`
- pre_requisitos: CRM Kanban e IA do CRM ligados, pelo menos um funil criado, e permissão de administrador
- passos: 1. Abra Configurações > Transferir para humano (CRM); 2. Veja na etiqueta de cada funil se está ligado e em qual fluxo; 3. Clique no funil que quer configurar.
- gotchas: aqui nada é configurado, é só a lista de escolha; a etiqueta reflete o padrão do funil, não as personalizações por etapa; com o CRM ou a IA do CRM desligados a plataforma devolve você à tela inicial sem avisar; sem funil criado a lista fica vazia.
- nav_target: `crm_handoff_settings_index`

### Definir quando e para quem a IA passa a conversa
- intent: Como faço a IA chamar um humano no meio do atendimento?; Qual a diferença entre transferir direto e por convite?; O que acontece se ninguém pegar a conversa?; Como coloco uma regra diferente só em uma etapa do funil?; Como escolho quem recebe a conversa?
- onde_fica: Configurações > Transferir para humano (CRM) > nome do funil
- rota: `crm_handoff_settings_edit` - `/app/accounts/:accountId/settings/assignment-policy/handoff/:pipelineId`
- gate: feature flag `crm`; papel `administrator` ou `crm_manage_ai`
- pre_requisitos: um funil com etapas criadas, caixas vinculadas ao funil e agentes cadastrados
- passos: 1. Escolha o funil no seletor do topo; 2. No padrão do funil, ligue a transferência para humano e escreva quando transferir; 3. Escolha direto ou convite e o destino; 4. Defina o tempo de espera e o que fazer se ninguém pegar; 5. Nas personalizações por etapa, deixe em Padrão o que herda e personalize onde a regra é diferente; 6. Salve.
- gotchas: a transferência só acontece de verdade quando o funil está configurado E a caixa de entrada tem atendente como membro: caixa de entrada sem membro deixa a promessa de que alguém vai assumir sem ninguém para atribuir, e nada na tela avisa isso; salvar grava o padrão e todas as etapas de uma vez, inclusive etapa que você deixou pela metade; etapa marcada como Padrão herda e ignora o que estiver preenchido nela; no rodízio a equipe sai da caixa em que a conversa chegou; direto atribui na hora, a IA para de responder e só entrega para quem está online, enquanto convite notifica e a IA continua atendendo até alguém pegar; o tempo de espera padrão é 15 minutos, Avisar de novo avisa até 8 vezes e Escalar exige escolher a pessoa.
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

### Montar e rodar uma busca de leads
- intent: Como acho empresas de um segmento na minha cidade?; Quantos leads uma busca traz?; O que e a jogada da busca?; O que significa o selo de modo no topo?; Para que serve Expandir raio automaticamente?; Por que apareceu que a busca ficou incompleta?; Por que a busca deu erro do Google?
- onde_fica: Barra lateral > Prospeccao > Buscar leads > Nova busca
- rota: `autonomia_prospecting_search` - `/app/accounts/:accountId/autonomia/prospecting/search`
- gate: papel `administrator` ou `prospecting_view` ou `prospecting_manage`
- perfil: montar e rodar busca exige administrador ou funcao com Editar prospeccao; quem tem so Ver prospeccao abre a tela e os resultados, mas nao ve Nova busca nem o tour. Atendente sem funcao nao ve o menu Prospeccao. Se o perfil nao puder, diga que buscar pede Editar prospeccao e que um administrador ajusta a funcao.
- pre_requisitos: Prospeccao ligada na conta pelo suporte; chaves do Google da plataforma configuradas pelo suporte (sem elas a busca no Google fica indisponivel ate o suporte configurar)
- passos: 1. Abra Prospeccao > Buscar leads e clique em Nova busca; 2. Em Onde buscar, escreva o Termo e a Localizacao e escolha uma sugestao ate aparecer Localizacao confirmada; 3. Escolha a Area de busca (Raio, Area visivel ou uma area desenhada) e o Raio (km); 4. Escolha a Forma de pesquisa, Google Meu Negocio ou Geral, e, se quiser, Sua jogada; 5. Defina o Limite, de 1 a 60, e o Tipo de decisor (hoje so Proprietario); 6. Deixe Expandir raio automaticamente como esta ou desmarque; 7. Se quiser, abra Filtros avancados e clique em Aplicar; 8. Clique em Buscar.
- gotchas: uma busca traz no maximo 60 leads, em ate 3 paginas de 20 do Google, e pedir mais e recusado; o botao Buscar so libera com termo, local confirmado e, na area desenhada, a area pronta; as sugestoes de local e a busca seguem o pais da busca da conta, e sem escolha e o Brasil; o selo no topo mostra o modo, Modo: GMN (atacar lacunas) ou Modo: Geral (qualificar leads), da nova busca ou da busca aberta; a jogada e opcional e so preenche os filtros avancados, com tres jogadas prontas por modo, as jogadas salvas da conta e Sem jogada; Expandir raio automaticamente vem ligado e so vale na area Raio: se o raio pedido nao completar o Limite depois dos filtros, tenta uma vez com o dobro do raio, ate 10 km, e so fica com essa tentativa se ela trouxer mais, e a tentativa conta no consumo mesmo quando descartada; no historico o raio aparece como ampliado de X km quando a expansao ficou; os filtros avancados valem antes do corte do Limite, entao a busca le mais posicoes do Google ate achar quem passa; se o Google parar no meio, a tela avisa que a busca ficou incompleta e mostra o que chegou, e buscar de novo tenta completar; busca concluida igual, feita pelo Buscar dentro da validade do cache, devolve o resultado guardado, mas o Repetir do historico sempre chama o Google de novo; cada pagina de resultados do Google conta no consumo, inclusive a da busca que falhou e a do raio maior; erro do Google aparece em portugues com o que fazer, e o erro de local fica abaixo do campo Localizacao; ao terminar, a busca poe na fila o enriquecimento e a pesquisa de empresa e decisor (so com a pesquisa liberada) e a verificacao de WhatsApp (so com sessao de WhatsApp na conta); Refazer tour, no rodape da tela, reabre o tour de 8 passos.
- nav_target: `autonomia_prospecting_search`

### Juntar leads em listas e preparar um publico de campanha
- intent: Como separo leads por praca ou campanha?; Como adiciono leads a uma lista?; Como envio a lista inteira ao CRM?; Como uso a lista numa campanha?; Quantos estao prontos para campanha?; Por que a lista de disponiveis nao mostra todos?
- onde_fica: Barra lateral > Prospeccao > Listas
- rota: `autonomia_prospecting_lists` - `/app/accounts/:accountId/autonomia/prospecting/lists`
- gate: papel `administrator` ou `prospecting_view` ou `prospecting_manage`
- perfil: ver as listas e os leads delas: administrador ou funcao com Ver prospeccao ou Editar prospeccao. Nova Lista, Adicionar leads, Remover e Campanha exigem Editar prospeccao. Enviar lista ao CRM exige tambem a permissao de cards do CRM (Editar na linha CRM da funcao, ou Administrador do CRM). Ligar a uma campanha existente exige tambem Editar campanhas.
- pre_requisitos: ter leads salvos por uma busca
- passos: 1. Abra Prospeccao > Listas e clique em Nova Lista; 2. De o Nome e, se quiser, a Descricao, e clique em Criar lista; 3. Em Adicionar leads, busque, marque ou use Selecionar visiveis e clique em Adicionar selecionados; 4. Abra a lista para ver Leads, Prontos, Contatos e CRM, e abra um lead no mesmo painel da busca; 5. Use Enviar lista ao CRM para mandar os leads; 6. Em Campanha, confira Prontos e Bloqueados, de o Nome do publico, escolha a Campanha existente ou Criar apenas etiqueta e clique em Criar publico.
- gotchas: as listas sao da conta e todos que veem a Prospeccao veem todas; ao entrar na lista, um lead novo ou qualificado fica pronto para campanha; conta como pronto quem esta pronto para campanha e tem WhatsApp verificado; Adicionar leads mostra no maximo os 100 leads mais recentes que voce enxerga, fora os que ja estao na lista, entao use a busca por nome, telefone ou endereco; Enviar lista ao CRM manda os leads visiveis da lista, sem os que ja estao no CRM ou foram descartados; criar o publico so gera a etiqueta do segmento, nada e disparado; na Campanha existente as campanhas de envio unico ativas aparecem primeiro, depois as da WhatsApp API (numero por QR code) agendadas; ligar a lista a uma campanha pede Editar campanhas; fica de fora do publico o descartado, o contato bloqueado, o lead marcado com Nao quer ser contatado, o contato marcado como quem nao quer receber mensagens ativas (de qualquer origem), quem esta sem telefone ou sem WhatsApp verificado e quem nao esta pronto; descartar um lead depois tira a etiqueta do contato, e a campanha da WhatsApp API (numero por QR code) ja em andamento o tira dos destinatarios que ainda esperam envio; descartar nao e recusa: para parar de vez, use Nao quer ser contatado no painel do lead, ou clique em Abrir contato no card do lead e use Marcar que nao quer receber; Remover tira o lead da lista sem apagar o lead nem o contato; nos filtros da lista Aberto agora so tem Sim; a lista nao tem botao de exportar.
- nav_target: `autonomia_prospecting_lists`

### Ajustar funil sugerido, pais da busca, cache e nota da prospeccao
- intent: Onde coloco a chave do Google?; Por que o mapa nao aparece?; Por que o botao Enriquecer esta desligado?; Como mudo o funil sugerido?; Como mudo o peso da nota dos leads?; Como busco em outro pais?; Onde vejo o consumo?; Por que nao consigo editar os pesos?
- onde_fica: Barra lateral > Prospeccao > Configuracoes (ou Barra lateral > Configuracoes > Prospeccao)
- rota: `settings_prospecting_index` - `/app/accounts/:accountId/settings/prospecting`
- gate: papel `administrator` ou `prospecting_manage`
- cobre: autonomia_prospecting_settings
- perfil: administrador ou funcao com Editar prospeccao. Quem tem so Ver prospeccao nao ve o atalho nem abre a tela; diga que ajustar a Prospeccao pede Editar prospeccao.
- pre_requisitos: Prospeccao ligada na conta pelo suporte
- passos: 1. Abra Prospeccao > Configuracoes; 2. Na aba Geral, confira as Chaves do Google, a Pesquisa de empresa e decisor e os avisos; 3. Escolha o Funil CRM padrao e a Etapa CRM padrao; 4. Escolha o Pais da busca; 5. Ajuste a Validade do cache (segundos) e confira o Consumo diario e o Consumo mensal; 6. Clique em Salvar; 7. Na aba Score, escolha a Forma padrao de pesquisa e o Perfil de score e clique em Salvar; 8. Para as jogadas salvas, use a aba Jogadas.
- gotchas: a conta nao cola chave do Google: as chaves sao da plataforma, e quem configura e o suporte; sem elas a busca no Google fica indisponivel ate o suporte configurar; sem a chave de mapa a busca funciona e o mapa nao aparece; a pesquisa de empresa e decisor, que libera Enriquecer e Pesquisar, e ligada pelo suporte, conta a conta; a IA da prospeccao usa so a chave da integracao CRM Kanban AI da conta, e a tela avisa quando ela falta; o funil e a etapa padrao sao o destino sugerido, e cada busca pode ter o proprio em Configuracoes da busca; o pais da busca vale para a conta toda, muda sugestoes de local, resultados do Google e formato dos telefones, e sem escolha e o Brasil; a validade do cache vem em 86400 segundos, um dia, e so vale para busca nova igual pelo Buscar, nunca para o Repetir; o consumo soma as chamadas pagas ao Google, uma por pagina lida, e mostra sem limite porque nao ha teto; qual motor da nota a conta usa e decisao do suporte: no motor antigo os Pesos do perfil so ficam editaveis em Customizado; no motor novo a aba mostra os Componentes da nota (Site, Telefone, Nota no Google, Volume de avaliacoes, Atividade recente e Fotos) so para leitura; Perfil exclusivo desta conta marca perfil restrito a ela; a Forma padrao de pesquisa muda o sentido da nota: no GMN nota alta e lacuna no perfil, no Geral e empresa bem estruturada; a aba Jogadas nao tem Salvar geral; pais fora da lista nao e aceito ao salvar.
- nav_target: `settings_prospecting_index`

### Desenhar a area da busca no mapa
- intent: Como desenho a area da busca no mapa?; Por que veio empresa fora do meu desenho?; Por que o botao Buscar nao libera com a area desenhada?
- onde_fica: Barra lateral > Prospeccao > Buscar leads > Nova busca > Onde buscar > Area de busca
- rota: `autonomia_prospecting_search` - `/app/accounts/:accountId/autonomia/prospecting/search`
- gate: papel `administrator` ou `prospecting_view` ou `prospecting_manage`
- perfil: administrador ou funcao com Editar prospeccao, porque so quem monta busca abre o formulario. Quem tem so Ver prospeccao ve a area das buscas ja feitas no mapa dos resultados, mas nao desenha.
- pre_requisitos: Localizacao confirmada na busca; mapa da plataforma configurado pelo suporte
- passos: 1. Abra Nova busca e confirme a Localizacao; 2. Em Area de busca, escolha Circulo desenhado, Retangulo desenhado ou Poligono desenhado; 3. Clique no mapa para marcar o centro do circulo, criar o retangulo ou marcar cada ponto do poligono; 4. Arraste a borda, os cantos ou os pontos para ajustar e o meio para mover; 5. No poligono, use Desfazer ultimo ponto para corrigir, e Limpar desenho para recomecar; 6. Quando aparecer Area pronta para a busca, clique em Buscar.
- gotchas: o mapa de desenho so abre depois do local confirmado; enquanto a area nao esta pronta aparece Desenhe a area para liberar a busca e o Buscar fica travado; o poligono precisa de pelo menos 3 pontos e aceita ate 100; o raio do circulo vai ate 50 km; so o poligono recorta o resultado: empresa fora dele sai, e lugar sem coordenada tambem; circulo, retangulo, Raio e Area visivel so orientam o Google para aquela regiao, entao pode vir empresa um pouco fora do desenho; se quiser corte exato, desenhe um poligono; Expandir raio automaticamente fica desligado em qualquer area que nao seja Raio, e nunca mexe no desenho; sem a chave de mapa da plataforma o mapa nao carrega e nao da para desenhar.
- nav_target: `autonomia_prospecting_search`

### Usar os filtros avancados e salvar uma jogada
- intent: Onde ficam os filtros avancados?; Por que a jogada desmarcou sozinha?; Como salvo meus filtros como jogada?; Por que nao consigo salvar mais jogadas?; Por que Aberto agora nao tem a opcao Nao?
- onde_fica: Barra lateral > Prospeccao > Buscar leads > Nova busca > Filtros avancados; na busca aberta, o icone Filtros no topo dos resultados
- rota: `autonomia_prospecting_search` - `/app/accounts/:accountId/autonomia/prospecting/search`
- gate: papel `administrator` ou `prospecting_view` ou `prospecting_manage`
- perfil: filtrar a busca nova e Salvar como jogada exigem administrador ou funcao com Editar prospeccao. Quem tem so Ver prospeccao usa o icone Filtros para refinar e ordenar os resultados ja trazidos, sem salvar jogada.
- pre_requisitos: nenhum alem da Prospeccao ligada
- passos: 1. Em Nova busca, escolha a jogada, se quiser, e clique em Filtros avancados; 2. Confira no topo da gaveta a Jogada base e o Modo; 3. Ajuste os quatro grupos: Dor do lead, Qualificacao minima, Visibilidade no Google e Operacional; 4. Clique em Aplicar; 5. Para guardar os filtros, use Salvar como jogada, de o Nome da jogada e clique em Salvar jogada; 6. Na busca aberta, o icone Filtros refina e ordena os leads na tela.
- gotchas: o filtro so vale depois de Aplicar, e fechar a gaveta sem aplicar descarta o rascunho; Limpar tudo aplica os filtros vazios na hora; a Posicao no Google vai de 1 a 40, nas duas pontas; Aberto agora e Tem horario so filtram por Sim; na busca nova os filtros valem antes do corte do Limite; no icone Filtros da busca aberta o refino so esconde leads da tela, nao refaz a busca, e o lead escondido sai da selecao; a jogada desmarca sozinha quando um filtro fica diferente dela, e trocar a Forma de pesquisa tira a jogada de outro modo e os filtros dela; Salvar como jogada fica travado sem pelo menos um filtro; o nome tem ate 60 caracteres e nao pode repetir outra jogada da conta; a conta guarda ate 30 jogadas salvas, e para salvar outra e preciso excluir uma em Configuracoes > Prospeccao > Jogadas; a jogada salva fica no modo em que foi salva e so aparece na grade desse modo.
- nav_target: `autonomia_prospecting_search`

### Repetir, editar e excluir uma busca do historico
- intent: Como repito uma busca?; Como edito uma busca antiga?; Por que nao vejo as buscas do meu colega?; Excluir a busca apaga os leads?; Como troco o funil so de uma busca?
- onde_fica: Barra lateral > Prospeccao > Buscar leads > Buscas recentes
- rota: `autonomia_prospecting_search` - `/app/accounts/:accountId/autonomia/prospecting/search`
- gate: papel `administrator` ou `prospecting_view` ou `prospecting_manage`
- perfil: ver o historico: administrador ou funcao com Ver prospeccao ou Editar prospeccao. Repetir, Editar e buscar, Configuracoes da busca e Excluir busca exigem administrador ou Editar prospeccao. Ver as buscas dos colegas exige ser administrador ou ter Ver buscas de todos na funcao; sem isso a pessoa ve so as proprias.
- pre_requisitos: ter feito pelo menos uma busca
- passos: 1. Abra Prospeccao > Buscar leads e olhe Buscas recentes; 2. Clique numa busca para abrir os resultados, e use Carregar mais para ver as antigas; 3. Use Repetir para rodar a mesma busca de novo na hora; 4. Use Editar e buscar para abrir o formulario preenchido, mudar o que quiser e clicar em Buscar; 5. No icone Configuracoes da busca, escolha o Funil CRM e a Etapa CRM so daquela busca e salve; 6. Use Excluir busca e confirme para tirar do historico.
- gotchas: Repetir sempre chama o Google de novo e conta no consumo, sem usar o cache; Repetir e Editar e buscar restauram termo, local confirmado, area e desenho, raio pedido, expansao, modo, jogada, filtros, limite, decisor e destino no CRM; cada linha mostra leads, contatos, CRM e score da busca; quem nao e administrador ve, exporta, edita e exclui so as proprias buscas, a menos que a funcao tenha Ver buscas de todos; as listas sao da conta e todos veem todas; excluir a busca tira do historico mas nao apaga os leads.
- nav_target: `autonomia_prospecting_search`

### Ler e trabalhar os resultados da busca
- intent: Como priorizo quem ligar primeiro?; O que significam as cores e os sinais do card?; Como ordeno por distancia ou posicao no Google?; Por que o lead esta Enriquecendo?; Por que o WhatsApp mostra Verificando?; O que sao os numeros e grupos de pinos no mapa?; Por que nao vejo a avaliacao do score?; Como marco que o lead nao quer ser contatado?; Como desfaco a recusa do lead?
- onde_fica: Barra lateral > Prospeccao > Buscar leads > abrir uma busca
- rota: `autonomia_prospecting_search` - `/app/accounts/:accountId/autonomia/prospecting/search`
- gate: papel `administrator` ou `prospecting_view` ou `prospecting_manage`
- perfil: ler resultados, ordenar, filtrar, abrir o painel e ver o mapa: administrador ou funcao com Ver prospeccao ou Editar prospeccao. Enriquecer, Nao quer ser contatado e Desfazer: pode ser contatado exigem administrador ou Editar prospeccao, so nos leads que a pessoa enxerga. Avaliacao do score e Fatores de atencao, no painel, so aparecem para o administrador da conta, qualquer que seja a funcao.
- pre_requisitos: uma busca concluida que voce enxerga
- passos: 1. Abra a busca em Buscas recentes; 2. Leia os cards na ordem de Prioridade: o anel, G #, Posicao e Ligar 1o; 3. Use o icone Filtros para trocar o campo em Ordenar e inverter a ordem; 4. Clique num pino do mapa ou no card para abrir o painel do lead; 5. No card, use Mapa, Detalhes, WhatsApp, Ligar e os links das redes; 6. Clique em Enriquecer num lead com site para buscar mais dados; 7. Se a pessoa pediu para nao receber mensagens, clique em Nao quer ser contatado no rodape do painel e confirme em Marcar recusa.
- gotchas: Nao quer ser contatado grava a recusa (origem Prospeccao) no contato do lead e nos contatos com o mesmo telefone ou e-mail, e campanhas e retornos automaticos deixam de enviar para eles; o lead ganha o selo Nao quer ser contatado no card e no topo do painel, inclusive se for descartado depois; Desfazer: pode ser contatado, confirmado em Desfazer recusa, tira a recusa dos contatos so quando nada mais a sustenta: se outro lead recusado alcanca o contato a marca fica, e se houver descadastro de e-mail ou marcacao manual a recusa continua com essa origem; o lead recusado que ganha telefone ou e-mail novo, pelo enriquecimento ou por busca refeita, marca tambem o contato desse numero ou e-mail; a faixa de cor do card segue a prioridade: 75 ou mais e Lead muito quente, 50 ou mais Oportunidade alta, 25 ou mais Lead morno e abaixo disso Prioridade baixa; Ligar 1o marca a posicao 1; o card mostra ate 4 sinais, como Tem site ou Sem site, fotos, posicao no Google, nota e avaliacoes; nota alta e oportunidade no modo GMN e ponto positivo no Geral; o numero do pino e a posicao do lead na busca, e com varios pinos proximos eles se agrupam; Distancia do centro so aparece quando a busca tem centro; ao trocar o campo de ordenar, a ordem volta a mostrar o melhor primeiro; o telefone vem no formato internacional e prefere o WhatsApp verificado, com o selo verificado; Verificando aparece enquanto a conta confere o numero pela sessao de WhatsApp dela; a verificacao precisa de um numero conectado por QR code (WhatsApp API) na conta, e sem ele nenhum lead fica verificado e a campanha fica sem quem incluir; so o selo verificado confirma o numero, o botao WhatsApp aparece mesmo sem verificacao; Enriquecer entra na fila e o card se atualiza sozinho, e pedir de novo com o lead na fila e recusado; Enriquecer fica desligado sem a pesquisa liberada pelo suporte ou sem site; sem a chave da integracao CRM Kanban AI a tela avisa e o enriquecimento traz so o que esta no site; enriquecimento parado volta a falha depois de 15 minutos rodando ou 2 horas na fila; para quem nao e administrador o painel mostra a prioridade e a frase da nota, sem os componentes; sem a chave de mapa da plataforma aparece que o mapa ainda nao esta disponivel, e o resto funciona.
- nav_target: `autonomia_prospecting_search`

### Pesquisar a empresa e o decisor de um lead
- intent: Como descubro o dono da empresa?; O que significa Aguardando capacidade?; Por que o decisor nao foi encontrado?; Como refaco a pesquisa?; O que e resultado reutilizado?; Como uso um socio como contato?
- onde_fica: Barra lateral > Prospeccao > Buscar leads > abrir uma busca > abrir o lead > Empresa e decisor
- rota: `autonomia_prospecting_search` - `/app/accounts/:accountId/autonomia/prospecting/search`
- gate: papel `administrator` ou `prospecting_view` ou `prospecting_manage`
- perfil: ver os selos, a barra de progresso e o painel Empresa e decisor: administrador ou funcao com Ver prospeccao ou Editar prospeccao. Pesquisar, Verificar novamente e Usar como contato exigem administrador ou Editar prospeccao.
- pre_requisitos: pesquisa de empresa e decisor liberada para a conta pelo suporte (confira em Configuracoes > Prospeccao > Geral)
- passos: 1. Abra a busca e acompanhe a barra X de Y concluidos; 2. Leia no card os selos Empresa e Decisor; 3. Clique no card para abrir o painel e desca ate Empresa e decisor; 4. Em Quem atende, veja os socios e a qualificacao de cada um; 5. Em Empresa, confira razao social, nome fantasia, CNPJ, situacao e UF; 6. Use Pesquisar, ou Verificar novamente e confirme em Refazer pesquisa; 7. Para trocar o decisor, clique em Usar como contato no socio certo.
- gotchas: com a pesquisa liberada, ao terminar a busca cada lead nunca pesquisado entra sozinho na fila; os estados sao Nao pesquisado, Na fila, Em pesquisa, Aguardando capacidade, Confirmado, Possivel, Ambiguo, Nenhum resultado, Falha tecnica e Bloqueado; Aguardando capacidade quer dizer que outra pesquisa da mesma empresa esta rodando, e a retomada e automatica; pesquisa parada volta a falha depois de 15 minutos em pesquisa ou 2 horas na fila ou aguardando; o mesmo lugar pesquisado ha menos de 90 dias e reaproveitado, sem nova consulta paga, e o painel mostra resultado reutilizado; Verificar novamente pesquisa de novo sem o resultado guardado, e o atual fica na tela ate o novo chegar; hoje so o tipo de decisor Proprietario tem pesquisa; quando nao ha decisor o painel diz o motivo, como empresa nao encontrada, mais de uma empresa possivel, sem quadro de socios, socios que sao empresas ou orgao publico; empresa com situacao irregular na Receita ganha alerta; Usar como contato torna o socio decisor e contato do lead, mas o contato do CRM nao muda quando e compartilhado com outro negocio ou ja existia com outro nome; com a pesquisa desligada o painel avisa e os botoes ficam travados, e o lead pode aparecer como Bloqueado.
- nav_target: `autonomia_prospecting_search`

### Enviar leads da prospeccao ao CRM
- intent: Como mando leads para o CRM?; Por que alguns leads ficaram de fora do envio?; Por que nao aparece Enviar ao CRM?; O que o card do CRM leva do lead?; O envio roda a automacao do estagio?
- onde_fica: Barra lateral > Prospeccao > Buscar leads > abrir uma busca > selecionar leads > Enviar ao CRM (tambem no card, no painel do lead e em Listas > Enviar lista ao CRM)
- rota: `autonomia_prospecting_search` - `/app/accounts/:accountId/autonomia/prospecting/search`
- gate: papel `administrator` ou `prospecting_view` ou `prospecting_manage`
- perfil: exige as duas permissoes: administrador ou Editar prospeccao, e a permissao de cards do CRM (Editar na linha CRM ou Administrador do CRM na funcao). Sem qualquer uma delas o botao nao aparece; diga para pedir ao administrador que ajuste a funcao.
- pre_requisitos: CRM ligado na conta e pelo menos um funil ativo com estagio
- passos: 1. Abra a busca e marque os leads, ou use Selecionar visiveis; 2. Clique em Enviar ao CRM na barra de selecao; 3. Escolha o Funil e o Estagio; 4. Confira a frase de confirmacao e clique em Enviar; 5. Leia o resumo com criados, ja existentes e falhas; 6. No card do lead enviado, use Abrir card ou Abrir contato.
- gotchas: lead que ja esta no CRM ou foi descartado fica fora do envio, e a barra avisa quantos; o card mostra a faixa Ja esta no CRM com funil, estagio e responsavel, ou sem responsavel; o envio vai em lotes de 30 e mostra o andamento; reenviar lead com card nao cria outro; o lead enviado sai da selecao e o que falhou continua selecionado para tentar de novo; o card nasce com empresa e contato, na prioridade da faixa do lead e com a linha do decisor na descricao; a automacao de entrada do estagio roda uma vez, so para o card criado agora; sem funil aparece Nenhum funil no CRM com o atalho Criar funil no CRM; se o CRM estiver desligado a tela nao carrega os funis; lead descartado so vai ao CRM depois de Desfazer descarte.
- nav_target: `autonomia_prospecting_search`

### Colocar leads da busca numa campanha
- intent: Como coloco leads da busca numa campanha?; Por que alguns leads ficaram de fora da campanha?; Por que nao consigo escolher a campanha?; Lead descartado ainda recebe a campanha?; Como paro de vez a campanha para um lead?
- onde_fica: Barra lateral > Prospeccao > Buscar leads > abrir uma busca > selecionar leads > Adicionar a campanha
- rota: `autonomia_prospecting_search` - `/app/accounts/:accountId/autonomia/prospecting/search`
- gate: papel `administrator` ou `prospecting_view` ou `prospecting_manage`
- perfil: Adicionar a campanha e So criar o segmento exigem administrador ou Editar prospeccao. Escolher uma campanha existente exige tambem Editar campanhas na funcao; sem ela o campo Campanha nao aparece e da para criar so o segmento.
- pre_requisitos: leads prontos para campanha com WhatsApp verificado; para ligar a uma campanha, uma campanha da WhatsApp API (numero por QR code) agendada ou uma de envio unico ativa
- passos: 1. Selecione os leads na busca; 2. Clique em Adicionar a campanha; 3. Em Campanha, escolha uma campanha ou So criar o segmento, sem campanha; 4. Confira o Nome do segmento, que vem com o termo da busca; 5. Clique em Adicionar; 6. Leia o resumo: quem entrou, a campanha, os contatos criados e quem ficou de fora, com o motivo.
- gotchas: nada e enviado aqui, a selecao vira uma lista e uma etiqueta de segmento nos contatos, e a campanha le essa etiqueta quando envia; entram so leads prontos para campanha, com telefone e WhatsApp verificado, sem bloqueio no contato e sem recusa de mensagens ativas no lead ou no contato; ficam de fora, com o motivo no resumo, descartado, contato bloqueado, Pediu para nao receber mensagens (inclui o lead marcado com Nao quer ser contatado e o contato marcado como quem nao quer receber mensagens ativas), sem telefone, sem WhatsApp verificado e ainda nao pronto; as campanhas de envio unico ativas aparecem primeiro, depois as da WhatsApp API (numero por QR code) agendadas; vao ate 500 leads por vez; nome de segmento igual a etiqueta que ja existe e recusado; descartar um lead depois tira a etiqueta do contato dele, e campanha agendada ou de envio unico que ainda nao foi enviada deixa de alcanca-lo; a campanha da WhatsApp API (numero por QR code) que ja comecou tira o descartado dos destinatarios que ainda esperam envio e o conta em Descartados na Prospeccao; descartar nao e recusa: para parar de vez, use Nao quer ser contatado no painel do lead, ou clique em Abrir contato no card do lead e use Marcar que nao quer receber.
- nav_target: `autonomia_prospecting_search`

### Descartar leads, desfazer o descarte e criar contatos em lote
- intent: Como descarto um lead?; Como desfaco um descarte?; Como crio contatos de varios leads de uma vez?
- onde_fica: Barra lateral > Prospeccao > Buscar leads > abrir uma busca > selecionar leads > Descartar ou Criar contatos; Desfazer descarte fica no painel do lead
- rota: `autonomia_prospecting_search` - `/app/accounts/:accountId/autonomia/prospecting/search`
- gate: papel `administrator` ou `prospecting_view` ou `prospecting_manage`
- perfil: Descartar, Desfazer descarte e Criar contatos exigem administrador ou funcao com Editar prospeccao. Quem tem so Ver prospeccao ve o lead descartado e o motivo, sem os botoes.
- pre_requisitos: uma busca com leads que voce enxerga
- passos: 1. Selecione os leads; 2. Para descartar, clique em Descartar, escolha o Motivo e confirme em Descartar; 3. Para desfazer, abra o lead descartado e clique em Desfazer descarte; 4. Para criar contatos, selecione os leads e clique em Criar contatos; 5. Leia o resumo de criados, ja existentes e falhas.
- gotchas: os motivos sao Sem interesse, Fora do perfil, Ja e cliente, Dados errados, Empresa fechada e Outro motivo, que pede o texto; da para descartar ate 500 leads por vez; o descartado continua na busca, esmaecido e com a faixa Descartado e o motivo; ele sai do envio ao CRM, dos contatos em lote e da campanha, e o contato perde a etiqueta de segmento que ja tinha; Desfazer descarte so existe no painel do lead e devolve o lead a Novo; Criar contatos vai em lotes de 30 e pula os descartados; nao existe criar contato de um lead so no card: o contato tambem nasce ao Enviar ao CRM e em Usar como contato; na campanha da WhatsApp API (numero por QR code) em andamento ou pausada, o descartado sai dos destinatarios que ainda esperam envio, a menos que o contato continue no publico por outra etiqueta, e o que ja foi enviado fica; a tela de campanhas mostra Descartados na Prospeccao com a contagem, ao lado de Recusaram mensagens ativas, e a campanha nao termina com falhas por isso; descartar nao grava nem desfaz a recusa: o selo Nao quer ser contatado continua no lead descartado; se a pessoa pediu para nao receber, use Nao quer ser contatado no painel do lead.
- nav_target: `autonomia_prospecting_search`

### Exportar os leads da busca em CSV ou Excel
- intent: Como exporto os leads para planilha?; Da para baixar em Excel?; Por que o arquivo veio com menos leads?
- onde_fica: Barra lateral > Prospeccao > Buscar leads > abrir uma busca > icone Exportar leads no topo dos resultados
- rota: `autonomia_prospecting_search` - `/app/accounts/:accountId/autonomia/prospecting/search`
- gate: papel `administrator` ou `prospecting_view` ou `prospecting_manage`
- perfil: administrador ou funcao com Ver prospeccao ou Editar prospeccao, so nas buscas que a pessoa enxerga (as proprias, ou todas com Ver buscas de todos).
- pre_requisitos: uma busca aberta com pelo menos um lead na tela
- passos: 1. Abra a busca; 2. Se quiser so alguns, selecione os leads; 3. Clique no icone Exportar leads; 4. Escolha CSV ou Excel (.xlsx); 5. Abra o arquivo baixado.
- gotchas: com leads selecionados o arquivo leva so eles; sem selecao leva os visiveis, entao o refino do icone Filtros reduz o arquivo; o arquivo segue a ordem da tela (na ordem padrao, a de prioridade); o botao fica travado sem leads na tela; as Listas nao tem botao de exportar; o arquivo sai com o numero da busca no nome.
- nav_target: `autonomia_prospecting_search`

### Editar e excluir as jogadas salvas
- intent: Onde edito ou apago uma jogada salva?; Quantas jogadas posso salvar?
- onde_fica: Barra lateral > Prospeccao > Configuracoes > aba Jogadas
- rota: `settings_prospecting_index` - `/app/accounts/:accountId/settings/prospecting`
- gate: papel `administrator` ou `prospecting_manage`
- perfil: administrador ou funcao com Editar prospeccao. Quem tem so Ver prospeccao ve as jogadas salvas na grade da busca, mas nao edita nem exclui.
- pre_requisitos: ter salvo pelo menos uma jogada na busca, em Filtros avancados > Salvar como jogada
- passos: 1. Abra Prospeccao > Configuracoes; 2. Entre na aba Jogadas; 3. Para mudar, clique em Editar, ajuste o Nome da jogada e os filtros e clique em Salvar jogada; 4. Para apagar, clique em Excluir e depois em Confirmar exclusao.
- gotchas: a conta guarda ate 30 jogadas salvas, e o teto so aparece como recusa ao tentar salvar mais uma na busca; excluir uma jogada libera a vaga; o nome tem ate 60 caracteres e nao pode repetir; cada jogada fica no modo em que foi salva, que a tela mostra, e so aparece na grade desse modo; as jogadas sao da conta, entao a mudanca vale para todos; jogada nova so nasce na busca, pelo Salvar como jogada; a aba nao tem Salvar geral: cada jogada se salva no proprio Editar jogada.
- nav_target: `settings_prospecting_index`

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
- intent: Onde edito os dados de um cliente?; Como vejo todas as conversas que já tive com esta pessoa?; Como junto dois cadastros do mesmo cliente?; Onde bloqueio um contato?; Onde anoto informações sobre o cliente?; Como marco que o contato não quer receber campanha?; Como desfaço a recusa de mensagens ativas?
- onde_fica: Contatos > clicar no contato
- rota: `contacts_edit` - `/app/accounts/:accountId/contacts/:contactId`
- gate: feature flag `crm`; papel `administrator` ou `agent` ou `contact_manage` ou `contact_view`
- cobre: contacts_edit_segment, contacts_edit_label
- pre_requisitos: contato já cadastrado
- passos: 1. Abra Contatos e clique no contato; 2. Ajuste os dados à esquerda e salve; 3. Use as abas de atributos, histórico, notas, mídia e mesclar; 4. Em histórico, veja as conversas anteriores; 5. Em notas, registre o que a equipe precisa saber; 6. Para juntar cadastros repetidos, abra mesclar, escolha o contato principal e confirme.
- gotchas: ao mesclar, o contato principal é o que sobrevive e o outro é excluído, com os dados do principal prevalecendo em caso de conflito, e não há desfazer; excluir contato é permanente; bloquear não apaga o contato, só impede novo contato; e-mail ou telefone repetido é recusado por já pertencer a outro cadastro; abrindo a ficha a partir de um segmento ou de uma etiqueta, a tela é a mesma e o voltar devolve para aquela lista; em Mensagens ativas, abaixo de Atualizar contato, Marcar que não quer receber tira o contato das campanhas e dos follow-ups automáticos, inclusive de campanha já em andamento, e responder a quem escreve segue normal, o que é diferente de bloquear; Desfazer recusa só aparece na recusa Marcado pela equipe; a recusa de origem Prospecção vem do botão Não quer ser contatado no painel do lead e só sai lá, pelo Desfazer: pode ser contatado; a do descadastro de e-mail não se desfaz pela ficha; ao mesclar dois contatos que recusaram, fica a recusa mais firme: a manual, depois a do descadastro de e-mail, depois a da Prospecção; contato novo ou que troca telefone ou e-mail herda sozinho a recusa de e-mail descadastrado ou de lead marcado com Não quer ser contatado.
- nav_target: `contacts_edit`

### Cadastrar empresas e achar a que você procura
- intent: Onde cadastro uma empresa?; Como agrupo os contatos de uma mesma empresa?; Onde busco uma empresa pelo nome ou domínio?; Por que não vejo Empresas no menu?
- onde_fica: Empresas
- rota: `companies_dashboard_index` - `/app/accounts/:accountId/companies`
- gate: feature flag `companies`; papel `administrator` ou `agent` ou `contact_view` ou `contact_manage`
- pre_requisitos: recurso de Empresas liberado na conta
- passos: 1. Abra Empresas; 2. Busque pelo nome ou domínio; 3. Ajuste a ordenação; 4. Clique em adicionar empresa e preencha os dados; 5. Ao salvar, a plataforma abre a ficha da empresa criada.
- gotchas: Empresas é liberado por conta, então pode simplesmente não aparecer no menu; criar a empresa não vincula contato nenhum, o vínculo é feito dentro da ficha ou pelo campo empresa do contato; busca e ordenação ficam no endereço da página, então dá para compartilhar o link já filtrado.
- nav_target: `companies_dashboard_index`

### Consultar cadastros sem alterar os dados compartilhados
- intent: Por que não aparece Editar contato?; Posso criar oportunidade sem editar a pessoa?; Por que Criar novo está indisponível no CRM?
- onde_fica: Relacionamentos > ficha do contato ou empresa; CRM > card > Relacionamento; Conversas > painel do contato
- rota: `contacts_edit` - `/app/accounts/:accountId/contacts/:contactId`
- gate: feature flag `crm`; papel `administrator` ou `agent` ou `contact_manage` ou `contact_view`
- pre_requisitos: acesso ao cadastro; permissões de Relacionamentos e do CRM são independentes
- passos: 1. Abra o contato ou a empresa para consultar dados, atributos e histórico; 2. Se a ficha indicar somente consulta, use as informações sem alterar o cadastro; 3. Com permissão de gerenciar oportunidades, use um contato existente ou continue sem vínculo; 4. Para criar ou editar pessoa e empresa, solicite ao administrador a permissão de gerenciar contatos.
- gotchas: gerenciar oportunidades não concede edição dos cadastros compartilhados. Sem edição, ficam protegidos também notas, etiquetas, avatar e vínculo com empresa, inclusive na lateral do atendimento. Atender conversas não concede criar oportunidades; consultar o CRM não permite arquivar ou criar/concluir/cancelar retornos. Reiniciar a cadência exige gerenciar a IA, enquanto o bloqueio de retorno no contato exige gerenciar cadastros. Valores de atributos não são o mesmo que suas definições e configuração. Permissões de envio de mensagem e exclusão seguem controles próprios. A quantidade de oportunidades não é limitada por este modo: a lista segue os filtros e a visibilidade do CRM, com paginação.
- nav_target: `contacts_edit`

### Consultar oportunidades dos contatos de uma empresa
- intent: Quais negociações esta empresa tem?; Como vejo as oportunidades de todos os contatos da empresa?
- onde_fica: Relacionamentos > Empresas > abrir empresa > Acompanhamento > Oportunidades
- rota: `companies_dashboard_show` - `/app/accounts/:accountId/companies/:companyId`
- gate: feature flag `companies`; papel `administrator` ou `agent` ou `contact_view` ou `contact_manage`
- pre_requisitos: Empresas, Relacionamentos e CRM habilitados; acesso à empresa e permissão de visualizar CRM. As oportunidades respeitam a visibilidade individual do usuário.
- passos: Abra **Oportunidades** no painel da empresa. Cada item mostra a negociação, o contato vinculado, funil, etapa, situação e valor. Busque pelo título, ajuste **Situação** e use **Próxima** para mais resultados. Clique para abrir a mesma oportunidade no CRM em outra aba; a ficha original permanece aberta.
- gotchas: os contatos considerados são os vinculados atualmente à empresa, inclusive os que não aparecem na primeira página de Contatos. Nome de empresa igual ou nome legado não cria associação. Ao trocar/desvincular um contato, suas oportunidades deixam de aparecer na empresa anterior na próxima consulta, sem apagar as negociações. Contatos continua sendo a aba inicial. Por padrão, arquivadas ficam fora. O total inclui somente os resultados permitidos. Moedas não são somadas nem convertidas; a consulta não altera cadastros.
- nav_target: `companies_dashboard_show`

### Ver a empresa por dentro e vincular os contatos dela
- intent: Como vinculo um contato a uma empresa?; Onde vejo as conversas dos contatos de uma empresa?; Como tiro um contato de uma empresa?; O que acontece com os contatos se eu excluir a empresa?
- onde_fica: Empresas > clicar na empresa
- rota: `companies_dashboard_show` - `/app/accounts/:accountId/companies/:companyId`
- gate: feature flag `companies`; papel `administrator` ou `agent` ou `contact_view` ou `contact_manage`
- pre_requisitos: empresa cadastrada e contatos existentes para vincular
- passos: 1. Abra Empresas e clique na empresa; 2. Ajuste nome, domínio, descrição e avatar e atualize; 3. Use as abas de histórico, notas e contatos; 4. Em contatos, adicione pesquisando e confirmando o vínculo; 5. Use remover para desvincular.
- gotchas: vincular um contato que já pertence a outra empresa é reatribuição, não cópia, e a tela avisa a qual empresa ele está ligado hoje; histórico e notas vêm dos contatos vinculados, então empresa sem contato aparece vazia; excluir a empresa é irreversível e desvincula todos os contatos, mas os contatos continuam na conta.
- nav_target: `companies_dashboard_show`

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
- onde_fica: Configurações > Modelos (a mesma tela também fica em Campanhas > Modelos WhatsApp)
- rota: `settings_templates` - `/app/accounts/:accountId/settings/templates`
- gate: papel `administrator`
- pre_requisitos: pelo menos uma caixa de WhatsApp conectada, e os modelos já existindo no provedor
- passos: 1. Abra Configurações > Modelos; 2. Sincronize os modelos; 3. Filtre por caixa, idioma e tipo; 4. Busque pelo nome ou pelo texto; 5. Abra o modelo para ver status, categoria e caixas.
- gotchas: esta tela só exibe, porque criar e editar modelo é sempre no provedor, e não há botão de criar aqui; sincronizar fica desligado sem nenhuma caixa de WhatsApp; a sincronização leva alguns minutos e a tela mostra a hora da última tentativa; respondendo só parte das caixas, aparece aviso de sincronização parcial e a lista fica incompleta; modelo ainda não enviado para aprovação não serve para campanha.
- nav_target: `settings_templates`

### Ver os modelos do WhatsApp pela área de Campanhas
- intent: Onde vejo os modelos antes de montar uma campanha do WhatsApp?; Quais modelos posso usar na campanha do WhatsApp Oficial?; Onde ficam os modelos do WhatsApp em Campanhas?
- onde_fica: Sidebar > Campanhas > Modelos WhatsApp, logo antes de WhatsApp Oficial
- rota: `campaigns_templates_index` - `/app/accounts/:accountId/campaigns/templates`
- gate: feature flag `campaigns`; papel `administrator`
- pre_requisitos: pelo menos uma caixa de WhatsApp conectada, e os modelos já existindo no provedor
- passos: 1. Abra Campanhas > Modelos WhatsApp; 2. Sincronize os modelos; 3. Filtre por caixa, idioma e tipo; 4. Confira que o modelo que vai usar está aprovado; 5. Siga para Campanhas > WhatsApp Oficial para montar a campanha.
- gotchas: é a mesma tela de Configurações > Modelos, só com outro caminho no menu; por enquanto só administrador vê; só exibe e sincroniza, porque criar e editar modelo é sempre no provedor; os modelos das campanhas de e-mail são outra coisa e ficam dentro de cada campanha de e-mail.
- nav_target: `campaigns_templates_index`

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
- onde_fica: Campanhas > E-mails > Biblioteca de modelos
- rota: `campaigns_email_templates` - `/app/accounts/:accountId/campaigns/email_campaigns/:campaignId?/templates`
- gate: feature flag `campaigns`; papel `administrator` ou `campaign_view` ou `campaign_manage`
- pre_requisitos: campanhas de e-mail liberadas na conta e permissão de gerenciar campanhas para aplicar modelos
- passos: 1. Abra Campanhas > E-mails; 2. Abra Biblioteca de modelos; 3. Escolha Modelos prontos ou Meus modelos, busque e filtre por objetivo; 4. Abra Prévia no computador ou celular; 5. Use o modelo na campanha atual ou preencha o remetente para criar uma nova; 6. Ajuste textos, imagens e links antes de enviar.
- gotchas: usar o modelo substitui o conteúdo atual da campanha, então quem já escreveu perde o que estava lá; sem permissão de gerenciar campanhas sobra só a pré-visualização; as miniaturas carregam conforme você rola; se o modelo não tiver conteúdo editável, a tela avisa e nada é aplicado.
- nav_target: `campaigns_email_templates`

### Trazer um modelo de e-mail de outra plataforma
- intent: Como trago um e-mail que fiz em outra plataforma?; Posso importar meu modelo de e-mail?; Como colo o código do meu e-mail aqui?; Dá para enviar o arquivo .html ou .zip do e-mail?; Por que a imagem do meu modelo não veio?; O que faço com um campo que não existe aqui?; Por que não consigo salvar o modelo trazido?; Como refaço com IA um pedaço que ficou como imagem?
- onde_fica: Campanhas > E-mails > Biblioteca de modelos > Trazer meu modelo (também no meio de Meus modelos quando está vazio)
- rota: `campaigns_email_template_import` - `/app/accounts/:accountId/campaigns/email_campaigns/templates/import/:importId?`
- gate: feature flag `email_template_import`; papel `administrator` ou `campaign_manage`
- pre_requisitos: recurso de trazer modelo ligado na conta (email_template_import) e permissão de gerenciar campanhas (campaign_manage)
- passos: 1. Abra a Biblioteca de modelos e clique em Trazer meu modelo; 2. Escolha Enviar arquivo (.html, ou .zip com as imagens), Colar o código ou Usar o endereço da página do e-mail; 3. Clique em Trazer este modelo e espere as três frases terminarem; 4. Compare Como era e Como ficou, no computador ou no celular, e leia o que mudou; 5. Resolva cada aviso amarelo pelo botão dele (Trocar imagem, Resolver, Escolher); 6. Clique em Está bom, continuar, confirme o nome e clique em Salvar em Meus modelos; 7. O modelo aparece primeiro em Meus modelos, marcado Novo, pronto para Usar modelo.
- gotchas: nada é salvo antes de Salvar em Meus modelos; imagem que não veio, campo que não existe aqui e pedaço que ficou como imagem impedem salvar até serem resolvidos (trocar ou tirar a imagem; trocar o campo por um da conta, por um texto igual para todos, ou apagar; refazer o pedaço com IA, deixar só o texto do pedaço ou tirar o pedaço); Refazer para editar (em Resolver) pede à IA para remontar só aquele pedaço em blocos editáveis, sem mudar o texto, e leva alguns segundos — se o texto não bater com o original, o pedaço continua como imagem e aparece Não deu para refazer; cada pedaço vai para a IA uma vez, até 5 pedaços por modelo e um limite por mês na conta; sem a IA ligada na conta, o botão fica apagado com Refazer com IA chega em breve; pedaço que a IA não consegue refazer (grande demais) deixa o botão apagado com A IA não consegue refazer este pedaço, sem gastar o limite; o rodapé antigo sai e entra o rodapé da conta com o link para sair da lista; contadores de abertura, códigos e textos escondidos saem; o endereço precisa começar com https://; colar aceita até 500 KB, .html até 500 KB e .zip até 2 MB; uma importação por vez na conta e até 10 a cada 10 minutos; dá para sair durante a preparação e voltar por Meus modelos, que mostra Ver como ficou; use só e-mails que são seus ou que você pode usar.
- nav_target: `campaigns_email_template_import`

### Ver o resultado de uma campanha de WhatsApp
- intent: Quantas pessoas receberam a campanha?; Quantos leram a mensagem?; Por que alguns contatos foram ignorados?; A campanha já terminou de enviar?; Como vejo contato por contato o que aconteceu?
- onde_fica: Campanhas > WhatsApp Oficial > Ver análises
- rota: `campaigns_whatsapp_analytics` - `/app/accounts/:accountId/campaigns/whatsapp/:campaignId/analytics`
- gate: feature flag `whatsapp_campaign`; papel `administrator` ou `campaign_view` ou `campaign_manage`
- pre_requisitos: uma campanha de WhatsApp Oficial já enviada ou em envio
- passos: 1. Abra Campanhas > WhatsApp Oficial; 2. Clique em ver análises; 3. Leia os números de público, enviadas, entregues, lidas, falhas e ignoradas; 4. Use as abas de status para filtrar; 5. Navegue pela lista para ver contato por contato.
- gotchas: entregues já inclui as lidas, então somar os dois conta o mesmo contato duas vezes; enviadas quer dizer aceita para entrega, não entregue no celular; ignoradas são contatos descartados antes do envio, quase sempre telefone ausente ou inválido, e é o número que vale olhar para limpar a base; campanhas enviadas antes desta tela existir aparecem sem dado, e isso não é erro; contato marcado como quem não quer receber mensagens ativas aparece em ignoradas com o motivo Contato não quer receber mensagens ativas.
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

### Abrir Relacionamentos
- intent: Onde ficam contatos e empresas?; Como configuro campos personalizados?; Onde estão os segmentos?
- onde_fica: Menu lateral > Relacionamentos, quando a nova navegação está habilitada na conta
- rota: `relationships_home` - `/app/accounts/:accountId/relationships`
- gate: feature flag `relationships_navigation`; papel `administrator` ou `agent` ou `contact_view` ou `contact_manage` ou `attribute_manage`
- pre_requisitos: nova navegação de Relacionamentos habilitada; cada destino mantém suas permissões e recursos
- passos: 1. Abra Relacionamentos; 2. Escolha Contatos, Empresas ou Atributos personalizados; 3. Em Contatos, use o seletor de visão para Todos, Ativos, Segmentos ou Etiquetas; 4. Use o link Relacionamentos para voltar à home.
- gotchas: os endereços antigos continuam funcionando; a home não concede acesso adicional; atributos de Conversa continuam na Central; navegação, campos e mídias são habilitações independentes.
- nav_target: `relationships_home`

### Consultar mídias da empresa
- intent: Onde vejo arquivos de uma empresa?; Como busco mídia pelo nome?; Como vejo a conversa de origem do arquivo?
- onde_fica: Empresas > ficha da empresa > Mídias > Visualizar tudo
- rota: `relationships_company_media` - `/app/accounts/:accountId/companies/:companyId/media`
- gate: feature flag `relationships_company_media`; papel `administrator` ou `agent`
- pre_requisitos: Empresas e mídias de Relacionamentos habilitadas na conta; acesso às conversas de origem
- passos: 1. Abra Mídias na lateral da empresa; 2. Busque pelo nome e combine contato, tipo e período; 3. Abra Visualizar tudo para a tabela; 4. Agrupe por contato e navegue nas páginas; 5. Use Visualizar, Baixar original ou Ir à mensagem.
- gotchas: considera o vínculo atual do contato com a empresa; mudar esse vínculo move a visualização do histórico permitido; ocorrências repetidas continuam separadas; previews são gerados sob demanda e podem ficar indisponíveis sem impedir o original; a lateral mostra cinco recentes; o catálogo cobre arquivos armazenados, incluindo notas autorizadas, e anexos externos ficam na conversa de origem; o período usa o fuso de relatórios da conta, UTC quando não configurado.
- nav_target: `relationships_company_media`
