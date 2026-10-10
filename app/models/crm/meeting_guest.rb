# == Schema Information
#
# Table name: crm_meeting_guests
#
#  id          :bigint           not null, primary key
#  email       :string
#  phone_number :string
#  guest_type  :integer          default("contact_guest"), not null
#  metadata    :jsonb            not null
#  name        :string
#  rsvp_status :integer          default("rsvp_pending"), not null
#  created_at  :datetime         not null
#  updated_at  :datetime         not null
#  account_id  :bigint           not null
#  contact_id  :bigint
#  meeting_id  :bigint           not null
#  user_id     :bigint
#
# Indexes
#
#  idx_crm_meeting_guests_contact          (contact_id)
#  idx_crm_meeting_guests_meeting          (account_id,meeting_id)
#  idx_crm_meeting_guests_unique_email     (account_id,meeting_id,email) UNIQUE
#  index_crm_meeting_guests_on_account_id  (account_id)
#  index_crm_meeting_guests_on_contact_id  (contact_id)
#  index_crm_meeting_guests_on_meeting_id  (meeting_id)
#  index_crm_meeting_guests_on_user_id     (user_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (contact_id => contacts.id) ON DELETE => cascade
#  fk_rails_...  (meeting_id => crm_meetings.id)
#  fk_rails_...  (user_id => users.id)
#
class Crm::MeetingGuest < ApplicationRecord
  self.table_name = 'crm_meeting_guests'

  belongs_to :account
  belongs_to :meeting, class_name: 'Crm::Meeting', inverse_of: :meeting_guests
  belongs_to :contact, optional: true
  belongs_to :user, optional: true

  enum guest_type: { contact_guest: 0, external_email: 1, internal_user: 2 }
  enum rsvp_status: { rsvp_pending: 0, rsvp_accepted: 1, rsvp_declined: 2, rsvp_tentative: 3 }

  # Convidado precisa de e-mail OU telefone (WhatsApp). Vazio vira NULL para a unicidade ignorar quem não tem.
  before_validation :normalize_contact_fields

  validates :guest_type, presence: true
  validates :account_id, :meeting_id, presence: true
  validates :email, presence: true, if: -> { phone_number.blank? }
  validates :phone_number, presence: true, if: -> { email.blank? }
  validates :email, uniqueness: { scope: [:account_id, :meeting_id] }, allow_nil: true
  validates :phone_number, uniqueness: { scope: [:account_id, :meeting_id] }, allow_nil: true
  validate :phone_number_must_be_e164
  validates :metadata, jsonb_attributes_length: true

  private

  def normalize_contact_fields
    self.email = email.to_s.strip.presence
    self.phone_number = phone_number.to_s.strip.presence
  end

  def phone_number_must_be_e164
    return if phone_number.blank?
    return if phone_number.start_with?('+') && TelephoneNumber.valid?(phone_number)

    errors.add(:phone_number, 'must be a valid E.164 number')
  end
end
