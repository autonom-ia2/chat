module Crm
  module Ai
    class AttributeSchemaBuilder
      TYPE_MAP = {
        'text' => 'text',
        'link' => 'text',
        'number' => 'number',
        'currency' => 'number',
        'percent' => 'number',
        'date' => 'date',
        'list' => 'list',
        'checkbox' => 'checkbox'
      }.freeze

      def initialize(account:, prefix:)
        @account = account
        @prefix = prefix.to_s
      end

      def perform
        { contact: payload_for(:contact_attribute), conversation: payload_for(:conversation_attribute) }
      end

      private

      # Prefixo vazio (default) = todos os campos customizados de contato/conversa entram no schema.
      def definitions
        @definitions ||= begin
          scope = @account.custom_attribute_definitions
                          .where(attribute_model: %i[contact_attribute conversation_attribute]).to_a
          @prefix.present? ? scope.select { |definition| definition.attribute_key.to_s.start_with?(@prefix) } : scope
        end
      end

      def payload_for(attribute_model)
        definitions.select { |definition| definition.attribute_model == attribute_model.to_s }
                   .map { |definition| definition_payload(definition) }
      end

      def definition_payload(definition)
        payload = {
          key: definition.attribute_key,
          label: definition.attribute_display_name,
          type: TYPE_MAP.fetch(definition.attribute_display_type, 'text')
        }
        payload[:options] = Array(definition.attribute_values).compact if definition.list?
        payload
      end
    end
  end
end
