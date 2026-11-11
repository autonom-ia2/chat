# #2858 F3 — a sugestão "pode ganhar" de um agente, fora do pedido da página (`SugestaoParaAgente`). Quem enfileira é a
# leitura da sugestão, uma vez por agente enquanto a trava dura (`enfileirar`), e só quando a guardada está velha (o
# catálogo da conta mudou) ou não existe. O job confere de novo antes de chamar o modelo: dois pedidos seguidos não
# pagam duas vezes. Sem nova tentativa: uma falha depois da chamada paga não paga de novo (a trava dá a próxima chance).
class Autonomia::FerramentasProntas::SugestaoJob < ApplicationJob
  queue_as :low
  sidekiq_options retry: false

  TRAVA = 'autonomia:prontas:sugestao'.freeze
  TRAVA_SEGUNDOS = 10.minutes.to_i

  def self.enfileirar(agent)
    return if Autonomia::FerramentasProntas::SugestaoParaAgente.atual?(agent)
    return unless Redis::Alfred.set("#{TRAVA}:#{agent.id}", 1, nx: true, ex: TRAVA_SEGUNDOS)

    perform_later(agent.id)
  end

  def perform(agent_id)
    agent = Autonomia::Agents::Agent.kept.find_by(id: agent_id)
    return if agent.nil? || Autonomia::FerramentasProntas::SugestaoParaAgente.atual?(agent)

    Autonomia::FerramentasProntas::SugestaoParaAgente.new(agent).call
  end
end
