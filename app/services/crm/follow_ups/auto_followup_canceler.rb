module Crm
  module FollowUps
    # Primary auto-stop path for the AI follow-up cadence: when the contact
    # REPLIES (inbound message) — or opts out via STOP/SAIR — cancel every
    # pending ai_followup touch on the card immediately, instead of waiting for
    # the next due sweep. Invoked from Crm::Conversations::CardSyncer on every
    # synced message.
    #
    # Strictly guarded and additive: it does NOTHING unless the triggering
    # message is INBOUND and the card has an ACTIVE ai_followup cadence. Manual
    # follow-ups, stage-automation follow-ups and the sync/AI-evaluation flow are
    # never touched.
    class AutoFollowupCanceler
      # Palavra sozinha = a forma canônica de opt-out do WhatsApp: o cliente responde só "SAIR",
      # "STOP", "PARAR". Só vale quando é a mensagem INTEIRA. Aceitar a palavra solta no meio de
      # uma frase transformaria "vou sair agora, te respondo depois" e "quero cancelar minha
      # reunião de amanhã" em opt-out — e opt-out falso mente justamente na auditoria de LGPD,
      # que é o número que esta lista existe para tornar confiável.
      OPT_OUT_KEYWORDS = %w[stop sair parar cancelar descadastrar unsubscribe].freeze

      # Frases que já carregam a intenção inteira, então valem em qualquer posição do texto
      # ("pode parar por favor", "olha, não quero mais receber essas mensagens"). É uma lista de
      # formas conhecidas, não compreensão de linguagem: uma recusa escrita de um jeito que não
      # está aqui entra como resposta comum — a cadência para do mesmo jeito, só não é marcada
      # como opt-out.
      OPT_OUT_PHRASES = [
        'pode parar', 'podem parar',
        'para de mandar', 'pare de mandar', 'parar de mandar',
        'para de me mandar', 'pare de me mandar', 'parar de me mandar',
        'para de enviar', 'pare de enviar', 'parar de enviar',
        'nao me envie mais', 'nao me envia mais', 'nao me manda mais', 'nao me mande mais',
        'parar de receber', 'cancelar o recebimento',
        'nao quero mais receber', 'nao quero receber mais', 'nao quero receber mensagens',
        'nao quero mais mensagens', 'nao quero mais essas mensagens',
        'me tira da lista', 'me tire da lista', 'me remove da lista', 'me remova da lista',
        'remova meu numero', 'remove meu numero', 'tira meu numero', 'tire meu numero',
        'sair da lista', 'descadastrar'
      ].freeze

      def initialize(card:, message: nil)
        @card = card
        @message = message
      end

      def maybe_cancel
        return unless @message&.incoming?
        return unless cadence_active?

        cancel_pending_follow_ups
        opted_out = opt_out?(@message)
        reason = opted_out ? 'opt_out' : 'replied'
        write_state(reason, opted_out)
        log_stopped(reason)
      end

      private

      def cadence_active?
        state['active'] == true
      end

      def cancel_pending_follow_ups
        @card.follow_ups.active.find_each do |follow_up|
          next unless follow_up.metadata.to_h['source'] == 'ai_followup'

          follow_up.update!(status: :canceled)
        end
      end

      def opt_out?(message)
        text = normalize_for_opt_out(message&.content)
        return false if text.blank?

        opt_out_keyword_match?(text) || opt_out_phrase_match?(text)
      end

      # Minúsculas + sem acento (I18n.transliterate) + espaços colapsados + pontuação de borda
      # removida, para que "Sair!", "  PARAR  " ou "Não quero mais receber." comparem igual às
      # formas normalizadas das listas acima. Pontuação NO MEIO da frase é preservada (não afeta
      # o match de palavra/frase feito a seguir).
      def normalize_for_opt_out(raw)
        text = I18n.transliterate(raw.to_s.downcase)
        text = text.gsub(/\s+/, ' ').strip
        text.gsub(/\A[[:punct:]]+|[[:punct:]]+\z/, '').strip
      end

      def opt_out_keyword_match?(text)
        OPT_OUT_KEYWORDS.include?(text)
      end

      def opt_out_phrase_match?(text)
        OPT_OUT_PHRASES.any? { |phrase| text.include?(phrase) }
      end

      def state
        (@card.metadata || {}).fetch('ai', {}).to_h.fetch('auto_followup_state', {}).to_h
      end

      def write_state(reason, opted_out)
        metadata = (@card.metadata || {}).deep_dup
        metadata['ai'] ||= {}
        metadata['ai']['auto_followup_state'] = state.merge(
          'active' => false,
          'stopped_reason' => reason,
          'opted_out' => opted_out,
          'next_due_at' => nil
        )
        @card.update!(metadata: metadata)
      end

      def log_stopped(reason)
        Crm::ActivityLogger.new(
          card: @card,
          actor: nil,
          event_type: 'ai_followup_stopped',
          conversation: @card.primary_conversation,
          payload: { reason: reason, trigger: 'inbound_reply', message_id: @message&.id }
        ).perform
      end
    end
  end
end
