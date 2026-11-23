module Enterprise::Concerns::Inbox
  extend ActiveSupport::Concern

  included do
    has_one :captain_inbox, dependent: :destroy, class_name: 'CaptainInbox'
    has_one :captain_assistant,
            through: :captain_inbox,
            class_name: 'Captain::Assistant'
    has_many :inbox_capacity_limits, dependent: :destroy
    has_many :calls, dependent: :destroy_async
    has_many :conversation_outcomes, dependent: :destroy_async
    has_one_attached :out_of_hours_call_audio
    has_one_attached :call_greeting_audio
    has_one_attached :unanswered_call_audio

    before_create :ensure_create_permitted
    # Caixa só se liga a portal da própria conta, e nunca ao da plataforma (#501).
    include ::PortalDaCaixa
  end

  # Fork (upgrade 4.20.1, #3120): only Twilio calls go through the upstream call routing (#16637, #16711): ring steps,
  # the per-call ring list, the out-of-hours decline and the auto-assignment hold. WhatsApp calls ring as on the fork,
  # from Whatsapp::IncomingCallService#broadcast_incoming. Every routing branch reads this one predicate.
  def rings_for_calls?
    twilio?
  end

  # Fork (upgrade 4.20.1, #3120): only Twilio calls decline out of hours, as on the fork (see rings_for_calls?).
  def closed_for_calls?
    twilio? && channel.business_hours_calls_enabled? && out_of_office?
  end

  def ensure_create_permitted
    raise CustomExceptions::Inbox::LimitExceeded.new({}) if account.inboxes.count >= account.usage_limits[:inboxes]
  end
end
