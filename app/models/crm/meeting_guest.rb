# == Schema Information
#
# Table name: crm_meeting_guests
#
#  id          :bigint           not null, primary key
#  email       :string           not null
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

  validates :email, :guest_type, presence: true
  validates :account_id, :meeting_id, presence: true
  validates :email, uniqueness: { scope: [:account_id, :meeting_id] }
  validates :metadata, jsonb_attributes_length: true
end
