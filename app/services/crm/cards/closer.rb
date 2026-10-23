module Crm
  module Cards
    # Win/Lose/Reopen a deal. Independent of stage (locked product decision):
    # a card in any stage can be marked won/lost. status drives closed_at via
    # the model callback; we only set the explicit attributes + audit trail.
    class Closer
      # Status verbs accepted by the close path. The frontend status pickers and
      # bulk bar emit result ∈ open/won/lost (manifest §5 / CrmCellStatus emits
      # 'open'), so 'open' is accepted here as an alias for the internal 'reopen'
      # verb — normalized in #initialize before any lookup. This keeps every
      # caller (single-card #close, BulkAction#change_status!) consistent without
      # each one re-implementing the mapping.
      RESULTS = { 'won' => :won, 'lost' => :lost, 'reopen' => :open }.freeze
      # Event type by the status actually written: num funil que não conta como venda (#1144) o desfecho grava
      # resolved/cancelled, e o evento acompanha.
      EVENT_TYPES = { won: 'won', lost: 'lost', resolved: 'resolved', cancelled: 'cancelled', open: 'reopen' }.freeze
      # External verb -> internal verb. 'open' (frontend "set to open") maps to
      # the 'reopen' transition; all other verbs pass through unchanged.
      VERB_ALIASES = { 'open' => 'reopen', 'resolved' => 'won', 'cancelled' => 'lost' }.freeze

      class InvalidResult < StandardError; end

      # O pedido é de reabrir ('reopen' ou o 'open' da tela)? No card arquivado, reabrir é restaurar (#2095).
      def self.reopen?(result)
        VERB_ALIASES.fetch(result.to_s, result.to_s) == 'reopen'
      end

      # payload_extra: o que mais vai na atividade do fechamento (IA entende a conversa F3: o fechamento da IA leva
      # `by: 'ai'`, o motivo e a confiança, Crm::Ai::FecharCard). Sem ele, a atividade é a de sempre.
      def initialize(card:, actor:, result:, value_cents: nil, currency: nil, lost_reason: nil, payload_extra: {})
        @card = card
        @payload_extra = payload_extra.to_h
        @actor = actor
        @result = VERB_ALIASES.fetch(result.to_s, result.to_s)
        @value_cents = value_cents
        @currency = currency
        @lost_reason = lost_reason
      end

      def perform
        target_status = RESULTS[@result]
        raise InvalidResult, "unknown result: #{@result}" if target_status.blank?

        @target_status = restauracao || Crm::Cards::Outcome.status_for(@card.pipeline, target_status).to_sym

        ActiveRecord::Base.transaction do
          @card.update!(close_attributes(@target_status))
          @restaurado ? log_restauracao! : log_activity!
          # IA entende a conversa F3: card fechado não tem mais o que "Encerrar".
          Crm::Ai::FecharCard.expirar_ao_fechar(@card) if Crm::Cards::Outcome::CLOSED_STATUSES.include?(@target_status.to_s)
        end
        @card
      end

      private

      # Card arquivado depois de fechado (Crm::Card::DESFECHO_ARQUIVADO): reabrir, ou pedir o mesmo desfecho, devolve o
      # que ele era, com a data de antes. Não é um fechamento novo: sem atividade de ganho, o crédito do fechamento e a
      # conversão de anúncio ficam como estavam.
      def restauracao
        desfecho = @card.desfecho_arquivado
        return if desfecho.blank?

        desfecho = Crm::Cards::Outcome.status_for(@card.pipeline, desfecho)
        return unless @result == 'reopen' || Crm::Cards::Outcome.status_for(@card.pipeline, RESULTS[@result]) == desfecho

        @restaurado = true
        desfecho.to_sym
      end

      def log_restauracao!
        Crm::ActivityLogger.new(card: @card, actor: @actor, event_type: 'reopen',
                                payload: @payload_extra.merge(desfecho_restaurado: @target_status.to_s)).perform
      end

      def close_attributes(target_status)
        attributes = { status: target_status, last_activity_at: Time.current }
        case target_status
        when :won
          if @value_cents.present?
            attributes[:value_cents] = @value_cents.to_i
            attributes[:currency] = @currency if @currency.present?
            lock_value_to_human!(attributes)
          end
        when :lost, :cancelled
          attributes[:lost_reason] = @lost_reason if @lost_reason.present?
        when :open
          attributes[:lost_reason] = nil
        end
        attributes
      end

      # Confirming the value at win-time is a human decision: lock the field so a
      # later AI evaluation does not overwrite it.
      def lock_value_to_human!(attributes)
        metadata = (@card.metadata || {}).deep_dup
        metadata['ai'] = (metadata['ai'] || {}).merge('value_source' => 'human')
        attributes[:metadata] = metadata
      end

      def log_activity!
        Crm::ActivityLogger.new(
          card: @card,
          actor: @actor,
          event_type: EVENT_TYPES[@target_status],
          payload: activity_payload
        ).perform
      end

      def activity_payload
        @payload_extra.merge(outcome_payload).merge(closed_with_payload)
      end

      def outcome_payload
        case @target_status
        when :won
          { value_cents: @card.value_cents, currency: @card.currency }
        when :lost, :cancelled
          { lost_reason: @card.lost_reason }.compact
        else
          {}
        end
      end

      # #1876: quem era o responsável, o time e o funil na hora do fechamento — não quem clicou nem quem vier depois. É
      # a base do crédito das metas; vale também para o fechamento da automação, que não tem autor.
      def closed_with_payload
        return {} unless Crm::Cards::Outcome::CLOSED_STATUSES.include?(@target_status.to_s)

        responsible = @card.current_responsible
        {
          closed_with: {
            responsible: responsible&.slice(:type, :id, :name),
            owner_id: @card.owner_id,
            team_id: @card.team_id,
            pipeline_id: @card.pipeline_id
          }
        }
      end
    end
  end
end
