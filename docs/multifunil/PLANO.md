# Multifunil — plano de entrega

**Data:** 08/10/2026 · **Base de código lida:** `origin/main` de 07/10 (`ca7e158040`)
**Mockup aprovado:** `docs/multifunil/jornada.html`
**Épico:** autonom-ia2/chat#1140 · PRs 1–11 = Issues #1141–#1151 · bug do merge = #1152
**Substitui:** o PRD e o plano técnico do ChatGPT (67–122 dias). Eles acertavam o diagnóstico, mas pecavam por excesso de engenharia.

## 1. O que vamos entregar

O cliente percorre um ciclo: entra como **lead**, vira **cliente** e volta com novos pedidos (outra cotação, um sinistro, uma 2ª via). Cada pedido é um **card** no funil certo, com seu responsável. Tudo acontece na mesma conversa, e cada pessoa vê só o que é dela.

Vale para qualquer ramo. O que muda de uma conta para outra são os funis e o texto "Quando usar", nunca o código.

## 2. Regras decididas

| # | Regra |
|---|---|
| R1 | Contato e conversa podem ter **vários cards**, inclusive vários no mesmo funil. |
| R2 | **O funil do card libera a visão da conversa.** O agente só vê uma conversa da caixa se ela tiver card num funil dele, de qualquer dono, aberto ou encerrado. |
| R3 | **Sem funil** (triagem): só quem tem esse item vê e recebe conversas ainda sem card. |
| R4 | Por pessoa e por caixa: **Todas** (todas as conversas dos funis dela) ou **Só as suas** (as que atende, participa ou de que é dona do card). |
| R5 | Padrão de quem já está na caixa: **Todos os funis, Todas**. Nada muda até o admin mexer. |
| R6 | Caixa hoje em "Agente vê apenas atribuídos" migra para **Só as suas** em cada agente que não é admin. Ninguém ganha nem perde visão na troca. |
| R7 | Caixa com mais de um funil não salva se ninguém tiver "Sem funil": conversa nunca fica invisível. Admin sempre vê tudo. |
| R8 | **Distribuição:** o rodízio de cada funil é formado por quem acessa aquele funil na caixa. |
| R9 | Com mais de um funil, o card nasce **quando o assunto é identificado** (IA ou pessoa), não num funil padrão fixo. Cada card começa na primeira etapa do seu funil. Caixa com um funil só: igual a hoje. |
| R10 | **Saída da triagem:** quando nasce o primeiro card, a conversa vai para o dono dele. Depois disso, card novo **não transfere**: o dono entra como **participante**. |
| R11 | Caixa **sem atribuição automática**: o card nasce sem dono e a conversa fica em "Não atribuídas" para quem acessa o funil. Quem assume vira atendente e dono do card em foco. |
| R12 | Caixa com **agente IA**: o agente faz a triagem e o card nasce com responsável "Agente IA". A passagem para humano usa a regra que já existe por funil e etapa; o rodízio é o de R8. Se o agente não identificar o assunto, a conversa vai para a triagem. |
| R13 | Cliente com card aberto que abre **conversa nova** (outro canal): ela é ligada ao card e vai para o dono, sem passar pela triagem. |
| R14 | Funil tem **tipo**: Comercial (ganho/perdido) ou Atendimento (resolvido/cancelado). Atendimento nunca conta como venda nem dispara conversão. |
| R15 | **Ganho** num funil Comercial com a opção ligada transforma o contato em **Cliente** (o campo `contact_type` já existe). Também dá para marcar à mão. |
| R16 | **Configuração única** em CRM → Configurar caixas: funis da caixa, criação de cards e quem vê o quê, com um único botão Salvar. O Editar funil só mostra onde o funil está ligado. |
| R18 | **Card do Kanban:** empresa em destaque, depois nome; o **assunto** aparece num selo próprio (sem a palavra "Negócio"). Sem empresa: nome e o selo do assunto. O assunto é o título do card: a IA define quando identifica; no card criado à mão, a pessoa escreve (a IA pode sugerir); sempre editável. Enquanto não há assunto, o selo não aparece. |
| R17 | A IA (Jev + IA) **sugere ou cria** conforme o modo da caixa. Na dúvida, mantém o que está e avisa. Nunca usamos regex nem lista de palavras para interpretar o cliente. |

## 3. Fora do escopo

