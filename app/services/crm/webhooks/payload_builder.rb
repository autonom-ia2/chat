module Crm
  module Webhooks
    # Builds the OUTBOUND webhook payload for a CRM card lifecycle event.
    #
    # Written from scratch (NOT a subclass of Crm::Cards::PayloadBuilder, which is
    # the in-app/agent-scoped drawer payload and leaks PII/AI). This builder is
    # DEFAULT-DENY: it never emits contact email/phone, owner email, metadata['ai'],
    # ai_summary, ai_value, or raw conversation content. Emission is account-scoped
    # (no Current.user), so there is no visibility context to gate on — we simply
    # do not include sensitive fields (plan B4/D4).
    #
    # Opt-in: when the subscribing Webhook has include_contact_pii = true, the
    # contact block gains email + phone_number (and nothing else).
    class PayloadBuilder
      # Stable, non-PII scalar attributes safe to expose to external systems.
      CARD_ATTRIBUTES = %i[
        id pipeline_id stage_id contact_id conversation_id inbox_id owner_id team_id
        title status value_cents currency lost_reason source priority score external_id
      ].freeze

      TIMESTAMP_FIELDS = %i[
        entered_stage_at last_activity_at last_message_at expected_close_at next_follow_up_at closed_at created_at updated_at
      ].freeze

      # @param card [Crm::Card]
      # @param event [String] canonical dotted event (e.g. 'crm.card.won')
      # @param event_id [Integer] stable id (crm_activities.id) for consumer dedup
      # @param changed_attributes [Hash, nil] activity payload diff, if any
      # @param include_contact_pii [Boolean] opt-in to embed contact email/phone
      def initialize(card:, event:, event_id:, changed_attributes: nil, include_contact_pii: false)
        @card = card
        @event = event
        @event_id = event_id
        @changed_attributes = changed_attributes
        @include_contact_pii = include_contact_pii
      end

      def perform
        {
          event: @event,
          event_id: @event_id,
          account_id: @card.account_id,
          timestamp: Time.current.iso8601,
          data: card_data,
          changed_attributes: @changed_attributes
        }
      end

      private

      def card_data
        CARD_ATTRIBUTES.index_with { |attribute| @card.public_send(attribute) }
                       .merge(timestamp_payload)
                       .tap { |data| append_nested(data) }
      end

      def timestamp_payload
        TIMESTAMP_FIELDS.index_with { |field| @card.public_send(field)&.iso8601 }
      end

      def append_nested(data)
        data[:is_standalone] = @card.standalone?
        data[:pipeline] = pipeline_payload
        data[:stage] = stage_payload
        data[:contact] = contact_payload
        data[:owner] = owner_payload
        data[:inbox] = inbox_payload
        # Campos do card (#1146) podem guardar CPF, placa: saem só com o mesmo opt-in de dados pessoais do contato.
        data[:custom_attributes] = @card.custom_attributes if @include_contact_pii
        data.compact!
      end

      def pipeline_payload
        return if @card.pipeline.blank?

        { id: @card.pipeline.id, name: @card.pipeline.name }
      end

      def stage_payload
        return if @card.stage.blank?

        { id: @card.stage.id, name: @card.stage.name, position: @card.stage.position }
      end

      # Default-deny: only stable id + name. email/phone_number ONLY when the
      # webhook explicitly opted in via include_contact_pii.
      def contact_payload
        return if @card.contact.blank?

        payload = { id: @card.contact.id, name: @card.contact.name }
        if @include_contact_pii
          payload[:email] = @card.contact.email
          payload[:phone_number] = @card.contact.phone_number
        end
        payload
      end

      # Owner email is intentionally excluded (PII default-deny).
      def owner_payload
        return if @card.owner.blank?

        { id: @card.owner.id, name: @card.owner.name }
      end

      def inbox_payload
        return if @card.inbox.blank?

        { id: @card.inbox.id, name: @card.inbox.name, channel_type: @card.inbox.channel_type }
      end
    end
  end
end
