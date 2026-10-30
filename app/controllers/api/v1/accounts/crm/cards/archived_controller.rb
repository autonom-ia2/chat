# A tela "Arquivados" do funil (#2095): os cards arquivados que a pessoa enxerga, do mais recente para o mais antigo.
#
#   GET .../crm/cards/archived?pipeline_id=&search=&page=&per_page=
#   => { payload: [Crm::Cards::ArchivedRows], meta: { count:, page:, per_page: } }
#
# Com `pipeline_id`, só os arquivados daquele funil (inclusive funil arquivado). Sem ele ("Procurar em todos os funis"),
# os arquivados de todos os funis que a pessoa vê e também os cards guardados com um funil arquivado, de qualquer
# status, para a tela apontar "Ver funis arquivados". A busca é a mesma da Lista (título, contato e empresa), pelo
# Crm::Cards::FilterQuery.
class Api::V1::Accounts::Crm::Cards::ArchivedController < Api::V1::Accounts::Crm::BaseController
  RESULTS_PER_PAGE = 25
  MAX_RESULTS_PER_PAGE = 50
  # A data do arquivamento é a da última atividade 'archive' do card (índice idx_crm_activities_card_time).
  ARCHIVED_AT_SQL = <<~SQL.squish.freeze
    (SELECT MAX(archive_activities.created_at) FROM crm_activities AS archive_activities
     WHERE archive_activities.account_id = crm_cards.account_id AND archive_activities.card_id = crm_cards.id
     AND archive_activities.event_type = 'archive')
  SQL

  def index
    authorize ::Crm::Card, :index?
    pipeline = policy_scope(::Crm::Pipeline).find(params[:pipeline_id]) if params[:pipeline_id].present?
    cards = pipeline ? archived_cards(pipeline) : archived_or_kept_cards
    page = cards.reorder(Arel.sql("#{ARCHIVED_AT_SQL} DESC NULLS LAST, crm_cards.id DESC")).page(current_page).per(per_page)

    render json: {
      payload: ::Crm::Cards::ArchivedRows.new(cards: page, user_context: pundit_user).perform,
      meta: { count: cards.unscope(:order).count, page: current_page, per_page: per_page }
    }
  end

  private

  def archived_cards(pipeline)
    filtered_cards(result: 'archived', pipeline_id: pipeline.id)
  end

  # Os arquivados de qualquer funil, mais os cards (qualquer status) que ficaram num funil arquivado.
  def archived_or_kept_cards
    table = ::Crm::Card.arel_table
    in_archived_pipeline = table[:pipeline_id].in(Current.account.crm_pipelines.archived.select(:id).arel)
    filtered_cards.where(table[:status].eq(::Crm::Card.statuses[:archived]).or(in_archived_pipeline))
  end

  def filtered_cards(filters = {})
    ::Crm::Cards::FilterQuery.new(
      scope: policy_scope(::Crm::Card), params: filters.merge(search: params[:search].presence).compact.with_indifferent_access,
      conversation_visibility: crm_visibility
    ).perform
  end

  # Lidos como params[...] para o Guia da Plataforma reconhecer os parâmetros desta leitura.
  def current_page
    [params[:page].to_i, 1].max
  end

  def per_page
    (params[:per_page].presence || RESULTS_PER_PAGE).to_i.clamp(1, MAX_RESULTS_PER_PAGE)
  end
end
