module Crm
  module Ai
    class Observer
      def initialize(card:)
        @card = card
      end

      def schedule_evaluation
        return unless Config.enabled?

        token = schedule_token
        Crm::Ai::EvaluateCardJob.set(wait: Config::DEBOUNCE_SECONDS.seconds).perform_later(@card.id, token)
      end

      # Alguém já agendou a avaliação deste card depois de `momento` (#1675): a troca de foco ou o card novo da mesma
      # mensagem. Lê o token do card como ele veio do banco.
      def agendada_desde?(momento)
        token = @card.metadata.to_h.dig('ai', 'evaluate_token')
        token.present? && token.to_f > momento.to_f
      end

      private

      def schedule_token
        token = Time.current.to_f
        # Lido de novo dentro da trava: o card em memória pode ser de antes de outro processo gravar o metadata
        # (estado do follow-up, última avaliação) e sobrescrevê-lo.
        # Um registro novo, não o @card: quem chamou pode ter alterações ainda não salvas nele.
        Crm::Card.transaction do
          fresh = Crm::Card.lock.find(@card.id)
          metadata = (fresh.metadata || {}).deep_dup
          metadata['ai'] = (metadata['ai'] || {}).merge(
            'evaluate_after' => (Time.current + Config::DEBOUNCE_SECONDS.seconds).iso8601,
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
