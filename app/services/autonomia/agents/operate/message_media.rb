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

        # O anexo está "em leitura" pelo leitor de mídia do CRM: transcrever aqui seria pagar duas vezes (#2109).
        EM_LEITURA = :em_leitura

        # `messages:` é o caminho do turno (os anexos das mensagens); `attachments:` é o do especialista,
        # que já escolheu os anexos (entrega 1). Um ou outro.
        def initialize(agent:, messages: [], attachments: nil)
          @messages = Array(messages)
          @attachments = attachments
          @agent = agent
        end

        # -> Result (images: [data-url], transcripts: [String], documents: [{name:, text:, checksum:}])
        def extract
          return EMPTY if attachments.empty?

          Result.new(images: collect_images(attachments), transcripts: collect_transcripts(attachments),
                     documents: collect_documents(attachments))
        rescue StandardError => e
          Rails.logger.warn("[autonomia][operate] media_extract_failed agent=#{@agent.id} #{e.class}")
          EMPTY
        end

        # SÓ OS DOCUMENTOS (entrega 1): até `limit` PDFs LEGÍVEIS, na ordem dada, em até `attempts`
        # EXTRAÇÕES — um PDF sem camada de texto não ocupa vaga, porque quem procura é o especialista e a
        # vaga é para uma apólice que se leia; mas cada tentativa baixa e lê um PDF, e é o orçamento de
        # tentativas que limita a espera. Sem pagar transcrição de áudio nem baixar imagem: nada disso
        # serve ao formulário. (O turno do principal continua em `extract`, com o teto por mensagem
        # contado ANTES de extrair — `attempts` igual a `limit` é exatamente isso.)
        def documents(limit: Config::MAX_DOCUMENTS_PER_MESSAGE, attempts: limit)
          elegiveis = attachments.lazy.select { |attachment| document?(attachment) }.first(attempts)
          elegiveis.lazy.filter_map { |attachment| document_text(attachment) }.first(limit)
        rescue StandardError => e
          Rails.logger.warn("[autonomia][operate] media_extract_failed agent=#{@agent&.id} #{e.class}")
          []
        end

        private

        def attachments
          @attachments ||= @messages.flat_map { |message| message.attachments.to_a }
        end

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

        # -> { name:, text:, checksum: } ou nil. Reusa o processor da base de conhecimento (pdf-reader,
        # com OCR quando o PDF é escaneado). NFC porque o texto sai decomposto: o `ô` de "bônus" vem
        # como `o` + acento, e uma busca por "bônus" não casa — medido na apólice real de 04/09.
        # `checksum` é a identidade do CONTEÚDO (calculada no upload): quem lê depois — o especialista —
        # sabe o que já entrou neste turno sem comparar nome de arquivo.
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

          { name: blob.filename.to_s, text: Config.truncate_text(text, Config::MAX_DOCUMENT_CHARS), checksum: blob.checksum }
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

          # Um só prazo no turno para esperar o leitor do CRM, em todos os áudios: no máximo ESPERA_EM_LINHA.
          ate_em = Crm::Ai::ReservaDaMidia::ESPERA_EM_LINHA.from_now
          audios.filter_map { |attachment| transcript_for(attachment, credential, ate_em) }
        end

        # Transcreve (ou reusa o cache compartilhado). NUNCA loga o texto. Falha de transcrição -> nil (o
        # prompt v2 manda pedir o texto/resumo quando não há transcrição).
        def transcript_for(attachment, credential, ate_em)
          cached = attachment.meta.to_h['transcribed_text'].to_s
          return cached if cached.present?

          lido_pelo_crm = texto_do_leitor_do_crm(attachment, ate_em)
          return lido_pelo_crm if lido_pelo_crm.present?

          texto = transcrever_uma_vez(attachment, credential)
          texto == EM_LEITURA ? texto_do_leitor_do_crm(attachment, ate_em) : texto.presence
        rescue StandardError => e
          Rails.logger.warn("[autonomia][operate] transcription_failed attachment=#{attachment.id} #{e.class}")
          nil
        end

        # A mesma reserva do leitor de mídia do CRM (Crm::Ai::ReservaDaMidia, #2141): trava curta que relê o cache e marca
        # o anexo "em leitura"; a transcrição roda fora de transação. Quem chega depois (o leitor do CRM ou outro turno)
        # vê a marca e espera o texto em vez de pagar de novo. Sem reserva: o texto já gravado, ou EM_LEITURA quando outro
        # processo está pagando (o turno espera o texto dele fora da trava).
        def transcrever_uma_vez(attachment, credential)
          dono = Crm::Ai::ReservaDaMidia.reservar(attachment) { attachment.meta.to_h['transcribed_text'].blank? }
          return attachment.meta.to_h['transcribed_text'].to_s.presence || EM_LEITURA unless dono

          text = nil
          begin
            text = Crm::Ai::TranscriptionClient.new(credential: credential).transcribe(attachment).to_s.strip
          ensure
            cache_transcript(attachment, text, dono) # best-effort: alimenta ESTE turno mesmo se o cache falhar
          end
          text
        end

        # O leitor de mídia do CRM lê fora da trava (#2109) e marca o anexo "em leitura" (Crm::Ai::ReservaDaMidia): o turno
        # espera o texto dele até `ate_em` antes de pagar a transcrição de novo. -> o texto, ou nil (a marca seguiu válida:
        # o turno vai sem a transcrição, e o leitor grava o texto para o próximo).
        def texto_do_leitor_do_crm(attachment, ate_em)
          return unless Crm::Ai::ReservaDaMidia.lendo?(attachment.meta.to_h)

          Crm::Ai::ReservaDaMidia.esperar(attachment, ate_em: ate_em).meta.to_h['transcribed_text'].to_s.presence
        end

        # Cache compartilhado (attachment.meta['transcribed_text']), gravado sobre o meta atual, e a reserva liberada (com
        # ou sem texto). NUNCA derruba o turno se a escrita falhar: a marca vence no PRAZO.
        def cache_transcript(attachment, text, dono)
          Crm::Ai::ReservaDaMidia.gravar(attachment, dono: dono) { |meta| text.present? ? meta.merge('transcribed_text' => text) : meta }
        rescue StandardError => e
          Rails.logger.warn("[autonomia][operate] transcription_cache_failed attachment=#{attachment.id} #{e.class}")
          nil
        end
      end
    end
  end
end
