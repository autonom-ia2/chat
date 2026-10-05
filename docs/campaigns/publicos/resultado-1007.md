# Resultado por campanha e Gestão de campanhas como visão geral (#1007)

Refs #990. Aceites do PRD cobertos: O1–O3, E1–E4, L8, K6 ("Ver no CRM"), G1–G4.
Tudo atrás de `CAMPAIGN_JOURNEY_ENABLED`; desligado, a Gestão de campanhas antiga abre como antes
e os endereços do Resultado levam às telas antigas (A5).

## 1. Telas

| tela | endereço | quem abre |
|---|---|---|
| Resultado | `/app/accounts/:id/campaigns/results/:channel/:campaignId` (`campaigns_journey_result`) | "Abrir" de cada linha de Campanha; clique numa linha da Gestão |
| Gestão de campanhas | `/app/accounts/:id/campaigns/management` (mesma rota `crm_campaign_management_index`) | menu Campanhas › Gestão de campanhas |

`channel`: `email`, `whatsapp_official`, `whatsapp_api`, `sms`. Chat ao vivo não tem resultado por
pessoa (#1008): a linha dele continua abrindo a tela antiga com `?legacy=1`. WhatsApp Oficial e SMS
usam o `display_id` da campanha (o `id` que o painel já usa); e-mail e WhatsApp API, o `id`.

Links antigos `…/campaigns/management?email_campaign=<id>` abrem o Resultado daquele e-mail.

## 2. API (só leitura, escopo da conta)

`GET /api/v1/accounts/:account_id/campaign_journey/results/:channel/:id`

```json
{ "payload": {
  "campaign": { "id": 5, "channel": "whatsapp_official", "name": "…", "status": "completed", "processing": false,
                "inbox": { "id": 1, "name": "…" }, "scheduled_at": "…", "template_name": "…",
                "audience": { "id": 3, "name": "…" } },
  "totals": { "audience": 14, "sent": 12, "delivered": 11, "read": 7, "failed": 1, "skipped": 1, "queued": 0, "replied": 3 },
  "filters": ["queued", "sent", "delivered", "read", "failed", "skipped", "replied"],
  "crm": { "source_id": "campaign:whatsapp:11", "enabled": true } } }
```

E-mail: `totals = { eligible, delivered, bounced, not_sent, replied }` (`CampaignJourney::EmailResultTotals`
+ Responderam) e `filters = ["replied"]`. `delivered`/`read` vêm `null` no canal que não registra.

`GET …/results/:channel/:id/recipients?status=&page=` → `{ rows, meta }`, 25 por página.
Linha: `{ id, contact: { id, name, phone_number (mascarado) }, status, message_content, error_code,
error_title, error_message, sent_at, delivered_at, read_at, failed_at, replied, conversation_display_id }`.
No e-mail só `status=replied` (quem respondeu; e-mail mascarado); a tabela completa do e-mail continua
sendo a dos relatórios de e-mail. `status` fora da lista → 422 `campaign_journey.invalid_filter`.

`GET …/results/:channel/:id/export?status=` → CSV (BOM, células seguras contra fórmula), streaming em lotes.
Mensagens: `name phone status replied sent_at delivered_at read_at failed_at error_code reason`.
E-mail: `name email status replied sent_at last_event_at reason`. Nome = primeiro nome + inicial do
último; telefone e e-mail mascarados; motivo por `EmailCampaigns::SafeErrorMessage` (sem e-mail nem
sequência longa de dígitos).

`GET …/campaign_journey/overview?days=7|30|90&channel=&page=` →
`{ period, channel, totals: { campaigns, reached, replied, deals: { cards, won } | null,
email_health: { hard_bounce_rate, complaint_rate, sent, bounce_limit, complaint_limit } | null },
campaigns: [{ channel, id, name, status, sent_at, sent, delivered, engagement: { kind, count, rate } | null,
replied, reply_rate, email: { click_rate, hard_bounce_rate, unsubscribe_rate } | null }], meta }`.

Permissões: `campaign_view` lê (Resultado, pessoas, Gestão); `campaign_manage` exporta (mesma regra do
export dos relatórios de e-mail). Sem a permissão → 401. Campanha de outra conta ou de outro canal → 404.
Flag desligada → 404. "Abrir conversa" (`conversation_display_id`) só vem para conversa que o agente
pode ver (`Conversations::PermissionFilterService`).

## 3. O que cada número quer dizer

- **E1, mensagens**: cada destinatário tem uma situação; Enviadas (sent+delivered+read) + Falharam +
  Puladas + Na fila = Público. Entregues inclui Lidas. A tela mostra a conta embaixo dos números.
  Diferença para a página antiga do WhatsApp: lá "Enviadas" contava quem tinha id da Meta, o que podia
  contar duas vezes um envio aceito que depois falhou; aqui conta pela situação.
- **E1, e-mail**: Entregues + Voltaram + Não enviados = Público elegível (api-999.md §5).
- **WhatsApp API**: pending/sending = Na fila; cancelled = Puladas (recusou, lead descartado, falta
  variável); o motor não recebe entregue nem lida, então esses números não aparecem.
- **SMS**: lê `campaign_recipients`. Até o #1004 registrar cada envio, campanha de SMS não tem linhas:
  a tela mostra zeros e um aviso ("ainda não tem registro por pessoa"), sem erro.
- **Responderam**: contatos cuja conversa ganhou a marca da campanha (#1002: mensagem recebida até 72h
  depois do envio). Lido do espelho `campaign_source_ids` das conversas, mesma sonda do filtro de
  campanha do Kanban. Conta todos os contatos da conta, mesmo de conversas que o agente não vê.
- **Viraram negócio no CRM** (Gestão): cards do CRM ligados (conversa principal ou
  `crm_card_conversations`) a uma conversa marcada pelas campanhas do período — os mesmos cards que o
  Kanban mostra filtrado pela campanha. "ganhos" = parte com `status = won`. `null` com o CRM desligado.
- **Pessoas alcançadas** (Gestão): soma de Entregues; no WhatsApp API, que não confirma entrega, Enviadas.
- **Campanha no período** (Gestão): e-mail que saiu do rascunho/agendamento, datado por `sent_at`
  (senão `scheduled_at`, senão `created_at`); WhatsApp Oficial/SMS com envio em andamento ou concluído,
  por `scheduled_at`; WhatsApp API não agendado, por `started_at` (senão `scheduled_at`). Até 500
  campanhas por período entram nos totais.
- **Saúde do e-mail** (Gestão): bounce permanente e reclamação das campanhas de e-mail do período sobre
  os aceitos pelo SES (mesmos denominadores da proteção; limites 5% e 0,1%).
- **E2**: com a campanha enviando (ou trabalho ativo de e-mail), a tela se atualiza a cada 15s com a aba
  visível; para ao sair da página.

## 4. Checklist O1 — Gestão de campanhas antiga → Resultado do e-mail

| item da Gestão antiga | onde fica agora |
|---|---|
| Filtro "campanha" (escolher uma) | o próprio Resultado (cada campanha tem o seu); a Gestão nova lista e abre |
| Filtro de situação da campanha (`EmailStatusFilter campaign`) | filtro Situação da lista Campanha; canal e período na Gestão |
| Botão Atualizar | "Atualizar" no topo do Resultado (+ atualização automática E2) |
| Ícone de ajuda das métricas (METRICS_HINT / DELIVERY_HINT) | texto embaixo dos números |
| KPI Enviados | ✓ |
| KPI Entregues (rótulo conforme a evidência) + "Detalhes" (confirmados pelo provedor / só aceitos) | ✓ mesmo rótulo e mesmo detalhe |
| KPI Abertos (aproximado) + taxa | ✓ |
| KPI Clicaram + taxa | ✓ |
| KPI Descadastros + taxa | ✓ |
| KPI Bounce permanente + taxa e base de envios | ✓ |
| KPI Reclamações + taxa e base | ✓ |
| KPI Temporários | ✓ |
| KPI Desconhecidos | ✓ |
| — | **novo**: Público elegível, Responderam, soma E1 |
| Status da importação (`RecipientImportStatus`) | ✓ (com recuperação para quem gerencia) |
| Saúde (`EmailCampaignHealth`: reavaliar, retomar, rever higiene, problemas) | ✓ mesmo componente; "problemas" leva à tabela filtrada |
| Gráfico ao longo do tempo (hora/dia) | ✓ mesmo componente |
| Cliques por link (único/total) | ✓ |
| Tabela de destinatários (busca, situação, problemas, detalhes com motivo, verificação prévia, tentativas, enviado, último evento, copiar e-mail, paginação) | ✓ mesmo componente `EmailRecipients` |
| Exportar CSV filtrado | ✓ dentro da tabela (sem máscara, `campaign_manage`, como antes) |
| Tabela comparativa entre campanhas (nome, situação, enviados, entregues, abertura, clique, bounce, descadastro) | Gestão nova: comparativo multicanal; no filtro E-mail ganha as colunas cliques, bounce permanente e descadastros |
| Paywall (relatórios de e-mail desligados) | ✓ mesmo texto no Resultado do e-mail |
| Estado vazio / carregando / erro | ✓ |
| — | **novo**: "Quem respondeu" com "Abrir conversa", "Baixar resultado" mascarado, faixa do CRM com "Ver no CRM", ações |

Ações (L8), no Resultado e no botão "⋯" das linhas de e-mail da lista Campanha: Editar e-mail (rascunho),
Pausar (enviando), Retomar (mesma regra `canResumeCampaign` da proteção), Duplicar (abre a cópia no editor),
Salvar como modelo (Meus modelos), Cancelar e Excluir rascunho (com confirmação; nada enquanto a importação
roda). Só `campaign_manage`. WhatsApp API mantém Pausar / Retomar / Cancelar no Resultado.

A página antiga do WhatsApp (`campaigns_whatsapp_analytics`) segue no endereço dela. O Resultado mantém
tudo dela (números, faixa "processando", gráfico de entrega, abas, mensagem gerada, motivo e código,
paginação) e ganha Responderam, "Abrir conversa" e exportação (O2).

## 5. Toques fora dos arquivos novos

| arquivo | linhas | motivo |
|---|---|---|
| `config/routes.rb` (Chatwoot) | +6 | leituras no namespace `campaign_journey` |
| `crowdin.yml` (Chatwoot) | +1 | catálogo novo fora do Crowdin |
| `i18n/locale/en/index.js`, `pt_BR/index.js` (Chatwoot) | +2 cada | registrar `resultJourney.json` |
| `config/fork_i18n.json` | +3 | registrar o catálogo do fork |
| `crm/crm.routes.js` (fork) | +2/−1 | Gestão abre o seletor (visão geral × página antiga) |
| `crm/pages/CrmKanbanPage.vue` (fork) | +7 | `?campaign_source_ids=` aplica o filtro de campanha ("Ver no CRM") |
| `CampaignJourney/campaignRows.js` (fork, #993) | rotas de "Abrir" + `source` da linha de e-mail | Abrir → Resultado |
| `journey/CampaignJourneyPage.vue` (fork, #993) | +12 | botão de ações do e-mail na linha |
| `journey/campaignJourney.routes.js` (fork) | +2 | registrar a rota do Resultado |
| `CampaignJourney/journeySidebar.js` (fork) | +2/−1 | Resultado acende "Campanha" no menu |
| `campaign_journey/campaign_marks.rb` (fork, #1002) | `source_id_for` | id da marca num lugar só |

Nenhuma migration, nenhuma coluna nova.

## 6. Verificação local

Banco `chatwoot_dev_1007` com dados sintéticos (sem envio real), Rails 3997, Vite 3047, Redis db 11, sem
Sidekiq. Capturas em `tmp/screenshots-1007/` (não versionadas): Resultado do e-mail e do WhatsApp e
Gestão em 1440/1280/1024/768/390, claro e escuro; WhatsApp API, SMS e lista em 1440 e 390.
