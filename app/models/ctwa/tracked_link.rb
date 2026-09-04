# == Schema Information
#
# Table name: ctwa_tracked_links
#
#  id                  :bigint           not null, primary key
#  clicks_count        :integer          default(0), not null
#  code                :string           not null
#  conversations_count :integer          default(0), not null
#  name                :string           not null
#  prefilled_text      :string           default("")
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#  created_by_id       :bigint
#  inbox_id            :bigint           not null
#
# Indexes
#
#  idx_ctwa_tracked_links_account  (account_id)
#  idx_ctwa_tracked_links_code     (code) UNIQUE
#  idx_ctwa_tracked_links_inbox    (inbox_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id) ON DELETE => cascade
#  fk_rails_...  (inbox_id => inboxes.id) ON DELETE => cascade
#
require 'cgi'

class Ctwa::TrackedLink < ApplicationRecord
  self.table_name = 'ctwa_tracked_links'

  CODE_ALPHABET = (('A'..'Z').to_a - %w[I O] + ('2'..'9').to_a).freeze
  CODE_FORMAT = /\A[A-Z2-9]{6}\z/

  belongs_to :account
  belongs_to :inbox

  before_validation :generate_code, on: :create

  validates :name, presence: true
  validates :code, presence: true, uniqueness: true, format: { with: CODE_FORMAT }
  validate :inbox_must_be_whatsapp

  scope :for_account, ->(account) { where(account_id: account.id) }

  def wa_link
    phone = inbox&.channel.try(:phone_number).to_s.delete('+')
    return if phone.blank?

    text = CGI.escape("#{prefilled_text} ##{code}")

    "https://wa.me/#{phone}?text=#{text}"
  end

  private

  # Public /l/:code redirects to wa.me, which only exists for WhatsApp channels —
  # any other inbox type would create a dead link (and a nil phone_number crash).
  def inbox_must_be_whatsapp
    return if inbox.blank? || inbox.channel.is_a?(Channel::Whatsapp)

    errors.add(:inbox, 'must be a WhatsApp inbox')
  end

  def generate_code
    return if code.present?

    loop do
      self.code = Array.new(6) { CODE_ALPHABET[SecureRandom.random_number(CODE_ALPHABET.length)] }.join
      break unless self.class.exists?(code: code)
    end
  end
end
