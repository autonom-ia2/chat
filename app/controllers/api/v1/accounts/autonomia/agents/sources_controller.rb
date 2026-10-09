class Api::V1::Accounts::Autonomia::Agents::SourcesController < Api::V1::Accounts::Autonomia::BaseController
  before_action :fetch_agent
  before_action :fetch_source, only: [:destroy, :resync]

  def index
    @sources = @agent.sources.order(created_at: :desc).to_a
    @material_projection = material_projection_for(@sources)
  end

  def create
    kind = resolved_kind
    return render_unprocessable(I18n.t('autonomia.source.invalid_kind')) if kind.nil?

    if knowledge_limit_reached?(kind)
      return render_unprocessable(
        I18n.t('autonomia.source.limit_reached', limit: Autonomia::Agents::Source::MAX_KNOWLEDGE_SOURCES)
      )
    end

    @source = @agent.sources.new(source_params)
    @source.account = Current.account
    @source.kind = kind
    attach_file
    @source.save!
    enqueue_source_processing
    @agent.sources.reset
    @material_projection = material_projection_for(@agent.sources.to_a)
    render :show, status: :created
  end

  def reusable
    sources = reusable_sources.includes(:agent).order(:reference, :id)
    render json: { payload: sources.map do |source|
      { id: source.id, agent_name: source.agent.name, reference: source.reference,
        source_type: source.source_type, status: source.status }
    end }
  end

  def copy
    source_id = params[:source_id]
    unless source_id.is_a?(Integer) && source_id.positive?
      return render_unprocessable(I18n.t('autonomia.source.invalid_source_id'), code: 'invalid_source_id')
    end

    @agent.with_lock do
      origin = reusable_sources.find(source_id)
      if knowledge_limit_reached?('knowledge')
        return render_unprocessable(I18n.t('autonomia.source.limit_reached', limit: Autonomia::Agents::Source::MAX_KNOWLEDGE_SOURCES))
      end

      copy_material!(origin)
    end
    enqueue_source_processing
    @agent.sources.reset
    @material_projection = material_projection_for(@agent.sources.to_a)
    render :show, status: :created
  end

  # Excluir material: remove a fonte + seus trechos (knowledge_entries dependent: :delete_all) e
  # revalida a confiança geral da base (MAPA DE TEMAS/knowledge_confidence/knowledge_summary), pois
  # o conteúdo aprovado restante mudou. Best-effort assíncrono — a exclusão responde já.
  def destroy
    agent = @source.agent
    before = @source.material_projection
    before_session_id = Autonomia::Agents::MaterialProjection.test_session_id(agent: agent)
    @source.destroy!
    agent.sources.reset
    after = Autonomia::Agents::MaterialProjection.new(agent: agent).call
    Autonomia::Agents::MaterialProjection.invalidate_if_effective_change!(
      agent: agent, before: before, after: after, expected_session_id: before_session_id
    )
    Autonomia::Agents::Knowledge::RecomputeOverallJob.perform_later(agent.id)
    head :no_content
  end

  # Re-sincroniza a fonte: novo IngestJob gera novo sync_token que supersede qualquer ingestão em
  # andamento (jobs velhos viram no-op pelo token-guard do model).
  def resync
    # #284 (2b) — a fonte sintética "FAQ aprovadas" não tem arquivo para reprocessar.
    return render_unprocessable(I18n.t('autonomia.faq.resync_not_allowed')) if Autonomia::Agents::Faq::KnowledgeWriter.faq_source?(@source)

    Autonomia::Agents::Knowledge::IngestJob.perform_later(@source.id)
    @agent.sources.reset
    @material_projection = material_projection_for(@agent.sources.to_a)
    render :show, status: :accepted
  end

  private

  def reusable_sources
    Autonomia::Agents::Source.knowledge_sources.ready.accepted.where(account: Current.account)
                             .joins(:agent).merge(agents_scope).where.not(autonomia_agent_id: @agent.id)
                             .where("autonomia_agent_sources.metadata->>'faq_suggestions' IS DISTINCT FROM 'true'")
  end

  def copy_material!(origin)
    @source = @agent.sources.new(account: Current.account, source_type: origin.source_type,
                                 reference: origin.reference, external_link: origin.external_link,
                                 metadata: { 'copied_from_source_id' => origin.id },
                                 byte_size: origin.byte_size, mime: origin.mime)
    @source.file.attach(origin.file.blob) if origin.file.attached?
    @source.save!
  end

  # Anexa o arquivo (quando há) e popula metadata visível (byte_size/mime) a partir do upload.
  def attach_file
    file = params[:file]
    return if file.blank?

    @source.file.attach(file)
    @source.byte_size = file.size if file.respond_to?(:size)
    @source.mime = file.content_type if file.respond_to?(:content_type)
  end

  # GAP (A) — aceita `kind` em `source[:kind]` OU `descriptor[:kind]` (o FE manda no descriptor do
  # upload). Default conservador `knowledge` (caminho atual, inalterado). Retorna o valor válido OU
  # nil quando vier fora do vocabulário do enum (o create responde 422, em vez do ArgumentError 500
  # do enum setter com valor inválido).
  def resolved_kind
    raw = (params.dig(:source, :kind).presence ||
           params.dig(:descriptor, :kind).presence ||
           params[:kind].presence ||
           'knowledge').to_s
    Autonomia::Agents::Source.kinds.key?(raw) ? raw : nil
  end

  # Teto só para CONHECIMENTO (mídia de envio tem pipeline próprio, sem limite). Conta as fontes
  # knowledge já existentes do agente; ao atingir o teto, o create responde 422 (o FE já desabilita
  # o dropzone, isto é a defesa de servidor).
  def knowledge_limit_reached?(kind)
    kind == 'knowledge' &&
      @agent.sources.knowledge_sources.count >= Autonomia::Agents::Source::MAX_KNOWLEDGE_SOURCES
  end

  def fetch_agent
    @agent = agents_scope.find(params[:agent_id])
  end

  def fetch_source
    @source = @agent.sources.find(params[:id])
  end

  def material_projection_for(sources)
    source_ids = sources.map(&:id)
    entry_versions = if source_ids.empty?
                       {}
                     else
                       @agent.knowledge_entries.ready.where(source_id: source_ids)
                             .group(:source_id)
                             .pluck(:source_id, Arel.sql('COUNT(*)'), Arel.sql('MAX(updated_at)'))
                             .to_h do |source_id, count, latest_updated_at|
                               [source_id, { ready_count: count, latest_updated_at: latest_updated_at }]
                             end
                     end

    Autonomia::Agents::MaterialProjection.new(
      agent: @agent, sources: sources, entry_versions: entry_versions
    ).call
  end

  # GAP (A) — knowledge segue o caminho atual (ingest → embed → revisora); mídia só é armazenada.
  def enqueue_source_processing
    return @source.mark_media_ready! if @source.kind_media?

    Autonomia::Agents::Knowledge::IngestJob.perform_later(@source.id)
  end

  def source_params
    params.require(:source).permit(:source_type, :reference, :external_link)
  end
end
