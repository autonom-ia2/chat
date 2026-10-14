# Agente de IA responsável por caixa + funil (#1447): na caixa, o funil é atendido por este agente. Quem grava é a tela
# "Caixas no CRM → Quem cuida do quê?" (Crm::Caixas::GravadorDeAgentes). Quem lê é o Crm::Ai::Config
# (responsible_agent, destinos_para).
#
# Onde o agente trabalha é do Agentes IA (autonomia_agent_inboxes, papel porta|area): o CRM só lê esse vínculo e só o
# muda por Autonomia::Agents::Areas. De qual funil ele cuida é desta tabela, e a linha só nasce (ou muda) com o agente
# vinculado como ÁREA na caixa. A porta não entra aqui: funil sem linha fica com ela.
#
# Se o vínculo de área sai por fora desta tela (página do agente, agente apagado, porta saindo da caixa), a linha fica
# e não tem efeito: quem lê exige o vínculo ativo. Voltando o vínculo, ela volta a valer. Pela tela, tirar o agente da
# caixa apaga as linhas dele junto.
class Crm::InboxAiAgent < ApplicationRecord
  self.table_name = 'crm_inbox_ai_agents'

  belongs_to :account
  belongs_to :inbox
  belongs_to :pipeline, class_name: 'Crm::Pipeline'
  belongs_to :agent, class_name: 'Autonomia::Agents::Agent', foreign_key: :autonomia_agent_id, inverse_of: false

  validates :pipeline_id, uniqueness: { scope: :inbox_id }
  validate :linked_records_must_belong_to_account
  validate :agent_must_be_kept
  validate :agent_must_be_area_of_inbox

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

  def agent_must_be_area_of_inbox
    return if agent.blank? || inbox.blank?
    return if ::Autonomia::Agents::AgentInbox.kept.area.exists?(account_id: account_id, inbox_id: inbox_id, autonomia_agent_id: agent.id)

    errors.add(:agent, 'must work as an area in the inbox')
  end
end
