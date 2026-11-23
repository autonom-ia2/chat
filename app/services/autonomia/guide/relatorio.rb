# Os números da tela Relatórios para o Guia (#3158, B8a), pela ferramenta `relatorio_de_atendimento`.
#
# Portado do `Captain::Copilot::ReportService` (somos Enterprise): chama os MESMOS builders v2 que alimentam
# a tela — `V2::Reports::Conversations::ReportBuilder` e os `*SummaryBuilder` —, então o número que o Guia
# diz é o número que a tela mostra. O período é cortado no fuso de relatório da conta.
#
# Três tipos:
#  - `resumo`: o total (ou a média) de uma métrica no período, da conta ou de um agente, caixa, etiqueta ou time;
#  - `serie`: a métrica por dia, semana ou mês;
#  - `ranking`: a métrica de cada agente, caixa, etiqueta ou time, do maior para o menor.
#
# Com `grafico`, os números do gráfico ficam no `Contexto` e o modelo recebe só o marcador `[grafico:<id>]`
# (o padrão do `chart.rb` do Copilot): ele não tem como inventar uma barra.
class Autonomia::Guide::Relatorio
  # O pedido não vira relatório: o motivo, em pt-BR, volta ao modelo para ele dizer à pessoa ou corrigir a chamada.
  Recusado = Class.new(StandardError)

  def initialize(account:, contexto:)
    @account = account
    @contexto = contexto
  end

  # -> String (JSON) para o modelo, dentro do teto da ferramenta. Levanta `Recusado` com o motivo.
  def call(params)
    pedido = Pedido.new(account: @account, params: params)
    relatorio = pedido.tipo == 'ranking' ? Ranking.new(pedido).call : Serie.new(pedido).call
    Saida.caber(desenhar(relatorio, pedido))
  end

  private

  # O gráfico é montado pelo relatório; aqui ele vai para o `Contexto` e o modelo recebe o marcador no lugar.
  def desenhar(montado, pedido)
    grafico = montado[:grafico_dados]
    relatorio = montado.except(:grafico_dados)
    return relatorio unless pedido.grafico?
    return relatorio.merge(grafico_nota: grafico_ausente(pedido)) if grafico.nil?

    id = @contexto.desenhar(grafico)
    return relatorio.merge(grafico_nota: 'Já há 3 gráficos nesta resposta; este não foi desenhado.') if id.nil?

    relatorio.merge(grafico: "[grafico:#{id}]",
                    grafico_nota: 'Ponha o marcador onde o gráfico deve aparecer e escreva só a conclusão, sem repetir os números das barras.')
  end

  def grafico_ausente(pedido)
    return 'O resumo é um número só e não tem gráfico. Para gráfico, peça serie ou ranking.' if pedido.tipo == 'resumo'

    'Nenhum valor do período passa de zero, então não há gráfico. Diga isso em vez de listar os zeros.'
  end
end
