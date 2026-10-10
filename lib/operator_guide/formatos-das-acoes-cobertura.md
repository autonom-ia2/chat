# Formato das ações do Guia — cobertura

Gerado por `bundle exec rails autonomia:guia:formatos` a partir do código (#900). Não edite à mão.
"Completa" quer dizer que o nome de todo campo aceito saiu do código com segurança.

| | Ações |
|---|---|
| No catálogo | 559 |
| Sem corpo | 163 |
| Com corpo | 396 |
| Com corpo e formato completo | 322 (81,3%) |
| Com corpo e formato incompleto | 74 |

## Por dentro dos campos

| | Total |
|---|---|
| Campos aninhados com vocabulário | 17 de 168 |
| Leituras cruas tipadas | 113 de 188 |

## Incompletas por motivo

Uma ação pode ter mais de um motivo.

| Motivo | Ações |
|---|---|
| leitura crua sem tipo | 59 |
| aceita qualquer campo | 5 |
| params inteiro repassado | 9 |
| lê o corpo cru | 2 |
| termina em código de fora do repositório | 1 |
| a rota não tem a action | 2 |

## Ações incompletas

- `DELETE assignment_policies/:assignment_policy_id/inboxes/:id` — a rota não tem a action no controller: a chamada dá erro
- `DELETE inboxes/:inbox_id/conference` — leitura crua sem tipo: call_sid
- `PATCH crm/pipelines/:id` — leitura crua sem tipo: goal, google_sync, meta_sync, outcome_labels
- `PATCH crm/pipelines/:pipeline_id/ai_settings` — aceita qualquer campo (permit! em app/controllers/api/v1/accounts/crm/ai_settings_controller.rb:58)
- `PATCH crm/stages/:id` — leitura crua sem tipo: funnel_stage_type
- `PATCH ctwa_tracked_links/:id` — leitura crua sem tipo: ctwa_tracked_link
- `PATCH portals/:id` — leitura crua sem tipo: portal.config.analytics
- `PATCH relationships/:entity/:id/values` — leitura crua sem tipo: field
- `PATCH relationships/configuration` — leitura crua sem tipo: configuration
- `POST agents/bulk_create` — leitura crua sem tipo: emails
- `POST assignment_policies/:assignment_policy_id/inboxes` — a rota não tem a action no controller: a chamada dá erro
- `POST autonomia/agents/:agent_id/sources` — leitura crua sem tipo: descriptor.kind
- `POST autonomia/agents/:agent_id/tools/:id/test` — leitura crua sem tipo: params
- `POST autonomia/build_threads` — leitura crua sem tipo: message (repassada a @thread.append_message!), type (repassada a @thread.persist_start_options!), with_knowledge (repassada a @thread.persist_start_options!)
- `POST autonomia/build_threads/:id/messages` — leitura crua sem tipo: message (repassada a @thread.append_message!)
- `POST autonomia/conversations/:conversation_id/copilot` — leitura crua sem tipo: draft, instruction, task, tone
- `POST autonomia/conversations/:conversation_id/copilot/chat` — leitura crua sem tipo: message
- `POST autonomia/insurance/quote_agent` — leitura crua sem tipo: quote_agent.behavior (repassada a ::Autonomia::Insurance::QuoteAgent::Builder.new), quote_agent.broker_name (repassada a ::Autonomia::Insurance::QuoteAgent::Builder.new), quote_agent.business_hours (repassada a ::Autonomia::Insurance::QuoteAgent::Builder.new), quote_agent.name (repassada a ::Autonomia::Insurance::QuoteAgent::Builder.new)
- `POST autonomia/prospecting/leads/:id/adopt_owner` — leitura crua sem tipo: owner_name (repassada a ::Autonomia::Prospecting::OwnerAdoption.new)
- `POST autonomia/prospecting/leads/campaign_segment` — leitura crua sem tipo: campaign_type, segment_name (repassada a ::Autonomia::Prospecting::SelectionCampaignSegment.new)
- `POST autonomia/prospecting/leads/discard` — leitura crua sem tipo: reason (repassada a ::Autonomia::Prospecting::LeadDiscard.new)
- `POST callbacks/facebook_pages` — leitura crua sem tipo: omniauth_token
- `POST callbacks/reauthorize_page` — leitura crua sem tipo: omniauth_token
- `POST callbacks/register_facebook_page` — leitura crua sem tipo: inbox_name
- `POST campaign_journey/recipient_previews` — leitura crua sem tipo: channel (repassada a ::CampaignJourney::RecipientPreview.new), message_body (repassada a ::CampaignJourney::RecipientPreview.new)
- `POST captain/assistants/:id/playground` — leitura crua sem tipo: playground_config
- `POST captain/bulk_actions` — leitura crua sem tipo: type (repassada a MODEL_TYPE.include?)
- `POST captain/tasks/follow_up` — leitura crua sem tipo: follow_up_context, message (repassada a Captain::FollowUpService.new)
- `POST captain/tasks/rewrite` — leitura crua sem tipo: content (repassada a Captain::RewriteService.new), operation (repassada a Captain::RewriteService.new)
- `POST contacts/export` — aceita qualquer campo (permit! em app/controllers/api/v1/accounts/contacts_controller.rb:47); leitura crua sem tipo: column_names
- `POST contacts/filter` — aceita qualquer campo (permit! em app/controllers/api/v1/accounts/contacts_controller.rb:63); params inteiro repassado a ::Contacts::FilterService.new
- `POST conversations` — params inteiro repassado a ConversationBuilder.new; leitura crua sem tipo: message (repassada a Messages::MessageBuilder.new)
- `POST conversations/:conversation_id/direct_uploads` — termina em código de fora do repositório (super em ActiveStorage::DirectUploadsController)
- `POST conversations/:conversation_id/messages` — params inteiro repassado a Messages::MessageBuilder.new
- `POST conversations/:id/toggle_typing_status` — params inteiro repassado a ::Conversations::TypingStatusManager.new
- `POST conversations/:id/transcript` — leitura crua sem tipo: email (repassada a ConversationReplyMailer.with(account: @conversation.accou...)
- `POST conversations/filter` — aceita qualquer campo (permit! em app/controllers/api/v1/accounts/conversations_controller.rb:52); params inteiro repassado a ::Conversations::FilterService.new
- `POST crm/cards/:card_id/contact` — leitura crua sem tipo: contact
- `POST crm/cards/:id/close` — leitura crua sem tipo: result (repassada a ::Crm::Cards::Closer.new)
- `POST crm/cards/bulk` — leitura crua sem tipo: action_name, bulk_action
- `POST crm/meetings/:id/sync` — leitura crua sem tipo: force
- `POST crm/meetings/suggest_times` — leitura crua sem tipo: date, duration_minutes
- `POST crm/pipelines` — leitura crua sem tipo: goal, outcome_labels
- `POST crm/pipelines/:pipeline_id/stages` — leitura crua sem tipo: funnel_stage_type
- `POST ctwa_tracked_links` — leitura crua sem tipo: ctwa_tracked_link
- `POST data_imports` — params inteiro repassado a DataImportSkipLogFinder.new
- `POST data_imports/:id/abandon` — params inteiro repassado a DataImportSkipLogFinder.new
- `POST data_imports/:id/retry` — params inteiro repassado a DataImportSkipLogFinder.new
- `POST data_imports/:id/start` — params inteiro repassado a DataImportSkipLogFinder.new
- `POST email_campaigns/ai/generate` — leitura crua sem tipo: brand_mode (repassada a modes.include?)
- `POST email_campaigns/campaigns/:id/resolve_video` — leitura crua sem tipo: poster_url, url (repassada a EmailCampaigns::VideoAsset.from_url)
- `POST email_campaigns/maintenance/backfills` — lê o corpo cru da requisição
- `POST email_campaigns/maintenance/backfills/:id/retry` — lê o corpo cru da requisição
- `POST email_campaigns/reputation/override` — leitura crua sem tipo: duration_seconds (repassada a ::EmailCampaigns::Reputation::Evaluator.new(Current.accou...), message_budget (repassada a ::EmailCampaigns::Reputation::Evaluator.new(Current.accou...), reason (repassada a ::EmailCampaigns::Reputation::Evaluator.new(Current.accou...)
- `POST email_campaigns/reputation/provider_release` — leitura crua sem tipo: reason (repassada a ::EmailCampaigns::Reputation::ProviderRelease.new.call)
- `POST inboxes/:id/set_agent_bot` — leitura crua sem tipo: agent_bot (repassada a AgentBot.accessible_to(Current.account).find)
- `POST inboxes/:inbox_id/conference` — leitura crua sem tipo: call_sid
- `POST integrations/hooks/:id/process_event` — leitura crua sem tipo: event (repassada a @hook.process_event)
- `POST integrations/slack` — leitura crua sem tipo: code (repassada a Integrations::Slack::HookBuilder.new)
- `POST portals` — leitura crua sem tipo: portal.config.analytics
- `POST portals/:portal_id/articles/reorder` — leitura crua sem tipo: positions_hash (repassada a Article.update_positions)
- `POST portals/:portal_id/categories/reorder` — leitura crua sem tipo: positions_hash (repassada a Category.update_positions)
- `POST tiktok/authorization` — leitura crua sem tipo: return_to
- `POST whatsapp_calls/:id/accept` — leitura crua sem tipo: sdp_answer (repassada a Whatsapp::CallService.new)
- `POST whatsapp_calls/:id/reject` — leitura crua sem tipo: sdp_answer (repassada a Whatsapp::CallService.new)
- `POST whatsapp_calls/:id/terminate` — leitura crua sem tipo: sdp_answer (repassada a Whatsapp::CallService.new)
- `POST whatsapp_calls/:id/upload_recording` — leitura crua sem tipo: recording (repassada a @call.message.attachments.create!)
- `POST whatsapp_calls/initiate` — leitura crua sem tipo: sdp_offer (repassada a provider_service.initiate_call)
- `PUT crm/pipelines/:id` — leitura crua sem tipo: goal, google_sync, meta_sync, outcome_labels
- `PUT crm/pipelines/:pipeline_id/ai_settings` — aceita qualquer campo (permit! em app/controllers/api/v1/accounts/crm/ai_settings_controller.rb:58)
- `PUT crm/stages/:id` — leitura crua sem tipo: funnel_stage_type
- `PUT ctwa_tracked_links/:id` — leitura crua sem tipo: ctwa_tracked_link
- `PUT portals/:id` — leitura crua sem tipo: portal.config.analytics
- `PUT relationships/configuration` — leitura crua sem tipo: configuration

## Leituras cruas sem tipo

- `api/v1/accounts/agents#bulk_create` emails — o código não converte nem compara o valor
- `api/v1/accounts/articles#reorder` positions_hash — repassada a Article.update_positions
- `api/v1/accounts/autonomia/agents/build_threads#create` message — repassada a @thread.append_message!
- `api/v1/accounts/autonomia/agents/build_threads#create` type — repassada a @thread.persist_start_options!
- `api/v1/accounts/autonomia/agents/build_threads#create` with_knowledge — repassada a @thread.persist_start_options!
- `api/v1/accounts/autonomia/agents/build_threads#messages` message — repassada a @thread.append_message!
- `api/v1/accounts/autonomia/agents/sources#create` descriptor.kind — o código não converte nem compara o valor
- `api/v1/accounts/autonomia/agents/tools#test` params — o código não converte nem compara o valor
- `api/v1/accounts/autonomia/conversation_copilot#chat` message — o código não converte nem compara o valor
- `api/v1/accounts/autonomia/conversation_copilot#create` draft — o código não converte nem compara o valor
- `api/v1/accounts/autonomia/conversation_copilot#create` instruction — o código não converte nem compara o valor
- `api/v1/accounts/autonomia/conversation_copilot#create` task — o código não converte nem compara o valor
- `api/v1/accounts/autonomia/conversation_copilot#create` tone — o código não converte nem compara o valor
- `api/v1/accounts/autonomia/insurance/quote_agent#create` quote_agent.behavior — repassada a ::Autonomia::Insurance::QuoteAgent::Builder.new
- `api/v1/accounts/autonomia/insurance/quote_agent#create` quote_agent.broker_name — repassada a ::Autonomia::Insurance::QuoteAgent::Builder.new
- `api/v1/accounts/autonomia/insurance/quote_agent#create` quote_agent.business_hours — repassada a ::Autonomia::Insurance::QuoteAgent::Builder.new
- `api/v1/accounts/autonomia/insurance/quote_agent#create` quote_agent.name — repassada a ::Autonomia::Insurance::QuoteAgent::Builder.new
- `api/v1/accounts/autonomia/prospecting/lead_batches#discard` reason — repassada a ::Autonomia::Prospecting::LeadDiscard.new
- `api/v1/accounts/autonomia/prospecting/leads#adopt_owner` owner_name — repassada a ::Autonomia::Prospecting::OwnerAdoption.new
- `api/v1/accounts/autonomia/prospecting/leads#create_campaign_segment` campaign_type — o código não converte nem compara o valor
- `api/v1/accounts/autonomia/prospecting/leads#create_campaign_segment` segment_name — repassada a ::Autonomia::Prospecting::SelectionCampaignSegment.new
- `api/v1/accounts/callbacks#facebook_pages` omniauth_token — o código não converte nem compara o valor
- `api/v1/accounts/callbacks#reauthorize_page` omniauth_token — o código não converte nem compara o valor
- `api/v1/accounts/callbacks#register_facebook_page` inbox_name — o código não converte nem compara o valor
- `api/v1/accounts/campaign_journey/recipient_previews#create` channel — repassada a ::CampaignJourney::RecipientPreview.new
- `api/v1/accounts/campaign_journey/recipient_previews#create` message_body — repassada a ::CampaignJourney::RecipientPreview.new
- `api/v1/accounts/captain/assistants#playground` playground_config — o código não converte nem compara o valor
- `api/v1/accounts/captain/bulk_actions#create` type — repassada a MODEL_TYPE.include?
- `api/v1/accounts/captain/tasks#follow_up` follow_up_context — o código não converte nem compara o valor
- `api/v1/accounts/captain/tasks#follow_up` message — repassada a Captain::FollowUpService.new
- `api/v1/accounts/captain/tasks#rewrite` content — repassada a Captain::RewriteService.new
- `api/v1/accounts/captain/tasks#rewrite` operation — repassada a Captain::RewriteService.new
- `api/v1/accounts/categories#reorder` positions_hash — repassada a Category.update_positions
- `api/v1/accounts/conference#create` call_sid — o código não converte nem compara o valor
- `api/v1/accounts/conference#destroy` call_sid — o código não converte nem compara o valor
- `api/v1/accounts/contacts#export` column_names — o código não converte nem compara o valor
- `api/v1/accounts/conversations#create` message — repassada a Messages::MessageBuilder.new
- `api/v1/accounts/conversations#transcript` email — repassada a ConversationReplyMailer.with(account: @conversation.accou...
- `api/v1/accounts/crm/cards#close` result — repassada a ::Crm::Cards::Closer.new
- `api/v1/accounts/crm/cards/bulk#create` action_name — o código não converte nem compara o valor
- `api/v1/accounts/crm/cards/bulk#create` bulk_action — o código não converte nem compara o valor
- `api/v1/accounts/crm/cards/contacts#create` contact — o código não converte nem compara o valor
- `api/v1/accounts/crm/meetings#suggest_times` date — o código não converte nem compara o valor
- `api/v1/accounts/crm/meetings#suggest_times` duration_minutes — o código não converte nem compara o valor
- `api/v1/accounts/crm/meetings#sync` force — o código não converte nem compara o valor
- `api/v1/accounts/crm/pipelines#create` goal — o código não converte nem compara o valor
- `api/v1/accounts/crm/pipelines#create` outcome_labels — o código não converte nem compara o valor
- `api/v1/accounts/crm/pipelines#update` goal — o código não converte nem compara o valor
- `api/v1/accounts/crm/pipelines#update` google_sync — o código não converte nem compara o valor
- `api/v1/accounts/crm/pipelines#update` meta_sync — o código não converte nem compara o valor
- `api/v1/accounts/crm/pipelines#update` outcome_labels — o código não converte nem compara o valor
- `api/v1/accounts/crm/stages#create` funnel_stage_type — o código não converte nem compara o valor
- `api/v1/accounts/crm/stages#update` funnel_stage_type — o código não converte nem compara o valor
- `api/v1/accounts/ctwa_tracked_links#create` ctwa_tracked_link — o código não converte nem compara o valor
- `api/v1/accounts/ctwa_tracked_links#update` ctwa_tracked_link — o código não converte nem compara o valor
- `api/v1/accounts/email_campaigns/ai#generate` brand_mode — repassada a modes.include?
- `api/v1/accounts/email_campaigns/reputations#override` duration_seconds — repassada a ::EmailCampaigns::Reputation::Evaluator.new(Current.accou...
- `api/v1/accounts/email_campaigns/reputations#override` message_budget — repassada a ::EmailCampaigns::Reputation::Evaluator.new(Current.accou...
- `api/v1/accounts/email_campaigns/reputations#override` reason — repassada a ::EmailCampaigns::Reputation::Evaluator.new(Current.accou...
- `api/v1/accounts/email_campaigns/reputations#provider_release` reason — repassada a ::EmailCampaigns::Reputation::ProviderRelease.new.call
- `api/v1/accounts/email_campaigns/videos#resolve` poster_url — o código não converte nem compara o valor
- `api/v1/accounts/email_campaigns/videos#resolve` url — repassada a EmailCampaigns::VideoAsset.from_url
- `api/v1/accounts/inboxes#set_agent_bot` agent_bot — repassada a AgentBot.accessible_to(Current.account).find
- `api/v1/accounts/integrations/hooks#process_event` event — repassada a @hook.process_event
- `api/v1/accounts/integrations/slack#create` code — repassada a Integrations::Slack::HookBuilder.new
- `api/v1/accounts/portals#create` portal.config.analytics — o código não converte nem compara o valor
- `api/v1/accounts/portals#update` portal.config.analytics — o código não converte nem compara o valor
- `api/v1/accounts/relationships/configurations#update` configuration — o código não converte nem compara o valor
- `api/v1/accounts/relationships/values#update` field — o código não converte nem compara o valor
- `api/v1/accounts/tiktok/authorizations#create` return_to — o código não converte nem compara o valor
- `api/v1/accounts/whatsapp_calls#accept` sdp_answer — repassada a Whatsapp::CallService.new
- `api/v1/accounts/whatsapp_calls#initiate` sdp_offer — repassada a provider_service.initiate_call
- `api/v1/accounts/whatsapp_calls#reject` sdp_answer — repassada a Whatsapp::CallService.new
- `api/v1/accounts/whatsapp_calls#terminate` sdp_answer — repassada a Whatsapp::CallService.new
- `api/v1/accounts/whatsapp_calls#upload_recording` recording — repassada a @call.message.attachments.create!

## Parâmetros das leituras

O Guia recusa parâmetro que a leitura não lê. Leitura sem lista conhecida não recusa nada.

| | Leituras |
|---|---|
| No catálogo | 330 |
| Com parâmetros conhecidos | 279 |
| Sem parâmetros conhecidos | 51 |

### Leituras sem parâmetros conhecidos

- `GET assignment_policies/:id/edit` — a rota não tem a action no controller
- `GET assignment_policies/new` — a rota não tem a action no controller
- `GET captain/assistant_responses/:id/edit` — a rota não tem a action no controller
- `GET captain/assistant_responses/new` — a rota não tem a action no controller
- `GET captain/assistants/:assistant_id/scenarios/:id/edit` — a rota não tem a action no controller
- `GET captain/assistants/:assistant_id/scenarios/new` — a rota não tem a action no controller
- `GET captain/assistants/:id/edit` — a rota não tem a action no controller
- `GET captain/assistants/new` — a rota não tem a action no controller
- `GET captain/custom_tools/:id/edit` — a rota não tem a action no controller
- `GET captain/custom_tools/new` — a rota não tem a action no controller
- `GET companies` — lê params em código de fora do repositório (Sift#filtrate)
- `GET companies/search` — lê params em código de fora do repositório (Sift#filtrate)
- `GET contacts` — lê params em código de fora do repositório (Sift#filtrate)
- `GET contacts/:contact_id/notes/:id/edit` — a rota não tem a action no controller
- `GET contacts/:contact_id/notes/new` — a rota não tem a action no controller
- `GET contacts/active` — lê params em código de fora do repositório (Sift#filtrate)
- `GET contacts/search` — lê params em código de fora do repositório (Sift#filtrate)
- `GET crm/calendar/events` — params inteiro repassado a ::Crm::Cards::CalendarQuery.new; params inteiro repassado a ::Crm::FollowUps::FilterQuery.new
- `GET crm/cards` — params inteiro repassado a ::Crm::Cards::FilterQuery.new
- `GET crm/cards/export` — params inteiro repassado a ::Crm::Cards::FilterQuery.new
- `GET crm/cards/summaries` — params inteiro repassado a ::Crm::Cards::GroupSummary.new
- `GET crm/follow_ups` — params inteiro repassado a ::Crm::FollowUps::FilterQuery.new
- `GET crm/kanban` — params inteiro repassado a Crm::Kanban::BoardContext.new
- `GET csat_survey_responses` — lê params em código de fora do repositório (Sift#filtrate)
- `GET csat_survey_responses/download` — lê params em código de fora do repositório (Sift#filtrate)
- `GET csat_survey_responses/metrics` — lê params em código de fora do repositório (Sift#filtrate)
- `GET data_imports/:id` — params inteiro repassado a DataImportSkipLogFinder.new
- `GET email_campaigns/campaigns` — permit com valor calculado
- `GET email_campaigns/reports` — permit com valor calculado
- `GET email_campaigns/reports/:id` — permit com valor calculado
- `GET email_campaigns/reports/:id/clicks` — permit com valor calculado
- `GET email_campaigns/reports/:id/export` — permit com valor calculado
- `GET email_campaigns/reports/:id/import_issues` — permit com valor calculado
- `GET email_campaigns/reports/:id/import_issues/export` — permit com valor calculado
- `GET email_campaigns/reports/:id/recipients` — permit com valor calculado
- `GET email_campaigns/reports/:id/timeline` — permit com valor calculado
- `GET integrations/hooks/:id` — a rota não tem a action no controller
- `GET macros` — params inteiro repassado a Macro.with_visibility
- `GET portals/:id/edit` — a rota não tem a action no controller
- `GET portals/:portal_id/articles/new` — a rota não tem a action no controller
- `GET portals/:portal_id/categories` — params inteiro repassado a @portal.categories.search
- `GET portals/:portal_id/categories/:id/edit` — a rota não tem a action no controller
- `GET portals/:portal_id/categories/new` — a rota não tem a action no controller
- `GET portals/new` — a rota não tem a action no controller
- `GET search` — params inteiro repassado a SearchService.new
- `GET search/articles` — params inteiro repassado a SearchService.new
- `GET search/contacts` — params inteiro repassado a SearchService.new
- `GET search/conversations` — params inteiro repassado a SearchService.new
- `GET search/messages` — params inteiro repassado a SearchService.new
- `GET teams/:id/edit` — a rota não tem a action no controller
- `GET teams/new` — a rota não tem a action no controller
