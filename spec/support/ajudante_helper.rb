# Tema 14 (#1434) — o ajudante: um agente interno que outro agente consulta pelo vínculo (`Specialist` com
# `delegate_agent_id`). Montagem comum dos specs do motor.
module AjudanteHelper
  def conta_da_fase2(ligada: true)
    create(:account, internal_attributes: { 'autonomia_agents_enabled' => true, 'autonomia_agents_fase2' => ligada })
  end

  def criar_principal(conta, nome: 'Joana', **extras)
    Autonomia::Agents::Agent.create!({ account: conta, name: nome, agent_type: 'custom', status: :active, enabled: true,
                                       instruction: 'Atenda o cliente da corretora.',
                                       config: { 'with_knowledge' => false } }.merge(extras))
  end

  def criar_ajudante(conta, nome: 'Regras do produto Auto', **extras)
    Autonomia::Agents::Agent.create!({ account: conta, name: nome, agent_type: 'custom', actuation: :internal,
                                       status: :active, enabled: true,
                                       instruction: 'Você conhece as regras do produto Auto.',
                                       config: { 'with_knowledge' => false, 'papel' => 'ajudante' } }.merge(extras))
  end

  # Um Copiloto da equipe de antes (interno, sem a marca de origem do ajudante): nunca vira ajudante (decisão c).
  def criar_copiloto(conta, nome: 'Ana Maciel')
    criar_ajudante(conta, nome: nome, config: { 'with_knowledge' => false })
  end

  def vincular(principal, ajudante, quando: 'Quando a dúvida for sobre o produto Auto')
    Autonomia::Agents::Specialist.create!(agent: principal, delegate: ajudante, name: ajudante.name, description: quando)
  end
end

RSpec.configure { |config| config.include AjudanteHelper }
