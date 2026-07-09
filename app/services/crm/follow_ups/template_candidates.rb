module Crm
  module FollowUps
    # Resolves the approved MARKETING reengagement templates of a conversation's
    # inbox into a normalized candidate list for the AI follow-up composer to
    # choose from (outside-24h path). This is the ONLY place template selection
    # lives now — the user no longer picks a template manually.
    #
    # Output: Array of hashes { kind:, name:, id:, language:, body:, variables: }
    #   kind     'native' (Channel::Whatsapp) | 'api' (Channel::Api campaign)
    #   id       WhatsappApiMessageTemplate#id for 'api'; nil for 'native'
    #   language Meta language code for 'native'; nil for 'api'
    #   body     the BODY text (template message) used by the AI to pick + fill
    #   variables positional/named placeholders detected in the body (e.g. %w[1 2])
    #
    # Native filtering mirrors store/modules/inboxes.js getFilteredWhatsAppTemplates
    # (approved, non-AUTHENTICATION, non-CSAT, drop interactive/location components)
    # PLUS the explicit category == 'MARKETING' requirement. API campaign templates
    # carry no Meta category (user-authored) so every active one is eligible.
    class TemplateCandidates
      VARIABLE_PATTERN = /\{\{\s*([^}]+?)\s*\}\}/.freeze
      UNSUPPORTED_COMPONENT_TYPES = %w[LIST PRODUCT CATALOG CALL_PERMISSION_REQUEST].freeze
      CSAT_NAME_PREFIX = 'customer_satisfaction_survey'.freeze
      TWILIO_ELIGIBLE_CATEGORIES = %w[marketing utility].freeze

      def initialize(conversation:)
        @conversation = conversation
      end

      def perform
        inbox = @conversation&.inbox
        return [] if inbox.blank?

        case inbox.channel_type
        when 'Channel::Whatsapp'
          native_candidates(inbox)
        when 'Channel::TwilioSms'
          twilio_candidates(inbox)
        when 'Channel::Api'
          api_candidates(inbox)
        else
          []
        end
      end

      private

      # Twilio-WhatsApp stores approved templates in channel.content_templates
      # (Twilio Content API shape) instead of Meta message_templates. Only the
      # whatsapp medium has the 24h window + template requirement (mirrors
      # MessagingWindow); the sms medium is never template-capable. Sending reuses
      # the existing native template_params path (MessageSender ->
      # SendOnTwilioService -> TemplateProcessorService), which resolves the
      # content_sid by matching friendly_name (candidate name) + language + status.
      def twilio_candidates(inbox)
        channel = inbox.channel
        return [] unless channel.try(:medium) == 'whatsapp'

        Array(channel.content_templates&.dig('templates')).filter_map do |template|
          next unless eligible_twilio?(template)

          {
            kind: 'twilio',
            name: template['friendly_name'],
            id: template['content_sid'],
            content_sid: template['content_sid'],
            language: template['language'],
            body: template['body'].to_s,
            variables: twilio_variables(template['variables']),
            category: template['category'].to_s.downcase
          }
        end
      end

      def eligible_twilio?(template)
        return false if template.blank?
        return false unless template['status'].to_s.casecmp('approved').zero?

        TWILIO_ELIGIBLE_CATEGORIES.include?(template['category'].to_s.downcase)
      end

      def twilio_variables(variables)
        return variables.keys.map(&:to_s) if variables.is_a?(Hash)

        Array(variables).map(&:to_s)
      end

      def api_candidates(inbox)
        return [] unless inbox.channel.try(:whatsapp_api_campaign_channel?)

        @conversation.account.whatsapp_api_message_templates.active.for_inbox(inbox.id).map do |template|
          {
            kind: 'api',
            name: template.name,
            id: template.id,
            language: nil,
            body: template.body.to_s,
            variables: Array(template.variables)
          }
        end
      end

      def native_candidates(inbox)
        Array(inbox.channel&.message_templates).filter_map do |template|
          next unless eligible_native?(template)

          body = body_text(template)
          next if body.blank?

          {
            kind: 'native',
            name: template['name'],
            id: nil,
            language: template['language'],
            body: body,
            variables: variables_in(body)
          }
        end
      end

      def eligible_native?(template)
        return false if template.blank?
        return false unless template['status'].to_s.casecmp('approved').zero?
        return false unless template['category'].to_s.casecmp('marketing').zero?
        return false if template['name'].to_s.start_with?(CSAT_NAME_PREFIX)

        !unsupported_components?(template)
      end

      def unsupported_components?(template)
        Array(template['components']).any? do |component|
          UNSUPPORTED_COMPONENT_TYPES.include?(component['type']) ||
            (component['type'] == 'HEADER' && component['format'] == 'LOCATION')
        end
      end

      def body_text(template)
        body = Array(template['components']).find { |component| component['type'] == 'BODY' }
        body&.dig('text').to_s
      end

      def variables_in(body)
        body.to_s.scan(VARIABLE_PATTERN).flatten.map(&:strip).uniq
      end
    end
  end
end
