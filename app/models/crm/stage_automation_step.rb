# == Schema Information
#
# Table name: crm_stage_automation_steps
#
#  id                  :bigint           not null, primary key
#  action_config       :jsonb            not null
#  action_type         :integer          default("create_follow_up"), not null
#  delay_seconds       :integer          default(0), not null
#  position            :integer          default(0), not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#  account_id          :bigint           not null
#  stage_automation_id :bigint           not null
#
# Indexes
#
#  idx_crm_stage_automation_steps_order                     (stage_automation_id,position)
#  index_crm_stage_automation_steps_on_account_id           (account_id)
#  index_crm_stage_automation_steps_on_stage_automation_id  (stage_automation_id)
#
# Foreign Keys
#
#  fk_rails_...  (account_id => accounts.id)
#  fk_rails_...  (stage_automation_id => crm_stage_automations.id)
#
class Crm::StageAutomationStep < ApplicationRecord
  self.table_name = 'crm_stage_automation_steps'

  belongs_to :account
  belongs_to :stage_automation, class_name: 'Crm::StageAutomation', inverse_of: :steps

  # `perguntar_ao_decisor` (#858): o Decisor responde sobre o card antes dos passos seguintes, que só rodam
  # se ele responder a chave combinada. action_config: { decisor_id, chave_que_segue }.
  enum action_type: { create_follow_up: 0, assign_owner: 1, move_stage: 2, perguntar_ao_decisor: 3 }

  validates :position, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :delay_seconds, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :action_config, jsonb_attributes_length: true
  validates :action_config, json_schema: { schema: ->(passo) { Crm::StageAutomationStepSchema.action_config(passo) } }
  validate :decisor_do_passo, if: :perguntar_ao_decisor?

  scope :ordered, -> { order(:position, :id) }

  private

  # O mesmo contrato do passo da regra de automação (#858): o Decisor tem de ser da conta, a chave uma das
  # respostas dele e o que ele lê, algo que um card tem. Conferência por igualdade; a recusa ensina o certo.
  # A forma do action_config ({ decisor_id, chave_que_segue }) fica com o esquema.
  def decisor_do_passo
    config = action_config.to_h.stringify_keys
    decisor = Autonomia::Decisor.find_by(id: config['decisor_id'].to_s, account_id: account_id)
    if decisor.blank?
      return errors.add(:action_config, 'decisor_id must be a Decisor of this account (action_config: { decisor_id, chave_que_segue })')
    end

    recusa = decisor.recusa_de_gatilho('etapa')
    return errors.add(:action_config, recusa) if recusa
    return if decisor.resposta?(config['chave_que_segue'])

    errors.add(:action_config, "chave_que_segue must be one of: #{decisor.chaves.join(', ')}")
  end
end
