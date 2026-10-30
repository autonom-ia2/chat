# == Schema Information
#
# Table name: channel_facebook_pages
#
#  id                :integer          not null, primary key
#  page_access_token :string           not null
#  user_access_token :string           not null
#  created_at        :datetime         not null
#  updated_at        :datetime         not null
#  account_id        :integer          not null
#  instagram_id      :string
#  page_id           :string           not null
#
# Indexes
#
#  index_channel_facebook_pages_on_page_id                 (page_id)
#  index_channel_facebook_pages_on_page_id_and_account_id  (page_id,account_id) UNIQUE
#

class Channel::FacebookPage < ApplicationRecord
  include Channelable
  include Reauthorizable

  # TODO: Remove guard once encryption keys become mandatory (target 3-4 releases out).
  if Chatwoot.encryption_configured?
    encrypts :page_access_token
    encrypts :user_access_token
  end

  self.table_name = 'channel_facebook_pages'

  MESSENGER_FIELDS = %w[
    messages message_deliveries message_echoes message_reads standby messaging_handovers messaging_postbacks
  ].freeze

  validates :page_id, uniqueness: { scope: :account_id }

  after_create_commit :subscribe
  before_destroy :unsubscribe

  def name
    'Facebook'
  end

  def create_contact_inbox(instagram_id, name)
    @contact_inbox = ::ContactInboxWithContactBuilder.new({
                                                            source_id: instagram_id,
                                                            inbox: inbox,
                                                            contact_attributes: { name: name }
                                                          }).perform
  end

  def subscribe
    # ref https://developers.facebook.com/docs/messenger-platform/reference/webhook-events
    # #2200: soma só os campos do Messenger; leadgen e feed da mesma Página continuam inscritos.
    page_subscription.add!(MESSENGER_FIELDS)
  rescue StandardError => e
    Rails.logger.warn("[Channel::FacebookPage] subscribed_apps page=#{page_id} #{e.class}: #{e.message}")
    true
  end

  # A mesma Página pode ser caixa de outra conta desta stack: aí os campos do Messenger continuam dela. Esta conferência
  # só vê o banco desta stack: Página que também é caixa na outra stack perde os campos do Messenger lá (risco aberto
  # no #2200). Duas remoções simultâneas da mesma Página podem deixar os campos inscritos (só sobra evento ignorado).
  def unsubscribe
    return true if Channel::FacebookPage.where(page_id: page_id).where.not(id: id).exists?

    page_subscription.remove!(MESSENGER_FIELDS)
  rescue StandardError => e
    Rails.logger.warn("[Channel::FacebookPage] subscribed_apps page=#{page_id} #{e.class}: #{e.message}")
    true
  end

  private

  def page_subscription
    Crm::MetaAds::PageSubscription.new(page_id: page_id, access_token: page_access_token)
  end
end
