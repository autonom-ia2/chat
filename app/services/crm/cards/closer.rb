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

      def initialize(card:, actor:, result:, value_cents: nil, currency: nil, lost_reason: nil)
        @card = card
        @actor = actor
        @result = VERB_ALIASES.fetch(result.to_s, result.to_s)
        @value_cents = value_cents
        @currency = currency
        @lost_reason = lost_reason
      end

      def perform
        target_status = RESULTS[@result]
        raise InvalidResult, "unknown result: #{@result}" if target_status.blank?

        @target_status = Crm::Cards::Outcome.status_for(@card.pipeline, target_status).to_sym

        ActiveRecord::Base.transaction do
          @card.update!(close_attributes(@target_status))
          log_activity!
        end
        @card
      end

      private

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
        case @target_status
        when :won
          { value_cents: @card.value_cents, currency: @card.currency }
        when :lost, :cancelled
          { lost_reason: @card.lost_reason }.compact
        else
          {}
        end
      end
    end
  end
end
