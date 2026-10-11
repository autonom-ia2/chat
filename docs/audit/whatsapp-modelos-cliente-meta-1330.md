# Modelos WhatsApp B (#1330, épico #1320): cliente Meta, perfil e "onde está em uso"

Só backend. Tela (D), Jev (E) e webhook (I) ficam fora.

## Decisões

- **WABA sempre a da caixa** (`channel.waba_id`) e token da caixa (`template_access_token`). Nenhum parâmetro escolhe
  WABA. O id do modelo só vale se estiver na lista sincronizada da caixa, e o cliente ainda confirma na Meta, pela lista
  da WABA da caixa, antes de editar ou apagar (um token serve caixas de 4 contas em produção).
- **Versão da Graph do cliente novo:** `WHATSAPP_API_VERSION` (GlobalConfig, padrão v22.0), a mesma do
  `FacebookApiClient`. O sync segue na URL do Chatwoot (v14.0, que a Meta atende pela versão mais antiga em vigor).
- **Sync com `fields=`** por prepend com nome próprio (`Whatsapp::Templates::SyncFields`), em initializer com
  `prepend_once`; fica à frente do módulo de voz do enterprise, que não mexe no sync. Os campos cobrem todos os leitores
  atuais de `message_templates`. Se a Graph recusar um campo (400, código 100), aquele sync segue sem `fields=` e avisa
  no log, em vez de parar de atualizar a lista.
- **Estado do fork na tabela `whatsapp_template_profiles`** (migration 20261020100000, só aditiva). Sem perfil, o modelo
  aparece pelo nome técnico: nada que funciona hoje depende do perfil.
- **Modelos do sistema** (avisos do agendamento por `Catalog.names`, `chat2you_resumo_anuncios`,
  `chat2you_alerta_anuncio`, `customer_satisfaction_survey_*`): não são criados, alterados nem apagados pela API nova;
  duplicar pode.
- **Permissões:** `whatsapp_templates_view` e `whatsapp_templates_manage` (pedido da orquestração; a issue citava
  `campaign_*`). A matriz e o front ficam com a D.
- **"Onde está em uso":** campanhas abertas, avisos do agendamento e follow-ups pendentes/atrasados. Follow-up só via
  `policy_scope(::Crm::Card)`; campanha exige `campaign_view` e página `agendamento_view`. O que a pessoa não vê vira só
  `uso_oculto: true`. Apagar ou alterar conteúdo com qualquer uso devolve 422.

## Efeito esperado no deploy

Pedir `fields=` muda o payload do sync: no primeiro sync depois do deploy, a cache de inbox invalida uma vez em todas as
contas com caixa Cloud.

## Pendências

- `WHATSAPP_APP_ID` vem do GlobalConfig; sem ele, o upload de mídia responde `app_not_configured`. Não confirmado se a
  Resumable Upload API aceita o token da caixa (system user da Embedded Signup): testar com uma caixa real.
- Os campos `correct_category`, `previous_category` e `quality_score` não foram conferidos contra a Graph real.
