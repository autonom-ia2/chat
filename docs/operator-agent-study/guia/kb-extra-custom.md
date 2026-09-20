# Guia Autonom.ia - KB extra custom

> **Registro histórico — desenho da V1, read-only.** Este documento descreve o Guia
> como ele foi desenhado em junho de 2026: só leitura, sem consultar os dados da conta
> e sem executar nada. Esse desenho foi substituído pelas issues #533 (o Guia consulta
> o que a conta tem, com a permissão de quem pergunta) e #536 (o Guia executa ações,
> sempre com confirmação na tela). Fica como registro de decisão — não leia como
> descrição do comportamento atual.


Complemento da base custom do Guia Autonom.ia para lacunas de CRM, IA, calendario, booking e integracoes. Conteudo para RAG interno; nao e logica de produto.

Base de URL: as rotas do frontend usam `frontendURL(...)`, portanto os paths abaixo ja consideram o prefixo `/app`.

## Route names custom usados

- `crm_kanban_index` - `/app/accounts/:accountId/crm`
- `crm_calendar_index` - `/app/accounts/:accountId/crm/calendar`
- `crm_integration_tokens_index` - `/app/accounts/:accountId/crm/settings/integration-tokens`
- `settings_integrations_crm_n8n` - `/app/accounts/:accountId/settings/integrations/crm_n8n`
- `public_booking_page` (Rails) - `/book/:slug`

## Route names auxiliares usados

- `settings_inboxes_page_channel` - `/app/accounts/:accountId/settings/inboxes/new/:sub_page`
- `settings_inbox_show` - `/app/accounts/:accountId/settings/inboxes/:inboxId/:tab?`
- `settings_integrations_webhook` - `/app/accounts/:accountId/settings/integrations/webhook`

## Fluxos

### Configurar IA do CRM por funil
- intent: "Como ligo a IA de um funil?"; "Onde configuro auto follow-up do CRM?"; "Como a IA decide mover cards de etapa?"; "Como ativo deteccao de callback?"
- onde_fica: Sidebar > CRM > CRM Kanban > selecionar funil > Editar funil > IA do funil
- rota: `crm_kanban_index` - `/app/accounts/:accountId/crm`
- perfil: `administrator`, `agent` sem custom role, ou custom role com `crm_manage_ai`/`crm_admin`; se o perfil nao puder, diga que ele pode visualizar o CRM quando tiver acesso, mas precisa de permissao de IA do CRM para alterar essas configuracoes.
- gate: `CRM_KANBAN_ENABLED=true`; `CRM_AI_ENABLED=true`; callback tambem respeita `AI_CALLBACK_DETECTION` (default ligado); backend bloqueia com `crm.ai.disabled` quando a IA esta desligada.
- pre_requisitos: funil ja criado; etapas do funil definidas; para auto-move, criterios de IA por etapa bem descritos.
- passos: 1. Abra CRM Kanban; 2. Selecione o funil; 3. Clique em Editar funil; 4. No bloco IA do funil, habilite IA, auto-move, callback e/ou follow-up automatico; 5. Preencha criterios por etapa, handoff e horarios de envio; 6. Clique em Salvar IA ou Salvar funil.
- gotchas: o painel so aparece ao editar um funil existente; auto-move depende de criterios por etapa; callback tem modos "so lembrar", "enviar mensagem" ou "ambos"; follow-up automatico envia mensagens, entao deve ser ligado com cuidado.
- nav_target: `crm_kanban_index`

