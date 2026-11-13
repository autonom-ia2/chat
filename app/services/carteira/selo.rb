# O selo de um seguro (E4, #2897): Cancelado, Vencido ou Ativo, e quantos dias faltam para ele terminar. Não é coluna:
# muda com o calendário. O dia vira no fuso DA CONTA (o mesmo do CRM e do painel), nunca no do servidor: às 22h de
# São Paulo o servidor já está no dia seguinte, e o seguro que vence hoje apareceria vencido. No dia do vencimento o
# seguro ainda vale. "Renovado" e "Em renovação" chegam com a renovação (E5).
module Carteira::Selo
  ATIVO = 'ativo'.freeze
  VENCIDO = 'vencido'.freeze
  CANCELADO = 'cancelado'.freeze
  # A ordem do bloco Seguros da ficha: o que pede atenção primeiro, o cancelado por último.
  URGENCIA = [VENCIDO, ATIVO, CANCELADO].freeze

  module_function

  def hoje(account)
    Time.current.in_time_zone(Crm::Timezone::Resolver.new(account: account).name_or_default).to_date
  end

  def de(apolice, hoje:)
    return CANCELADO if apolice.cancelado_em

    apolice.fim_vigencia < hoje ? VENCIDO : ATIVO
  end

  # Negativo quando já terminou.
  def dias(apolice, hoje:)
    (apolice.fim_vigencia - hoje).to_i
  end

  # No empate, quem termina antes.
  def por_urgencia(apolices, hoje:)
    apolices.sort_by { |apolice| [URGENCIA.index(de(apolice, hoje: hoje)), apolice.fim_vigencia, apolice.id] }
  end
end
