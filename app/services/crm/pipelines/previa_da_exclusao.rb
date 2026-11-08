# Prévia do "excluir funil de vez" (#2096, Parte B): quantos cards, quantos abertos, quanto em vendas some com ele e
# quais reuniões futuras serão canceladas. Só números, ids e datas: nada do cliente.
#
# O valor em vendas sai sem o Crm::ValorDeVenda.ve? (quem não vê valor de venda na tela) e sem ve_o_card? por card:
# a prévia e a exclusão são só de administrador (Crm::CardPolicy#permanent_delete?), que vê todo card e todo valor. Se
# um dia outra função puder excluir de vez, esta soma precisa passar pelos dois.
#
# Vendas: os cards ganhos, inclusive os arquivados que eram ganhos (o desfecho guardado da Parte A, #2094,
# Crm::Card::DESFECHO_ARQUIVADO), e só se o funil conta como venda. Somadas por moeda: cards em moedas diferentes não se
# somam. `won_value_cents` e `currency` trazem a soma quando há uma moeda só (o caso comum); com mais de uma, os dois vêm
# nulos e a tela lê `won_values`.
class Crm::Pipelines::PreviaDaExclusao
  MAX_REUNIOES = 100

  def initialize(pipeline)
    @pipeline = pipeline
    @cards = pipeline.cards
  end

  def perform
    total = @cards.count
    abertos = @cards.where(status: :open).count
    vendas = vendas_por_moeda
    {
      pipeline_id: @pipeline.id, cards_count: total, open_cards_count: abertos, closed_or_archived_count: total - abertos,
      won_value_cents: (vendas.first[:value_cents] if vendas.one?), currency: (vendas.first[:currency] if vendas.one?),
      won_values: vendas, upcoming_meetings_count: reunioes.count, upcoming_meetings: lista_de_reunioes
    }
  end

  private

  def vendas_por_moeda
    return [] unless @pipeline.counts_as_sale?

    @cards.where(status: :won)
          .or(@cards.where(status: :archived).where("crm_cards.metadata->>'desfecho_arquivado' = 'won'"))
          .group(:currency).order(:currency).sum(:value_cents)
          .map { |moeda, valor| { currency: moeda, value_cents: valor } }
  end

  def reunioes
    Crm::Meeting.where(account_id: @pipeline.account_id, card_id: @cards.select(:id)).upcoming
  end

  def lista_de_reunioes
    reunioes.order(:starts_at, :id).limit(MAX_REUNIOES).map do |meeting|
      { card_id: meeting.card_id, starts_at: meeting.starts_at, provider: meeting.provider }
    end
  end
end