### Usar sugestoes e resumo por IA no card do CRM
- intent: "Como peco para a IA analisar um card?"; "Onde aceito a etapa sugerida pela IA?"; "Como vejo resumo da conversa no card?"
- onde_fica: Sidebar > CRM > CRM Kanban > abrir card > paineis de IA no drawer do card
- rota: `crm_kanban_index` - `/app/accounts/:accountId/crm`
- perfil: `administrator`, `agent` sem custom role, ou custom role com `crm_manage_ai`/`crm_admin` para analisar, aceitar, dispensar e atualizar resumo; custom role apenas com `crm_view` pode ser orientada a visualizar o card, mas nao a executar acoes de IA.
- gate: `CRM_KANBAN_ENABLED=true`; `CRM_AI_ENABLED=true`.
- pre_requisitos: card existente; para resumo, card precisa estar vinculado a uma conversa visivel ao usuario.
- passos: 1. Abra o card; 2. Veja o painel Sugestao de estagio; 3. Clique em Analisar agora quando quiser reavaliar; 4. Aceite para mover o card ou dispense a sugestao; 5. No painel Resumo da conversa por IA, use Atualizar quando precisar regenerar.
- gotchas: se a IA ficar abaixo do limiar, a tela mostra que nao encontrou etapa adequada; resumo nao aparece para card sem conversa; aceitar sugestao move o card de etapa.
- nav_target: `crm_kanban_index`

### Conectar ou autorizar calendario em uma caixa de e-mail
- intent: "Como libero agenda Google no CRM?"; "Como autorizo calendario da Microsoft?"; "Por que nao aparece caixa para agendar reuniao?"; "Como reconecto calendario de uma inbox?"
- onde_fica: Configuracoes > Caixas de entrada > Nova caixa > Email > Google ou Microsoft; para revisar caixa existente: Configuracoes > Caixas de entrada > selecionar caixa
- rota: `settings_inboxes_page_channel` - `/app/accounts/:accountId/settings/inboxes/new/email`; relacionado: `settings_inbox_show` - `/app/accounts/:accountId/settings/inboxes/:inboxId/:tab?`
- perfil: `administrator`; se o perfil nao puder, diga que conexao OAuth de e-mail/calendario e acao administrativa e peca a um administrador da conta para conectar ou reautorizar a caixa.
- gate: feature flag `inbox_management`; feature `channel_email`; `CRM_CALENDAR_MEETINGS_ENABLED=true` para solicitar escopo de calendario automaticamente no OAuth e habilitar agendamento/booking.
- pre_requisitos: credenciais OAuth Google ou Microsoft configuradas para a conta ou globalmente; permissao no provedor para consentir acesso de e-mail e calendario.
- passos: 1. Abra Nova caixa e escolha Email; 2. Escolha Google ou Microsoft; 3. Entre com a conta de e-mail que sera a caixa; 4. Aceite as permissoes solicitadas, incluindo calendario; 5. Ao voltar, confirme que a caixa aparece no CRM Calendar e nos perfis de agendamento.
- gotchas: `calendar_enabled` e `calendar_scope_granted` so ficam ativos se o provedor devolver escopo de calendario; caixas Google/Microsoft conectadas antes da flag podem precisar reautorizar; entrar com o mesmo e-mail no fluxo OAuth atualiza a caixa existente em vez de criar outra; provedores "outros" por IMAP/SMTP nao habilitam calendario.
- nav_target: `settings_inboxes_page_channel`

### Configurar pagina de agendamento em caixa compartilhada e links por agente
- intent: "Como varios vendedores usam o mesmo e-mail para agenda?"; "Como gero um link de agendamento para cada agente?"; "O que significa caixa compartilhada no booking?"
- onde_fica: Sidebar > CRM > CRM Calendar > Pagina de agendamento
- rota: `crm_calendar_index` - `/app/accounts/:accountId/crm/calendar`; link gerado usa `public_booking_page` - `/book/:slug`
- perfil: `administrator`; se o perfil nao puder, diga que a API de perfis de agendamento e administrativa. Custom role com `crm_manage_pipelines` pode ver controles de CRM, mas deve pedir a um administrador para salvar/gerar links de booking.
- gate: `CRM_KANBAN_ENABLED=true`; `CRM_CALENDAR_MEETINGS_ENABLED=true`; caixa precisa ser Google ou Microsoft com `calendar_enabled=true`.
- pre_requisitos: caixa de e-mail Google/Microsoft conectada com calendario; agentes adicionados como membros da caixa; funil/etapa padrao recomendados para criar o lead corretamente.
- passos: 1. Abra CRM Calendar; 2. Clique em Pagina de agendamento; 3. Habilite a pagina da caixa; 4. Em Atribuicao, escolha Por agente (links individuais); 5. Marque Caixa compartilhada quando varios agentes usam o mesmo e-mail; 6. Salve e copie o link de cada agente.
- gotchas: em modo por agente, compartilhe os links individuais, nao o slug base; agente sem acesso a caixa nao e elegivel; com `calendar_shared`, disponibilidade e calculada pelos compromissos CRM do agente, nao pelo free/busy agregado da caixa compartilhada.
- nav_target: `crm_calendar_index`

