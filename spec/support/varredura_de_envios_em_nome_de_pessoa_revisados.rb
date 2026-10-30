# Os envios com remetente que NÃO precisam da marca de envio automático (#1669), cada um com o motivo, conferidos um a
# um em 16/10/2026. Usado pela guarda varredura_de_envios_em_nome_de_pessoa_spec: um envio novo fora daqui e sem marca
# reprova. "arquivo#Dono#método" => motivo (um envio no método) ou { motivo:, envios: N }.
module VarreduraDeEnviosEmNomeDePessoa
  REVISADOS = {
    # Remetente é a própria pessoa, no painel ou numa ferramenta dela.
    'app/controllers/api/v1/accounts/conversations/messages_controller.rb#Api::V1::Accounts::Conversations::MessagesController#create' =>
      'painel: Current.user responde',
    'app/controllers/api/v1/accounts/conversations/messages_controller.rb#Api::V1::Accounts::Conversations::MessagesController#create_mcp_message' =>
      'painel/MCP: Current.user',
    'app/controllers/api/v1/accounts/conversations_controller.rb#Api::V1::Accounts::ConversationsController#create' =>
      'painel: 1ª mensagem da conversa nova, Current.user',
    'app/services/macros/execution_service.rb#Macros::ExecutionService#add_private_note' => 'macro: a pessoa executa no painel',
    'app/services/macros/execution_service.rb#Macros::ExecutionService#send_message' => 'macro: a pessoa executa no painel',
    'app/services/macros/execution_service.rb#Macros::ExecutionService#send_attachment' => 'macro: a pessoa executa no painel',
    'app/services/whatsapp/contact_info_request_service.rb#Whatsapp::ContactInfoRequestService#perform' =>
      'pedido de dados: botão do painel (Current.user)',
    'app/services/conversa_canal/encaminhamento.rb#ConversaCanal::Encaminhamento#copiar' =>
      'encaminhar (#1702): a pessoa escolhe as mensagens e o destino no painel (Current.user)',
    'app/services/whatsapp/templates/reenvio_do_modelo.rb#Whatsapp::Templates::ReenvioDoModelo#criar' =>
      'encaminhar (#1767): o atendente encaminha no painel; remetente é ele',
    'app/services/crm/meta_ads/instagram_private_reply.rb#Crm::MetaAds::InstagramPrivateReply#record!' =>
      'responder no privado (#2196): quem gere os anúncios clica no comentário; remetente é ele (Current.user)',
    'lib/integrations/slack/slack_message_helper.rb#Integrations::Slack::SlackMessageHelper#create_message' =>
      'a pessoa responde pelo Slack',
    'lib/integrations/dyte/processor_service.rb#Integrations::Dyte::ProcessorService#create_a_dyte_integration_message' =>
      'a pessoa abre a reunião',
    'enterprise/app/services/voice/call_message_builder.rb#Voice::CallMessageBuilder#create_message!' =>
      'registro da ligação: quem atendeu (pessoa) ou o contato',
    # Remetente é o contato (canais de entrada) ou nenhum (eco, importação).
    'app/services/autonomia/agents/operate/reaction_materializer.rb#Autonomia::Agents::Operate::ReactionMaterializer#call' => 'contato',
    'app/jobs/whatsapp_hybrid/rich_native/poll_vote_job.rb#WhatsappHybrid::RichNative::PollVoteJob#record_vote!' =>
      'contato: o voto do cliente numa enquete nativa (#1709), registrado como mensagem dele',
    'app/jobs/whatsapp_hybrid/rich_native/event_response_job.rb#WhatsappHybrid::RichNative::EventResponseJob#record!' =>
      'contato: a resposta do cliente a um evento nativo (#1709), registrada como mensagem dele',
    'app/services/line/incoming_message_service.rb#Line::IncomingMessageService#message_created?' => 'contato',
    'app/services/sms/incoming_message_service.rb#Sms::IncomingMessageService#perform' => 'contato',
    'app/services/telegram/incoming_message_service.rb#Telegram::IncomingMessageService#perform' => 'contato do Telegram',
    'app/services/twilio/incoming_message_service.rb#Twilio::IncomingMessageService#perform' => 'contato',
    'app/services/twitter/direct_message_parser_service.rb#Twitter::DirectMessageParserService#perform' => 'contato',
    'app/services/twitter/tweet_parser_service.rb#Twitter::TweetParserService#create_message' => 'contato',
    'app/services/whatsapp/history_message_service.rb#Whatsapp::HistoryMessageService#import_message' =>
      'saída importada vai sem remetente',
    'app/services/whatsapp/incoming_message_base_service.rb#Whatsapp::IncomingMessageBaseService#create_message' =>
      'eco sem remetente; entrada, o contato',
    'app/builders/messages/facebook/message_builder.rb#Messages::Facebook::MessageBuilder#build_message' =>
      'eco sem remetente; entrada, o contato',
    'app/builders/messages/instagram/base_message_builder.rb#Messages::Instagram::BaseMessageBuilder#build_message' =>
      'eco sem remetente; entrada, o contato',
    'app/builders/messages/instagram/message_builder.rb#Messages::Instagram::MessageBuilder#get_story_object_from_source_id' =>
      'mesmo message_params do builder de Instagram',
    'app/services/instagram/test_event_service.rb#Instagram::TestEventService#create_test_text' => 'evento de teste: contato',
    'app/controllers/api/v1/widget/conversations_controller.rb#Api::V1::Widget::ConversationsController#create' => 'widget: contato',
    'app/controllers/api/v1/widget/messages_controller.rb#Api::V1::Widget::MessagesController#create' => 'widget: contato',
    'app/controllers/public/api/v1/inboxes/messages_controller.rb#Public::Api::V1::Inboxes::MessagesController#create' =>
      'API pública da caixa: contato',
    'app/mailboxes/mailbox_helper.rb#MailboxHelper#create_message' => 'e-mail recebido: contato',
    # O próprio builder: os parâmetros vêm de quem chama, e quem chama é varrido.
    'app/builders/messages/message_builder.rb#Messages::MessageBuilder#perform' => 'o builder; os chamadores são varridos',
    # Campanha: a marca existe, mas não como chave literal visível aqui.
    'app/builders/campaigns/campaign_conversation_builder.rb#Campaigns::CampaignConversationBuilder#perform' =>
      'campanha: o MessageBuilder grava o `campaign_id` dos parâmetros em additional_attributes',
    'app/services/campaign_journey/sent_message_recorder.rb#CampaignJourney::SentMessageRecorder#record_at_send' =>
      'campanha: message_attributes leva additional_attributes campaign_id (campaign_attributes)',
    'app/services/campaign_journey/sent_message_recorder.rb#CampaignJourney::SentMessageRecorder#record_at_reply' =>
      'campanha: message_attributes leva additional_attributes campaign_id (campaign_attributes)',
    # Sem pessoa: atividade, modelo do sistema, robô de outro sistema, rascunho em memória, provedor externo.
    'app/jobs/conversations/activity_message_job.rb#Conversations::ActivityMessageJob#perform' => 'atividade (fora do scope chat)',
    'app/services/message_templates/template/auto_resolve.rb#MessageTemplates::Template::AutoResolve#perform' =>
      'mensagem de sistema (template/activity), sem remetente',
    'app/services/message_templates/template/csat_survey.rb#MessageTemplates::Template::CsatSurvey#perform' =>
      'mensagem de sistema (template), sem remetente',
    'app/services/message_templates/template/email_collect.rb#MessageTemplates::Template::EmailCollect#perform' =>
      { motivo: 'duas mensagens de sistema (template), sem remetente', envios: 2 },
    'app/services/message_templates/template/greeting.rb#MessageTemplates::Template::Greeting#perform' =>
      'mensagem de sistema (template), sem remetente',
    'app/services/message_templates/template/out_of_office.rb#MessageTemplates::Template::OutOfOffice#perform' =>
      'mensagem de sistema (template), sem remetente',
    'app/services/rich_messages/attachment_limit_check.rb#RichMessages::AttachmentLimitCheck#attachment_limit_draft' =>
      'rascunho em memória, não é gravado',
    'app/services/rich_messages/creation_check.rb#RichMessages::CreationCheck#rich_message_draft' => 'rascunho em memória',
    'app/models/channel/twilio_sms.rb#Channel::TwilioSms#send_message' => 'API do Twilio, não é Message',
    'app/services/twilio/send_on_twilio_service.rb#Twilio::SendOnTwilioService#send_csat_template_message' =>
      'API do Twilio, não é Message',
    'app/services/twilio/send_on_twilio_service.rb#Twilio::SendOnTwilioService#send_template_message' => 'API do Twilio',
    'lib/integrations/captain/processor_service.rb#Integrations::Captain::ProcessorService#create_conversation' =>
      'robô do Captain (sem remetente User)',
    'lib/integrations/dialogflow/processor_service.rb#Integrations::Dialogflow::ProcessorService#create_conversation' =>
      'robô do Dialogflow (sem remetente User)',
    'enterprise/app/jobs/captain/conversation/message_builder.rb#Captain::Conversation::MessageBuilder#create_outgoing_message' =>
      'remetente é o Captain::Assistant',
    'enterprise/app/jobs/captain/inbox_pending_conversations_resolution_job.rb#Captain::InboxPendingConversationsResolutionJob#create_private_note' =>
      'Captain::Assistant, nota privada',
    'enterprise/app/jobs/captain/inbox_pending_conversations_resolution_job.rb#Captain::InboxPendingConversationsResolutionJob' \
    '#create_handoff_message' =>
      'remetente é o Captain::Assistant',
    'enterprise/app/services/captain/conversation/resolution_message_service.rb#Captain::Conversation::ResolutionMessageService#perform' =>
      'remetente é o Captain::Assistant',
    # Dados de demonstração e de relatório: nunca em produção.
    'lib/seeders/account_seeder.rb#Seeders::AccountSeeder#create_messages' => 'seed',
    'lib/seeders/reports/assistant_conversation_creator.rb#Seeders::Reports::AssistantConversationCreator#incoming_message' => 'seed',
    'lib/seeders/reports/assistant_conversation_creator.rb#Seeders::Reports::AssistantConversationCreator#assistant_reply' => 'seed',
    'lib/seeders/reports/assistant_conversation_creator.rb#Seeders::Reports::AssistantConversationCreator#human_reply' => 'seed',
    'lib/seeders/reports/message_creator.rb#Seeders::Reports::MessageCreator#create_incoming_message' => 'seed',
    'lib/seeders/reports/message_creator.rb#Seeders::Reports::MessageCreator#create_outgoing_message' => 'seed'
  }.freeze
end
