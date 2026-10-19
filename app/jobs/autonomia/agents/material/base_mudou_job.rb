# #1426 (tema 4b) — a base do agente mudou (um material foi revisado ou saiu: Reviewer.recompute_overall!). Espera 2 min
# depois da ÚLTIMA mudança (vários envios seguidos viram uma rodada só: cada aviso grava uma marca nova e só o job da
# última marca segue) e então:
# 1. confere as contradições entre os materiais aprovados, se a base mudou desde a última conferência;
# 2. pede o autoteste automático (Autoteste.quando_automatica: base mudada, 30 min da última automática, sem rodada
#    viva). Base mudada mas ainda dentro dos 30 min (ou com rodada rodando): o mesmo aviso volta no horário em que pode
#    rodar, para o resultado não ficar preso à base antiga. Uma mudança nova no meio troca a marca e vence.
# Só na Fase 2 e fora da Lia (Material.conferir?).
class Autonomia::Agents::Material::BaseMudouJob < ApplicationJob
  queue_as :low
  ESPERA = 2.minutes
  CHAVE = 'conferencia_da_base'.freeze

  def self.agendar(agent)
    return unless Autonomia::Agents::Material.conferir?(agent)

    marca = SecureRandom.hex(8)
    agent.alterar_chave_do_material!(CHAVE) { |atual| (atual.is_a?(Hash) ? atual : {}).merge('agendada' => marca) }
    set(wait: ESPERA).perform_later(agent.id, marca)
  end

  def perform(agent_id, marca)
    agent = Autonomia::Agents::Agent.kept.find_by(id: agent_id)
    return unless Autonomia::Agents::Material.conferir?(agent)
    return unless agent.chave_do_material(CHAVE).to_h['agendada'] == marca

    conferir_contradicoes(agent)
    autoteste_automatico(agent, marca)
  end

  private

  def autoteste_automatico(agent, marca)
    quando = Autonomia::Agents::Material::Autoteste.quando_automatica(agent)
    return if quando.nil?
    return self.class.set(wait_until: quando).perform_later(agent.id, marca) if quando.future?

    Autonomia::Agents::Material::Autoteste.pedir!(agent, quando: 'base_mudou')
  end

  def conferir_contradicoes(agent)
    return if agent.chave_do_material(CHAVE).to_h['hash_da_base'] == Autonomia::Agents::Material.hash_da_base(agent)

    Autonomia::Agents::Material::Contradicoes.new(agent).conferir!
  end
end
