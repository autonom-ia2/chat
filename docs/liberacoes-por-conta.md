# Liberação de funcionalidade por conta

Funcionalidade atrás de flag tende a ficar ligada só na conta piloto: entra, é testada numa conta e ninguém volta para
liberar nas outras. Este documento é o catálogo das flags (de quem é cada uma e se pode ser ligada) e o registro do
que está em piloto. A regra de processo está em [processo-de-release.md](processo-de-release.md#pedido-de-vaga):
todo PR declara a "Liberação" e a Orquestração confere em produção depois do deploy.

## Como conferir

```sh
ruby .github/scripts/feature_flags_por_conta.rb [flag ...] > "$TMPDIR/flags.sql"   # Ruby do projeto (rbenv)
```

O SQL abre `BEGIN READ ONLY`, conta as contas ativas (`status = 0`) com cada flag e lista os IDs. Roda pelo `psql`
dentro do `chatwoot-web` via SSM, nas duas stacks (comandos em [prospeccao_e0_rollout_rollback.md](prospeccao_e0_rollout_rollback.md)).
Nunca por `rails runner`.

De onde vem o estado de uma conta nova (`before_create`):

- `Featurable#enable_default_features` liga o que estiver `enabled` no `ACCOUNT_LEVEL_FEATURE_DEFAULTS`
  (InstallationConfig), que segue o `enabled` do `config/features.yml` só para itens novos: o ConfigLoader do deploy
  não sobrescreve o valor já gravado. Mudar o padrão de uma flag existente é por migration com
  `FeatureFlagRollout.padrao!` (`lib/feature_flag_rollout.rb`).
- `Autonomia::AccountProvisioningDefaults` depois põe na coluna `feature_flags` um número fixo como base
  (`AUTONOMIA_DEFAULT_ACCOUNT_FEATURE_FLAGS`, padrão `8950126033336532983`) e **religa por cima os padrões por nome**
  do `ACCOUNT_LEVEL_FEATURE_DEFAULTS`, menos as `chatwoot_internal` (#1175). Não toca na `feature_flags_ext_1`.
  Antes do #1175 o número apagava tudo o que o padrão por nome tinha ligado nessa coluna (era o caso do `companies`).
- Desde o #1175 (migration `20261025100000`) a conta nova nasce com as que, segundo a Orquestração em 13/10/2026,
  já estão ligadas em todas as contas: `data_import`,
  `delayed_automations`, Relacionamentos (as três), `meta_ads_hub`, `email_template_import`,
  `whatsapp_templates_journey`, `crm_configurar_caixas` e `companies`, além de `campaign_open_window_text`
  (`20261024100001`) e das que já eram padrão. Antes, a conta 23 do autonomia (criada em 08/10) nasceu com o Instagram
  assistido e sem Relacionamentos nem Anúncios da Meta.
- Super Admin → liga e desliga por conta.
- Lista de contas por variável de ambiente (`INSTAGRAM_TESTER_ALLOWED_ACCOUNT_IDS` e afins) → não aparece no SQL;
  conferir a variável.

## Catálogo

### Nossas (criadas pelo fork)

| Flag | Origem |
|---|---|
| `relationships_attributes`, `relationships_company_media`, `relationships_navigation` | #760 (Relacionamentos) |
| `instagram_assisted_onboarding` | Instagram assistido (#995) |
| `meta_ads_hub` | Anúncios da Meta (#1100) |
| `email_template_import` | Importar modelo de e-mail (#1099) |
| `crm_booking_v2` | Agendamento WhatsApp-first (#1187): página de agendamento sem Google/Microsoft, link por cliente, avisos no WhatsApp, Resultados, IA marcando horário e "+ Novo › Reunião" pela agenda (#1265). Também exige `CRM_CALENDAR_MEETINGS_ENABLED=true` na stack (ligado nas duas). Desligada = página e gaveta antigas, sem deploy |
| `customer_base` | Base de clientes (#1240): leitura nova da planilha na importação de contatos e em Públicos (#1246). Desligada = leitura igual ao `main`, provado linha a linha em `docs/base-de-clientes/BATERIA-F0.md` |
| `whatsapp_templates_journey` | Modelos do WhatsApp (#1320/#1330): criar, editar, apagar, duplicar e subir mídia de modelos na Meta pela API nova. Desligada = essas escritas respondem 404 sem chamar a Meta; listar e "onde está em uso" seguem abertos. Bit 16 da `feature_flags_ext_1` |
| `crm_configurar_caixas` | Caixas no CRM (#1149): a tela CRM → Caixas no CRM no lugar da gaveta Configurar caixas — o que chega em cada caixa, quem cuida de quê e o que o sistema faz sozinho — e a API `crm/caixas`. Desligada = gaveta antiga e a API responde 404. Antes de ligar numa conta grande, repetir o EXPLAIN da lista restrita na maior conta. Bit 17 da `feature_flags_ext_1` |
| `campaign_open_window_text` | Conversa aberta na campanha (#1335): na campanha do WhatsApp oficial, quem falou com a caixa nas últimas 24 h recebe uma mensagem escrita (sem modelo), com a ajuda para escrever; a janela é conferida de novo em cada envio e o 131047 cai para o modelo. Ligada em todas as contas e nas novas (migration `20261024100001`). Desligada = modelo para todos e a API `campaign_journey/conversa_aberta` responde 404. Bit 18 da `feature_flags_ext_1` |

### Do Chatwoot, oferecidas aos clientes

`companies`, `data_import`, `api_and_webhooks`, `branded_email_templates`, `delayed_automations`,
`whatsapp_manual_transfer`, `whatsapp_reconfigure` (marcada `deprecated` no Chatwoot), `whatsapp_embedded_signup_inbox_creation`, `audit_log_ip_address`,
`channel_voice`, `csat_review_notes`, `ip_lookup`, além das que já estão em todas as contas.

### Do Chatwoot, desligadas por decisão

- **Captain** (`captain_integration`, `captain_integration_v2`, `captain_document_auto_sync`): IA do Chatwoot
  Enterprise, `premium`. O fork tem os Agentes Autonom.ia no lugar e não toca no Captain
  ([autonomia_agents_plan.md](autonomia_agents_plan.md)). Fica de fora: análise de template do WhatsApp com IA e os
  medidores de crédito do Captain no Billing. `CAPTAIN_OPEN_AI_API_KEY` é só a chave reserva da IA do CRM e não liga o
  Captain.
- Demais `premium` sem uso: `advanced_search`, `saml`, `sla`, `custom_tools`, `advanced_assignment`,
  `conversation_required_attributes`.

### Do Chatwoot, internas: não ligar

Marcadas `chatwoot_internal` no `features.yml`: chaves da operação da nuvem do Chatwoot.

- **`crm_v2`**: com ela, contatos, busca, filtros, exportação e o resumo de Relacionamentos mostram só
  `contact_type = 'lead'` (`Contact.resolved_contacts`). Desde o #1166 o lead vira cliente no ganho da venda; ligar
  `crm_v2` esconderia os clientes.
- `search_with_gin`, `advanced_search_indexing`, `inbox_view`, `reply_mailer_migration`, `unread_count_for_filters`,
  `captain_v1_action_classifier`, `help_center_embedding_search`, `shopify_integration`, `contact_chatwoot_support_team`,
  `conversation_unread_counts`.

## Estado em 09/10/2026

Contas ativas: hub2you 15 (1, 3, 5, 6, 16, 17, 18, 27, 40, 43, 44, 45, 47, 48, 50); autonomia 7 (1, 2, 16, 17, 18,
20, 23). Só as flags ligadas em parte das contas.

### autonomia

| Flag | Ligadas | Sem a flag |
|---|---|---|
| `email_template_import` (nossa) | 0/7 | todas |
| `instagram_assisted_onboarding` (nossa) | 2/7 | 2, 16, 17, 18, 20 |
| `meta_ads_hub` (nossa) | 5/7 | 16, 23 |
| `relationships_company_media` (nossa) | 5/7 | 16, 23 |
| `relationships_attributes`, `relationships_navigation` (nossas) | 6/7 | 23 |
| `whatsapp_reconfigure` | 1/7 | todas menos 16 |
| `branded_email_templates` | 2/7 | 16, 17, 18, 20, 23 |
| `audit_log_ip_address` | 3/7 | 16, 17, 20, 23 |
| `api_and_webhooks` | 4/7 | 16, 17, 18 |
| `data_import` | 4/7 | 16, 18, 23 |
| `companies`, `delayed_automations` | 5/7 | 16, 23 |
| `whatsapp_manual_transfer`, `whatsapp_embedded_signup_inbox_creation` | 6/7 | 23 |

### hub2you

| Flag | Ligadas | Sem a flag |
|---|---|---|
| `instagram_assisted_onboarding` (nossa) | 2/15 | todas menos 16 e 18 |
| `meta_ads_hub`, `email_template_import` (nossas) | 14/15 | 5 |
| `channel_voice`, `csat_review_notes`, `data_import` | 14/15 | 5 |
| `api_and_webhooks` | 14/15 | 3 |
| `branded_email_templates` | 14/15 | 50 |
| `ip_lookup` | 14/15 | 1 |

`crm_v2` e o Captain estão desligados em todas as contas das duas stacks, como deve ser.

## Pilotos em aberto

Cada linha precisa de uma decisão do Rodrigo: liberar para todas, manter em piloto até uma data, ou é proposital
(conta de teste, conta sem o canal). A Orquestração traz a lista quando a data vence.

| Flag | Stack | Contas | Decisão | Até |
|---|---|---|---|---|
| `instagram_assisted_onboarding` | as duas | hub2you 16, 18; autonomia 1, 23 | pendente | |
| `email_template_import` | autonomia | nenhuma | pendente | |
| `customer_base` (dona: sessão Base de Clientes, #1240) | hub2you | 16 | piloto | 24/10/2026 (proposta) |
| `crm_booking_v2` (dona: sessão Agendamento CRM, #1187) | as duas | hub2you 1 (desde 11/10/2026) e 16 (desde 10/10/2026); autonomia 1 (desde 11/10/2026) | piloto: Hub2You 1 e 16 + Autonom.ia 1. **Condição para ligar em contas novas: #1303 no ar** (teto global no desenho da prévia do link, conferência do tipo real das logos, inclusive a de fundo escuro, e da foto; identidade salva validada). Consentimento decidido pelo Rodrigo em 11/10 (#1271): marcação pela equipe = o cliente combinou o horário com a atendente; "Avisar o cliente" vem ligado com a frase de orientação, o aviso diz quem marcou e o motivo fica registrado na reunião (`metadata.notice_basis`). Aviso por WAHA só em conta com o app da WAHA instalado (definições `waha_whatsapp_*` presentes); o teste real do #1275 é na conta 16 (HUBBER COMUNIDADE); o fallback por telefone na resposta não tem prova com envio real. Falta o teste do Rodrigo pelo playbook para decidir a liberação nas demais contas | |
| flags que faltam na conta 23 do autonomia | autonomia | 23 | pendente: a causa (conta nova sem as flags do fork) foi corrigida no #1175 só para contas novas; conferir a 23 em produção | |
| flags que faltam na conta 5 do hub2you | hub2you | 5 | pendente | |
