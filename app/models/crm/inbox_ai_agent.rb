# Agente de IA responsável por caixa + funil (#1447): na caixa, o funil é atendido por este agente. Quem grava é a tela
# "Caixas no CRM → Quem cuida do quê?". Quem lê é o Crm::Ai::Config (responsible_agent, destinos_para).
#
# O agente NÃO precisa estar ligado à caixa para ser gravado: o agente de área normalmente não tem vínculo com ela. O
# vínculo (Autonomia::Agents::Areas.vincular!/desvincular!) é do Agentes IA e chega na F1 dele (#1433); até lá, quem
# lê exige o vínculo (AgentInbox) e a linha sem vínculo não tem efeito.
class Crm::InboxAiAgent < ApplicationRecord
  self.table_name = 'crm_inbox_ai_agents'

  belongs_to :account
  belongs_to :inbox
  belongs_to :pipeline, class_name: 'Crm::Pipeline'
  belongs_to :agent, class_name: 'Autonomia::Agents::Agent', foreign_key: :autonomia_agent_id, inverse_of: false

  validates :pipeline_id, uniqueness: { scope: :inbox_id }
  validate :linked_records_must_belong_to_account
  validate :agent_must_be_kept

  private

  def linked_records_must_belong_to_account
    return if account_id.blank?

    %i[inbox pipeline agent].each do |association_name|
      record = public_send(association_name)
      next if record.blank? || record.account_id == account_id

      errors.add(association_name, 'must belong to the same account')
    end
  end

  def agent_must_be_kept
    errors.add(:agent, 'must not be deleted') if agent&.deleted_at.present?
  end
end
