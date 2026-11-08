module Crm
  module Cards
    # Transactional, scope-safe, idempotent bulk mutation over an array of card
    # ids for a SINGLE account. Reuses the existing single-card paths (Mover,
    # Closer, archive) so every per-card change still writes its Crm::Activity
    # entry and fires the realtime/webhook broadcast — bulk is purely a fan-out
    # over the audited primitives, never a shortcut around them.
    #
    # Policy safety: cards outside the caller's visible scope are silently
    # skipped (reported as failed with a `forbidden` error) — the bulk endpoint
    # can never touch a card the user could not touch one-by-one.
    #
    # Idempotency: each action is naturally idempotent. Moving to the current
    # stage is a no-op (Mover), re-archiving an archived card is a no-op, and
    # re-closing with the same result is a no-op (status guard). Re-running the
    # same bulk request therefore yields the same end state.
    #
    # Result: `{ updated: [card_id, ...], failed: [{ id:, error: }, ...] }`.
    class BulkAction
      # Soft-delete = status archived (reversible), matching CardsController#destroy.
      ACTIONS = %w[move assign status delete].freeze
      # Brecha A3 (#1874): cada card passa pela mesma regra da ação de um card só (chave do cargo, card visível e funil).
      # Sem a chave, todo card volta `forbidden` e nada muda; com ela, a recusa por funil continua card a card.
      POLICY_BY_ACTION = { 'move' => :move?, 'assign' => :update?, 'status' => :close?, 'delete' => :destroy? }.freeze
      MAX_IDS = 100

      class InvalidAction < StandardError; end
      # A regra do card recusou a mudança (a mensagem é o código, como no card único); o card fica como estava.
      class Refused < StandardError; end

      def initialize(account:, user:, account_user:, ids:, action:, payload: {})
        @account = account
        @user = user
        @account_user = account_user
        @ids = Array(ids).map { |id| id.to_s[/\d+/]&.to_i }.compact.uniq.first(MAX_IDS)
        @action = action.to_s
        @payload = (payload || {}).to_h.with_indifferent_access
      end

      def perform
        raise InvalidAction, "unknown action: #{@action}" unless ACTIONS.include?(@action)

        updated = []
        failed = []

        # Resolve the target stage once for `move` (shared across all ids); a bad
        # stage_id fails the whole request fast rather than per-card.
        target_stage = resolve_target_stage if @action == 'move'

        @ids.each do |id|
          card = visible_cards_by_id[id]
          next failed << { id: id, error: 'forbidden' } if card.blank?
          # Acesso por funil (#1148) e chave da ação (#1874); mover exige também o funil de destino.
          next failed << { id: id, error: 'forbidden' } if forbidden?(card, target_stage)

          # Each card is its own transaction so a single failure (e.g. a card
          # that vanished mid-request) reports as `failed` without rolling back
          # the cards that already succeeded — the desired partial-success
          # semantics for a fan-out bulk operation.
          ActiveRecord::Base.transaction(requires_new: true) do
            apply_action!(card, target_stage: target_stage)
            updated << card.id
          end
        rescue StandardError => e
          failed << { id: id, error: e.message }
        end

        { updated: updated, failed: failed }
      end

      private

      def apply_action!(card, target_stage:)
        case @action
        when 'move'   then move_card!(card, target_stage)
        when 'assign' then assign_owner!(card)
        when 'status' then change_status!(card)
        when 'delete' then archive_card!(card)
        end
      end

      def move_card!(card, target_stage)
        moved = Crm::Cards::Mover.new(card: card, actor: @user, target_stage: target_stage).perform
        broadcast(moved, ::Events::Types::CRM_CARD_MOVED)
      end

      def assign_owner!(card)
        owner_id = @payload[:owner_id].presence
        # owner_id may be nil to unassign; an unchanged owner is a no-op.
        return if card.owner_id == owner_id&.to_i

        # Acesso por funil (#1148, decisão a): só vira dono quem tem o funil do card.
        card_guard.ensure_owner_allowed!(owner_id, inbox_id: card.inbox_id, pipeline_id: card.pipeline_id)
        card.update!(owner_id: owner_id, last_activity_at: Time.current)
        Crm::ActivityLogger.new(
          card: card, actor: @user, event_type: 'update', payload: { owner_id: card.owner_id }
        ).perform
        broadcast(card, ::Events::Types::CRM_CARD_UPDATED)
      end

      def change_status!(card)
        # Bulk bar emits result ∈ open/won/lost (manifest §5). Closer accepts
        # 'open' as an alias for its internal 'reopen' verb (see
        # Closer::VERB_ALIASES), so a bulk "set to open" reopens the card instead
        # of silently failing every id with Closer::InvalidResult.
        result = @payload[:result].to_s
        return restore_card!(card, result) if Crm::Cards::Restorer.reabrir_e_restaurar?(card)

        closed = Crm::Cards::Closer.new(card: card, actor: @user, result: result).perform
        broadcast(closed, ::Events::Types::CRM_CARD_UPDATED)
      end

      # Card arquivado (#2095, com a flag crm_arquivados): "Aberto" restaura, com as recusas do restaurar (funil arquivado, cliente que já voltou),
      # sem forçar; ganho ou perdido é recusado, como no card único (restaure antes).
      def restore_card!(card, result)
        raise Refused, Crm::Cards::Restorer::CLOSE_ARCHIVED unless Crm::Cards::Closer.reopen?(result)

        restored = Crm::Cards::Restorer.new(card: card, actor: @user).perform
        raise Refused, restored.error unless restored.restored?

        broadcast(card, ::Events::Types::CRM_CARD_UPDATED)
      end

      def archive_card!(card)
        return unless Crm::Cards::Archiver.new(card: card, actor: @user).perform

        broadcast(card, ::Events::Types::CRM_CARD_ARCHIVED)
      end

      def broadcast(card, event_name)
        Crm::Cards::Broadcaster.broadcast(card, event_name)
      end

      def resolve_target_stage
        stage_id = @payload[:stage_id]
        raise InvalidAction, 'stage_id required' if stage_id.blank?

        @account.crm_pipeline_stages.find(stage_id)
      end

      def forbidden?(card, target_stage)
        return true unless Pundit.policy!(user_context, card).public_send(policy_query(card))

        target_stage.present? && !card_guard.move_allowed?(card, target_stage.pipeline_id)
      end

      # Reabrir o card arquivado é restaurar (#2095): a regra é a do restaurar (Crm::CardPolicy#restore?), não a do fechar.
      # Só com a flag crm_arquivados; sem ela, como antes.
      def policy_query(card)
        return :restore? if @action == 'status' && Crm::Cards::Restorer.reabrir_e_restaurar?(card)

        POLICY_BY_ACTION.fetch(@action)
      end

      def user_context
        { user: @user, account: @account, account_user: @account_user }
      end

      def card_guard
        @card_guard ||= Crm::Access::CardGuard.new(user: @user, account: @account, account_user: @account_user)
      end

      def visible_scope
        Crm::Cards::VisibleScopeQuery.new(
          scope: @account.crm_cards,
          account: @account,
          user: @user,
          account_user: @account_user
        ).perform
      end

      def visible_cards_by_id
        @visible_cards_by_id ||= visible_scope.where(id: @ids).index_by(&:id)
      end
    end
  end
end
