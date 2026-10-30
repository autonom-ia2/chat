module Crm
  module Ai
    # Converts media attachments in a card's recent conversation window into
    # text, cached on `attachment.meta`:
    #   audio → meta['transcribed_text']  (shared with EE transcription)
    #   image → meta['ai_caption']
    # Idempotent (skips already-done attachments) and capped per run to bound
    # cost/latency. Failures are marked done so they are not retried forever.
    # #1926: a janela é a da avaliação de etapa (ContextBuilder.janela_da_avaliacao), não as 12 últimas: áudio ou imagem
    # que a avaliação lê também chega transcrito/descrito. O teto por rodada (limit) segue, das mais novas às mais antigas.
    # IA entende a conversa F4 (flag `crm_ia_leitor_de_midia`): o anexo é lido pelo Crm::Ai::LeitorDeMidia, o mesmo da
    # chegada (mesmas chaves, trava e teto do dia), e o PDF entra também. Sem a flag, igual.
    class MediaEnricher
      def initialize(card:, limit: Config::MAX_MEDIA_ENRICH_PER_EVAL)
        @card = card
        @account = card.account
        @limit = limit
      end

      def perform
        return 0 unless Config.media_enabled?

        credential = CredentialResolver.new(account: @account).resolve
        return 0 if credential.blank?

        count = 0
        pending_attachments.each do |attachment|
          break if count >= @limit

          enrich(attachment, credential)
          count += 1
        end
        count
      end

      private

      def pending_attachments
        conversation = @card.primary_conversation
        return [] if conversation.blank?

        mensagens = conversation.messages
                                .where(private: false)
                                .where.not(message_type: :activity)
                                .reorder(id: :desc)
                                .limit(ContextBuilder.janela_da_avaliacao(1))
        # Com o leitor, a mesma seleção da chegada (o teto por mensagem e por tipo do Crm::Ai::LeitorDeMidia).
        return mensagens.flat_map { |mensagem| leitor_de(mensagem).escolhidos } if leitor?

        mensagens.flat_map(&:attachments).select { |attachment| needs_enrich?(attachment) }
      end

      def leitor_de(mensagem) = Crm::Ai::LeitorDeMidia.new(mensagem, pipeline: @card.pipeline)

      def needs_enrich?(attachment)
        meta = attachment.meta.to_h
        case attachment.file_type.to_s
        when 'audio'
          meta['transcribed_text'].to_s.blank? && !meta['crm_ai_audio_done']
        when 'image'
          meta['ai_caption'].to_s.blank? && !meta['crm_ai_image_done']
        else
          false
        end
      end

      def enrich(attachment, credential)
        return ler_pelo_leitor(attachment) if leitor?

        case attachment.file_type.to_s
        when 'audio' then transcribe(attachment, credential)
        when 'image' then caption(attachment, credential)
        end
      end

      def transcribe(attachment, credential)
        text = TranscriptionClient.new(credential: credential).transcribe(attachment)
        store(attachment, 'transcribed_text', text, done_key: 'crm_ai_audio_done')
      rescue StandardError => e
        Rails.logger.warn("[CRM AI] transcription failed attachment=#{attachment.id}: #{e.message}")
        store(attachment, 'transcribed_text', nil, done_key: 'crm_ai_audio_done')
      end

      def caption(attachment, credential)
        client = ResponsesClient.new(
          credential: credential,
          feature: 'midia', account: @card.account, pipeline: @card.pipeline
        )
        text = VisionCaptioner.new(client: client).caption(attachment)
        store(attachment, 'ai_caption', text, done_key: 'crm_ai_image_done')
      rescue StandardError => e
        Rails.logger.warn("[CRM AI] caption failed attachment=#{attachment.id}: #{e.message}")
        store(attachment, 'ai_caption', nil, done_key: 'crm_ai_image_done')
      end

      # Arquivo que ainda não chegou ao storage fica pendente (o job da chegada tenta de novo), e a avaliação segue.
      def ler_pelo_leitor(attachment)
        leitor_de(attachment.message).ler(attachment)
      rescue ActiveStorage::FileNotFoundError
        Rails.logger.warn("[crm][midia] arquivo_ainda_nao_chegou origem=avaliacao anexo=#{attachment.id}")
        false
      end

      def leitor?
        @leitor = Crm::Ai::LeitorDeMidia.ligada?(@account) unless defined?(@leitor)
        @leitor
      end

      def store(attachment, key, value, done_key:)
        meta = attachment.meta.to_h
        meta[key] = value.to_s if value.present?
        meta[done_key] = true
        meta['crm_ai_enriched_at'] = Time.current.iso8601
        attachment.update!(meta: meta)
      end
    end
  end
end
