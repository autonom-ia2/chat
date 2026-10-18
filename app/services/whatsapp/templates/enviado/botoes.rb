# Os botões na foto do envio (#1717): tipo e texto do modelo, na ordem dele; o botão de link leva o endereço com a
# variável resolvida pelo valor enviado. Nada mais sai do `processed_params`: nem o código do cupom (COPY_CODE), nem
# o payload da resposta rápida, nem o flow_token.
module Whatsapp::Templates::Enviado::Botoes
  MAX = 10
  TEXTO_MAX = 40
  Placeholders = CampaignJourney::TemplatePlaceholders

  module_function

  # botoes_do_modelo: os botões do componente BUTTONS (do modelo ou do cartão); enviados: processed_params['buttons'].
  def de(botoes_do_modelo, enviados)
    enviados = Array(enviados)
    Array(botoes_do_modelo).first(MAX).each_with_index.map do |botao, indice|
      tipo = botao['type'].to_s.downcase
      foto = { 'tipo' => tipo, 'texto' => botao['text'].to_s.strip.first(TEXTO_MAX).presence }
      tipo == 'url' ? foto.merge('url' => url(botao['url'], enviados[indice])) : foto
    end
  end

  # A Meta põe a variável do link no fim ({{1}}); o valor sai em buttons[i].parameter. Sem valor, ou com variável que
  # sobrou sem resolver, não há endereço a mostrar.
  def url(modelo, enviado)
    chaves = Placeholders.keys(modelo)
    return Whatsapp::Templates::Enviado::Links.link(modelo) if chaves.empty?

    valor = enviado.is_a?(Hash) ? enviado['parameter'].to_s.strip : ''
    return if valor.empty?

    resolvido = Placeholders.render(modelo, chaves.index_with { valor })
    Whatsapp::Templates::Enviado::Links.link(resolvido) unless resolvido.include?(Placeholders::OPEN)
  end
end