- Esconder mensagens dentro de uma mesma conversa. Quem vê a conversa vê todas as mensagens dela.
- Hierarquia gestor → subordinados. A gestora é configurada com "Todos os funis" nas caixas dela.
- Dois bots respondendo o cliente ao mesmo tempo.
- Fila durável de efeitos (outbox), vínculo por mensagem com revisões, os 180 testes do plano antigo e novo microserviço.

## 4. Mudanças de dados

Todas aditivas, exceto a remoção do índice. Nada de tabela paralela de "processo": o card continua sendo o processo.

| Mudança | Para quê |
|---|---|
| Remover `idx_crm_cards_unique_open_conversation` | Permitir vários cards abertos na conversa. Sai só **depois** do código plural no ar. |
| `crm_card_conversations.focused_at` | Assunto atual: o card com o valor mais recente. |
| `messages.content_attributes['crm_card_id']` | Saber a qual assunto pertence cada mensagem. Usa coluna que já existe, sem tabela nova. |
| Nova `crm_inbox_agent_accesses` (conta, caixa, usuário, `all_pipelines`, `triage`, `own_only`) | R2–R5. **Sem linha = Todos os funis + Todas**, que é o comportamento de hoje. |
| Nova `crm_inbox_agent_pipelines` (acesso, funil) | Os funis da pessoa naquela caixa, com chave estrangeira real. |
| `crm_pipelines.kind`, `promotes_contact`, `when_to_use` | R14, R15 e o texto que a IA lê. |
| `crm_cards.status`: + `resolved` (4) e `cancelled` (5) | R14. Os valores 0–3 atuais não mudam. |
| `crm_cards.custom_attributes` + novo `attribute_model` de card | Campos próprios de cada card (placa do Onix ≠ placa do HB20). |
| `crm_inbox_settings.default_pipeline_id` / `visibility_mode` | Continuam valendo para caixa com um funil e como origem da migração R6. Não são apagados. |

## 5. Onde o acesso precisa entrar

Este é o ponto crítico do projeto. Uma regra de visão (R2–R4), aplicada por um serviço único, `Crm::Access::ConversationScope`, em todos os lugares onde hoje a regra é "membro da caixa":

| Lugar | Arquivo | Observação |
|---|---|---|
| Lista, filtros, contadores, ações em massa, conversas do contato | `app/services/conversations/permission_filter_service.rb` (`accessible_conversations`) | Ponto único. A versão EE com funções personalizadas também passa por aqui. |
| Abrir conversa por link ou API | `app/policies/conversation_policy.rb` (`inbox_access?` / `team_access?`) | Quem acessa pelo time também precisa respeitar o funil. |
| Busca | `app/services/search_service.rb` (`accessable_inbox_ids`) | |
| Notificações de conversa nova e passagem para humano | `app/listeners/notification_listener.rb` (`inbox.members`) | |
| Tempo real (WebSocket) | `app/listeners/action_cable_listener.rb` (`inbox.members`) | **Vazamento** se ficar de fora: a mensagem chega no navegador de quem não deveria ver. |
| Cards no CRM (Kanban, lista, calendário) | `app/services/crm/cards/visible_scope_query.rb`, `crm/conversations/visibility.rb`, `crm/cards/broadcaster.rb` | Passa a usar o mesmo serviço. |
| Cache de contadores | `app/services/conversations/unread_counts/*` | Criar card muda quem vê: o cache precisa ser invalidado. |

Agente com "Todos os funis" e "Todas" não passa pelo filtro novo: zero mudança e zero custo para quem não configurar.

## 6. Sequência de entrega

Cada PR entra na `main` sem mudar o comportamento de quem não configurar (R5). As entregas seguem pelo trem de release e pela fila de merge.

**Piloto:** conta **16** (chat.hub2you.ai), funil **Comercial**, que tem dois assuntos de venda: **Agentes de IA** e **Chat2You**. É exatamente o caso de **dois cards no mesmo funil, em momentos diferentes**. O teste acontece só no Chat2You (Hub2You); a Autonomia é espelho do mesmo código e segue junto. Como o piloto tem um funil só, a ordem começa pelo que ele usa: vários cards no mesmo funil. O acesso por funil vem depois.

### Entrega 1 — vários cards no mesmo funil (piloto conta 16, manual) · ~2 a 3 semanas

