# Os arquivos que a pessoa anexou na conversa com o Guia (#857), lidos para o turno.
#
# O arquivo sobe antes, por `GuideController#arquivo`, e volta como signed_id. A cada pergunta a tela
# manda os signed_ids da conversa, e aqui eles viram texto pelos MESMOS extratores da base de
# conhecimento (PDF, Word, Excel, texto, JSON). O texto entra no prompt dentro da cerca de documento
# (`PromptParts::Documentos`): é dado para ler, nunca ordem.
#
# Só resolve blob criado nesta conta: um signed_id válido de outra conta não vira documento aqui.
class Autonomia::Guide::Arquivos
  PROPOSITO = :autonomia_guide_arquivo
  VALIDADE = 1.day
  MAX_BYTES = 10.megabytes
  MAX_POR_TURNO = 5

  # Content-type detectado (Marcel) -> formato do extrator da base de conhecimento.
  FORMATOS = {
    'application/pdf' => 'pdf',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document' => 'docx',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' => 'xlsx',
    'text/plain' => 'txt',
    'text/csv' => 'txt',
    'text/markdown' => 'md',
    'application/json' => 'json'
  }.freeze

  # O extrator lê `file.download` e `file.attached?`; o blob solto não tem o segundo.
  Arquivo = Struct.new(:blob) do
    def attached?
      true
    end

    # Passa pelo tempfile do ActiveStorage em vez de baixar direto para a memória.
    def download
      blob.open(&:read)
    end
  end
  Fonte = Struct.new(:file, :reference, :source_type)

  def self.formato(content_type)
    FORMATOS[content_type.to_s]
  end

  def self.assinar(blob)
    blob.signed_id(purpose: PROPOSITO, expires_in: VALIDADE)
  end

  # Marca no metadata do blob: é por ela que a limpeza acha os anexos do Guia.
  MARCA = 'autonomia_guide_arquivo'.freeze

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

  private

  def documento(signed_id)
    blob = ActiveStorage::Blob.find_signed(signed_id.to_s, purpose: PROPOSITO)
    return if blob.nil? || blob.metadata['autonomia_account_id'] != @account.id

    texto = extrair(blob)
    { name: blob.filename.to_s, text: texto.first(::Autonomia::Agents::Config::MAX_DOCUMENT_CHARS) } if texto.present?
  rescue StandardError => e
    Rails.logger.warn("[autonomia][guide][arquivo] account=#{@account.id} #{e.class}: #{e.message}")
    nil
  end

  def extrair(blob)
    formato = self.class.formato(blob.content_type)
    return if formato.nil?

    fonte = Fonte.new(Arquivo.new(blob), blob.filename.to_s, formato)
    extrator(fonte).extract.to_s.unicode_normalize(:nfc).strip
  end

  # PDF sem OCR, como no atendimento: rasterizar um escaneado leva minutos e o turno do Guia tem teto
  # de tempo. PDF com texto é lido; escaneado volta vazio, e o Guia diz que não conseguiu ler.
  def extrator(fonte)
    return ::Autonomia::Agents::Knowledge::Processors::Pdf.new(fonte, ocr: false) if fonte.source_type == 'pdf'

    ::Autonomia::Agents::Knowledge::Processors::Dispatcher.for(fonte)
  end
end
