# `resumo` e `serie` do relatório do Guia (#3158): uma métrica da conta, ou de um agente, caixa, etiqueta ou
# time, no período. Portado do `metric_series` do `Captain::Copilot::ReportService`.
#
# O total é o `aggregate_value` do builder, o mesmo número do cartão da tela. Somar os pontos contaria duas
# vezes uma conversa que a métrica conta uma vez só (as passagens do robô, por exemplo).
class Autonomia::Guide::Relatorio::Serie
  Rotulos = Autonomia::Guide::Relatorio::Rotulos

  def initialize(pedido)
    @pedido = pedido
  end

  def call
    base = { relatorio: @pedido.tipo, metrica: @pedido.metrica, de: @pedido.de.iso8601, ate: @pedido.ate.iso8601,
             fuso: @pedido.fuso, de_quem: de_quem, **total }
    return base if @pedido.tipo == 'resumo'

    base.merge(agrupado_por: @pedido.agrupar, **nota_do_agrupamento, pontos: pontos, grafico_dados: (grafico if @pedido.grafico?))
  end

  private

  def builder
    @builder ||= V2::Reports::Conversations::ReportBuilder.new(
      @pedido.account,
      @pedido.params_do_builder.merge(type: @pedido.tipo_do_builder, id: @pedido.id_do_builder,
                                      metric: @pedido.metrica, group_by: @pedido.grupo_do_builder)
    )
  end

  def de_quem
    return 'conta' if @pedido.alvo.nil?

    "#{@pedido.por} #{Rotulos.nome(@pedido.alvo)} (id #{@pedido.alvo.id})"
  end

  # Média em segundos, com o tempo escrito ao lado; contagem como número.
  def total
    valor = builder.aggregate_value
    return { total: valor } unless @pedido.media?

    { media_segundos: valor&.to_f&.round, media: Rotulos.tempo(valor) }
  end

  def nota_do_agrupamento
    return {} unless @pedido.reagrupado?

    { nota: "O período passa de #{Autonomia::Guide::Relatorio::Pedido::MAX_PONTOS} pontos, então foi agrupado por #{@pedido.agrupar}." }
  end

  def pontos_do_builder
    @pontos_do_builder ||= builder.timeseries.map do |ponto|
      [Time.zone.at(ponto[:timestamp]).in_time_zone(@pedido.fuso), ponto]
    end
  end

  # Cada período com o valor; na média, também quantos eventos ela mediu (0 = nada medido naquele período).
  def pontos
    pontos_do_builder.map do |comeco, ponto|
      rotulo = Rotulos.periodo(comeco, @pedido.grupo_do_builder, @pedido)
      next rotulo.merge(valor: ponto[:value]) unless @pedido.media?

      rotulo.merge(segundos: ponto[:value]&.to_f&.round, eventos: ponto[:count])
    end
  end

  # As colunas do gráfico. Tempo vai em minutos, com uma casa: segundos não cabem num eixo legível.
  def grafico
    barras = pontos_do_builder.map do |comeco, ponto|
      valor = @pedido.media? ? (ponto[:value].to_f / 60).round(1) : ponto[:value]
      { rotulo: Rotulos.coluna(comeco, @pedido.grupo_do_builder), valor: valor }
    end
    Autonomia::Guide::Grafico.montar(modo: 'serie', titulo: Rotulos.titulo(@pedido, por: @pedido.agrupar, quem: quem),
                                     medida: Rotulos.nome_da_metrica(@pedido.metrica), pedido: @pedido, barras: barras)
  end

  def quem
    @pedido.alvo && Rotulos.nome(@pedido.alvo)
  end
end
