# #3211: as quatro opções da paridade da conversa nascem ligadas em todo agente, menos na Lia
# (Autonomia::Agents::ParidadeDaConversa). O exemplo que prova o comportamento com elas desligadas grava `false` no agente,
# explícito, com estes atalhos.
module ParidadeDaConversaHelper
  # -> { chave => false } das opções pedidas; sem argumento, as quatro.
  def paridade_desligada(*chaves)
    (chaves.presence || Autonomia::Agents::ParidadeDaConversa::CHAVES).index_with(false)
  end

  # Grava `false` nas opções pedidas (sem argumento, nas quatro) do agente, mantendo o resto do `config`.
  def desligar_paridade!(agent, *chaves)
    agent.update!(config: agent.config.to_h.merge(paridade_desligada(*chaves)))
  end
end

RSpec.configure { |config| config.include ParidadeDaConversaHelper }
