class Api::V1::Accounts::Crm::StagesController < Api::V1::Accounts::Crm::BaseController
  FUNNEL_STAGE_TYPES = %w[lead qualified opportunity negotiation].freeze

  before_action :fetch_pipeline, only: [:index, :create]
  before_action :fetch_stage, only: [:update, :destroy]

  def index
    authorize ::Crm::PipelineStage
    @stages = @pipeline.stages.order(:position, :id)
    @stages_count = @stages.count
    # One grouped query instead of N — the funnel-edit drawer needs the real (all-status)
    # count per stage to warn before a delete that the backend would otherwise reject.
    # Acesso por funil (#1148, PR D): quem tem restrição conta só os cards que vê (inclusive "só atribuídas").
    cards = card_scope.restricted? ? policy_scope(::Crm::Card) : ::Crm::Card
    @cards_count_by_stage = cards.where(stage_id: @stages.map(&:id)).group(:stage_id).count
  end

  def create
    @stage = Current.account.crm_pipeline_stages.new(stage_params.merge(pipeline: @pipeline))
    apply_default_ai_criteria!(@stage)
    # New stages must honor the funnel classification too — update-only handling
    # would silently drop the mapping the funnel drawer sends on stage creation.
    metadata = @stage.metadata || {}
    apply_funnel_stage_type!(metadata)
    apply_category!(metadata)
    apply_template_variant!(metadata)
    @stage.metadata = metadata
    authorize @stage
    @stage.save!
    render :show, status: :created
  end

  def update
    @stage.update!(stage_params.merge(metadata: merged_stage_metadata))
    render :show
  end

  def destroy
    case Crm::PipelineStages::Destroyer.new(stage: @stage, target_stage_id: params[:target_stage_id], actor: Current.user).perform
    when Crm::PipelineStages::Destroyer::HAS_CARDS
      render_unprocessable('crm.stage_has_cards')
    when Crm::PipelineStages::Destroyer::LAST_STAGE
      render_unprocessable('crm.stage_is_last')
    when Crm::PipelineStages::Destroyer::IN_USE
      render_unprocessable('crm.stage_in_use')
    else
      head :no_content
    end
  end

  def reorder
    authorize ::Crm::PipelineStage, :reorder?
    ensure_visible_stages!(Array(params[:stage_ids]))
    return render_unprocessable('crm.invalid_stage_reorder') unless stage_reorderer.perform == Crm::PipelineStages::Reorderer::SUCCESS

    head :ok
  end

  private

  def fetch_pipeline
    @pipeline = policy_scope(::Crm::Pipeline).find(params[:pipeline_id])
  end

  def fetch_stage
    @stage = visible_stages.find(params[:id])
    authorize @stage
  end

  # Acesso por funil (#1148, PR D): etapa de funil que a pessoa não vê é 404 (mesmo para quem gerencia funis).
  def visible_stages
    policy_scope(::Crm::PipelineStage).where(pipeline_id: policy_scope(::Crm::Pipeline).select(:id))
  end

  def ensure_visible_stages!(stage_ids)
    return unless card_scope.restricted?
    raise ActiveRecord::RecordNotFound unless visible_stages.where(id: stage_ids).count == stage_ids.uniq.size
  end

  def card_scope
    @card_scope ||= ::Crm::Access::CardScope.new(user: Current.user, account: Current.account, account_user: Current.account_user)
  end

  def stage_params
    parameter_set(:stage).permit(
      :name, :description, :color, :position, :win_probability, :wip_limit,
      :sla_seconds, :sla_warning_seconds, :is_won_stage, :is_lost_stage, metadata: {}
    )
  end

  def stage_reorderer
    Crm::PipelineStages::Reorderer.new(account: Current.account, stage_ids: params[:stage_ids])
  end

  # Shallow-merge the incoming metadata into the stored column so a partial
  # PATCH never clobbers sibling keys such as metadata['ai'] (AI criteria).
  def merged_stage_metadata
    metadata = (@stage.metadata || {}).deep_dup
    incoming = stage_params[:metadata].presence
    metadata.merge!(incoming.to_h.stringify_keys) if incoming
    apply_funnel_stage_type!(metadata)
    apply_category!(metadata)
    metadata
  end

  # funnel_stage_type may arrive top-level or nested in metadata; top-level
  # wins. A blank/invalid value clears the classification.
  def apply_funnel_stage_type!(metadata)
    provided = params[:stage]&.key?(:funnel_stage_type)
    return unless provided || metadata.key?('funnel_stage_type')

    type = (provided ? params.dig(:stage, :funnel_stage_type) : metadata['funnel_stage_type']).presence
    if FUNNEL_STAGE_TYPES.include?(type)
      metadata['funnel_stage_type'] = type
    else
      metadata.delete('funnel_stage_type')
    end
  end

  # Categoria da etapa vinda do modelo (#1498): só as conhecidas; vazio ou outro valor tira. Pode vir solta ou dentro de
  # metadata (a solta vale mais); sem nenhuma das duas, fica como está.
  def apply_category!(metadata)
    provided = params[:stage]&.key?(:category)
    return unless provided || metadata.key?('category')

    category = (provided ? params.dig(:stage, :category) : metadata['category']).to_s
    if ::Crm::PipelineStage::CATEGORIES.include?(category)
      metadata['category'] = category
    else
      metadata.delete('category')
    end
  end

  # #1548 (passo 2): a etapa nova que veio do modelo (template_position) segue a variante do tipo de conta, mesmo que a
  # tela mande a categoria de hoje (painel em cache, por exemplo). Só ao criar: funil que já existe não muda.
  def apply_template_variant!(metadata)
    return if @pipeline.counts_as_sale?

    category = Crm::PipelineStages::TemplateVariant.category_for(
      account: Current.account, template: @pipeline.metadata&.dig('template'), position: params.dig(:stage, :template_position)
    )
    metadata['category'] = category if category
  end

  def apply_default_ai_criteria!(stage)
    return if Crm::Ai::Config.stage_ai_criteria(stage).present?

    # #1548: a etapa que veio do modelo traz a posição dela no modelo (template_position); o modelo é o do funil.
    defaults = Crm::Ai::DefaultStageCriteria.metadata_for(
      stage.name, atender: !@pipeline.counts_as_sale?,
                  template: @pipeline.metadata&.dig('template'), position: params.dig(:stage, :template_position)
    )
    return if defaults.blank?

    stage.metadata = (stage.metadata || {}).merge(defaults)
  end
end
