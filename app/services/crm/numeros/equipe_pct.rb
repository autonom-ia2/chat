# A barra coletiva de quem vende em CRM › Números (#1897, Decisão 4 do #1871): "A equipe está em 66% da meta do mês",
# sem nomes nem valores. Soma as metas dos funis de Vender que a pessoa enxerga no painel, na moeda dela, e o que foi
# ganho no mês nesses funis (a mesma conta da meta do painel de hoje, Crm::Reports::Summary#goal_payload). Sem meta: nil.
class Crm::Numeros::EquipePct
  def initialize(account:, range:, moeda:, pipelines:)
    @account = account
    @range = range
    @moeda = moeda
    @pipelines = pipelines
  end

  def perform
    metas = @pipelines.where(counts_as_sale: true).pluck(:id, :metadata).filter_map { |id, metadata| meta(id, metadata) }
    alvo = metas.sum(&:last)
    return if alvo.zero?

    ganho = Crm::Relacao.cards_do_funil(@account).where(pipeline_id: metas.map(&:first), currency: @moeda, closed_at: @range)
                        .com_desfecho(:won).sum(:value_cents)
    ((ganho.to_f / alvo) * 100).round
  end

  private

  def meta(id, metadata)
    goals = (metadata || {})['goals'] || {}
    cents = goals['monthly_target_cents'].to_i
    return if cents.zero? || (goals['currency'].presence || 'BRL') != @moeda

    [id, cents]
  end
end