| PR | Conteúdo | Depende de |
|---|---|---|
| **1. Núcleo plural** | O finder devolve lista + assunto atual. Os **8 consumidores** param de pegar "o card da conversa": `CardSyncer`, `cards_controller` (`by_conversation`, `card_stages`), `FromConversationHandler` (passa a criar card novo quando pedido, inclusive no mesmo funil), `AutomationRules::CrmConditions/CrmActions`, `Decisores::Estado/Aplicador`. Dedup não reaproveita card quando é pedido um novo. Sync atendente → dono só no card em foco. `responsible_descriptor` com o dono do card primeiro. `focused_at`. | — |
| **2. Migration do índice** | Remove o índice único. Só depois do PR 1 em produção. | PR 1 no ar |
| **3. Tela da conversa** | Painel "Assuntos", "Assunto atual", modal "Novo assunto", vários selos na lista, "Este envio fica no assunto". **O card do Kanban não muda** (R18). | PR 1 |
| **4. Tipo de funil e ciclo do cliente** | `kind`, `resolved`/`cancelled`, `promotes_contact` → `contact_type: customer`, "Marcar como cliente". | — |

### Entrega 2 — a IA organiza · ~3 semanas

| PR | Conteúdo |
|---|---|
| **5. Identificar o assunto** | Jev decide a cada mensagem "identificou / ainda não"; IA maior só na dúvida ou com mais de um assunto. Lê o "Quando usar" de cada funil e entende **dois assuntos no mesmo funil** (Agentes de IA e Chat2You no Comercial). Modos Sugerir e Automático por caixa. Roda em job (teto de 15 s do rack-timeout). |
| **6. Campos do card** | `custom_attributes` no card. O extrator e a cotação do agente gravam no card em foco. |
| **7. IA e follow-up por card** | Etapa, atributos e follow-up só no card em foco. Trava: um envio automático por conversa por vez. |

### Entrega 3 — acesso por funil e distribuição · ~3 a 4 semanas

| PR | Conteúdo | Depende de |
|---|---|---|
| **8. Acesso por funil (backend)** | Tabelas, `Crm::Access::ConversationScope`, os 7 pontos da seção 5, migração R6, validação R7, matriz de testes de acesso. | PR 1 |
| **9. Tela CRM → Configurar caixas** | Três blocos e um Salvar. Editar funil vira atalho. Aviso em Caixa → Agentes. `PipelineLinkSyncer` deixa de desligar os outros funis. | PR 8 |
| **10. Distribuição** | Rodízio por funil (R8), triagem e saída da triagem (R3, R10), participantes, caixa sem atribuição automática (R11), agente IA (R12), conversa nova de cliente (R13), filtro Funil e aba Participando na lista. | PR 8 |
| **11. Números** | Taxa de ganho só com funis Comerciais, carga pelo dono do card, conversão só por ganho Comercial. | PR 4 |

A Entrega 3 precisa de uma conta com **mais de um funil** para o piloto do acesso: definir quando chegarmos lá.

### Pode sair já, separado

- **Bug atual:** `ContactMergeAction` não move os cards para o contato que fica. Eles ficam presos ao contato apagado.

## 7. Como validamos

- **Matriz de acesso:** agente × funil × Todas/Só as suas × triagem × atendente/participante. Cada um dos 7 pontos da seção 5 tem teste verificando quem vê e quem **não** vê, incluindo o WebSocket.
- Testes de cada PR na CI. Cenários do mockup como testes de ponta a ponta: lead → cliente, cliente cota mais, triagem, sem atribuição automática, agente IA.
- Revisor independente antes de cada merge. Teste de fumaça em produção depois de cada deploy, na conta piloto.
- Antes de ligar a IA (PR 8): medir o custo por conversa na conta piloto.

## 8. Riscos

| Risco | Como tratamos |
|---|---|
| Lista de conversas mais lenta | O filtro só roda para agente com acesso restrito. Usar `EXISTS` com índice por conversa e funil. Medir com `EXPLAIN` na conta piloto antes de abrir para outras. |
| Vazamento por um caminho esquecido | Serviço único + matriz de testes nos 7 pontos, incluindo tempo real e busca. |
| Contadores errados | Invalidar o cache quando nasce ou muda um card. |
| Rollback depois de existirem vários cards | Não recriar o índice. O recuo é desligar a configuração ou a IA da caixa; o código plural fica. |
| Merge = deploy nas duas instalações | Tudo nasce desligado (R5). Migrações aditivas; a do índice vai sozinha. |

## 9. Pendências

1. Conta para o piloto do acesso por funil (Entrega 3): precisa de mais de um funil.
