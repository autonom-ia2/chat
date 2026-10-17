# Botão de link com o fim variável (`https://loja.com/rastreio/{{1}}`, #1705, épico #1320): a Meta pede o valor no envio,
# em `buttons[i] = { type: 'url', parameter: }` na mesma posição do botão no modelo. Lido da estrutura do modelo e com o
# `CampaignJourney::TemplatePlaceholders` (sem expressão regular).
#
# Só o envio pela conversa pede (`SendableFormat.check(..., url_suffix: true)`, no `ConversationSendGuard`): Garantir,
# candidatos fora da janela e campanha olham o modelo, não um envio, e seguem as regras deles.
module Whatsapp::Templates::UrlSuffix
  REASON = 'url_parameter'.freeze

  module_function

  def reason(components, recorded)
    buttons = components.find { |component| component['type'].to_s.casecmp?('BUTTONS') }
    sent = Array(recorded['buttons'])
    missing = Array(buttons&.dig('buttons')).each_with_index.any? { |button, index| variable?(button) && !filled?(sent[index]) }
    REASON if missing
  end

  def variable?(button)
    button.is_a?(Hash) && button['type'].to_s.casecmp?('URL') && CampaignJourney::TemplatePlaceholders.keys(button['url']).any?
  end

  def filled?(sent)
    sent.is_a?(Hash) && sent['parameter'].to_s.strip.present?
  end
end
