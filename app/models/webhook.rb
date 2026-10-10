# == Schema Information
#
# Table name: webhooks
#
#  id                  :bigint           not null, primary key
#  include_contact_pii :boolean          default(FALSE), not null
#  name                :string
#  secret              :string
#  subscriptions       :jsonb
#  url                 :text
#  webhook_type        :integer          default("account_type")
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :integer
#  inbox_id            :integer
#
# Indexes
#
#  index_webhooks_on_account_id_and_url  (account_id,url) UNIQUE
#

class Webhook < ApplicationRecord
  belongs_to :account
  belongs_to :inbox, optional: true

  include WebhookSecretable

  validates :account_id, presence: true
  validates :url, uniqueness: { scope: [:account_id] }, format: URI::DEFAULT_PARSER.make_regexp(%w[http https])
  validate :validate_webhook_subscriptions
  enum webhook_type: { account_type: 0, inbox_type: 1 }

  CORE_WEBHOOK_EVENTS = %w[conversation_status_changed conversation_updated conversation_created contact_created contact_updated
                           message_created message_updated webwidget_triggered inbox_created inbox_updated
                           conversation_typing_on conversation_typing_off].freeze

  # CRM lifecycle events use the canonical DOTTED form everywhere (subscription
  # value, payload[:event], dispatcher constant); the listener method is the
  # name with dots->underscores (crm.card.won -> crm_card_won). Plan §3.1.
  CRM_WEBHOOK_EVENTS = %w[crm.card.created crm.card.moved crm.card.won crm.card.lost
                          crm.card.resolved crm.card.cancelled crm.card.reopened crm.card.archived].freeze

  # Gated behind Crm::Config.enabled? so CE installs (CRM disabled) never offer
  # dead crm.* subscriptions. Computed at call time so the ENV gate is honored
  # without a constant freeze ordering hazard.
  def self.allowed_webhook_events
    return CORE_WEBHOOK_EVENTS unless defined?(Crm::Config) && Crm::Config.enabled?

    CORE_WEBHOOK_EVENTS + CRM_WEBHOOK_EVENTS
  end

  private

  def validate_webhook_subscriptions
    invalid_subscriptions = !subscriptions.instance_of?(Array) ||
                            subscriptions.blank? ||
                            (subscriptions.uniq - self.class.allowed_webhook_events).length.positive?
    errors.add(:subscriptions, I18n.t('errors.webhook.invalid')) if invalid_subscriptions
  end
end

Webhook.include_mod_with('Audit::Webhook')
