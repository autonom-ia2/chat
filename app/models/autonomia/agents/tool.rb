module Autonomia
  module Agents
    class Tool < ApplicationRecord
      self.table_name = 'autonomia_agent_tools'

      MAX_PER_AGENT = 10
      MAX_SLUG_LENGTH = 64
      SLUG_FORMAT = /\A[a-zA-Z][a-zA-Z0-9_]{0,63}\z/
      HTTP_METHODS = %w[GET POST].freeze
      PARAM_TYPES = %w[string number integer boolean].freeze

      belongs_to :account
      belongs_to :agent, class_name: 'Autonomia::Agents::Agent', foreign_key: :autonomia_agent_id,
                         inverse_of: :tools

      encrypts :headers_config if Chatwoot.encryption_configured?

      before_validation :normalize_slug
      before_validation :normalize_collections
      before_create :ensure_within_limit

      validates :name, presence: true
      validates :slug, presence: true, uniqueness: { scope: :autonomia_agent_id },
                       length: { maximum: MAX_SLUG_LENGTH }, format: { with: SLUG_FORMAT }
      validates :http_method, inclusion: { in: HTTP_METHODS }
      validates :endpoint_url, presence: true
      validate :validate_endpoint_url
      validate :validate_param_schema
      validate :validate_headers_config

      scope :enabled, -> { where(enabled: true) }

      def self.masked_header_value
        '••••••••'
      end

      def openai_schema
        {
          type: 'function',
          name: slug,
          description: description.presence || name,
          parameters: {
            type: 'object',
            properties: param_properties,
            required: required_param_names,
            additionalProperties: false
          },
          strict: true
        }
      end

      def masked_headers_config
        Array(headers_config).map do |header|
          item = header.to_h.deep_stringify_keys
          item['value'] = self.class.masked_header_value if item['secret'] == true && item['value'].present?
          item
        end
      end

      private

      def ensure_within_limit
        Agent.lock.find(autonomia_agent_id)
        return if agent.tools.count < MAX_PER_AGENT

        errors.add(:base, "Limite de #{MAX_PER_AGENT} ferramentas por agente atingido")
        throw(:abort)
      end

      def normalize_slug
        self.slug = name.to_s.parameterize(separator: '_') if slug.blank? && name.present?
        self.slug = slug.to_s.gsub(/[^a-zA-Z0-9_]/, '_').squeeze('_').delete_prefix('_')[0, MAX_SLUG_LENGTH]
      end

      def normalize_collections
        self.headers_config = Array(headers_config).filter_map do |header|
          item = header.to_h.deep_stringify_keys
          key = item['key'].to_s.strip
          next if key.blank?

          {
            'key' => key,
            'value' => item['value'].to_s,
            'secret' => ActiveModel::Type::Boolean.new.cast(item['secret'])
          }
        end

        self.param_schema = Array(param_schema).filter_map do |param|
          item = param.to_h.deep_stringify_keys
          name_value = item['name'].to_s.strip
          next if name_value.blank?

          {
            'name' => name_value,
            'type' => PARAM_TYPES.include?(item['type'].to_s) ? item['type'].to_s : 'string',
            'description' => item['description'].to_s,
            'required' => item.key?('required') ? ActiveModel::Type::Boolean.new.cast(item['required']) : true
          }
        end
        self.response_mapping = response_mapping.to_h if response_mapping.respond_to?(:to_h)
      end

      def validate_endpoint_url
        uri = URI.parse(endpoint_url.to_s)
        errors.add(:endpoint_url, 'deve usar HTTPS') unless uri.is_a?(URI::HTTPS)
        errors.add(:endpoint_url, 'deve possuir host') if uri.host.blank?
        errors.add(:endpoint_url, 'não pode apontar para localhost') if uri.host.to_s.match?(/\Alocalhost\z|\.local\z/i)
        errors.add(:endpoint_url, 'não pode usar IP direto') if ip_host?(uri.host)
      rescue URI::InvalidURIError
        errors.add(:endpoint_url, 'inválida')
      end

      def ip_host?(host)
        IPAddr.new(host)
        true
      rescue IPAddr::InvalidAddressError
        false
      end

      def validate_param_schema
        names = param_schema.map { |param| param['name'] }
        errors.add(:param_schema, 'possui parâmetros duplicados') if names.uniq.length != names.length
        return if names.all? { |name| name.match?(/\A[a-zA-Z_][a-zA-Z0-9_]*\z/) }

        errors.add(:param_schema, 'possui nomes inválidos')
      end

      def validate_headers_config
        return if headers_config.all? { |header| header['key'].to_s.match?(/\A[A-Za-z0-9-]+\z/) }

        errors.add(:headers_config, 'possui cabeçalhos inválidos')
      end

      def param_properties
        param_schema.to_h { |param| [param['name'], param.slice('type', 'description')] }
      end

      def required_param_names
        param_schema.select { |param| param['required'] != false }.map { |param| param['name'] }
      end
    end
  end
end
