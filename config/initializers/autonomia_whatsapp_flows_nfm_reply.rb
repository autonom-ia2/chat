# frozen_string_literal: true

# Preserve WhatsApp Flows responses (interactive.nfm_reply) in incoming Chatwoot
# messages so downstream webhooks can process the submitted form payload.
#
# Since Chatwoot 4.17 the core also handles nfm_reply natively: it sets the message
# content to I18n `conversations.messages.whatsapp.flow_response` and stores
# `content_attributes['whatsapp_flow_response']` ({ name, body, response_json }) for the
# dashboard bubble. This patch stays because external webhooks (n8n) depend on the
# `content_attributes['flow_response']` contract below, which carries `flow_token` and
# the raw interactive payload that the core does not persist. The placeholder is only
# applied when the core leaves the content blank.
module Autonomia
  module WhatsappFlowsNfmReplyPatch
    FLOW_PLACEHOLDER = '[Flow] Formulário recebido'

    def create_message(*args, **kwargs)
      super(*args, **kwargs)

      flow_response = autonomia_extract_flow_response(args.first)
      return if flow_response.blank?
      return if @message.blank?

      begin
        @message.content_attributes = (@message.content_attributes || {}).merge(
          'flow_response' => flow_response
        )
        @message.content = FLOW_PLACEHOLDER if @message.content.blank?
      rescue StandardError => e
        Rails.logger.error("[Autonomia][FlowsPatch] failed to preserve nfm_reply: #{e.class}: #{e.message}")
      end
    end

    private

    def autonomia_extract_flow_response(message)
      return unless message.is_a?(Hash)

      interactive = message[:interactive] || message['interactive']
      return unless interactive.is_a?(Hash)

      type = interactive[:type] || interactive['type']
      return unless type == 'nfm_reply'

      nfm_reply = interactive[:nfm_reply] || interactive['nfm_reply']
      return unless nfm_reply.is_a?(Hash)

      response_json = nfm_reply[:response_json] || nfm_reply['response_json']
      flow_token = nfm_reply[:flow_token] || nfm_reply['flow_token'] ||
                   interactive[:flow_token] || interactive['flow_token']

      {
        'type' => 'nfm_reply',
        'flow_token' => flow_token,
        'response_json' => response_json,
        'raw' => interactive
      }.compact
    end
  end
end

Rails.application.config.to_prepare do
  unless defined?(Whatsapp::IncomingMessageBaseService)
    Rails.logger.warn('[Autonomia][FlowsPatch] Whatsapp::IncomingMessageBaseService not found. Patch not applied.')
    next
  end

  target = Whatsapp::IncomingMessageBaseService
  has_create_message =
    target.instance_methods.include?(:create_message) ||
    target.protected_instance_methods.include?(:create_message) ||
    target.private_instance_methods.include?(:create_message)

  unless has_create_message
    Rails.logger.warn('[Autonomia][FlowsPatch] create_message not found. Patch not applied.')
    next
  end

  if target.ancestors.include?(Autonomia::WhatsappFlowsNfmReplyPatch)
    Rails.logger.info('[Autonomia][FlowsPatch] Patch already applied.')
    next
  end

  target.prepend(Autonomia::WhatsappFlowsNfmReplyPatch)
  Rails.logger.info('[Autonomia][FlowsPatch] Patch applied to Whatsapp::IncomingMessageBaseService#create_message.')
end
