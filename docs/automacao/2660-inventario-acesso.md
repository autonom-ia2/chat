# Automação livre · o que pode virar passo (inventário da #2660)

- **Issue:** #2660 · épico #2414 · decisão do Rodrigo em 06/11/2026: "Liberar tudo, com guardas".
- **Base lida:** `main` em `e2b081d250`. Só leitura de código; nenhuma regra mudou ainda.
- **Decidido:** o Rodrigo escolheu "Liberar mais" em 06/11/2026 (seção 3).
- **Próximo passo:** um PR por lote (seção 4), cada um com o `acoes_permitidas_spec`, parecer da Funções e da
  qualidade, e OK dele.

## 1. Em poucas palavras

Hoje a automação só mexe em 11 coisas da plataforma (etiqueta, atributo, contato, empresa, conversa, atribuição,
card, etapa, agente na caixa). Outras 207 estão trancadas.

Lemos o código de cada uma das 207. O resultado:

| | Recursos |
|---|---|
| Ficam trancadas para sempre (grupo 1: usuários, canais, integrações, credenciais) | 33 |
| Podem ser liberadas, inteiras (33) ou em parte (35) | **68** |
| Continuam trancadas, com motivo concreto | 106 |

"Em parte" quer dizer: o recurso entra, mas uma ou outra ação dele fica de fora (por exemplo, a automação pode criar
um time, mas não apagar).

**O que continua trancado, e por quê.** Só cinco motivos:

1. **Perigoso.** Usuário, função, conta, canal, integração, credencial, segurança, faturamento. Inclui configurar
   agente de IA (é quem fala com o cliente, como o robô de atendimento, que já é trancado).
2. **Apagar estrutura.** Apagar funil, etapa, caixa, time, portal.
3. **Não dá para desfazer.** A plataforma termina o serviço depois, num job ou em lote; ou a ação grava fora (Meta,
   Google, agenda); ou só gasta IA paga e não grava nada.
4. **Fala com o cliente.** Mensagem, ligação, campanha, comentário público, anúncio. Para falar com o cliente já
   existem os passos próprios (mensagem, aviso, e-mail, modelo aprovado).
5. **Já existe caminho melhor.** Por exemplo, a rota que troca a lista inteira de etiquetas; a automação usa a que
   põe e tira uma a uma.

**As guardas continuam valendo para tudo que for liberado:** a automação age com a permissão de quem a ligou,
conferida a cada vez (inclusive as funções personalizadas e as chaves de cada área); e tudo que ela muda fica no
desfazer do Guia por 5 dias.

## 2. O que mais ajuda nos 20 exemplos

Das lacunas dos 20 exemplos (`F9-fechamento-20-exemplos.md`, seção 6), quatro são só "ação trancada":

| Lacuna | O que libera | Exemplos |
|---|---|---|
| G3 criar retorno | `crm/follow_ups` | 1, 2, 3, 4, 5, 9, 12, 14, 15, 16, 19 (11) |
| G4 criar card | `POST crm/cards` e `POST crm/cards/from_conversation` | 4, 6, 8, 9, 10, 11, 16, 18 (8) |
| G25 fechar card ganho/perdido | `POST crm/cards/:id/close` | 4, 6, 12, 18 (4) |
| G17 criar contato | `POST contacts` | 8, 11 (2) |
| G19 nota no contato | `contacts/notes` | 5, 19 (2) |

