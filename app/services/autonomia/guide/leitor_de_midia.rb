# Transforma um arquivo em texto para o Guia ler (#857): documento, áudio ou imagem.
#
# Cada tipo usa a peça que a plataforma já tem:
# - documento (PDF, Word, Excel, CSV, texto, JSON): os extratores da base de conhecimento;
# - áudio: o mesmo transcritor da IA do CRM;
# - imagem: o mesmo leitor de imagem da IA do CRM, pedindo TODO o texto visível — um contrato
#   fotografado tem que chegar inteiro, não como legenda de uma frase.
#
# Documento é lido no nosso servidor, sem IA: fica no cache (Redis) por um dia, pelo blob.
# Áudio e imagem custam IA. Num anexo de conversa — que vive para sempre — o texto fica gravado no
# próprio anexo (`ler_anexo`): é pago uma vez na vida do arquivo. O áudio usa o mesmo campo da IA do
# CRM (`transcribed_text`), então o que um transcreveu o outro aproveita.
class Autonomia::Guide::LeitorDeMidia
  CACHE = 1.day

  DOCUMENTOS = {
    'application/pdf' => 'pdf',
    'application/vnd.openxmlformats-officedocument.wordprocessingml.document' => 'docx',
    'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet' => 'xlsx',
    'text/plain' => 'txt',
    'text/csv' => 'txt',
    'text/markdown' => 'md',
    'application/json' => 'json'
  }.freeze

  INSTRUCOES_DA_IMAGEM = 'Você lê imagens para um assistente que trabalha numa plataforma de atendimento.'.freeze
  PEDIDO_DA_IMAGEM = 'Transcreva todo o texto visível nesta imagem, na ordem em que aparece, e depois descreva em ' \
                     'poucas linhas o que ela mostra. Não invente nada que não esteja na imagem.'.freeze

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
  # O transcritor recebe um anexo de conversa (`attachment.file.blob`).
  Audio = Struct.new(:file, :id)

  # 'documento', 'audio', 'imagem' ou nil para o que não se lê.
  def self.tipo(content_type)
    tipo = content_type.to_s.downcase.split(';').first.to_s
    return 'documento' if DOCUMENTOS.key?(tipo)
    return 'audio' if tipo.start_with?('audio/')

    'imagem' if tipo.start_with?('image/')
  end

  # Onde o texto pago fica gravado no anexo de conversa. `transcribed_text` é o campo que a IA do CRM
  # e a transcrição do Chatwoot já usam para áudio.
  CAMPO_NO_ANEXO = { 'audio' => 'transcribed_text', 'imagem' => 'guia_texto_da_imagem' }.freeze

  def initialize(account:)
    @account = account
  end

  # Anexo de conversa: áudio e imagem são lidos uma vez e gravados no anexo; documento vai pelo cache.
  def ler_anexo(anexo)
    blob = anexo.file&.blob
    return '' if blob.nil?

    campo = CAMPO_NO_ANEXO[self.class.tipo(blob.content_type)]
    return ler(blob) if campo.nil?

    gravado = anexo.meta.to_h[campo].to_s
    return gravado if gravado.present?

    texto = extrair(blob)
    gravar(anexo, campo, texto) if texto.present?
    texto
  end

  # -> String (vazia quando não há o que ler).
  def ler(blob)
    Rails.cache.fetch("autonomia:guide:midia:#{blob.id}:#{blob.checksum}", expires_in: CACHE) { extrair(blob) }.to_s
  end

  private

  # A leitura já foi paga: se o anexo não salvar (um arquivo antigo que não passa na validação de
  # hoje), o texto ainda vai para a pessoa, e a próxima leitura tenta gravar de novo.
  def gravar(anexo, campo, texto)
    anexo.update!(meta: anexo.meta.to_h.merge(campo => texto))
  rescue ActiveRecord::ActiveRecordError => e
    Rails.logger.warn("[autonomia][guide][midia] anexo=#{anexo.id} não gravou o texto: #{e.class}: #{e.message}")
  end

  def extrair(blob)
    case self.class.tipo(blob.content_type)
    when 'documento' then documento(blob)
    when 'audio' then audio(blob)
    when 'imagem' then imagem(blob)
    end.to_s.unicode_normalize(:nfc).strip
  end

  # PDF sem OCR, como no atendimento: rasterizar um escaneado leva minutos e o turno do Guia tem teto de
  # tempo. PDF com texto é lido; escaneado volta vazio, e o Guia diz que não conseguiu ler.
  def documento(blob)
    formato = DOCUMENTOS.fetch(blob.content_type.to_s.split(';').first)
    fonte = Fonte.new(Arquivo.new(blob), blob.filename.to_s, formato)
    return ::Autonomia::Agents::Knowledge::Processors::Pdf.new(fonte, ocr: false).extract if formato == 'pdf'

    ::Autonomia::Agents::Knowledge::Processors::Dispatcher.for(fonte).extract
  end

  def audio(blob)
    ::Crm::Ai::TranscriptionClient.new(credential: credencial).transcribe(Audio.new(Arquivo.new(blob), nil))
  end

  def imagem(blob)
    return if blob.byte_size > ::Crm::Ai::Config::IMAGE_BYTE_LIMIT

    data_url = "data:#{blob.content_type};base64,#{Base64.strict_encode64(blob.open(&:read))}"
    cliente = ::Crm::Ai::ResponsesClient.new(credential: credencial, feature: 'guia_midia', account: @account)
    cliente.create(
      model: ::Crm::Ai::Config::VISION_MODEL, instructions: INSTRUCOES_DA_IMAGEM,
      input: [{ role: 'user', content: [{ type: 'input_text', text: PEDIDO_DA_IMAGEM },
                                        { type: 'input_image', image_url: data_url }] }],
      reasoning_effort: ::Crm::Ai::Config::VISION_REASONING_EFFORT
    )[:text]
  end

  def credencial
    @credencial ||= ::Crm::Ai::CredentialResolver.new(account: @account).resolve
  end
end
