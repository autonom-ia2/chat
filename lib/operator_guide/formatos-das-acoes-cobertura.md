# Formato das ações do Guia — cobertura

Gerado por `bundle exec rails autonomia:guia:formatos` a partir do código (#900). Não edite à mão.
"Completa" quer dizer que o nome de todo campo aceito saiu do código com segurança.

| | Ações |
|---|---|
| No catálogo | 498 |
| Sem corpo | 132 |
| Com corpo | 366 |
| Com corpo e formato completo | 222 (60,7%) |
| Com corpo e formato incompleto | 144 |

## Incompletas por motivo

Uma ação pode ter mais de um motivo.

| Motivo | Ações |
|---|---|
| leitura crua sem tipo | 130 |
| aceita qualquer campo | 5 |
| params inteiro repassado | 9 |
| lê o corpo cru | 2 |
| termina em código de fora do repositório | 1 |
| a rota não tem a action | 2 |

## Ações incompletas

- `DELETE assignment_policies/:assignment_policy_id/inboxes/:id` — a rota não tem a action no controller: a chamada dá erro
- `DELETE autonomia/agents/:id/avatar` — leitura crua sem tipo: avatar
- `DELETE conversations/:conversation_id/participants` — leitura crua sem tipo: user_ids
- `DELETE crm/stages/:id` — leitura crua sem tipo: target_stage_id
- `DELETE inbox_members` — leitura crua sem tipo: user_ids
- `DELETE inboxes/:inbox_id/conference` — leitura crua sem tipo: call_sid
- `DELETE portals/:portal_id/articles/bulk_actions/delete_articles` — leitura crua sem tipo: ids
- `DELETE teams/:team_id/team_members` — leitura crua sem tipo: user_ids
- `PATCH agents/:id` — leitura crua sem tipo: custom_role_id
- `PATCH autonomia/agents/:id/avatar` — leitura crua sem tipo: avatar
- `PATCH branded_email_layout` — leitura crua sem tipo: branded_email_layout
- `PATCH contacts/:id` — leitura crua sem tipo: include_contact_inboxes
- `PATCH conversations/:conversation_id/draft_messages` — leitura crua sem tipo: draft_message.message
- `PATCH conversations/:conversation_id/participants` — leitura crua sem tipo: user_ids
- `PATCH crm/pipelines/:id` — leitura crua sem tipo: goal, google_sync, meta_sync
- `PATCH crm/pipelines/:pipeline_id/ai_settings` — aceita qualquer campo (permit! em app/controllers/api/v1/accounts/crm/ai_settings_controller.rb:58)
- `PATCH crm/stages/:id` — leitura crua sem tipo: funnel_stage_type
- `PATCH inbox_members` — leitura crua sem tipo: user_ids
- `PATCH inboxes/:id` — leitura crua sem tipo: branded_email_layout
- `PATCH onboarding` — leitura crua sem tipo: onboarding_step
- `PATCH portals/:id` — leitura crua sem tipo: blob_id, portal.config.analytics
- `PATCH portals/:portal_id/articles/bulk_actions/update_category` — leitura crua sem tipo: category_id, ids
- `PATCH portals/:portal_id/articles/bulk_actions/update_status` — leitura crua sem tipo: ids
- `PATCH relationships/:entity/:id/values` — leitura crua sem tipo: field
- `PATCH relationships/configuration` — leitura crua sem tipo: configuration
- `PATCH teams/:team_id/team_members` — leitura crua sem tipo: user_ids
- `POST actions/contact_merge` — leitura crua sem tipo: base_contact_id, mergee_contact_id
- `POST agents` — leitura crua sem tipo: custom_role_id
- `POST agents/bulk_create` — leitura crua sem tipo: emails
- `POST assignment_policies/:assignment_policy_id/inboxes` — a rota não tem a action no controller: a chamada dá erro
- `POST autonomia/agents/:agent_id/sources` — leitura crua sem tipo: descriptor.kind, file
- `POST autonomia/agents/:agent_id/tools/:id/test` — leitura crua sem tipo: params
- `POST autonomia/agents/:id/suggest` — leitura crua sem tipo: history, message
- `POST autonomia/agents/:id/test` — leitura crua sem tipo: history, images, message
- `POST autonomia/build_threads` — leitura crua sem tipo: client_message_id, force_close, image_signed_ids, message, no_materials, type, with_knowledge
- `POST autonomia/build_threads/:id/messages` — leitura crua sem tipo: client_message_id, force_close, image_signed_ids, message, no_materials
- `POST autonomia/builder_images` — leitura crua sem tipo: file
- `POST autonomia/conversations/:conversation_id/copilot` — leitura crua sem tipo: draft, instruction, task, tone
- `POST autonomia/conversations/:conversation_id/copilot/chat` — leitura crua sem tipo: agent_id, message
- `POST autonomia/decisores/:id/exemplos` — leitura crua sem tipo: conversation_id, resposta
- `POST autonomia/decisores/:id/teste` — leitura crua sem tipo: conversation_ids
- `POST autonomia/guide/acoes/executar` — leitura crua sem tipo: dados
- `POST autonomia/guide/acoes/preparar` — leitura crua sem tipo: acao, dados
- `POST autonomia/guide/arquivos` — leitura crua sem tipo: file
- `POST autonomia/guide/chat` — leitura crua sem tipo: arquivos, conversa_id, history, message, route_context
- `POST autonomia/guide/transcricao` — leitura crua sem tipo: file
- `POST autonomia/insurance/quote_agent` — leitura crua sem tipo: quote_agent.behavior, quote_agent.broker_name, quote_agent.business_hours, quote_agent.name
- `POST autonomia/prospecting/leads/:id/adopt_owner` — leitura crua sem tipo: owner_name
- `POST autonomia/prospecting/leads/:id/research` — leitura crua sem tipo: force
- `POST autonomia/prospecting/leads/campaign_segment` — leitura crua sem tipo: campaign_id, campaign_type, lead_ids, segment_name
- `POST autonomia/prospecting/leads/contacts` — leitura crua sem tipo: lead_ids
- `POST autonomia/prospecting/leads/crm_cards` — leitura crua sem tipo: lead_ids
- `POST autonomia/prospecting/leads/discard` — leitura crua sem tipo: lead_ids, reason
- `POST autonomia/prospecting/lists/:id/leads` — leitura crua sem tipo: lead_id
- `POST callbacks/facebook_pages` — leitura crua sem tipo: omniauth_token
- `POST callbacks/reauthorize_page` — leitura crua sem tipo: inbox_id, omniauth_token
- `POST callbacks/register_facebook_page` — leitura crua sem tipo: inbox_name
- `POST campaign_imports` — leitura crua sem tipo: import_file
- `POST captain/assistants/:id/playground` — leitura crua sem tipo: playground_config
- `POST captain/bulk_actions` — leitura crua sem tipo: ids, type
- `POST captain/copilot_threads/:copilot_thread_id/copilot_messages` — leitura crua sem tipo: conversation_id
- `POST captain/tasks/follow_up` — leitura crua sem tipo: conversation_display_id, follow_up_context, message
- `POST captain/tasks/label_suggestion` — leitura crua sem tipo: conversation_display_id
- `POST captain/tasks/reply_suggestion` — leitura crua sem tipo: conversation_display_id
- `POST captain/tasks/rewrite` — leitura crua sem tipo: content, conversation_display_id, operation
- `POST captain/tasks/summarize` — leitura crua sem tipo: conversation_display_id
- `POST companies/:company_id/contacts` — leitura crua sem tipo: contact_id
- `POST contacts` — leitura crua sem tipo: inbox_id, source_id
- `POST contacts/export` — aceita qualquer campo (permit! em app/controllers/api/v1/accounts/contacts_controller.rb:47); leitura crua sem tipo: column_names
- `POST contacts/filter` — aceita qualquer campo (permit! em app/controllers/api/v1/accounts/contacts_controller.rb:63); params inteiro repassado a ::Contacts::FilterService.new; leitura crua sem tipo: include_contact_inboxes, page
- `POST contacts/import` — leitura crua sem tipo: import_file
- `POST conversations` — params inteiro repassado a ConversationBuilder.new; leitura crua sem tipo: message
- `POST conversations/:conversation_id/assignments` — leitura crua sem tipo: assignee_type
- `POST conversations/:conversation_id/direct_uploads` — termina em código de fora do repositório (super em ActiveStorage::DirectUploadsController)
- `POST conversations/:conversation_id/messages` — params inteiro repassado a Messages::MessageBuilder.new
- `POST conversations/:conversation_id/participants` — leitura crua sem tipo: user_ids
- `POST conversations/:id/custom_attributes` — leitura crua sem tipo: merge
- `POST conversations/:id/toggle_typing_status` — params inteiro repassado a ::Conversations::TypingStatusManager.new
- `POST conversations/:id/transcript` — leitura crua sem tipo: email
- `POST conversations/filter` — aceita qualquer campo (permit! em app/controllers/api/v1/accounts/conversations_controller.rb:52); params inteiro repassado a ::Conversations::FilterService.new
- `POST crm/cards/:card_id/contact` — leitura crua sem tipo: contact
- `POST crm/cards/:id/close` — leitura crua sem tipo: result
- `POST crm/cards/:id/link_conversation` — leitura crua sem tipo: primary
- `POST crm/cards/bulk` — leitura crua sem tipo: action_name, bulk_action, ids
- `POST crm/cards/from_conversation` — leitura crua sem tipo: conversation_display_id
- `POST crm/meetings/:id/sync` — leitura crua sem tipo: force
- `POST crm/meetings/draft_invite` — leitura crua sem tipo: card_id
- `POST crm/meetings/suggest_times` — leitura crua sem tipo: card_id, date, duration_minutes
- `POST crm/pipelines` — leitura crua sem tipo: goal
- `POST crm/pipelines/:pipeline_id/stages` — leitura crua sem tipo: funnel_stage_type
- `POST crm/stages/reorder` — leitura crua sem tipo: stage_ids
- `POST ctwa_tracked_links` — leitura crua sem tipo: ctwa_tracked_link
- `POST data_imports` — params inteiro repassado a DataImportSkipLogFinder.new
- `POST data_imports/:id/abandon` — params inteiro repassado a DataImportSkipLogFinder.new
- `POST data_imports/:id/retry` — params inteiro repassado a DataImportSkipLogFinder.new
- `POST data_imports/:id/start` — params inteiro repassado a DataImportSkipLogFinder.new
- `POST email_campaigns/ai/generate` — leitura crua sem tipo: assets, base_mjml, brief, campaign_id, placeholders
- `POST email_campaigns/ai/rewrite` — leitura crua sem tipo: instruction, text
- `POST email_campaigns/campaigns/:campaign_id/recipients` — leitura crua sem tipo: import_file
- `POST email_campaigns/campaigns/:id/assets` — leitura crua sem tipo: file
- `POST email_campaigns/campaigns/:id/resolve_video` — leitura crua sem tipo: poster_signed_id, poster_url, signed_id, url
- `POST email_campaigns/campaigns/:id/test_send` — leitura crua sem tipo: to_email
- `POST email_campaigns/maintenance/backfills` — lê o corpo cru da requisição
- `POST email_campaigns/maintenance/backfills/:id/retry` — lê o corpo cru da requisição
- `POST email_campaigns/reputation/override` — leitura crua sem tipo: duration_seconds, message_budget, reason
- `POST email_campaigns/reputation/provider_release` — leitura crua sem tipo: reason
- `POST google/authorization` — leitura crua sem tipo: return_to
- `POST inbox_members` — leitura crua sem tipo: user_ids
- `POST inboxes/:id/set_agent_bot` — leitura crua sem tipo: agent_bot
- `POST inboxes/:id/set_call_recording` — leitura crua sem tipo: recording_enabled, transcription_enabled
- `POST inboxes/:id/set_inbound_calls` — leitura crua sem tipo: inbound_calls_enabled
- `POST inboxes/:inbox_id/conference` — leitura crua sem tipo: call_sid
- `POST instagram/authorization` — leitura crua sem tipo: return_to
- `POST integrations/hooks/:id/process_event` — leitura crua sem tipo: event
- `POST integrations/shopify/auth` — leitura crua sem tipo: shop_domain
- `POST integrations/slack` — leitura crua sem tipo: code, inbox_id
- `POST macros/:id/execute` — leitura crua sem tipo: conversation_ids
- `POST microsoft/authorization` — leitura crua sem tipo: return_to
- `POST notifications/destroy_all` — leitura crua sem tipo: type
- `POST notion/authorization` — leitura crua sem tipo: return_to
- `POST portals` — leitura crua sem tipo: blob_id, portal.config.analytics
- `POST portals/:portal_id/articles/reorder` — leitura crua sem tipo: positions_hash
- `POST portals/:portal_id/categories/reorder` — leitura crua sem tipo: positions_hash
- `POST teams/:team_id/team_members` — leitura crua sem tipo: user_ids
- `POST tiktok/authorization` — leitura crua sem tipo: return_to
- `POST upload` — leitura crua sem tipo: attachment, external_url
- `POST whatsapp/authorization` — leitura crua sem tipo: inbox_id
- `POST whatsapp_calls/:id/accept` — leitura crua sem tipo: sdp_answer
- `POST whatsapp_calls/:id/reject` — leitura crua sem tipo: sdp_answer
- `POST whatsapp_calls/:id/terminate` — leitura crua sem tipo: sdp_answer
- `POST whatsapp_calls/:id/upload_recording` — leitura crua sem tipo: recording
- `POST whatsapp_calls/initiate` — leitura crua sem tipo: sdp_offer
- `PUT agents/:id` — leitura crua sem tipo: custom_role_id
- `PUT branded_email_layout` — leitura crua sem tipo: branded_email_layout
- `PUT contacts/:id` — leitura crua sem tipo: include_contact_inboxes
- `PUT conversations/:conversation_id/draft_messages` — leitura crua sem tipo: draft_message.message
- `PUT conversations/:conversation_id/participants` — leitura crua sem tipo: user_ids
- `PUT crm/pipelines/:id` — leitura crua sem tipo: goal, google_sync, meta_sync
- `PUT crm/pipelines/:pipeline_id/ai_settings` — aceita qualquer campo (permit! em app/controllers/api/v1/accounts/crm/ai_settings_controller.rb:58)
- `PUT crm/stages/:id` — leitura crua sem tipo: funnel_stage_type
- `PUT inboxes/:id` — leitura crua sem tipo: branded_email_layout
- `PUT onboarding` — leitura crua sem tipo: onboarding_step
- `PUT portals/:id` — leitura crua sem tipo: blob_id, portal.config.analytics
- `PUT relationships/configuration` — leitura crua sem tipo: configuration