G4, G25 e G17 não estão na lista `fora`: são ações que faltam em recursos já liberados (`crm/cards`, `contacts`).
G3, G4, G19 e G25 já estão no trem do #2414 (seção 4); desta issue, só G17 ainda fecha lacuna. G14 tem passo
nativo no trem (#2642). G21 (prospecção) fica só em parte: montar entra, buscar no Google não (motivo 3).

## 3. Decisões do Rodrigo (06/11/2026: "Liberar mais")

| # | Pergunta | Decisão |
|---|---|---|
| D1 | Hoje o spec proíbe **todo** DELETE como passo (`acoes_permitidas_spec.rb:40`). Vários DELETE só apagam dado dentro da requisição, e o desfazer alcança. | **Abrir.** Entra o DELETE de item simples que o desfazer alcança e que não é estrutura: os marcados `DELETE*` nas tabelas (tirar pessoa do time, apagar nota do contato, apagar resposta pronta). DELETE de estrutura e DELETE sem desfazer continuam fora. A trava do spec vira "nenhum DELETE de estrutura nem sem desfazer". O DELETE da política de distribuição e o da caixa do funil ficam fora mesmo assim: param a distribuição e a criação de card. |
| D2 | Retorno com **envio automático** (`automation_mode: auto_send_message`) manda mensagem ao cliente no vencimento. | **Liberado,** pelo passo nativo `retorno` do G3 (#2640), não pela rota crua: vale o `Creator` e o `AutoSendValidator`, só modelo UTILITY, e o histórico mostra que mandou. A rota crua `POST crm/follow_ups` fica fora (motivo 5: o passo nativo é o caminho). |
| D3 | **Configurar agente de IA** (instrução, material, ferramentas, onde atende) ficou trancado (motivo 1). | **Ligar e desligar o agente entra:** `PATCH`/`PUT autonomia/agents/:id`, só com `enabled` e `status` (`active` ou `paused`). Fica `proibe` em todos os outros campos: `name`, `agent_type`, `mode`, `tone`, `greeting`, `fallback_message`, `handoff_rule`, `human_card`, `actuation`, `instruction`, `starter_questions`, `config` (e `agent.*`). `status: draft` fica fora pelo `um_de` (modificador do #2654). `autonomia/agents` sai do grupo `sempre` do yml. |
| D4 | `crm/ai_settings`: ligar a IA do funil faz ela avaliar e mover cards sozinha, com gasto contínuo. | **Liberar com os 4 `proibe`** da tabela, os campos que mandam mensagem ao cliente. O gasto segue a regra "sem freio no uso do cliente". `crm/ai_settings` sai do `sempre`; o spec que o espera lá muda junto (`acoes_permitidas_spec.rb:53`). |
| D5 | Artigo e portal ficam **públicos na hora**; o layout de e-mail muda o HTML em volta de todo e-mail enviado ao cliente. | **Artigo só como rascunho:** `fixos: { status: draft }`. **Layout de e-mail fica trancado.** |
| D6 | **Desligar** regra antiga ou automação de etapa como passo. | **Fora.** Na F9, o caminho é o próprio conversor. |
| D7 | `POST crm/cards/:card_id/contact` exige o cabeçalho `Idempotency-Key`, que a porta interna não manda. | **A porta interna manda a chave** (id da execução e do passo). É mudança no motor, no lote B. |
| D8 | **Pausar** campanha (e-mail e WhatsApp API), IA dos comentários e anúncio: o desfazer de hoje trava a campanha ou não alcança. | **Fora** até corrigir o desfazer. |

A regra das funções personalizadas ("só o administrador" e as quatro proteções) não muda: cada rota continua
pedindo a chave dela, e a automação age com a função de quem a ligou.

## 4. Lotes

**Já no trem do #2414 (não entram nos lotes desta issue):**

| PR | O que faz | Como |
|---|---|---|
| #2640 | criar retorno (G3), com envio automático (D2) | passo nativo `retorno` |
| #2641 | criar card (G4) | passo nativo de card |
| #2642 | campanha como passo (G14) | passo nativo de campanha |
| #2644 | nota no contato (G19) | `POST contacts/:contact_id/notes` no yml |
| #2654 | fechar card ganho ou perdido (G25) | `POST crm/cards/:id/close` no yml, com `um_de` |

O #2644 deixa mudar e apagar nota de fora ("a automação não reescreve o que alguém anotou"). A D1 cita "apagar nota
do contato" como exemplo do que abre. Quem fizer o lote que toca `contacts/notes` confirma com a Automação qual vale.

**Os lotes desta issue, na ordem proposta:**

| Ordem | Lote | O que entra | Exemplos que ajuda |
|---|---|---|---|
| 1 | **B · card e contato** | criar contato (G17) e contato pelo card (D7, com a chave no motor); ligar e desligar contato e conversa do card; restaurar card (`proibe: force`); cliente e lead; contato na empresa; criar empresa; fatos da memória do card; aceitar sugestão de etapa da IA | 8, 11 (G17), e o resto deixa o card completo nos exemplos de card |
| 2 | **A · retorno e agenda** | alterar, concluir, cancelar e remarcar retorno; série de retornos; registrar se a reunião aconteceu; horários da agenda de quem ligou; página de agendamento; link de agendamento (sem mandar) | ajuda os 11 do G3 depois que o retorno existe (mexer no retorno criado); nenhum fecha sozinho |
| 3 | **D1 · trava do DELETE** | a trava do spec vira "nenhum DELETE de estrutura nem sem desfazer" e entram os `DELETE*` | nenhum direto; pode ir junto com o lote que tiver mais `DELETE*` (D) |
| 4 | **D · configuração do atendimento** | times e pessoas no time, respostas prontas, filtros, visões salvas, SLA, política de distribuição e de capacidade, funis e caixas do funil, ajuste do CRM por caixa, horário de atendimento, metas, participantes da conversa, nome de etiqueta | nenhum direto |
| 5 | **E · IA do CRM** | ajustes da IA do funil (D4), ligar e desligar agente de IA (D3), decisores, foco e assunto da conversa, catálogo da memória, ações do consultor de anúncios, sugestões de FAQ e relatos de mensagem | nenhum direto |
| 6 | **C · rascunho de campanha e prospecção** | rascunho de campanha, prévia de destinatários, campanha e modelo de e-mail em rascunho, modelo local do WhatsApp API; prospecção: lista, lead vira contato ou card, filtros salvos | 9 (G21) em parte. Fica depois do #2642 para não pisar na campanha nativa |
| 7 | **F · conteúdo e painel** | portal, artigo como rascunho e categoria (D5), identidade visual, macros (criar e editar, sem executar), link rastreado, página de site do anúncio, foto do cuidado dos comentários, avisos e notificações de quem ligou, passos do onboarding | nenhum direto |

Todos mexem em `lib/operator_guide/automacao-recursos.yml`, como #2644 e #2654. Um lote por vez no trem, depois
deles.

As ações que faltam de recursos já liberados e não entraram em lote ficam como estão: `PATCH conversations/:id`,
mudo, não lida, transcrição, apagar atributo. Entram quando um caso pedir, com a mesma leitura do controller.

## 5. A tabela

Legenda do veredito: **LIBERAR** · **PARTE** (o recurso entra, algumas ações não) · **FORA n** (motivo n da
seção 1). `DELETE*` = DELETE que só apaga dado, dentro da requisição: entra pela D1.

No `proibe` de rota do CRM, citar os dois caminhos (`campo` e `objeto.campo`): o `parameter_set` do CRM aceita o
corpo com raiz ou solto (`crm/base_controller.rb:48`).

### 5.1 Grupo 1 · usuários, canais, integrações, credenciais (33) · FORA 1, inteiro

`agents`, `agent_bots`, `api/v1/accounts`, `custom_roles`, `saml_settings`, `webhooks`, `callbacks`,
`dashboard_apps`, `email_oauth_apps`, `crm/integration_tokens`, `crm/meta_ads_connections`, `integrations/dyte`,
`integrations/hooks`, `integrations/linear`, `integrations/notion`, `integrations/shopify`, `integrations/slack`,
`google/authorizations`, `instagram/authorizations`, `microsoft/authorizations`, `notion/authorizations`,
`tiktok/authorizations`, `twitter/authorizations`, `whatsapp/authorizations`, `whatsapp/access_requests`,
`whatsapp/manual_setup`, `instagram/testers`, `autonomia/insurance/connection`, `autonomia/invite_connections`,
`channels/twilio_channels`, `inboxes`, `waha_inboxes`, `whatsapp_hybrid_connections`.

### 5.2 Grupo 2 · IA, CRM e agentes (42)

| Recurso | Veredito | Entra (com guarda) | Fica fora e por quê | Evidência |
|---|---|---|---|---|
| crm/ai_settings | PARTE (D4) | `PATCH`/`PUT crm/pipelines/:pipeline_id/ai_settings` com `proibe: [auto_followup, service_reminders, callback_enabled, callback_mode]` (e `ai_settings.*`) | `improve_criteria`: IA paga num job, só devolve texto (3). Os 4 campos ligam mensagem automática ao cliente (4) | ai_settings_controller.rb:12-33; settings_updater.rb:19-41 |
| crm/ai_suggestions | LIBERAR | `POST :id/accept`, `POST :id/dismiss` | — (a conferir: o accept de "fechar" arquiva pelo FecharCard; ver se o desfazer alcança) | suggestion_applier.rb:11-40 |
| crm/stage_criteria | FORA 3 | — | `improve`: IA paga em job, nada gravado | stage_criteria_controller.rb:24-33 |
| crm/memoria_chaves | LIBERAR | `PATCH crm/memoria/chaves/:id` | — (só administrador) | memoria_chaves_controller.rb:13-28 |
| crm/memoria_fatos | LIBERAR | criar fato, aceitar, destravar, "não vale mais" | — (o fato fica travado no nome de quem ligou) | memoria_fatos_controller.rb:20-50 |
| crm/meta_ads_ai | FORA 3 | — | `daily_action`, `quote_message`: IA paga, texto só para a tela | meta_ads_ai_controller.rb:19-52 |
| crm/meta_ads_advisor_actions | LIBERAR | `open`, `accept`, `dismiss` | — (só marca status; não fala com a Meta; pede `meta_ads_manage`) | meta_ads_advisor_actions_controller.rb:16-33 |
| crm/conversation_cards | PARTE | `focus`, `repasse/manter`, aceitar e dispensar sugestão de assunto | `repasse`: solta o atendente e pode passar à IA; já existem atribuir e `ia_assumir` (5) | conversation_cards_controller.rb:14-55; repasse.rb:100-110 |
| crm/caixas | FORA 1 | — | `PUT` salva a caixa inteira: funis, pessoas e agentes de IA do canal | caixas_controller.rb:21-36 |
| autonomia/agents | PARTE (D3) | `PATCH`/`PUT autonomia/agents/:id` só com `enabled` e `status` (`um_de: [active, paused]`); `proibe` nos outros campos (seção 3) | criar e configurar (instrução, ferramentas, modo, atuação): quem fala com o cliente (1); DELETE (2); avatar (3) | agents_controller.rb:76-90,200-207; agent.rb:99 |
| autonomia/agents/ajuda | FORA 1 | — | troca o conjunto de principais do agente | ajuda_controller.rb:12-16 |
| autonomia/agents/base_de_seguros | FORA 1 | — | troca a base do agente; comparar é IA paga (3) | base_de_seguros_controller.rb:29-51 |
| autonomia/agents/build_threads | FORA 3 | — | o Construtor chama IA paga e reescreve o agente | build_threads_controller.rb:19-67 |
| autonomia/agents/builder_images | FORA 3 | — | envio de arquivo; a receita não carrega arquivo | builder_images_controller.rb:7-27 |
| autonomia/agents/channels | FORA 1 | — | liga e desliga o agente num canal | channels_controller.rb:18-35 |
| autonomia/agents/faq_suggestions | PARTE | `POST :id/ignore` | `approve`: grava o que o agente diz ao cliente, sem revisão, com embedding pago (1) | faq_suggestions_controller.rb:18-34 |
| autonomia/agents/instruction_versions | FORA 1 | — | `restore` troca a instrução do agente | instruction_versions_controller.rb:20-23 |
| autonomia/agents/material | FORA 3 | — | autoteste é IA paga em job; resolver muda o material (1) | material_controller.rb:12-28 |
| autonomia/agents/message_reports | LIBERAR | `POST autonomia/agents/message_reports` | — | message_reports_controller.rb:11-18 |
| autonomia/agents/onde_atende | FORA 1 | — | muda caixas e janela em que o agente atende | onde_atende_controller.rb:6-31 |
| autonomia/agents/playground | FORA 3 | — | IA paga, não grava | playground_controller.rb:15-31 |
| autonomia/agents/sources | FORA 3 | — | OCR e embedding pagos em job | sources_controller.rb:24-52 |
| autonomia/agents/tools | FORA 1 | — | ferramenta HTTP com cabeçalho secreto (credencial); teste chama fora (3) | tools_controller.rb:16-88 |
| autonomia/quem_atende | FORA 1 | — | troca quem atende a caixa | quem_atende_controller.rb:22-28 |
| autonomia/conversation_copilot | FORA 3 | — | IA paga, resposta só na tela | conversation_copilot_controller.rb:11-38 |
| autonomia/text_copilot | FORA 3 | — | IA paga, só reescreve texto | text_copilot_controller.rb:18-24 |
| autonomia/decisores | PARTE | `POST autonomia/decisores`; `PATCH`/`PUT :id` com `proibe: [respostas, exemplos]`; `POST :id/exemplos` | `teste`: IA paga síncrona (3). DELETE (2). `respostas` quebra os ramos das regras; `exemplos` troca a lista inteira (5) | decisores_controller.rb:25-82 |
| autonomia/decisoes | FORA 3 | — | `resolver` em SEM_DESFAZER | acoes.rb:89 |
| autonomia/insurance/quote_agent | FORA 1 | — | cria agente que fala com o cliente, com credencial de portal | quote_agent_controller.rb:3-15 |
| captain/assistant_responses | FORA 3 | — | embedding pago em job no after_commit | assistant_response.rb:41,82 |
| captain/assistants | FORA 1 | — | configura o agente; DELETE (2); playground (3) | assistants_controller.rb:12-35 |
| captain/bulk_actions | FORA 3 | — | SEM_DESFAZER (lote) | acoes.rb:79 |
| captain/copilot_messages | FORA 3 | — | IA paga em job | copilot_messages_controller.rb:13-19 |
| captain/copilot_threads | FORA 3 | — | IA paga em job | copilot_threads_controller.rb:16-55 |
| captain/custom_tools | FORA 1 | — | ferramenta HTTP com autenticação (credencial) | custom_tools_controller.rb:12-56 |
| captain/documents | FORA 3 | — | busca URL de fora e chama IA em job | document.rb:59-62,163-169 |
| captain/faq_suggestions | PARTE | `PATCH`/`PUT :id`, `POST :id/dismiss` | `approve`: embedding pago em job (3) | faq_suggestions_controller.rb:25-44 |
| captain/inboxes | FORA 1 | — | liga e desliga o assistente num canal | inboxes_controller.rb:9-17 |
| captain/message_reports | LIBERAR | `POST captain/message_reports` | — | message_reports_controller.rb:7-8 |
| captain/preferences | FORA 1 | — | modelos e recursos de IA da conta | preferences_controller.rb:8-12 |
| captain/scenarios | FORA 1 | — | muda a instrução do assistente | scenarios_controller.rb:12-21 |
| captain/tasks | FORA 3 | — | IA paga síncrona, só devolve texto | tasks_controller.rb:4-44 |

### 5.3 Grupo 3 · fala com o cliente ou sai da plataforma (51)

A porta interna só manda corpo em JSON (`chamada_interna.rb:47-55`): nada que sobe arquivo roda como passo.

| Recurso | Veredito | Entra (com guarda) | Fica fora e por quê | Evidência |
|---|---|---|---|---|
| conversations/messages | FORA 4 | — | mandar e reenviar: SEM_DESFAZER, passo mensagem já existe. Apagar no Híbrido apaga "para todos" no WhatsApp. `PATCH` é o conector informando entrega (1). Traduzir é pago (3) | messages_controller.rb:10-46 |
| conversations/message_edits | FORA 4 | — | edita no WhatsApp do cliente | message_edits_controller.rb:1-11 |
| conversations/message_reactions | FORA 4 | — | reação vai ao WhatsApp | message_reactions_controller.rb:1-10 |
| conversations/contact_info_requests | FORA 4 | — | SEM_DESFAZER; pede dados no WhatsApp | acoes.rb:59 |
| conversations/draft_messages | FORA 3 | — | grava no Redis, fora do desfazer; apagaria o rascunho de quem atende | draft_messages_controller.rb:9-17 |
| conversations/direct_uploads | FORA 3 | — | encanamento de envio de arquivo | direct_uploads_controller.rb:1-21 |
| conversations/comentario | FORA 4 | — | responder, esconder e apagar agem na Meta | comentario_controller.rb:5-49 |
| conversa_canal/encaminhamentos | FORA 4 | — | manda para outras conversas; recusa o token da porta interna (403) | encaminhamentos_controller.rb:6-33 |
| conversa_canal/reacoes | FORA 4 | — | reação ao cliente | reacoes_controller.rb:1-13 |
| conversa_canal/convites_do_email | FORA 4 | — | responde o convite por e-mail | convites_do_email_controller.rb:1-12 |
| conversa_canal/ditados | FORA 3 | — | transcrição paga, com arquivo; não grava | ditados_controller.rb:15-16 |
| contacts/calls | FORA 4 | — | SEM_DESFAZER, ligação | acoes.rb:60 |
| whatsapp_calls | FORA 4 | — | ligação ao vivo na Meta | whatsapp_calls_controller.rb:19-42 |
| conference | FORA 4 | — | conferência Twilio | conference_controller.rb:13-33 |
| campaigns | FORA 4 | — | criar é SEM_DESFAZER; editar muda o que sai sozinho; apagar usa update_all (3) | campaigns_controller.rb:12-30 |
| whatsapp_api_campaigns | FORA 4 (D8) | — | criar e retomar: SEM_DESFAZER. Pausar: o desfazer volta "rodando" sem religar o envio (3). Cancelar: update_all (3) | whatsapp_api_campaign.rb:85-107 |
| campaign_journey/campaign_pauses | FORA 4 | — | retomar dispara na hora | campaign_pauses_controller.rb:11-31 |
| campaign_journey/campaigns | FORA 4 | — | envia ou agenda; rascunho de e-mail usa insert_all/delete_all (3) e tem rota melhor (5) | campaigns_controller.rb:6-95 |
| campaign_journey/conversa_aberta | FORA 3 | — | IA paga só sugere texto | conversa_aberta_controller.rb:4-27 |
| campaign_journey/conversation_audiences | FORA 3 | — | IA paga em job, update_all, insert_all | conversation_audiences_controller.rb:44-90 |
| campaign_journey/drafts | LIBERAR | `POST`, `PATCH`/`PUT :id`; `DELETE*` | — (só o rascunho; disparar não passa aqui) | drafts_controller.rb:9-45 |
| campaign_journey/recipient_previews | LIBERAR | `POST` | — (só conta destinatários; útil só se o passo usar a resposta) | recipient_previews_controller.rb:1-3 |
| email_campaigns/ai | FORA 3 | — | IA paga em job; estado no Redis | ai_controller.rb:15-63 |
| email_campaigns/assets | FORA 3 | — | envio de arquivo | assets_controller.rb:9-24 |
| email_campaigns/campaigns | PARTE | `POST`, `PATCH`/`PUT :id` (só em rascunho), `POST :id/duplicate` | enviar, agendar, retomar: SEM_DESFAZER (4). Apagar e cancelar: delete_all/update_all (3). Pausar (D8). Reavaliar é guarda de reputação (1) | campaigns_controller.rb:20-113 |
| email_campaigns/maintenance | FORA 1 | — | manutenção da proteção de e-mail | maintenance_controller.rb:13-26 |
| email_campaigns/recipients | FORA 3 | — | arquivo e importação em job | recipients_controller.rb:15-42 |
| email_campaigns/reputations | FORA 1 | — | guarda de reputação de envio | reputations_controller.rb:16-37 |
| email_campaigns/sender_identities | FORA 1 | — | domínio de envio na AWS | sender_identities_controller.rb:10-33 |
| email_campaigns/template_imports | FORA 3 | — | lê URL ou arquivo de fora; IA paga; salvar tem rota melhor (5) | template_imports_controller.rb:1-66 |
| email_campaigns/templates | PARTE | `POST` | apagar: anexos com purge_later (3) | templates_controller.rb:18-31 |
| email_campaigns/test_sends | FORA 4 | — | manda e-mail para endereços de fora | test_sends_controller.rb:1-9 |
| email_campaigns/videos | FORA 3 | — | lê URL de fora, não grava | videos_controller.rb:1-17 |
| crm/booking_invites | PARTE | `POST` (só cria o link); `DELETE*` (cancela com update!, sem apagar) | `deliver` manda na conversa: passo mensagem com o link da agenda já existe (4). `copied` é gesto da tela | booking_invites_controller.rb:26-58 |
| seus_posts_comentarios | FORA 4 | — | responder, esconder, apagar na Meta | seus_posts_comentarios_controller.rb:7-71 |
| seus_posts_cuidado | PARTE | `PUT .../cuidado/foto` (texto local que a IA usa) | ligar faz a IA responder em público (4); mudar todos usa update_all (3); prévias são IA paga (3). A conferir: exige `?perfil=` | seus_posts_cuidado_controller.rb:69-213 |
| agentes_do_post | FORA 3 | — | pausar usa update_all; ligar faz a IA responder (4); testar é IA paga | agentes_do_post_controller.rb:15-207 |
| agentes_do_post_materiais | FORA 3 | — | arquivo e IngestJob | agentes_do_post_materiais_controller.rb:9-41 |
| crm/meta_ads_facebook_comments | FORA 4 | — | responder, esconder, apagar na Meta | meta_ads_facebook_comments_controller.rb:8-61 |
| crm/meta_ads_instagram_comments | FORA 4 | — | idem | meta_ads_instagram_comments_controller.rb:7-13 |
| crm/meta_ads_whatsapp_reports | FORA 1 | — | troca o número que recebe valores de venda; teste manda WhatsApp (4) | meta_ads_whatsapp_reports_controller.rb:5-45 |
| crm/meta_ads_ad_management | FORA 3 (D8) | — | grava status na Meta; ligar gasta dinheiro | meta_ads_ad_management_controller.rb:5-35 |
| crm/meta_ads_creation | FORA 3 | — | publica e gasta na Meta | meta_ads_creation_controller.rb:6-77 |
| crm/meta_ads_cuidado | PARTE | `PUT .../cuidado/foto` | ligar, prévias, antigos: como seus_posts_cuidado | meta_ads_cuidado_controller.rb:62-95 |
| crm/meta_ads_lead_forms | FORA 1 | — | assina leads na Meta (3); destino dos leads é configuração da integração | meta_ads_lead_forms_controller.rb:4-66 |
| crm/meta_ads_site_pages | LIBERAR | `POST crm/meta_ads_connection/site_pages` | — (link rastreado local) | meta_ads_site_pages_controller.rb:6-31 |
| crm/google_conversion_feeds | FORA 1 | — | emite token de URL pública | google_conversion_feeds_controller.rb:3-4 |
| whatsapp_api_message_templates | LIBERAR | `POST`, `PATCH`/`PUT :id`; `DELETE*` (arquiva) | — (modelo local, sem a Meta) | whatsapp_api_message_templates_controller.rb:14-28 |
| whatsapp_template_suggestions | FORA 3 | — | IA paga, não salva | whatsapp_template_suggestions_controller.rb:1-20 |
| inboxes/whatsapp_templates | FORA 3 | — | grava modelo oficial na Meta | whatsapp_templates_controller.rb:4-50 |
| inboxes/whatsapp_conversation_assets | FORA 3 | — | envio de arquivo | whatsapp_conversation_assets_controller.rb:5-30 |

### 5.4 Grupos 4 a 7 · lote, automação, retorno e reunião, etiquetas (28)

| Recurso | Veredito | Entra (com guarda) | Fica fora e por quê | Evidência |
|---|---|---|---|---|
| bulk_actions | FORA 3 | — | lote em job; SEM_DESFAZER | bulk_actions_controller.rb:23-31 |
| crm/cards/bulk | FORA 5 | — | mover e alterar já entram um a um; ganhar/perder entra pelo `close` (lote B) | bulk_action.rb:70-76 |
| articles/bulk_actions | PARTE (D5) | mudar categoria e status de vários artigos | apagar: update_all nas traduções (3); traduzir: IA paga em job (3) | articles/bulk_actions_controller.rb:10-38 |
| macros | PARTE | `POST`, `PATCH`/`PUT :id` (a macro só roda quando uma pessoa clica) | executar: SEM_DESFAZER; apagar: anexos com purge_later (3) | macros_controller.rb:49-52 |
| data_imports | FORA 1 | — | recebe token de sistema de fora; importa em job (3) | data_imports_controller.rb:22-150 |
| contact_imports | FORA 3 | — | arquivo, validação e importação em job | contact_imports_controller.rb:24-65 |
| campaign_imports | FORA 3 | — | arquivo e jobs | campaign_imports_controller.rb:25-107 |
| campaign_import_audiences | FORA 3 | — | validação em job; canal da campanha (4) | campaign_import_audiences_controller.rb:22-116 |
| brand_kit_imports | FORA 3 | — | busca site de fora em job | brand_kit_imports_controller.rb:14-19 |
| actions/contact_merges | FORA 3 | — | apaga o contato absorvido com destroy_async e update_all; apagar contato é só na tela | contact_merge_action.rb:72-137 |
| autonomia/tarefas | FORA 3 | — | começar e seguir em SEM_DESFAZER; o resto em job | tarefas_controller.rb:43-62 |
| automation_rules | FORA 1 (D6) | — | a regra roda como sistema, sem conferir a permissão de quem ligou (o motor antigo não chama policy): escapa da guarda. Criar multiplica regras ligadas | automation_rules_controller.rb:24-78 |
| autonomia/automacoes | FORA 1 | — | ligar põe o dono do token como `ligada_por`: B herda os direitos de quem ligou A. A cadeia não pega automação criada por automação. Desligar usa update_all (3) | automacoes_controller.rb:46-81; definicao.rb:36-62 |
| autonomia/automacoes_ia | FORA 3 | — | `testar_passo`: IA paga, não grava; os passos de IA já existem (5) | automacoes_ia_controller.rb:5-20 |
| crm/stage_automations | FORA 1 (D6) | — | nasce ligada e roda sem policy, como automation_rules; trocar `steps` troca a lista | persister.rb:16-49 |
| crm/stage_automation_steps | FORA 1 | — | muda passo de automação de etapa ligada, sem policy | stage_automation_steps_controller.rb:7-23 |
| autonomia/vigias | FORA 1 | — | a vigia é o alarme contra automação descontrolada; automação não pode silenciar o próprio alarme | vigia.rb:1-16 |
| crm/follow_ups | PARTE (D2) | `PATCH`/`PUT :id` com `proibe: [automation_mode, follow_up.automation_mode]`; concluir, cancelar, remarcar, dispensar lembrete; `DELETE*` (só cancela) | `POST`: criar é o passo nativo `retorno` (#2640), com o envio automático pela regra do G3 (5). Trocar o modo pela rota crua passaria por fora do `AutoSendValidator` | follow_ups_controller.rb:48-208 |
| crm/follow_up_series | LIBERAR | `PATCH`/`PUT :id`, pausar, retomar, encerrar | — | follow_up_series_controller.rb:16-34 |
| crm/meetings | PARTE | `POST :id/record_outcome` (registra se aconteceu; pode mover o card, cascata D6) | criar, alterar, apagar: agenda Google/Microsoft e aviso ao cliente (3/4). Sincronizar (3). Resumo, convite, sugerir horário: IA paga (3) | meetings_controller.rb:44-139 |
| crm/meeting_actions | FORA 5 | — | lembrar e mandar link de novo: passo mensagem com o link da agenda já existe | meeting_actions_controller.rb:25-34 |
| crm/booking_pages | PARTE | `POST` (nasce desligada); `PATCH`/`PUT :id` com `proibe: [calendar_inbox_id, notice_inbox_id]` (e `booking_page.*`); publicar, pausar, passar reuniões | DELETE (2). Logo e foto: arquivo. Salvar identidade e token de prévia (1). Convite de teste (4). Sugestões: IA paga (3). `PUT :id/people` troca a lista (5). A conferir: `apply_identity` | booking_pages_controller.rb:39-117 |
| crm/booking_page_meetings | FORA 3 | — | marca reunião na agenda de fora e avisa o cliente | booking_page_meetings_controller.rb:11-41 |
| crm/booking_profiles | FORA 1 | — | tela antiga; mexe no canal de e-mail | booking_profiles_controller.rb:1-78 |
| crm/booking_stats | FORA 4 | — | reenviar convite ao cliente | booking_stats_controller.rb:37-43 |
| crm/my_booking_hours | LIBERAR | `PUT crm/my_booking_hours` | — (sempre a agenda de quem ligou) | my_booking_hours_controller.rb:6-42 |
| contacts/labels | FORA 5 | — | troca a lista inteira; já existe `contacts/alterar_etiquetas` | label_concern.rb:2-4 |
| conversations/labels | FORA 5 | — | troca a lista inteira; já existe `conversations/alterar_etiquetas` | label_concern.rb:2-4 |

### 5.5 Grupo 8 · configuração e dados (53)

O que o desfazer do Guia não alcança: `delete_all`, `update_all`, `upsert`, `update_column(s)`, `dependent:
:nullify` e FK `on_delete: cascade` (`diario.rb:14-17`). Onde a ação usa um deles, a parte fica fora.

| Recurso | Veredito | Entra (com guarda) | Fica fora e por quê | Evidência |
|---|---|---|---|---|
| teams | PARTE | `POST`, `PATCH`/`PUT :id` | DELETE: SEM_DESFAZER | teams_controller.rb:21 |
| team_members | PARTE | `POST`; `DELETE*` (só os ids enviados) | `PATCH` troca a lista inteira (5) | team_members_controller.rb:16-20 |
| canned_responses | LIBERAR | `POST`, `PATCH`/`PUT :id`; `DELETE*` | — | canned_responses_controller.rb:21-32 |
| custom_filters | LIBERAR | `POST`, `PATCH`/`PUT :id`; `DELETE*` | — (o filtro é de quem ligou) | custom_filters_controller.rb:37 |
| crm/saved_views | LIBERAR | `POST`; `PATCH`/`PUT :id` com `proibe: [position]`; `DELETE*` | — | saved_views_controller.rb:62 |
| sla_policies | PARTE | `POST`, `PATCH`/`PUT :id` | DELETE: SEM_DESFAZER | sla_policies_controller.rb:21 |
| assignment_policies | PARTE | `POST`, `PATCH`/`PUT :id` | DELETE: desliga a distribuição das caixas ligadas; fica fora mesmo com a D1 | assignment_policy.rb:28 |
| assignment_policies/inboxes | FORA 5 | — | o controller só tem `index`; a rota que funciona é `inboxes/:inbox_id/assignment_policy` | assignment_policies/inboxes_controller.rb:5 |
| agent_capacity_policies | PARTE | `POST`, `PATCH`/`PUT :id` | DELETE: nullify por update_all (3) | agent_capacity_policy.rb:23 |
| agent_capacity_policies/inbox_limits | LIBERAR | `POST`, `PATCH`/`PUT :id`; `DELETE*` | — | inbox_limits_controller.rb:9-20 |
| agent_capacity_policies/users | LIBERAR | `POST`; `DELETE*` | — (só a coluna da política; não toca papel nem função) | users_controller.rb:13-18 |
| inboxes/assignment_policies | LIBERAR | `POST inboxes/:inbox_id/assignment_policy`; `DELETE*` | — | inboxes/assignment_policies_controller.rb:15-28 |
| inbox_csat_templates | FORA 4 | — | cria modelo na Meta/Twilio; analisar é IA paga (3) | inbox_csat_templates_controller.rb:22-32 |
| csat_survey_responses | LIBERAR | `PATCH :id` (só a nota interna da avaliação) | — | csat_survey_responses_controller.rb:6 |
| crm/pipelines | PARTE | `POST`, `PATCH`/`PUT :id`, `POST :id/restore`, todos com `proibe: [status, is_default, position, metadata, meta_sync, google_sync]` (e `pipeline.*`) | DELETE arquiva e move cards em lote (2/3). `status` arquiva; `metadata` sobrescreve IA e metas; `meta_sync`/`google_sync` mandam eventos para fora | pipelines_controller.rb:90-189 |
| crm/pipeline_inboxes | PARTE | `POST crm/pipelines/:pipeline_id/inboxes` | DELETE: para de criar card pela caixa; fica fora mesmo com a D1 | pipeline_inboxes_controller.rb:14-27 |
| crm/inbox_settings | PARTE | `PATCH :inbox_id` com `proibe: [crm_enabled, subject_ai_mode]` (e `inbox_setting.*`) | `crm_enabled` expira sugestões com update_all (3); `subject_ai_mode` liga IA paga | inbox_setting.rb:45-68 |
| crm/service_schedules | LIBERAR | `POST`, `PATCH`/`PUT :id`; `DELETE*` | — | service_schedules_controller.rb:13-37 |
| crm/metas | LIBERAR | `PUT crm/metas` | — (pede `sales_value_view`) | metas_controller.rb:36 |
| crm/cards/contacts | LIBERAR (D7) | `POST crm/cards/:card_id/contact` | — (hoje dá 422 sem `Idempotency-Key`) | crm/cards/contacts_controller.rb:17 |
| crm/cards/restores | LIBERAR | `POST crm/cards/restore` com `proibe: [force]` | `force` restaura com outro card aberto do cliente e duplica | restorer.rb:99 |
| crm/contacts/relacoes | FORA 3 | — | SEM_DESFAZER (arquiva cards em lote) | acoes.rb:103 |
| relationships/configurations | FORA 5 | — | exige a revisão atual (2ª execução dá 409); cria atributo sem descrição; atributo já é liberado | relationships/configuration.rb:48-54 |
| relationships/values | FORA 5 | — | exige o valor anterior (409); `PATCH` de contato e empresa já grava o mesmo atributo | value_patch.rb:16 |
| nomes_de_etiquetas | PARTE | `PATCH`/`PUT :label_id` | DELETE: delete_all (3) | nomes_de_etiquetas_controller.rb:25 |
| notification_settings | FORA 1 | — | preferência pessoal do usuário; troca as listas inteiras | notification_settings_controller.rb:15-27 |
| notifications | PARTE | marcar lida e não lida, adiar; `DELETE*` | ler todas: update_all; apagar todas: job (3). Esconde alerta de quem ligou | notifications_controller.rb:19-44 |
| onboarding_progress | LIBERAR | pular e retomar passo | — (só administrador) | onboarding/progress.rb:106 |
| onboardings | FORA 1 | — | muda nome e idioma da conta; na nuvem cria caixa | onboardings_controller.rb:32-39 |
| portals | PARTE (D5) | `POST`, `PATCH`/`PUT :id`, arquivar, com `proibe: [custom_domain, slug, config.analytics]` (e `portal.*`) | DELETE e mandar instruções: SEM_DESFAZER. Apagar logo: purge (3). Domínio é infra, slug quebra links, analytics injeta script | portals_controller.rb:49-109 |
| articles | PARTE (D5) | `POST`, `PATCH`/`PUT :id` com `fixos: { status: draft }` e `proibe: [position, draft_title, draft_content]` (e `article.*`) | DELETE: nullify (3). Reordenar: update_column (3). Rascunho grava com update_columns (3) | articles_controller.rb:102; article.rb:43-174 |
| categories | PARTE | `POST`, `PATCH`/`PUT :id` com `proibe: [position, related_category_ids]` (e `category.*`) | DELETE: destroy_async (2/3). Reordenar muda a ordem do portal. `related_category_ids` troca a lista (5) | categories_controller.rb:24-36 |
| brand_kits | LIBERAR | `POST`, `PATCH`/`PUT :id` com `proibe: [logo_source_url, logo, remove_logo]` (e `brand_kit.*`); restaurar, padrão; `DELETE*` (só arquiva) | `logo_source_url` baixa URL de fora; `remove_logo` apaga arquivo em job | brand_kits_controller.rb:35-85 |
| branded_email_layouts | FORA 1 (D5) | — | muda o HTML em volta de todo e-mail ao cliente; fica até o Rodrigo decidir | email_template.rb:55 |
| upload | FORA 3 | — | arquivo no storage fora do desfazer; busca URL de fora | upload_controller.rb:22-40 |
| ctwa_tracked_links | PARTE | `POST`, `PATCH`/`PUT :id` | DELETE: cascade nos cliques (3) e quebra link em anúncio | schema.rb:4985 |
| contacts/notes | LIBERAR | `POST` (#2644, G19); `PATCH`/`PUT :id`; `DELETE*` | — (o #2644 deixa mudar e apagar de fora; ver seção 4) | contacts/notes_controller.rb:13-21 |
| contacts/opt_outs | FORA 4 | — | registrar corta mensagem ao cliente (como `blocked`, já proibido); apagar solta a recusa dele | opt_outs_controller.rb:13-31 |
| contacts/customers | LIBERAR | `POST contacts/:contact_id/customer`; `DELETE*` (volta a lead) | — | customers_controller.rb:7-12 |
| contacts/contact_inboxes | LIBERAR | `POST` com `proibe: [source_id, hmac_verified]` | `source_id` solto toma a identidade de outro contato | contact_inbox_builder.rb:61-89 |
| contact_inboxes | LIBERAR | `POST contact_inboxes/filter` (só procura, não grava) | — (útil só se o passo usar a resposta) | contact_inboxes_controller.rb:4 |
| companies/contacts | LIBERAR | `POST companies/:company_id/contacts`; `DELETE*` (só tira o contato da empresa) | — | contact_membership_service.rb:9-14 |
| conversations/participants | PARTE | `POST`; `DELETE*` (só os ids enviados) | `PATCH`/`PUT` trocam a lista inteira (5) | participants_controller.rb:19-27 |
| conversations/passar_para | FORA 5 | — | para pessoa já existe atribuir; para IA, `ia_assumir` | passar_para_controller.rb:14 |
| conversa_canal/pastas_do_email | FORA 3 | — | upsert/delete_all; Spam bloqueia o remetente | mover_para_pasta.rb:40-55 |
| autonomia/avisos | LIBERAR | `PATCH`/`PUT :id` (aviso de quem ligou, visto ou novo) | — (esconde aviso de quem ligou) | avisos_controller.rb:28 |
| autonomia/prospecting/lead_batches | PARTE | `POST leads/contacts` (até 30, na requisição) | descartar: job que tira etiqueta fora da requisição (3) | lead_discard.rb:7-35 |
| autonomia/prospecting/lead_consent_refusals | FORA 4 | — | consentimento do lead, propagado aos contatos, em job | lead_consent_refusals_controller.rb:9-10 |
| autonomia/prospecting/leads | PARTE | lead vira contato, vira card (um ou até 30), adotar dono | `PATCH` com `no_consent` grava recusa em job (3/4). Enriquecer e pesquisar: IA paga e site de fora (3). Conferir WhatsApp chama o WAHA (3). Segmento de campanha (4) | leads_controller.rb:18-135 |
| autonomia/prospecting/lists | PARTE | `POST` com `proibe: [metadata]` (e `list.*`); pôr lead na lista; `DELETE*` tirar lead | segmento de campanha (4); `metadata` guarda as etiquetas do segmento | lists_controller.rb:49-84 |
| autonomia/prospecting/saved_presets | LIBERAR | `POST`, `PATCH`/`PUT :id`; `DELETE*` | — | saved_presets_controller.rb:27 |
| autonomia/prospecting/searches | PARTE | `PATCH`/`PUT :id` (só funil e etapa) | criar: busca paga no Google e jobs (3). DELETE: nullify (3) | searches_controller.rb:52-75 |
| autonomia/prospecting/settings | LIBERAR | `PATCH`/`PUT` com `proibe: [cache_ttl_seconds]` (e `settings.*`) | cache menor = mais chamada paga ao Google | settings_controller.rb:20 |

### 5.6 Ações que faltam em recursos já liberados (lote B)

| Ação | Veredito | Guarda | Observação |
|---|---|---|---|
| `POST crm/cards`, `POST crm/cards/from_conversation` | FORA 5 | — | G4 é o passo nativo de card (#2641) |
| `POST crm/cards/:id/close` | no trem | `um_de: { result: [won, lost] }`, `proibe: [force]` | G25 (#2654) |
| `POST crm/cards/:id/link_contact`, `unlink_contact`, `link_conversation`, `unlink_conversation`, `restore` | LIBERAR | — | ligam e desligam na requisição (`cards_controller.rb:175-220`) |
| `POST crm/cards/:id/evaluate_ai`, `summarize` | FORA 3 | — | IA paga em job; os passos de IA já existem (5) |
| `POST crm/cards/:id/reset_auto_followup` | FORA 4 | — | rearma o follow-up automático da IA, que fala com o cliente |
| `POST contacts` | LIBERAR | `proibe: [avatar, avatar_url, blocked]` | G17. Cria na transação (`contacts_controller.rb:87-94`); a foto buscaria URL de fora |
| `POST companies` | LIBERAR | `proibe: [avatar]` | como o `PATCH` já liberado |
| `POST crm/stages/reorder` | FORA 5 | — | reordenar fica fora (já decidido no #2460) |
| `PATCH inbox_members` | FORA 5 | — | troca a lista inteira (já decidido) |
