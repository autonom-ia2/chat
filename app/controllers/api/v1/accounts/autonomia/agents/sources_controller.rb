class Api::V1::Accounts::Autonomia::Agents::SourcesController < Api::V1::Accounts::Autonomia::BaseController
  before_action :fetch_agent
  before_action :fetch_source, only: [:destroy, :resync]

  def index
    @sources = @agent.sources.order(created_at: :desc)
  end

  def create
    kind = resolved_kind
    return render_unprocessable(I18n.t('autonomia.source.invalid_kind')) if kind.nil?

    recusa = recusa_do_envio(kind)
    return render_unprocessable(recusa) if recusa

    @source = @agent.sources.new(source_params)
    @source.account = Current.account
    @source.kind = kind
    attach_file
    @source.save!
    # GAP (A) — pipeline por `kind`. knowledge segue o caminho ATUAL (ingest → embed → revisora).
    # media é caminho NOVO: NÃO enfileira IngestJob (sem embed/revisora); só armazena e marca ready.
    if @source.kind_media?
      @source.mark_media_ready!
    else
      Autonomia::Agents::Knowledge::IngestJob.perform_later(@source.id)
    end
    render :show, status: :created
  end

  # Excluir material: remove a fonte + seus trechos (knowledge_entries dependent: :delete_all) e
  # revalida a confiança geral da base (MAPA DE TEMAS/knowledge_confidence/knowledge_summary), pois
  # o conteúdo aprovado restante mudou. Best-effort assíncrono — a exclusão responde já.
  def destroy
    agent = @source.agent
    @source.destroy!
    Autonomia::Agents::Knowledge::RecomputeOverallJob.perform_later(agent.id)
    head :no_content
  end

  # Re-sincroniza a fonte: novo IngestJob gera novo sync_token que supersede qualquer ingestão em
  # andamento (jobs velhos viram no-op pelo token-guard do model).
  def resync
    # #284 (2b) — a fonte sintética "FAQ aprovadas" não tem arquivo para reprocessar.
    return render_unprocessable(I18n.t('autonomia.faq.resync_not_allowed')) if Autonomia::Agents::Faq::KnowledgeWriter.faq_source?(@source)
    return render_unprocessable(I18n.t('autonomia.source.foto_fora_da_fase2')) if foto?(@source.source_type) && !fase2?

    Autonomia::Agents::Knowledge::IngestJob.perform_later(@source.id)
    render :show, status: :accepted
  end

  private

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

  # A mensagem de recusa do envio, ou nil: arquivo que não é upload, foto recusada e, por último, o teto da base.
  def recusa_do_envio(kind)
    return I18n.t('autonomia.source.file_invalid') unless arquivo_enviado_ou_nenhum?

    recusa = recusa_da_foto(kind)
    return I18n.t("autonomia.source.#{recusa}") if recusa
    return unless knowledge_limit_reached?(kind)

    I18n.t('autonomia.source.limit_reached', limit: Autonomia::Agents::Source::MAX_KNOWLEDGE_SOURCES)
  end

  # Teto só para CONHECIMENTO (mídia de envio tem pipeline próprio, sem limite). Conta as fontes
  # knowledge já existentes do agente; ao atingir o teto, o create responde 422 (o FE já desabilita
  # o dropzone, isto é a defesa de servidor).
  def knowledge_limit_reached?(kind)
    kind == 'knowledge' &&
      @agent.sources.knowledge_sources.count >= Autonomia::Agents::Source::MAX_KNOWLEDGE_SOURCES
  end

  # #1426 (revisão adversarial) — o arquivo vem só como upload. Um texto em `file` seria lido pelo ActiveStorage como
  # signed_id e anexaria um blob que já existe, inclusive de outra conta. A tela sempre manda o arquivo.
  def arquivo_enviado_ou_nenhum?
    params[:file].blank? || params[:file].is_a?(ActionDispatch::Http::UploadedFile)
  end

  # #1426 — a foto como material (tipo `foto`, lida por OCR e revisada): só na Fase 2, só no que o agente sabe, nunca na
  # Lia (instrução mantida pela Autonom.ia) e só uma imagem de verdade, conferida pelos BYTES (FotoConferida), nunca pelo
  # tipo que o cliente declarou. Devolve a chave i18n da recusa, ou nil.
  def recusa_da_foto(kind)
    return unless foto?(source_params[:source_type])
    return 'foto_fora_da_fase2' unless fase2?
    return 'foto_so_no_que_sabe' unless kind == 'knowledge'
    return 'foto_agente_de_cotacao' if @agent.instrucao_mantida?
    return 'foto_sem_arquivo' if params[:file].blank?

    problema = foto_conferida(params[:file])
    "foto_#{problema}" if problema
  end

  def foto_conferida(arquivo)
    return :tamanho if arquivo.size > Autonomia::Agents::Config::MAX_IMAGE_BYTES

    arquivo.tempfile.rewind
    Autonomia::Agents::Knowledge::FotoConferida.problema(arquivo.tempfile.read)
  ensure
    arquivo.tempfile.rewind
  end

  def foto?(source_type)
    source_type == Autonomia::Agents::Source::FOTO
  end

  def fase2?
    Autonomia::Agents::Fase2.ligada?(Current.account)
  end

  def fetch_agent
    @agent = agents_scope.find(params[:agent_id])
  end

  def fetch_source
    @source = @agent.sources.find(params[:id])
  end

  def source_params
    params.require(:source).permit(:source_type, :reference, :external_link)
  end
end
