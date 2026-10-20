# O crédito do mês de uma pessoa em CRM › Números (#1897, Decisão 3 do #1871): a venda e o caso resolvido contam 100%
# para quem era o responsável no fechamento (`closed_with` do último fechamento em crm_activities, gravado desde a F1,
# #1876), não para quem clicou nem para quem virou dono depois. Fechamento sem pessoa responsável (robô ou ninguém)
# não conta para ninguém.
#
# Venda antiga, de antes do registro, conta pelo dono atual do card, e a resposta marca `estimado` ("contadas pelo
# responsável atual"). Venda é o status ganho, mesmo que o card tenha mudado de funil depois.
class Crm::Numeros::Credito
  STATUSES = %w[won resolved].freeze
  MAX_CARDS = 20_000
  CAMPOS = %i[id status value_cents currency owner_id].freeze

  def initialize(account:, user:, range:)
    @account = account
    @user = user
    @range = range
  end

  def perform
    meus = fechados.select { |fechado| responsavel_de(fechado) == @user.id }
    ganhos = meus.select { |fechado| fechado[:status] == 'won' }
    resolvidos = meus.select { |fechado| fechado[:status] == 'resolved' }
    {
      vendas: ganhos.size,
      valores: por_moeda(ganhos),
      resolvidos: resolvidos.size,
      estimado: meus.any? { |fechado| fechamentos[fechado[:id]].nil? },
      ganhos: ganhos.pluck(:id),
      resolvidos_ids: resolvidos.pluck(:id)
    }
  end

  private

  def por_moeda(ganhos)
    ganhos.group_by { |fechado| fechado[:currency] }.transform_values { |lista| lista.sum { |fechado| fechado[:value_cents] } }
  end

  def fechados
    @fechados ||= @account.crm_cards.where(status: STATUSES.map { |status| Crm::Card.statuses[status] }, closed_at: @range)
                          .order(:id).limit(MAX_CARDS)
                          .pluck(*CAMPOS).map { |linha| CAMPOS.zip(linha).to_h }
  end

  # O `closed_with` do último fechamento de cada card (ganho ou resolvido; o reaberto não fecha).
  def fechamentos
    @fechamentos ||= Crm::Activity.where(account_id: @account.id, card_id: fechados.pluck(:id), event_type: STATUSES)
                                  .select('DISTINCT ON (card_id) card_id, payload')
                                  .order(:card_id, created_at: :desc, id: :desc)
                                  .to_h { |activity| [activity.card_id, activity.payload['closed_with']] }
  end

  def responsavel_de(fechado)
    registro = fechamentos[fechado[:id]]
    return fechado[:owner_id] if registro.nil?

    responsavel = registro['responsible']
    responsavel['id'].to_i if responsavel.is_a?(Hash) && responsavel['type'] == 'agent'
  end
end