### Gerenciar tokens de integracao do CRM
- intent: "Onde crio token para integrar o CRM?"; "Como gero token para n8n?"; "Como revogo ou rotaciono um token do CRM?"
- onde_fica: URL direta de CRM Settings > Integration tokens; tambem acessivel pelo guia de n8n em Configuracoes > Integracoes > n8n (Conexoes do CRM)
- rota: `crm_integration_tokens_index` - `/app/accounts/:accountId/crm/settings/integration-tokens`
- perfil: `administrator` ou custom role com `crm_admin`; agentes comuns, agentes sem custom role e custom roles sem `crm_admin` nao podem gerenciar tokens. Diga que tokens sao credenciais administrativas e devem ser criados por admin/CRM admin.
- gate: `CRM_KANBAN_ENABLED=true`; edicao backend exige policy de `crm_admin`.
- pre_requisitos: saber o nome da integracao e os escopos minimos necessarios (`crm_view`, `crm_manage_cards`, `crm_move_cards`, `crm_manage_pipelines`, `crm_manage_ai`, `crm_view_reports`, `crm_admin`).
- passos: 1. Abra a pagina de tokens; 2. Informe um nome identificavel; 3. Marque somente os escopos necessarios; 4. Crie o token; 5. Copie o segredo exibido uma unica vez; 6. Use Rotacionar ou Revogar quando precisar trocar ou encerrar o acesso.
- gotchas: o segredo nao e mostrado de novo depois de dispensado; rotacionar revoga o token anterior imediatamente; revogar remove o acesso na hora; para n8n, a tela mostra o header `api_access_token`.
- nav_target: `crm_integration_tokens_index`

### Configurar integracao CRM com n8n
- intent: "Como conecto o CRM ao n8n?"; "Quais eventos do CRM posso enviar por webhook?"; "Onde configuro automacao externa para cards?"
- onde_fica: Configuracoes > Integracoes > n8n (Conexoes do CRM)
- rota: `settings_integrations_crm_n8n` - `/app/accounts/:accountId/settings/integrations/crm_n8n`; relacionado: `settings_integrations_webhook` - `/app/accounts/:accountId/settings/integrations/webhook`
- perfil: `administrator`; se o perfil nao puder, diga que a tela de integracoes e webhooks e administrativa. Custom role `crm_admin` pode acessar tokens pela rota do CRM, mas nao substitui o acesso administrativo a Configuracoes > Integracoes.
- gate: feature flag `integrations`; feature `crm_integration`; `CRM_KANBAN_ENABLED=true` para exibir eventos de CRM no formulario de webhook.
- pre_requisitos: endpoint HTTPS publico do n8n; token de CRM com escopos adequados; decidir quais eventos assinar.
- passos: 1. Abra n8n (Conexoes do CRM); 2. Clique para criar token de API do CRM; 3. Copie o token no n8n usando o header `api_access_token`; 4. Volte e crie um webhook; 5. Marque eventos como `crm.card.created`, `crm.card.moved`, `crm.card.won`, `crm.card.lost`, `crm.card.reopened` ou `crm.card.archived`.
- gotchas: n8n local ou URL privada pode ser bloqueado por protecao SSRF; eventos de CRM so aparecem no webhook quando `CRM_KANBAN_ENABLED=true`; token e webhook sao duas partes separadas da integracao.
- nav_target: `settings_integrations_crm_n8n`

