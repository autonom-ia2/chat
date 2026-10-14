module Crm
  class ActivityLogger
    def initialize(card:, actor:, event_type:, payload: {}, conversation: nil)
      @card = card
      @account = card&.account
      @actor = actor
      @event_type = event_type
      @payload = payload || {}
      @conversation = conversation
    end

    # A linha do tempo é do card: lembrete sem card (#1461) não tem onde registrar.
    def perform
      return if @card.nil?

      Crm::Activity.create!(
        account: @account,
        card: @card,
        conversation: @conversation,
        actor_type: actor_type,
        actor_id: @actor&.id,
        event_type: @event_type,
        payload: @payload,
        created_at: Time.current
      )
    end

    private

    def actor_type
      return 'system' if @actor.blank?

      @actor.class.name.underscore
    end
  end
end
