# O conversor do Chatwoot (`Whatsapp::TemplateParameterConverterService`) só reconhece o formato por partes (body, header,
# footer, buttons); um `processed_params` só com as partes novas (#1334: `carousel`, `limited_time_offer`) seria lido
# como o formato antigo e viraria variáveis do corpo. Prependido pelo `config/initializers/whatsapp_templates.rb`.
#
# #1473: `buttons` com resposta rápida e payload pode trazer `nil` nas posições sem nada a enviar (o índice é a
# posição do botão no modelo). O Chatwoot recusa buracos na lista; aqui eles valem só quando há um payload, para que
# o envio de antes (sem payload) continue lido como sempre foi.
module Whatsapp::Templates::ForkParamKeys
  KEYS = %w[carousel limited_time_offer].freeze

  private

  def enhanced_format?(processed_params)
    return super unless processed_params.is_a?(Hash) && processed_params.keys.map(&:to_s).intersect?(KEYS)

    validate_enhanced_structure(processed_params)
  end

  def valid_buttons?(buttons)
    return super unless quick_reply_payload?(buttons)

    buttons.all? { |button| button.nil? || (button.is_a?(Hash) && button['type']) }
  end

  def quick_reply_payload?(buttons)
    buttons.is_a?(Array) &&
      buttons.any? { |button| button.is_a?(Hash) && button['type'] == 'quick_reply' && button['payload'].present? }
  end
end