### Configurar CRM por caixa de entrada
- intent: "Como faco conversas virarem cards automaticamente?"; "Como defino funil padrao por inbox?"; "Como restringo cards da caixa para o agente atribuido?"
- onde_fica: Sidebar > CRM > CRM Kanban > Configuracoes de inbox
- rota: `crm_kanban_index` - `/app/accounts/:accountId/crm`
- perfil: `administrator`, `agent` sem custom role, ou custom role com `crm_manage_pipelines`/`crm_admin`; se o perfil nao puder, diga que ele precisa de permissao para gerenciar funis/configuracoes do CRM.
- gate: `CRM_KANBAN_ENABLED=true`.
- pre_requisitos: caixas de entrada criadas; funil e etapas existentes quando quiser definir padrao.
- passos: 1. Abra CRM Kanban; 2. Clique em Configuracoes de inbox; 3. Ative CRM na caixa desejada; 4. Escolha visibilidade entre todos os cards da inbox ou apenas atribuidos; 5. Defina funil/etapa padrao; 6. Marque Criar card automaticamente e salve.
- gotchas: se CRM ativo for desligado, a criacao automatica tambem e desligada; `assigned_only` muda a visibilidade de agentes; funil/etapa padrao precisam pertencer a mesma conta.
- nav_target: `crm_kanban_index`

### Criar automacoes por etapa do funil
- intent: "Como automatizo uma etapa do CRM?"; "Como criar follow-up ao mover card?"; "Como atribuir responsavel automaticamente quando entrar numa etapa?"
- onde_fica: Sidebar > CRM > CRM Kanban > Editar funil > etapa > icone de automacoes
- rota: `crm_kanban_index` - `/app/accounts/:accountId/crm`
- perfil: `administrator`, `agent` sem custom role, ou custom role com `crm_manage_pipelines`/`crm_admin`; se o perfil nao puder, diga que automacoes de etapa fazem parte da gestao de funis.
- gate: `CRM_KANBAN_ENABLED=true`.
- pre_requisitos: funil salvo; etapa existente; agentes disponiveis quando a acao for atribuir responsavel.
- passos: 1. Abra Editar funil; 2. Na etapa desejada, clique no icone de automacoes; 3. Crie uma regra e escolha gatilho de entrada ou saida; 4. Adicione passos como Criar follow-up, Atribuir responsavel ou Mover estagio; 5. Defina atraso e parametros; 6. Salve a regra.
- gotchas: automacoes so aparecem para etapas ja salvas; regras podem encadear movimentos, entao evite loops; follow-ups criados pela automacao aparecem no card e no calendario.
- nav_target: `crm_kanban_index`

### Salvar e compartilhar visoes da lista do CRM
- intent: "Como salvo uma visualizacao do CRM?"; "Como compartilhar filtros e colunas da lista?"; "Onde aplico uma visao salva?"
- onde_fica: Sidebar > CRM > CRM Kanban > alternar para Lista > botao de visoes salvas
- rota: `crm_kanban_index` - `/app/accounts/:accountId/crm`
- perfil: `administrator`, `agent` ou custom role com `crm_view`; se o perfil nao puder, diga que ele precisa ao menos de acesso de visualizacao do CRM. Somente dono da visao ou administrador edita/exclui uma visao existente.
- gate: `CRM_KANBAN_ENABLED=true`.
- pre_requisitos: funil selecionado; modo Lista aberto; filtros, colunas, ordenacao, agrupamento ou densidade ajustados.
- passos: 1. Abra o CRM em modo Lista; 2. Ajuste filtros, colunas e ordenacao; 3. Clique no botao de visoes salvas; 4. Crie uma nova visao; 5. Escolha visibilidade privada, time ou conta; 6. Aplique a visao quando quiser restaurar a configuracao.
- gotchas: visoes privadas aparecem so para o dono; visoes de time/conta aparecem para outros usuarios com acesso ao CRM; a visao salva captura configuracao da lista, nao altera cards.
- nav_target: `crm_kanban_index`
