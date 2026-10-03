# Os arquivos que a pessoa anexou na conversa com o Guia (#857), lidos para o turno.
#
# O arquivo sobe antes, por `GuideController#arquivo`, e volta como signed_id. A cada pergunta a tela
# manda os signed_ids da conversa, e aqui eles viram texto pelo `LeitorDeMidia` (documento, áudio ou
# imagem). O texto entra no prompt dentro da cerca de documento (`PromptParts::Documentos`): é dado
# para ler, nunca ordem.
#
# Só resolve blob criado nesta conta: um signed_id válido de outra conta não vira documento aqui.
class Autonomia::Guide::Arquivos
  PROPOSITO = :autonomia_guide_arquivo
  VALIDADE = 1.day
  MAX_BYTES = 25.megabytes
  MAX_POR_TURNO = 5
  # Marca no metadata do blob: é por ela que a limpeza acha os anexos do Guia.
  MARCA = 'autonomia_guide_arquivo'.freeze

  def self.legivel?(content_type)
    ::Autonomia::Guide::LeitorDeMidia.tipo(content_type).present?
  end

  def self.assinar(blob)
    blob.signed_id(purpose: PROPOSITO, expires_in: VALIDADE)
  end

  def self.metadata(account)
    { 'autonomia_account_id' => account.id, MARCA => true }
  end

  # Anexos do Guia sem uso depois que o link venceu: ninguém mais consegue lê-los.
  def self.vencidos
    ActiveStorage::Blob.where(created_at: ...VALIDADE.ago).where('metadata LIKE ?', %(%"#{MARCA}":true%))
  end

  def initialize(account:)
    @account = account
  end

  # -> [{ name:, text: }], só dos arquivos que deram texto.
  def ler(signed_ids)
    Array(signed_ids).first(MAX_POR_TURNO).filter_map { |signed_id| documento(signed_id) }
  end

  # O blob deste signed_id, se for desta conta.
  def blob(signed_id)
    blob = ActiveStorage::Blob.find_signed(signed_id.to_s, purpose: PROPOSITO)
    blob if blob.present? && blob.metadata['autonomia_account_id'] == @account.id
  end

  private

  def documento(signed_id)
    arquivo = blob(signed_id)
    return if arquivo.nil?

    texto = ::Autonomia::Guide::LeitorDeMidia.new(account: @account).ler(arquivo)
    { name: arquivo.filename.to_s, text: texto.first(::Autonomia::Agents::Config::MAX_DOCUMENT_CHARS) } if texto.present?
  rescue StandardError => e
    Rails.logger.warn("[autonomia][guide][arquivo] account=#{@account.id} #{e.class}: #{e.message}")
    nil
  end
end
