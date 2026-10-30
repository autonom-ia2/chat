# == Schema Information
#
# Table name: crm_follow_ups
#
#  id                 :bigint           not null, primary key
#  automation_mode    :integer          default("reminder_only"), not null
#  canceled_at        :datetime
#  completed_at       :datetime
#  description        :text
#  due_at             :datetime         not null
#  follow_up_type     :integer          default("task"), not null
#  metadata           :jsonb            not null
#  occurrence_at      :datetime
#  recipient_mode     :integer          default("legacy"), not null
#  recipient_user_ids :bigint           default([]), not null, is an Array
#  status             :integer          default("pending"), not null
#  timezone           :string           default("UTC"), not null
#  title              :string           not null
#  created_at         :datetime         not null
#  updated_at         :datetime         not null
#  account_id         :bigint           not null
#  assignee_id        :bigint
#  card_id            :bigint
#  company_id         :bigint
#  contact_id         :bigint
#  conversation_id    :bigint
#  created_by_id      :bigint
#  inbox_id           :bigint
#  recipient_team_id  :bigint
#  series_id          :bigint
#
# Indexes
#
#  idx_crm_followups_assignee_due             (account_id,assignee_id,due_at,status)
#  idx_crm_followups_card                     (account_id,card_id)
#  idx_crm_followups_conversation             (account_id,conversation_id)
#  idx_crm_followups_due_processor            (status,due_at,id)
#  idx_crm_followups_series_occurrence_uniq   (series_id,occurrence_at) UNIQUE WHERE (series_id IS NOT NULL)
#  idx_crm_followups_status_due               (account_id,status,due_at)
#  index_crm_follow_ups_on_account_id         (account_id)
#  index_crm_follow_ups_on_assignee_id        (assignee_id)
#  index_crm_follow_ups_on_card_id            (card_id)
#  index_crm_follow_ups_on_company_id         (company_id)
#  index_crm_follow_ups_on_contact_id         (contact_id)
#  index_crm_follow_ups_on_conversation_id    (conversation_id)
#  index_crm_follow_ups_on_created_by_id      (created_by_id)
#  index_crm_follow_ups_on_inbox_id           (inbox_id)
#  index_crm_follow_ups_on_recipient_team_id  (recipient_team_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (assignee_id => users.id)
#  fk_rails_...  (card_id => crm_cards.id) ON DELETE => cascade
#  fk_rails_...  (company_id => companies.id) ON DELETE => cascade
#  fk_rails_...  (contact_id => contacts.id) ON DELETE => cascade
#  fk_rails_...  (conversation_id => conversations.id) ON DELETE => cascade
#  fk_rails_...  (created_by_id => users.id)
#  fk_rails_...  (inbox_id => inboxes.id) ON DELETE => nullify
#  fk_rails_...  (recipient_team_id => teams.id) ON DELETE => nullify
#  fk_rails_...  (series_id => crm_follow_up_series.id) ON DELETE => nullify
#
class Crm::FollowUp < ApplicationRecord
  include Crm::FollowUpRecipients

  self.table_name = 'crm_follow_ups'

  belongs_to :account
  # #1461: lembrete só no calendário ou de um cliente sem negócio aberto não tem card.
  belongs_to :card, class_name: 'Crm::Card', optional: true
  # #1460: a vez de um lembrete que repete.
  belongs_to :series, class_name: 'Crm::FollowUpSeries', optional: true, inverse_of: :follow_ups
  belongs_to :conversation, optional: true
  belongs_to :contact, optional: true
  # #1461: lembrete criado pela ficha da empresa (Relacionamento).
  belongs_to :company, optional: true
  belongs_to :inbox, optional: true
  belongs_to :assignee, class_name: 'User', optional: true
  belongs_to :created_by, class_name: 'User', optional: true

  enum follow_up_type: { task: 0, message: 1, call: 2, meeting: 3, note: 4 }
  enum status: { pending: 0, done: 1, canceled: 2, overdue: 3 }
  enum automation_mode: { reminder_only: 0, snooze_conversation: 1, auto_send_message: 2 }

  # Marca do toque da cadência da IA (Crm::FollowUps::AutoFollowupTouchBuilder).
  AI_FOLLOWUP_SOURCE = 'ai_followup'.freeze
  # No modo "IA lembra a equipe", o toque que dispara vira lembrete para a pessoa com esta marca
  # (Crm::FollowUps::AutoFollowupRunner#create_reminder).
  AI_REMINDER_ACTION_MODE = 'ai_reminder'.freeze

  validates :title, :due_at, :timezone, presence: true
  validates :metadata, jsonb_attributes_length: true
  validate :linked_records_must_belong_to_account
  validate :snooze_requires_conversation
  validate :auto_send_requirements
  validate :needs_an_owner
  validate :without_card_only_reminds

  scope :active, -> { where(status: [statuses[:pending], statuses[:overdue]]) }
  # Retorno que a pessoa faz (Lista nova, #2283): ativo (o vencido vira overdue no DueProcessor), lembrete ou adiar a
  # conversa. Envio automático e toque da cadência da IA também têm hora, mas quem age é o sistema: ficam fora. O toque
  # da IA que já virou lembrete para a equipe (action_mode ai_reminder) é da pessoa e entra.
  scope :retorno_da_pessoa, lambda {
    active.where(automation_mode: [automation_modes[:reminder_only], automation_modes[:snooze_conversation]])
          .where("COALESCE(crm_follow_ups.metadata->>'source', '') <> ? OR crm_follow_ups.metadata->>'action_mode' = ?",
                 AI_FOLLOWUP_SOURCE, AI_REMINDER_ACTION_MODE)
  }
  scope :due, ->(time = Time.current) { pending.where(due_at: ..time) }
  # Pré-voo (#1624): o que vence depois de `from` e até `to`; o que já venceu é do DueProcessor.
  scope :due_within, ->(from, to) { pending.where('crm_follow_ups.due_at > ? AND crm_follow_ups.due_at <= ?', from, to) }

  # O retorno da pessoa sem conversa ou de conversa visível (SQL de ids de Crm::Conversations::Visibility#scope). `all: true`
  # só para quem vê todas as conversas da conta (Visibility#all_conversations?): aí não há filtro.
  scope :retorno_visivel, lambda { |visible_conversation_ids_sql, all: false|
    next retorno_da_pessoa if all
    raise ArgumentError, 'retorno_visivel precisa das conversas visíveis' if visible_conversation_ids_sql.blank?

    retorno_da_pessoa.where("crm_follow_ups.conversation_id IS NULL OR crm_follow_ups.conversation_id IN (#{visible_conversation_ids_sql})")
  }

  # O retorno da pessoa mais perto de cada card, { card_id => follow_up (só id e due_at) }, numa consulta (a página da
  # Lista). O "Feito" usa o id; a hora diz a situação e a cor do retorno (#2283).
  def self.proximos_retornos_da_pessoa(card_ids, conversation_visibility:)
    return {} if card_ids.blank?

    all = conversation_visibility.all_conversations?
    visible_sql = conversation_visibility.scope(Conversation.all).select(:id).to_sql unless all
    retorno_visivel(visible_sql, all: all)
      .joins(:card).where('crm_follow_ups.account_id = crm_cards.account_id') # lembrete de outra conta não conta
      .where(card_id: card_ids)
      .select('DISTINCT ON (crm_follow_ups.card_id) crm_follow_ups.card_id, crm_follow_ups.id, crm_follow_ups.due_at')
      .reorder(Arel.sql('crm_follow_ups.card_id, crm_follow_ups.due_at, crm_follow_ups.id'))
      .index_by(&:card_id)
  end

  private

  # A mesma trava do banco (crm_follow_ups_has_owner): alguém precisa ser dono do lembrete.
  def needs_an_owner
    return if [card_id, contact_id, company_id, created_by_id, created_by].any?(&:present?)

    errors.add(:base, 'needs a card, a contact or a creator')
  end

  # Sem card não há conversa nem cliente para mandar mensagem: só o lembrete para a equipe.
  def without_card_only_reminds
    return if card_id.present? || card.present? || reminder_only?

    errors.add(:automation_mode, 'must be reminder_only without a card')
  end

  def snooze_requires_conversation
    return unless snooze_conversation?
    return if conversation_id.present?

    errors.add(:conversation, 'is required for snooze follow-ups')
  end

  def auto_send_requirements
    return unless auto_send_message?

    Crm::FollowUps::AutoSendValidator.new(self).validate
  end

  def linked_records_must_belong_to_account
    validate_same_account(:card)
    validate_same_account(:conversation)
    validate_same_account(:contact)
    validate_same_account(:inbox)
    validate_same_account(:series)
    validate_same_account(:company)
    validate_assignee_account
    validate_created_by_account
  end

  def validate_same_account(association_name)
    record = public_send(association_name)
    return if record.blank? || account_id.blank?
    return if record.account_id == account_id

    errors.add(association_name, 'must belong to the same account')
  end

  def validate_assignee_account
    return if assignee.blank? || account_id.blank?
    return if assignee.account_users.exists?(account_id: account_id)

    errors.add(:assignee, 'must belong to the same account')
  end

  def validate_created_by_account
    return if created_by.blank? || account_id.blank?
    return if created_by.account_users.exists?(account_id: account_id)

    errors.add(:created_by, 'must belong to the same account')
  end
end
