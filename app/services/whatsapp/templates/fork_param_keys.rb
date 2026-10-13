# O conversor do Chatwoot (`Whatsapp::TemplateParameterConverterService`) só reconhece o formato por partes (body, header,
# footer, buttons); um `processed_params` só com as partes novas (#1334: `carousel`, `limited_time_offer`) seria lido
# como o formato antigo e viraria variáveis do corpo. Prependido pelo `config/initializers/whatsapp_templates.rb`.
module Whatsapp::Templates::ForkParamKeys
  KEYS = %w[carousel limited_time_offer].freeze

  private

  def enhanced_format?(processed_params)
    return super unless processed_params.is_a?(Hash) && processed_params.keys.map(&:to_s).intersect?(KEYS)

    validate_enhanced_structure(processed_params)
  end
end
