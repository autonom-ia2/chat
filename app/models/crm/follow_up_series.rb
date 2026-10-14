# #1460 — a regra de um lembrete que repete. Cada vez vira uma linha em crm_follow_ups (series_id + occurrence_at),
# criada pelo Crm::FollowUps::SeriesMaterializer; as datas saem do Crm::FollowUps::SeriesSchedule, no fuso da série.
# Fase 1 (decisão do Rodrigo, 14/10/2026): só lembrete para a equipe (reminder_only). Mensagem ao cliente repetida
# fica para depois.
# == Schema Information
#
# Table name: crm_follow_up_series
#
#  id                 :bigint           not null, primary key
#  automation_mode    :integer          default("reminder_only"), not null
#  description        :text
#  ended_at           :datetime
#  ends_mode          :integer          default("never"), not null
#  ends_on            :date
#  frequency          :integer          not null
#  metadata           :jsonb            not null
#  occurrences_count  :integer
#  paused_at          :datetime
#  recipient_mode     :integer          default("legacy"), not null
#  recipient_user_ids :bigint           default([]), not null, is an Array
#  starts_at          :datetime         not null
#  status             :integer          default("active"), not null
#  timezone           :string           default("UTC"), not null
#  title              :string           not null
#  weekdays           :integer          default([]), not null, is an Array
#  weekdays_only      :boolean          default(FALSE), not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint           not null
#  card_id            :bigint
#  company_id         :bigint
#  contact_id         :bigint
#  conversation_id    :bigint
#  created_by_id      :bigint
#  recipient_team_id  :bigint
#
# Indexes
#
#  idx_crm_follow_up_series_account_status          (account_id,status)
#  index_crm_follow_up_series_on_card_id            (card_id)
#  index_crm_follow_up_series_on_company_id         (company_id)
#  index_crm_follow_up_series_on_contact_id         (contact_id)
#  index_crm_follow_up_series_on_conversation_id    (conversation_id)
#  index_crm_follow_up_series_on_created_by_id      (created_by_id)
#  index_crm_follow_up_series_on_recipient_team_id  (recipient_team_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (card_id => crm_cards.id) ON DELETE => cascade
#  fk_rails_...  (company_id => companies.id) ON DELETE => cascade
#  fk_rails_...  (contact_id => contacts.id) ON DELETE => cascade
#  fk_rails_...  (conversation_id => conversations.id) ON DELETE => nullify
#  fk_rails_...  (created_by_id => users.id)
#  fk_rails_...  (recipient_team_id => teams.id) ON DELETE => nullify
#
class Crm::FollowUpSeries < ApplicationRecord
  include Crm::FollowUpRecipients

  self.table_name = 'crm_follow_up_series'

  MAX_OCCURRENCES = 500
  WEEKDAYS = (0..6)

  belongs_to :account
  belongs_to :card, class_name: 'Crm::Card', optional: true
  belongs_to :contact, optional: true
  belongs_to :company, optional: true
  belongs_to :conversation, optional: true
  belongs_to :created_by, class_name: 'User', optional: true
  has_many :follow_ups, class_name: 'Crm::FollowUp', foreign_key: :series_id, inverse_of: :series, dependent: :nullify

  # validate: true — valor fora da lista vira erro de validação (422), não ArgumentError.
  enum :frequency, { daily: 0, weekly: 1, monthly: 2, yearly: 3 }, validate: true
  enum :ends_mode, { never: 0, on_date: 1, after_count: 2 }, prefix: :ends, validate: true
  enum :status, { active: 0, paused: 1, ended: 2 }
  enum :automation_mode, { reminder_only: 0 }

  validates :title, :frequency, :starts_at, :timezone, presence: true
  validates :occurrences_count, numericality: { only_integer: true, in: 1..MAX_OCCURRENCES }, if: :ends_after_count?
  validates :ends_on, presence: true, if: :ends_on_date?
  validates :metadata, jsonb_attributes_length: true
  validate :timezone_must_exist
  validate :weekdays_must_fit
  validate :needs_an_owner
  validate :links_must_belong_to_account

  def schedule
    Crm::FollowUps::SeriesSchedule.new(self)
  end

  # Uma vez de mentira (não salva), para saber quem receberia agora sem vez marcada.
  def recipient_preview
    Crm::FollowUp.new(account_id: account_id, card: card, created_by: created_by, recipient_mode: recipient_mode,
                      recipient_user_ids: recipient_user_ids, recipient_team: recipient_team)
  end

  private

  def timezone_must_exist
    errors.add(:timezone, :invalid) if timezone.present? && ActiveSupport::TimeZone[timezone].nil?
  end

  def weekdays_must_fit
    return unless weekly?
    return errors.add(:weekdays, :blank) if weekdays.blank?

    errors.add(:weekdays, :invalid) unless weekdays.all? { |day| WEEKDAYS.cover?(day) }
  end

  def needs_an_owner
    return if [card_id, contact_id, company_id, created_by_id].any?(&:present?)

    errors.add(:base, 'needs a card, a contact, a company or a creator')
  end

  def links_must_belong_to_account
    %i[card contact company conversation].each do |association|
      record = public_send(association)
      next if record.blank? || account_id.blank? || record.account_id == account_id

      errors.add(association, 'must belong to the same account')
    end
  end
end
