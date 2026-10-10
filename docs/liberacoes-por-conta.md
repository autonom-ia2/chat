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
  (InstallationConfig), que segue o `enabled` do `config/features.yml`. As flags do fork nascem `enabled: false`, menos `instagram_assisted_onboarding`.
- `Autonomia::AccountProvisioningDefaults` depois **sobrescreve a coluna `feature_flags` inteira** com um número fixo
  (`AUTONOMIA_DEFAULT_ACCOUNT_FEATURE_FLAGS`, padrão `8950126033336532983`). Não é uma lista de nomes, e não toca na
  coluna `feature_flags_ext_1`.
- **Todas as flags nossas estão em `feature_flags_ext_1`.** Então só chega a uma conta nova a que estiver `enabled`
  no `ACCOUNT_LEVEL_FEATURE_DEFAULTS`. Conferido em produção em 09/10/2026, nas duas stacks: Relacionamentos,
  `meta_ads_hub`, `email_template_import`, `delayed_automations` e `companies` estão `enabled: false`; só
  `instagram_assisted_onboarding` está `true`. Por isso a conta 23 do autonomia (criada em 08/10) nasceu com o
  Instagram assistido e sem Relacionamentos nem Anúncios da Meta. A correção (decidir quais flags toda conta nova
  recebe, e por onde) fica em Issue própria.
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
| `customer_base` | Base de clientes (#1240): leitura nova da planilha na importação de contatos e em Públicos (#1246). Desligada = leitura igual ao `main`, provado linha a linha em `docs/base-de-clientes/BATERIA-F0.md` |

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
| flags que faltam na conta 23 do autonomia | autonomia | 23 | pendente (conta nova não recebe flag de `feature_flags_ext_1`) | |
| flags que faltam na conta 5 do hub2you | hub2you | 5 | pendente | |
