# Os cards abertos de uma pessoa em CRM › Números (#1897, F3 do #1871), separados pelo tipo do funil (Vender ou
# Atender). Cada número conta o mesmo que a lista do "Ver" mostra: responsável = a pessoa (dono do card), retorno
# atrasado = `next_follow_up_at` vencido (follow_up_status=overdue do Kanban) e parado = sem mensagem nem mudança de
# etapa há 7 dias (stale_days=7 do Kanban, Crm::Cards::SharedFilters).
class Crm::Numeros::MeusCards
  DIAS_PARADO = 7
  PARADO_SQL = 'GREATEST(crm_cards.last_message_at, crm_cards.entered_stage_at)'.freeze

  attr_reader :venda_ids, :atende_ids

  def initialize(account:, user:)
    @account = account
    @user = user
    pipelines = account.crm_pipelines.pluck(:id, :counts_as_sale)
    @venda_ids = pipelines.filter_map { |id, venda| id if venda }
    @atende_ids = pipelines.filter_map { |id, venda| id unless venda }
  end

  def vendendo
    @vendendo ||= abertos(@venda_ids)
  end

  def atendendo
    @atendendo ||= abertos(@atende_ids)
  end

  def atrasados(cards)
    cards.where('crm_cards.next_follow_up_at < ?', Time.current)
  end

  def parados(cards)
    cards.where("#{PARADO_SQL} IS NULL OR #{PARADO_SQL} < ?", DIAS_PARADO.days.ago)
  end

  # O funil do "Ver": onde a pessoa tem mais cards abertos; sem nenhum, o funil padrão (ou o primeiro) que ela enxerga.
  def funil_principal(cards, visiveis)
    cards.group(:pipeline_id).order(Arel.sql('COUNT(*) DESC'), :pipeline_id).limit(1).count.keys.first ||
      visiveis.find_by(is_default: true)&.id || visiveis.order(:position, :id).pick(:id)
  end

  private

  def abertos(pipeline_ids)
    @account.crm_cards.where(status: Crm::Card.statuses[:open], owner_id: @user.id, pipeline_id: pipeline_ids)
  end
end
