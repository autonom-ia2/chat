# Ditado da resposta de e-mail (#1786): a pessoa fala e o texto entra na caixa de resposta para revisar antes de
# enviar ("como no Claude"). Usa o mesmo motor que transcreve os áudios do atendimento (Crm::Ai::TranscriptionClient,
# em português, com a chave de IA da conta ou da instalação, via Crm::Ai::CredentialResolver). O transcritor lê o
# próprio arquivo recebido, sem subir para o armazenamento e baixar de volta dentro da requisição; nada fica guardado.
# O navegador para o ditado sozinho no teto de tempo (useDitado), para a transcrição caber nos 15 s da requisição.
class ConversaCanal::Ditado
  class Falha < StandardError; end

  # O transcritor lê `attachment.file.blob`, como num anexo de conversa. Aqui o "blob" é o arquivo da requisição.
  Anexo = Struct.new(:file, :id)
  Arquivo = Struct.new(:blob)
  # O whisper decide o formato pela extensão do arquivo. O navegador manda o tipo da gravação, e o Safari grava em
  # `audio/mp4`, que levou 400 da OpenAI com a extensão .mp4 (testado no demo, 18/10); como m4a, passa. Cada tipo de
  # gravação vira um tipo e uma extensão que o whisper aceita. O tipo vem sem os parâmetros (`;codecs=opus`).
  FORMATOS = {
    'audio/mp4' => %w[audio/x-m4a m4a], 'audio/x-m4a' => %w[audio/x-m4a m4a], 'audio/m4a' => %w[audio/x-m4a m4a],
    'audio/aac' => %w[audio/x-m4a m4a], 'audio/webm' => %w[audio/webm webm], 'audio/ogg' => %w[audio/ogg ogg],
    'audio/wav' => %w[audio/wav wav], 'audio/x-wav' => %w[audio/wav wav], 'audio/wave' => %w[audio/wav wav],
    'audio/mpeg' => %w[audio/mpeg mp3], 'audio/flac' => %w[audio/flac flac]
  }.freeze

  BlobDoAudio = Struct.new(:tempfile, :content_type, :key, :extensao) do
    def filename
      ActiveStorage::Filename.new("ditado.#{extensao}")
    end

    def byte_size
      tempfile.size
    end

    def open(&)
      File.open(tempfile.path, 'rb', &)
    end
  end

  def self.disponivel?(account)
    Crm::Ai::CredentialResolver.new(account: account).configured?
  end

  def initialize(account:, audio:)
    @account = account
    @audio = audio
  end

  def texto
    credencial = Crm::Ai::CredentialResolver.new(account: @account).resolve
    raise Falha, I18n.t('conversa_canal.ditado.sem_ia') if credencial.blank?

    conferir_audio!
    texto = transcrever(credencial)
    raise Falha, I18n.t('conversa_canal.ditado.vazio') if texto.blank?

    texto
  rescue Falha
    raise
  rescue StandardError => e
    Rails.logger.warn("[ConversaCanal::Ditado] account_id=#{@account.id} erro=#{e.class.name}")
    raise Falha, I18n.t('conversa_canal.ditado.falhou')
  end

  private

  def transcrever(credencial)
    tipo, extensao = formato
    blob = BlobDoAudio.new(@audio.tempfile, tipo, "ditado-#{SecureRandom.hex(8)}", extensao)
    Crm::Ai::TranscriptionClient.new(credential: credencial).transcribe(Anexo.new(Arquivo.new(blob), nil)).to_s.strip
  end

  def formato
    FORMATOS[@audio.content_type.to_s.split(';').first.to_s.strip.downcase]
  end

  def conferir_audio!
    valido = @audio.respond_to?(:tempfile) && formato.present?
    raise Falha, I18n.t('conversa_canal.ditado.sem_audio') unless valido
    raise Falha, I18n.t('conversa_canal.ditado.grande') if @audio.size > Crm::Ai::Config::TRANSCRIPTION_BYTE_LIMIT
  end
end
