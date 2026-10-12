# Preço por mensagem entregue do WhatsApp oficial (#1332, épico #1320). Contrato do #1322: "custo por envio do WhatsApp =
# a chave WHATSAPP_MESSAGE_PRICES". A tabela mora no GlobalConfig (Super Admin), com o valor de fábrica em
# config/installation_config.yml; nenhum preço fica no código. Doc: docs/campaigns/modelos-whatsapp/precos.md.
#
#   Whatsapp::Pricing.per_message('MARKETING')            # => #<Price amount=0.3217 currency="BRL" ...>
#   Whatsapp::Pricing.per_message('utility', country: 'BR')
#   Whatsapp::Pricing.free_tier('service')                 # => { messages: 1000, period: 'month', per: 'phone_number' }
#
# Categorias: as da Meta (marketing, utility, authentication) e `service` (resposta dentro da janela de 24 h), em
# qualquer caixa. País sem tabela ou categoria desconhecida devolvem nil: quem chama não mostra preço em vez de inventar.
module Whatsapp::Pricing
  CONFIG_KEY = 'WHATSAPP_MESSAGE_PRICES'.freeze
  DEFAULT_COUNTRY = 'BR'.freeze
  CATEGORIES = %w[marketing utility authentication service].freeze

  Price = Data.define(:category, :amount, :currency, :country, :effective_from)

  module_function

  def per_message(category, country: DEFAULT_COUNTRY)
    category = category.to_s.downcase
    table = country_table(country)
    return unless table && CATEGORIES.include?(category)

    amount = decimal(table.dig('prices', category))
    return unless amount

    Price.new(category: category, amount: amount, currency: table['currency'].to_s, country: country.to_s.upcase,
              effective_from: table['effective_from'].to_s)
  end

  def free_tier(category, country: DEFAULT_COUNTRY)
    tier = country_table(country)&.dig('free_tier', category.to_s.downcase)
    return unless tier.is_a?(Hash) && tier['messages'].to_i.positive?

    { messages: tier['messages'].to_i, period: tier['period'].to_s, per: tier['per'].to_s }
  end

  def country_table(country)
    table = config[country.to_s.upcase]
    table.is_a?(Hash) ? table : nil
  end

  # O valor salvo no Super Admin (texto JSON ou mapa) ou, sem ele, o de fábrica do installation_config.yml.
  def config
    parse(GlobalConfig.get_value(CONFIG_KEY).presence || factory_value)
  end

  # O arquivo não muda com o servidor no ar: lido uma vez.
  def factory_value
    @factory_value ||= ConfigLoader.new.general_configs.find { |item| item['name'] == CONFIG_KEY }&.dig('value')
  end

  def parse(value)
    value = JSON.parse(value) if value.is_a?(String)
    value.is_a?(Hash) ? value.deep_stringify_keys : {}
  rescue JSON::ParserError
    Rails.logger.error "[Whatsapp::Pricing] #{CONFIG_KEY} is not valid JSON"
    {}
  end

  def decimal(value)
    return if value.blank?

    amount = BigDecimal(value.to_s)
    amount.finite? && !amount.negative? ? amount : nil
  rescue ArgumentError
    nil
  end
end
