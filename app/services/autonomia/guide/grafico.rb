# Um gráfico de barras sob a resposta do Guia (#3158), no padrão do `Captain::Copilot::Chart`.
#
# A ferramenta monta os dados aqui e os deixa no `Contexto`; o modelo recebe só o marcador `[grafico:<id>]`.
# Os números desenhados nunca passam por ele. O formato é o que o `GuideGrafico.vue` lê:
#   { modo: 'ranking'|'serie', titulo, medida, de, ate, barras: [{ rotulo, valor }] }
#
# Tetos: 60 barras por gráfico e 3 gráficos por turno (`Contexto::MAX_GRAFICOS`), porque os gráficos vão para o
# jsonb do turno e para o Redis do pedido.
module Autonomia::Guide::Grafico
  MAX_BARRAS = 60

  module_function

  # -> Hash com chaves de texto, ou nil quando nenhum valor passa de zero (um gráfico vazio não diz nada).
  # No ranking ficam as primeiras barras (as maiores); na série, as mais recentes.
  def montar(modo:, titulo:, medida:, pedido:, barras:)
    return nil if barras.none? { |barra| barra[:valor].to_f.positive? }

    cortadas = modo == 'serie' ? barras.last(MAX_BARRAS) : barras.first(MAX_BARRAS)
    { 'modo' => modo, 'titulo' => titulo.to_s, 'medida' => medida.to_s, 'de' => pedido.de.iso8601, 'ate' => pedido.ate.iso8601,
      'barras' => cortadas.map { |barra| { 'rotulo' => barra[:rotulo].to_s, 'valor' => barra[:valor] } } }
  end
end
