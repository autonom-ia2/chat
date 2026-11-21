# #3098: as compras de cada pessoa dentro de uma janela de dias, pela régua de venda do resultado da campanha
# (CampaignJourney::ResultReplies: ganho, arquivado depois de ganho, renovação resolvida com apólice nova; valor = prêmio
# da apólice nova ou o valor do card). Ligadas à pessoa pelo contact_id do card. Serve ao resultado da campanha
# (ComprasDaCampanha) e ao histórico da Automação livre (Autonomia::Automacao::ComprasDoHistorico).
class CampaignJourney::ComprasNaJanela
  RR = CampaignJourney::ResultReplies

  # `pipeline_ids`: nil = todos os funis; senão só os que a pessoa vê nos relatórios (#1148).
  def initialize(account, dias:, pipeline_ids: nil)
    @account = account
    @dias = dias
    @pipeline_ids = pipeline_ids
  end

  # `inicios`: { contact_id => início da janela }. Uma linha por card fechado como venda entre o início e o início + dias:
  # { contato:, inicio:, fechado_em:, moeda:, centavos: }.
  def de(inicios)
    return [] if inicios.empty?

    linhas(inicios.keys, inicios.values.min..(inicios.values.max + @dias.days)).filter_map do |contato, fechado_em, moeda, centavos|
      inicio = inicios[contato]
      next unless fechado_em.between?(inicio, inicio + @dias.days)

      { contato: contato, inicio: inicio, fechado_em: fechado_em, moeda: moeda, centavos: centavos.to_i }
    end
  end

  # [{ currency, cents }] por moeda, maior primeiro; moeda sem dinheiro fica de fora.
  def self.valor(compras)
    compras.group_by { |compra| compra[:moeda] }
           .map { |moeda, linhas| { currency: moeda, cents: linhas.sum { |linha| linha[:centavos] } } }
           .select { |item| item[:cents].positive? }
           .sort_by { |item| -item[:cents] }
  end

  private

  # Só os cards fechados entre o primeiro início e o último fim de janela: o resto do histórico da pessoa não vem.
  def linhas(contatos, periodo)
    cards = Crm::Card.where(account_id: @account.id, contact_id: contatos, closed_at: periodo)
    cards = cards.where(pipeline_id: @pipeline_ids) unless @pipeline_ids.nil?
    cards.joins(RR::RENEWAL_PREMIUM_JOIN).where(RR::CLOSED_SALE)
         .pluck(:contact_id, :closed_at, Arel.sql(RR::CURRENCY), Arel.sql(RR::CENTS))
  end
end
