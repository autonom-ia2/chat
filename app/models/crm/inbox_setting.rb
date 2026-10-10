# == Schema Information
#
# Table name: crm_inbox_settings
#
#  id                  :bigint           not null, primary key
#  auto_create_card    :boolean          default(FALSE), not null
#  crm_enabled         :boolean          default(FALSE), not null
#  subject_ai_mode     :integer          default("off"), not null
#  visibility_mode     :integer          default("all_inbox_cards"), not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#  default_pipeline_id :bigint
#  default_stage_id    :bigint
#  inbox_id            :bigint
#
# Indexes
#
#  index_crm_inbox_settings_on_account_id                  (account_id)
#  index_crm_inbox_settings_on_account_id_and_crm_enabled  (account_id,crm_enabled)
#  index_crm_inbox_settings_on_account_id_and_inbox_id     (account_id,inbox_id) UNIQUE
#  index_crm_inbox_settings_on_default_pipeline_id         (default_pipeline_id)
#  index_crm_inbox_settings_on_default_stage_id            (default_stage_id)
#  index_crm_inbox_settings_on_inbox_id                    (inbox_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (default_pipeline_id => crm_pipelines.id)
#  fk_rails_...  (default_stage_id => crm_pipeline_stages.id)
#  fk_rails_...  (inbox_id => inboxes.id) ON DELETE => nullify
#
class Crm::InboxSetting < ApplicationRecord
  self.table_name = 'crm_inbox_settings'

  belongs_to :account
  belongs_to :inbox
  belongs_to :default_pipeline, class_name: 'Crm::Pipeline', optional: true
  belongs_to :default_stage, class_name: 'Crm::PipelineStage', optional: true

  enum visibility_mode: { all_inbox_cards: 0, assigned_only: 1 }
  # Multifunil (#1145): o que a IA faz quando identifica o assunto da conversa. Desligada é o padrão.
  enum subject_ai_mode: { off: 0, suggest: 1, auto: 2 }, _prefix: :subject_ai

  after_update_commit :expirar_sugestoes_de_assunto, if: :saiu_do_modo_sugerir?

  validates :inbox_id, uniqueness: { scope: :account_id }
  validate :linked_records_must_belong_to_account
  validate :default_stage_must_belong_to_default_pipeline

  private

  # #1221: a caixa deixou de sugerir (outro modo ou CRM desligado). As sugestões que esperavam resposta saem da tela.
  def saiu_do_modo_sugerir?
    return false unless saved_change_to_subject_ai_mode? || saved_change_to_crm_enabled?

    !(subject_ai_suggest? && crm_enabled?)
  end

  # O painel aberto dessas conversas lê de novo (aviso em tempo real), em vez de mostrar a sugestão até recarregar.
  def expirar_sugestoes_de_assunto
    pendentes = Crm::SubjectDecision.suggested.where(account_id: account_id,
                                                     conversation_id: account.conversations.where(inbox_id: inbox_id).select(:id))
    conversation_ids = pendentes.distinct.pluck(:conversation_id)
    return if conversation_ids.empty?

    pendentes.update_all(state: 'expired', updated_at: Time.current) # rubocop:disable Rails/SkipsModelValidations
    account.conversations.where(id: conversation_ids).find_each { |conversation| Crm::Subjects::Notifier.notify(conversation) }
  end

  def linked_records_must_belong_to_account
    validate_same_account(:inbox)
    validate_same_account(:default_pipeline)
    validate_same_account(:default_stage)
  end

  def default_stage_must_belong_to_default_pipeline
    return if default_stage.blank? || default_pipeline.blank?
    return if default_stage.pipeline_id == default_pipeline_id

    errors.add(:default_stage, 'must belong to the selected default pipeline')
  end

  def validate_same_account(association_name)
    record = public_send(association_name)
    return if record.blank? || account_id.blank?
    return if record.account_id == account_id

    errors.add(association_name, 'must belong to the same account')
  end
end
