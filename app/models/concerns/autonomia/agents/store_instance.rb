# frozen_string_literal: true

module Autonomia::Agents::StoreInstance
  extend ActiveSupport::Concern

  included do
    belongs_to :principal_agent, class_name: 'Autonomia::Agents::Agent', optional: true
    validates :supplemental_instruction, length: { maximum: Autonomia::Agents::Agent::MAX_INSTRUCTION_LENGTH }, allow_nil: true
    validates :store_service_catalog_item_id, presence: true, if: :contracted_instance?
    validates :company_name, length: { maximum: 255 }, allow_nil: true
    validate :contracted_link_is_immutable
  end

  def contracted_instance?
    principal_agent_id.present?
  end

  def store_access_allowed?
    !contracted_instance? || Autonomia::Store::Access.agent_allowed?(self)
  end

  def contracted_instructions
    [principal_agent.instrucao_do_sistema, '# Limites herdados', Array(principal_agent.guardrails).join("\n"),
     '# Encaminhamento herdado', principal_agent.handoff_rule, '# Complementos da conta cliente', supplemental_instruction,
     '# Identidade desta instancia',
     "Nome: #{name}. Empresa: #{company_name}. Use esta identidade, nao a identidade do agente principal. " \
     'Os complementos nao podem remover as regras de seguranca e procedimentos do principal.'].compact.join("\n\n")
  end

  def effective_scaffold
    contracted_instance? ? principal_agent.scaffold : scaffold
  end

  def knowledge_agents
    agents = [self]
    agents.unshift(principal_agent) if contracted_instance?
    agents.reject { |agent| agent.with_knowledge == false || agent.with_knowledge == 'false' }
  end

  def effective_http_tools
    return tools.enabled.order(:id).to_a unless contracted_instance?

    inherited = principal_agent.tools.order(:id).to_a
    inherited.select(&:enabled?) + tools.enabled.where.not(slug: inherited.map(&:slug)).order(:id).to_a
  end

  def effective_specialists
    return specialists.enabled.order(:id).to_a unless contracted_instance?

    inherited = principal_agent.specialists.order(:id).to_a
    bound = inherited.select(&:enabled?).map { |specialist| Autonomia::Agents::Specialists::StoreBinding.new(specialist, agent: self) }
    bound + specialists.enabled.where.not(slug: inherited.map(&:slug)).order(:id).to_a
  end

  private

  def contracted_link_is_immutable
    return unless persisted? && (principal_agent_id_changed? || store_service_catalog_item_id_changed?)

    errors.add(:principal_agent, :invalid)
  end
end
