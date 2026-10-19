# #1426 (tema 4, decisão do Rodrigo) — a foto mandada na criação, além de ir para a conversa com o Construtor,
# entra na base como material: é lida por OCR (Processors::Foto) e passa pela revisão como qualquer arquivo.
#
# Roda depois de cada turno gerado (Builder::SubmitJob), quando o rascunho já existe, e olha só as fotos do último
# turno da pessoa, as mesmas que o Construtor acabou de ler. Reaproveita a imagem já enviada (o mesmo blob, sem
# segunda cópia); um turno gerado de novo não repete a foto. Só com a Fase 2 ligada e só na criação (agente em
# rascunho): o ajuste de um agente que já atende não muda. A Lia (instrução mantida) fica de fora.
#
# A foto passa pela mesma conferência da porta (FotoConferida: tipo pelos bytes, tamanho e pixels). A checagem de
# repetida e de base cheia e a gravação correm sob a trava da linha do agente: dois turnos ao mesmo tempo não gravam a
# mesma foto duas vezes nem passam do teto. A foto vai marcada como da criação (`origem`): tirá-la da base não apaga a
# imagem da conversa (Source#soltar_foto_da_conversa).
class Autonomia::Agents::Knowledge::FotosDaCriacao
  PROPOSITO = :autonomia_builder_image

  def initialize(thread)
    @thread = thread
    @agent = thread.agent
    @account = thread.account
  end

  def para_base!
    return unless criacao_na_fase2?

    blobs_do_turno.each { |blob| guardar(blob) }
  end

  private

  def criacao_na_fase2?
    @agent.present? && @agent.draft? && !@agent.instrucao_mantida? && Autonomia::Agents::Fase2.ligada?(@account)
  end

  def ultimo_turno
    Array(@thread.messages).reverse.find { |mensagem| mensagem['role'] == 'user' } || {}
  end

  # As mesmas defesas do Construtor ao ler a imagem (Builder#image_part): propósito do upload, blob desta conta,
  # tipo de imagem e tamanho.
  def blobs_do_turno
    ids = Array(ultimo_turno['image_signed_ids']).map(&:to_s).compact_blank
    ids.first(Autonomia::Agents::Config::MAX_IMAGES_PER_MESSAGE).filter_map { |id| blob_valido(id) }
  end

  def blob_valido(signed_id)
    blob = ActiveStorage::Blob.find_signed(signed_id, purpose: PROPOSITO)
    return if blob.blank?
    return unless blob.metadata['autonomia_account_id'].to_s == @account.id.to_s
    return if blob.byte_size > Autonomia::Agents::Config::MAX_IMAGE_BYTES
    return if Autonomia::Agents::Knowledge::FotoConferida.problema(blob.download)

    blob
  end

  def guardar(blob)
    source = @agent.with_lock { nova_fonte(blob) unless ja_na_base?(blob) || base_cheia? }
    Autonomia::Agents::Knowledge::IngestJob.perform_later(source.id) if source
  end

  def nova_fonte(blob)
    source = @agent.sources.new(account: @account, kind: :knowledge, source_type: Autonomia::Agents::Source::FOTO,
                                reference: blob.filename.to_s)
    source.byte_size = blob.byte_size
    source.mime = blob.content_type
    source.origem = Autonomia::Agents::Source::ORIGEM_FOTO_DA_CRIACAO
    source.file.attach(blob)
    source.save!
    source
  end

  def ja_na_base?(blob)
    ActiveStorage::Attachment.exists?(record_type: Autonomia::Agents::Source.name, name: 'file', blob_id: blob.id,
                                      record_id: @agent.sources.select(:id))
  end

  def base_cheia?
    @agent.sources.knowledge_sources.count >= Autonomia::Agents::Source::MAX_KNOWLEDGE_SOURCES
  end
end
