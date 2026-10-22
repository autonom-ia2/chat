class Api::V1::Accounts::Crm::PipelinesController < Api::V1::Accounts::Crm::BaseController
  PIXEL_ID_MAX_LENGTH = 20
  RESTORE_NOT_ARCHIVED = 'crm.pipeline_restore_not_archived'.freeze

  before_action :fetch_pipeline, only: [:show, :update, :destroy, :restore, :archive_preview]
  before_action :ensure_outcome_labels_format, only: [:update]

  # `status=archived` lista os funis arquivados (#2095), com quantos cards abertos cada um guarda. Sem ele, os ativos,
  # como sempre.
  def index
    authorize ::Crm::Pipeline
    archived = params[:status].to_s == 'archived'
    @pipelines = policy_scope(::Crm::Pipeline).where(status: archived ? :archived : :active).order(:position, :id)
    @pipelines_count = @pipelines.count
    @open_cards_counts = open_cards_counts(@pipelines) if archived
  end

  def show; end

  def create
    @pipeline = Current.account.crm_pipelines.new(permitted_pipeline_params)
    @pipeline.created_by = Current.user
    authorize @pipeline
    return render_outcome_labels_invalid unless outcome_labels_param_valid?

    @pipeline.save!
    update_goal!
    update_outcome_labels!
    update_template!
    render :show, status: :created
  end

  def update
    @pipeline.assign_attributes(permitted_pipeline_params)
    return render_archive_blocked unless save_pipeline!

    update_goal!
    update_outcome_labels!
    update_meta_sync!
    update_google_sync!
    update_template!
    render :show
  end

  # Arquivar (#2095): com `move_to_stage_id` (etapa de outro funil ativo que a pessoa vê), os cards abertos vão para lá
  # antes, na mesma transação (Crm::Pipelines::Archiver). Sem ele, ficam no funil e voltam quando ele for restaurado.
  def destroy
    moved = ::Crm::Pipelines::Archiver.new(pipeline: @pipeline, actor: Current.user, target_stage: archive_target_stage).perform
    @moved_cards_count = moved.size
    @open_cards_count = @pipeline.cards.open.count
    render :show
  rescue ::Crm::Pipelines::Archiver::InvalidTarget
    render_unprocessable(::Crm::Pipelines::Archiver::INVALID_TARGET)
  end

  # Restaurar o funil arquivado (#2095): ele volta ao seletor do Kanban com os cards abertos que ficaram nele.
  def restore
    return render_unprocessable(RESTORE_NOT_ARCHIVED) unless @pipeline.archived?

    @pipeline.active!
    @open_cards_count = @pipeline.cards.open.count
    render :show
  end

  # O que a tela mostra antes de arquivar (#2095): quantos cards abertos ficam e quais caixas criam card neste funil.
  def archive_preview
    render json: { payload: { open_cards_count: @pipeline.cards.open.count, inboxes: linked_inboxes } }
  end

  private

  # Último funil ativo ou único principal ativo não se arquiva. A regra vale para a mudança que vai ser gravada (DELETE,
  # ou PATCH com o status em qualquer forma: "archived", 1, "1"), conferida e gravada numa trava da conta: dois
  # arquivamentos ao mesmo tempo não zeram os funis ativos. false quando a regra recusou (nada foi gravado).
  def save_pipeline!
    return @pipeline.save! unless @pipeline.will_save_change_to_status?(to: 'archived')

    Current.account.with_lock do
      @archive_blocked = @pipeline.motivo_para_nao_arquivar
      @archive_blocked.nil? && @pipeline.save!
    end
  end

  def render_archive_blocked
    render json: { error: "crm.pipeline_archive_#{@archive_blocked}", message: I18n.t("crm.pipelines.archive_#{@archive_blocked}") },
           status: :unprocessable_entity
  end

  def fetch_pipeline
    @pipeline = policy_scope(::Crm::Pipeline).find(params[:id])
    authorize @pipeline
  end

  # A etapa para onde vão os cards abertos ao arquivar: de outro funil ativo que a pessoa enxerga. Id que não serve é
  # recusado, nunca ignorado: arquivar sem mover não pode acontecer por engano.
  def archive_target_stage
    stage_id = params[:move_to_stage_id].presence
    return if stage_id.nil?

    visible_active = policy_scope(::Crm::Pipeline).active.where.not(id: @pipeline.id).select(:id)
    stage = Current.account.crm_pipeline_stages.where(pipeline_id: visible_active).find_by(id: stage_id)
    raise ::Crm::Pipelines::Archiver::InvalidTarget, ::Crm::Pipelines::Archiver::INVALID_TARGET if stage.nil?

    stage
  end

  def open_cards_counts(pipelines)
    Current.account.crm_cards.open.where(pipeline_id: pipelines.select(:id)).group(:pipeline_id).count
  end

  # As caixas ligadas ao funil; `auto_create_card` diz se a caixa cria card nele sozinha.
  def linked_inboxes
    @pipeline.pipeline_inboxes.includes(:inbox).where.not(inbox_id: nil).order(:id).map do |link|
      { id: link.inbox_id, name: link.inbox&.name, auto_create_card: link.auto_create_card }
    end
  end

  # #1580: outcome_labels fora de { success:, failure: } em texto é recusado antes de gravar qualquer coisa (o create
  # salva o funil antes de update_outcome_labels!), depois da autorização. O que chega por metadata['outcome_labels']
  # o modelo confere.
  def ensure_outcome_labels_format
    render_outcome_labels_invalid unless outcome_labels_param_valid?
  end

  def outcome_labels_param_valid?
    labels = params.dig(:pipeline, :outcome_labels)
    labels.nil? || ::Crm::Pipeline.outcome_labels_valid?(labels)
  end

  def render_outcome_labels_invalid
    render json: { message: I18n.t('crm.pipelines.outcome_labels_invalid'), attributes: ['outcome_labels'] },
           status: :unprocessable_entity
  end

  def pipeline_params
    parameter_set(:pipeline).permit(:name, :description, :status, :is_default, :position, :counts_as_sale, :when_to_use, metadata: {})
  end

  # Valor de venda (#2075): quem não vê a meta em R$ não a muda. O metadata que a tela devolve vem sem metadata['goals']
  # (_pipeline.json.jbuilder): gravá-lo como veio apagaria a meta sem querer, então a meta salva fica.
  def permitted_pipeline_params
    attributes = pipeline_params
    return attributes if goal_visible? || !attributes.key?(:metadata)

    goals = (@pipeline&.persisted? && @pipeline.metadata.to_h['goals'])
    metadata = attributes[:metadata].to_h.except('goals')
    attributes.merge(metadata: goals ? metadata.merge('goals' => goals) : metadata)
  end

  def goal_visible?
    ::Crm::ValorDeVenda.ve?(Current.account_user)
  end

  # Monthly sales target lives in metadata['goals'] and is merged in separately
  # so it never clobbers metadata['ai'] (pipeline AI settings).
  def update_goal!
    goal = params.dig(:pipeline, :goal)
    return if goal.nil? || !goal_visible?

    metadata = (@pipeline.metadata || {}).deep_dup
    target = goal[:monthly_target_cents].to_i
    if target.positive?
      metadata['goals'] = {
        'monthly_target_cents' => target,
        'currency' => (goal[:currency].presence || 'BRL').to_s.upcase
      }
    else
      metadata.delete('goals')
    end
    @pipeline.update!(metadata: metadata)
  end

  # Nome dos dois desfechos do funil (#1144), ex.: "Contratado"/"Desistiu". Em branco volta ao padrão da tela
  # (Ganho/Perdido ou Resolvido/Cancelado). Fica em metadata['outcome_labels'], gravado à parte como a meta.
  def update_outcome_labels!
    labels = params.dig(:pipeline, :outcome_labels)
    return if labels.nil?

    metadata = (@pipeline.metadata || {}).deep_dup
    cleaned = %w[success failure].index_with { |key| labels[key].to_s.strip.first(::Crm::Pipeline::OUTCOME_LABEL_MAX_LENGTH) }.compact_blank
    if cleaned.empty?
      metadata.delete('outcome_labels')
    else
      metadata['outcome_labels'] = cleaned
    end
    @pipeline.update!(metadata: metadata)
  end

  # Modelo do funil (#1498): Suporte, Cobrança… Só um dos modelos conhecidos; outro valor é ignorado. Fica em
  # metadata['template'], gravado à parte como a meta, para não apagar o resto do metadata.
  # O modelo que chega dentro de metadata passa pela mesma lista: desconhecido sai.
  def update_template!
    metadata = (@pipeline.metadata || {}).deep_dup
    template = params.dig(:pipeline, :template).to_s
    if ::Crm::Pipeline::TEMPLATES.include?(template)
      metadata['template'] = template
    elsif metadata.key?('template') && ::Crm::Pipeline::TEMPLATES.exclude?(metadata['template'])
      metadata.delete('template')
    end
    @pipeline.update!(metadata: metadata) if metadata != @pipeline.metadata
  end

  # Meta CAPI sync config lives in metadata['meta_sync'] and is merged in
  # separately so it never clobbers metadata['ai'] or metadata['goals'].
  def update_meta_sync!
    meta_sync = params.dig(:pipeline, :meta_sync)
    return if meta_sync.nil?

    bool = ActiveModel::Type::Boolean.new
    metadata = (@pipeline.metadata || {}).deep_dup
    metadata['meta_sync'] = {
      'enabled' => bool.cast(meta_sync[:enabled]) || false,
      'events' => {
        'won' => bool.cast(meta_sync.dig(:events, :won)) || false,
        'lost' => bool.cast(meta_sync.dig(:events, :lost)) || false,
        'moved' => bool.cast(meta_sync.dig(:events, :moved)) || false
      },
      'dataset_id' => meta_sync[:dataset_id].presence
    }.merge({ 'pixel_id' => sanitized_pixel_id(meta_sync[:pixel_id]) }.compact)
    @pipeline.update!(metadata: metadata)
  end

  # Pixel of the website mode (#1011): digits only, up to 20. Anything else clears it
  # (nil, key left out) instead of failing the whole funnel save. Checked per character, no regex.
  def sanitized_pixel_id(value)
    pixel_id = value.to_s.strip
    return if pixel_id.empty? || pixel_id.size > PIXEL_ID_MAX_LENGTH
    return unless pixel_id.each_char.all? { |char| char.between?('0', '9') }

    pixel_id
  end

  # Google offline conversions config lives in metadata['google_sync'] and is merged
  # in separately so it never clobbers metadata['ai'], 'goals' or 'meta_sync'.
  def update_google_sync!
    google_sync = params.dig(:pipeline, :google_sync)
    return if google_sync.nil?

    bool = ActiveModel::Type::Boolean.new
    metadata = (@pipeline.metadata || {}).deep_dup
    metadata['google_sync'] = {
      'enabled' => bool.cast(google_sync[:enabled]) || false,
      'events' => {
        'won' => bool.cast(google_sync.dig(:events, :won)) || false,
        'lost' => bool.cast(google_sync.dig(:events, :lost)) || false,
        'moved' => bool.cast(google_sync.dig(:events, :moved)) || false
      },
      'conversion_names' => {
        'won' => google_sync.dig(:conversion_names, :won).presence
      }.compact
    }
    @pipeline.update!(metadata: metadata)
  end
end
