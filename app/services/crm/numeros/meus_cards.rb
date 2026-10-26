# Os cards abertos de uma pessoa em CRM › Números (#1897, F3 do #1871), separados pelo tipo do funil (Vender ou
# Atender), só nos funis que ela enxerga no Kanban. Cada número conta o mesmo que a lista do "Ver" mostra: o funil
# principal (onde ela tem mais cards abertos; o Kanban e a Lista abrem um funil por vez), responsável = a pessoa (dono do
# card), retorno atrasado = `next_follow_up_at` vencido (follow_up_status=overdue) e parado = sem mensagem nem mudança
# de etapa há 7 dias (stale_days=7, Crm::Cards::SharedFilters).
class Crm::Numeros::MeusCards
  DIAS_PARADO = 7
  PARADO_SQL = 'GREATEST(crm_cards.last_message_at, crm_cards.entered_stage_at)'.freeze
  FECHADOS = [Crm::Card.statuses[:won], Crm::Card.statuses[:resolved]].freeze

  def initialize(account:, user:, visiveis:)
    @account = account
    @user = user
    @visiveis = visiveis
    pipelines = visiveis.pluck(:id, :counts_as_sale)
    @ids = { venda: pipelines.filter_map { |id, venda| id if venda }, atende: pipelines.filter_map { |id, venda| id unless venda } }
  end

  # Em todos os funis do tipo: decide o papel.
  def algum?(tipo)
    abertos(@ids[tipo]).exists?
  end

  def funil(tipo)
    @funil ||= {}
    return @funil[tipo] if @funil.key?(tipo)

    @funil[tipo] = principal(tipo)
  end

  # Os abertos no funil principal: o que o "Ver" abre.
  def abertos_no_funil(tipo)
    abertos(funil(tipo))
  end

  def atrasados(cards)
    cards.where('crm_cards.next_follow_up_at < ?', Time.current)
  end

  def parados(cards)
    cards.where("#{PARADO_SQL} IS NULL OR #{PARADO_SQL} < ?", DIAS_PARADO.days.ago)
  end

  # Os ids que a Lista mostra em "fechados neste mês" (result + closed_in=this_month, responsável = eu) no funil
  # principal. A Lista pega ganho e resolvido nas duas abas (Crm::Cards::FilterQuery#apply_result_filter).
  def fechados_na_lista(tipo, desde)
    return [] if funil(tipo).nil?

    Crm::Relacao.cards_do_funil(@account).where(pipeline_id: funil(tipo), owner_id: @user.id, status: FECHADOS, closed_at: desde..).pluck(:id)
  end

  private

  def abertos(pipeline_ids)
    Crm::Relacao.cards_do_funil(@account).where(status: Crm::Card.statuses[:open], owner_id: @user.id, pipeline_id: pipeline_ids)
  end

  def principal(tipo)
    abertos(@ids[tipo]).group(:pipeline_id).order(Arel.sql('COUNT(*) DESC'), :pipeline_id).limit(1).count.keys.first ||
      @visiveis.where(id: @ids[tipo]).order(is_default: :desc, position: :asc, id: :asc).pick(:id)
  end
end
