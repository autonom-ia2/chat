# O PREÇO POR DIA E POR PESSOA do Seguro Viagem (#3226): o total do plano dividido pelos dias da viagem e pelos
# viajantes, arredondado para baixo em centavos. O agente não faz conta (instrução 4.1): quem entrega o valor pronto é a
# ferramenta, e a cotação e os detalhes passam por aqui.
#
# Os dias são os mesmos do PDF (`ComparativoPdf`): ida e volta inclusive. Plano anual não tem preço por dia: ele vale para
# todas as viagens do ano, e dividir pelo período desta viagem daria um número que não existe.
module Autonomia::Agents::Tools::Native::SeguroViagem::PorDia
  SeguroViagem = Autonomia::Agents::Tools::Native::SeguroViagem

  module_function

  # Ida e volta inclusive: de 02/02 a 06/02 são 5 dias.
  def dias(saida, retorno)
    (retorno - saida).to_i + 1
  end

  # -> 'R$ 24,54', ou nil no plano anual, sem preço, sem as datas da viagem ou sem viajantes.
  def por_pessoa(plano, pedido)
    return nil if SeguroViagem::Planos.anual?(plano) || plano['preco_total'].blank?

    divisor = dias_do_pedido(pedido).to_i * Array(pedido.to_h['idades']).size
    return nil unless divisor.positive?

    SeguroViagem::Dinheiro.brl((BigDecimal(plano['preco_total'].to_s) / divisor).floor(2))
  end

  # nil sem as duas datas em AAAA-MM-DD.
  def dias_do_pedido(pedido)
    dias(Date.iso8601(pedido.to_h['data_saida'].to_s), Date.iso8601(pedido.to_h['data_retorno'].to_s))
  rescue Date::Error
    nil
  end
end
