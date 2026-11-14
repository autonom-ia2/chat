# O selo de um seguro (E4, #2897; os da renovação na E5, #2898): Cancelado, Renovado, Vencido, Em renovação ou Ativo, e
# quantos dias faltam para ele terminar. Não é coluna: muda com o calendário. O dia vira no fuso DA CONTA (o mesmo do
# CRM e do painel), nunca no do servidor: às 22h de São Paulo o servidor já está no dia seguinte, e o seguro que vence
# hoje apareceria vencido. No dia do vencimento o seguro ainda vale.
#
# A ordem decide: o cancelado é Cancelado mesmo renovado; o renovado é Renovado mesmo depois do fim; o que terminou sem
# renovar é Vencido. "Em renovação" é o seguro que ainda vale e tem card de renovação que ninguém fechou como "não
# renovou" nem tirou do quadro. Tudo sai das colunas da apólice (quem as mantém em dia é
# Carteira::Renovacao::Desfecho), sem ler o CRM: é a mesma regra dos grupos em SQL (Carteira::Consulta).
module Carteira::Selo
  ATIVO = 'ativo'.freeze
  EM_RENOVACAO = 'em_renovacao'.freeze
  RENOVADO = 'renovado'.freeze
  VENCIDO = 'vencido'.freeze
  CANCELADO = 'cancelado'.freeze
  # A ordem do bloco Seguros da ficha: o que pede atenção primeiro, o cancelado por último.
  URGENCIA = [VENCIDO, EM_RENOVACAO, RENOVADO, ATIVO, CANCELADO].freeze
  # As colunas da apólice que o selo lê. Quem busca a apólice com poucas colunas (Carteira::ResumoPorPessoa) traz estas.
  COLUNAS = %i[cancelado_em renovado_em fim_vigencia crm_card_id nao_renovou_em renovacao_card_removido_em].freeze

  module_function

  def hoje(account)
    Time.current.in_time_zone(Crm::Timezone::Resolver.new(account: account).name_or_default).to_date
  end

  def de(apolice, hoje:)
    return CANCELADO if apolice.cancelado_em
    return RENOVADO if apolice.renovado_em
    return VENCIDO if apolice.fim_vigencia < hoje

    com_renovacao_aberta?(apolice) ? EM_RENOVACAO : ATIVO
  end

  # Tem card de renovação, sem "não renovou" e sem ter sido tirado do quadro. (O renovado sai antes, pelo selo.)
  def com_renovacao_aberta?(apolice)
    apolice.crm_card_id.present? && apolice.nao_renovou_em.nil? && apolice.renovacao_card_removido_em.nil?
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
