module Autonomia
  module Agents
    module Operate
      # Track B (Onda 2): extrai a mídia das mensagens INCOMING do turno atual (as que o cliente acabou
      # de mandar) e a converte no que o Answerer consome:
      #   - imagem/figurinha (file_type:image) -> data-url base64 inline (input_image). Lê o blob via
      #     ActiveStorage (`blob.download`), NUNCA URL pública/assinada -> anti-SSRF e sem vazar signed URL.
      #     Allowlist de content-type (IMAGE_CONTENT_TYPES) + <= MAX_IMAGE_BYTES + teto MAX_IMAGES_PER_MESSAGE.
      #   - áudio (file_type:audio) -> transcrição via Crm::Ai::TranscriptionClient (cred OpenAI da conta,
      #     NÃO loga o conteúdo), cacheada em attachment.meta['transcribed_text'] (chave compartilhada com a EE).
      #
      # Fail-safe: erro em um anexo é engolido (o turno segue com o que deu certo). NUNCA loga base64 nem
      # o texto transcrito. Stickers do WhatsApp chegam como file_type:image (webp) -> cobertos pelo path de imagem.
      class MessageMedia
        Result = Struct.new(:images, :transcripts, :documents, keyword_init: true) do
          def empty?
            images.empty? && transcripts.empty? && documents.empty?
          end
        end

        EMPTY = Result.new(images: [], transcripts: [], documents: []).freeze

        # O `Knowledge::Processors::Pdf` espera uma FONTE da base de conhecimento (`file`,
        # `reference`, `source_type`). Um anexo de conversa tem o blob mas não o resto. Este
        # adaptador dá ao processor a forma que ele pede, sem tocar no caminho de ingestão — que é
        # o mesmo código, exercitado todo dia pelo outro consumidor.
        SourceLike = Struct.new(:file, :reference, :source_type)

        def initialize(messages:, agent:)
          @messages = Array(messages)
          @agent = agent
        end

        # -> Result (images: [data-url], transcripts: [String], documents: [{name:, text:}])
        def extract
          attachments = @messages.flat_map { |message| message.attachments.to_a }
          return EMPTY if attachments.empty?

          Result.new(images: collect_images(attachments), transcripts: collect_transcripts(attachments),
                     documents: collect_documents(attachments))
        rescue StandardError => e
          Rails.logger.warn("[autonomia][operate] media_extract_failed agent=#{@agent.id} #{e.class}")
          EMPTY
        end

        private

        def collect_images(attachments)
          attachments
            .select { |attachment| attachment.file_type.to_s == 'image' }
            .first(Config::MAX_IMAGES_PER_MESSAGE) # capa ANTES de baixar: limita blob.download a <=4
            .filter_map { |attachment| image_data_url(attachment) }
        end

        # Blob -> data-url base64. Checa byte_size ANTES de baixar (evita carregar um anexo gigante na
        # memória) e DEPOIS (defesa em profundidade). content-type validado contra a allowlist do builder.
        def image_data_url(attachment)
          blob = attachment.file&.blob
          return if blob.blank?

          content_type = blob.content_type.to_s.downcase.split(';').first
          return unless Config::IMAGE_CONTENT_TYPES.include?(content_type)
          return if blob.byte_size > Config::MAX_IMAGE_BYTES

          data = blob.download
          return if data.blank? || data.bytesize > Config::MAX_IMAGE_BYTES

          "data:#{content_type};base64,#{Base64.strict_encode64(data)}"
        rescue StandardError
          nil # anexo ilegível -> descarta a imagem, mantém o turno. NUNCA loga o conteúdo.
        end

        # PDF anexado -> texto. Na renovação é a apólice, e é ela que traz classe de bônus,
        # sinistros, seguradora anterior e as coberturas contratadas — o que faz a cotação sair sem
        # interrogatório. Capa ANTES de baixar, como nas imagens.
        def collect_documents(attachments)
          attachments
            .select { |attachment| document?(attachment) }
            .first(Config::MAX_DOCUMENTS_PER_MESSAGE)
            .filter_map { |attachment| document_text(attachment) }
        end

        # `file_type` do Chatwoot para PDF é `:file` — genérico. Quem decide é o content-type do
        # blob, contra a allowlist; sem isso, qualquer anexo entraria no extrator de PDF.
        def document?(attachment)
          return false unless attachment.file_type.to_s == 'file'

          blob = attachment.file&.blob
          return false if blob.blank?

          content_type = blob.content_type.to_s.downcase.split(';').first
          Config::DOCUMENT_CONTENT_TYPES.include?(content_type) && blob.byte_size <= Config::MAX_DOCUMENT_BYTES
        end

        # -> { name:, text: } ou nil. Reusa o processor da base de conhecimento (pdf-reader, com
        # OCR quando o PDF é escaneado). NFC porque o texto sai decomposto: o `ô` de "bônus" vem
        # como `o` + acento, e uma busca por "bônus" não casa — medido na apólice real de 04/09.
        def document_text(attachment)
          blob = attachment.file.blob
          source = SourceLike.new(attachment.file, blob.filename.to_s, 'pdf')
          # `ocr: false` é o que separa este caminho do da base de conhecimento. O OCR rasteriza
          # página por página a 300 DPI: um escaneado de 5 MB são dezenas de páginas e centenas de
          # segundos, dentro de um turno que tem 120s de teto e um cliente esperando. Sem camada de
          # texto, o documento não é lido e o agente pede os dados — que é o que ele já fazia.
          text = ::Autonomia::Agents::Knowledge::Processors::Pdf.new(source, ocr: false).extract.to_s
          text = text.unicode_normalize(:nfc).strip
          return if text.blank?

          { name: blob.filename.to_s, text: Config.truncate_text(text, Config::MAX_DOCUMENT_CHARS) }
        rescue StandardError => e
          # Documento ilegível não derruba o turno: o agente segue e pergunta os dados. NUNCA loga
          # o conteúdo — é a apólice de uma pessoa.
          Rails.logger.warn("[autonomia][operate] document_extract_failed agent=#{@agent.id} #{e.class}")
          nil
        end

        def collect_transcripts(attachments)
          # Capa ANTES de transcrever: limita a custo/latência da API a no máximo MAX_AUDIO_PER_MESSAGE.
          audios = attachments.select { |attachment| attachment.file_type.to_s == 'audio' }
                              .first(Config::MAX_AUDIO_PER_MESSAGE)
          return [] if audios.empty?

          credential = Crm::Ai::CredentialResolver.new(account: @agent.account).resolve
          return [] if credential.blank?

          audios.filter_map { |attachment| transcript_for(attachment, credential) }
        end

        # Transcreve (ou reusa o cache compartilhado). NUNCA loga o texto. Falha de transcrição -> nil (o
        # prompt v2 manda pedir o texto/resumo quando não há transcrição).
        def transcript_for(attachment, credential)
          cached = attachment.meta.to_h['transcribed_text'].to_s
          return cached if cached.present?

          text = Crm::Ai::TranscriptionClient.new(credential: credential).transcribe(attachment).to_s.strip
          return if text.blank?

          cache_transcript(attachment, text) # best-effort: a transcrição alimenta ESTE turno mesmo se o cache falhar
          text
        rescue StandardError => e
          Rails.logger.warn("[autonomia][operate] transcription_failed attachment=#{attachment.id} #{e.class}")
          nil
        end

        # Cache compartilhado (attachment.meta['transcribed_text']). Recarrega antes do merge p/ reduzir
        # sobrescrita de chaves concorrentes; NUNCA derruba o turno se a escrita falhar (rescue -> nil).
        def cache_transcript(attachment, text)
          attachment.reload
          attachment.update!(meta: attachment.meta.to_h.merge('transcribed_text' => text))
        rescue StandardError
          nil
        end
      end
    end
  end
end
