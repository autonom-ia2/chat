module Crm
  module Ai
    class Observer
      def initialize(card:)
        @card = card
      end

      # `espera`: o debounce. A mensagem do cliente usa o de sempre; a da equipe, uma espera maior (#1923,
      # Crm::Conversations::CardEmFoco::ESPERA_DA_EQUIPE).
      def schedule_evaluation(espera: Config::DEBOUNCE_SECONDS.seconds)
        return unless Config.enabled?

        token = marcar(Time.current.to_f, espera: espera)
        Crm::Ai::EvaluateCardJob.set(wait: espera).perform_later(@card.id, token)
      end

      # Alguém já agendou a avaliação deste card depois de `momento` (#1675): a troca de foco ou o card novo da mesma
      # mensagem. Lê o token do card como ele veio do banco.
      def agendada_desde?(momento)
        token = @card.metadata.to_h.dig('ai', 'evaluate_token')
        token.present? && token.to_f > momento.to_f
      end

      # Há uma avaliação deste card esperando a vez (#1923): quando rodar, ela lê o que chegou agora. Lê o card como ele
      # veio do banco; `evaluate_after` que já passou é de uma avaliação que rodou (ou caiu).
      def pendente?
        depois = @card.metadata.to_h.dig('ai', 'evaluate_after')
        depois.present? && Time.zone.parse(depois.to_s) > Time.current
      rescue ArgumentError
        false
      end

      # Grava o token do agendamento no card (#1693: a avaliação conjunta usa o mesmo token em todos os cards dela). Uma
      # avaliação agendada antes, deste card, fica velha e não roda (EvaluateCardJob e EvaluateCardsJob).
      def marcar(token, espera: Config::DEBOUNCE_SECONDS.seconds)
        # Lido de novo dentro da trava: o card em memória pode ser de antes de outro processo gravar o metadata
        # (estado do follow-up, última avaliação) e sobrescrevê-lo.
        # Um registro novo, não o @card: quem chamou pode ter alterações ainda não salvas nele.
        Crm::Card.transaction do
          fresh = Crm::Card.lock.find(@card.id)
          metadata = (fresh.metadata || {}).deep_dup
          metadata['ai'] = (metadata['ai'] || {}).merge(
            'evaluate_after' => (Time.current + espera).iso8601,
            'evaluate_token' => token
          )
          fresh.update!(metadata: metadata)
          # Quem chamou continua com o metadata gravado: um save seguinte dele não apaga o token.
          @card.metadata = fresh.metadata
          @card.clear_attribute_changes([:metadata])
        end
        token
      end
    end
  end
end
