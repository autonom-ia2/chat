module Crm
  module Reports
    # Follow-up health snapshot: counts by status plus overdue and due-soon (pending within the next 48h).
    # Account-wide, optionally narrowed to the selected pipeline's cards.
    #
    # #1876: atrasado é o que venceu e ninguém fez. O DueProcessor passa a cada minuto e troca o lembrete vencido de
    # `pending` para `overdue`; contar só o `pending` vencido deixava o número perto de zero. Agora conta os dois estados
    # e separa o que é da IA (os toques que ela mesma agenda) do que é da equipe.
    class FollowUps < BaseReport
      DUE_SOON_WINDOW = 48.hours
      AI_SOURCES = [
        'ai_followup', # Crm::FollowUps::AutoFollowupTouchBuilder, o mesmo marcador que o DueProcessor lê
        Crm::FollowUps::CallbackScheduler::SOURCE,
        Crm::FollowUps::ServiceReminderScheduler::SOURCE
      ].freeze

      def perform
        by_status = Crm::FollowUp.statuses.keys.index_with { |status| status_counts[status] || 0 }
        ai = overdue_scope.where(ai_source_condition).count
        total = overdue_scope.count

        {
          by_status: by_status,
          overdue: total,
          overdue_by: { ai: ai, human: total - ai },
          due_soon: due_soon_scope.count
        }
      end

      private

      def base_scope
        scope = account.crm_follow_ups
        return scope if pipeline.blank? && !Crm::Relacao.ligada?(account)

        cards = Crm::Relacao.cards_do_funil(account)
        cards = cards.where(pipeline_id: pipeline.id) if pipeline.present?
        scope.where(card_id: cards.select(:id))
      end

      # A chave do enum vem como texto ("pending"); a leitura antiga procurava pelo número e tudo saía 0.
      def status_counts
        @status_counts ||= base_scope.group(:status).count
      end

      def overdue_scope
        base_scope.where(status: Crm::FollowUp.statuses[:overdue])
                  .or(base_scope.where(status: Crm::FollowUp.statuses[:pending], due_at: ...now))
      end

      def ai_source_condition
        ["crm_follow_ups.metadata ->> 'source' IN (?)", AI_SOURCES]
      end

      def due_soon_scope
        base_scope.where(status: Crm::FollowUp.statuses[:pending], due_at: now..(now + DUE_SOON_WINDOW))
      end
    end
  end
end
