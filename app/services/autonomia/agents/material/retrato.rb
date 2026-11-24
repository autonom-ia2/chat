# #1426 (tema 4b) — o que a gaveta "O que sabe" lê do material, além da lista de materiais (que segue na API de
# sources): os problemas, um por vez. Nunca a instrução, o prompt nem o texto do material (só a primeira linha da
# tabela sem cabeçalho). Fora do material da Fase 2: vazio.
class Autonomia::Agents::Material::Retrato
  def initialize(agent)
    @agent = agent
  end

  def to_h
    return { problemas: [] } unless Autonomia::Agents::Material.conferir?(@agent)

    { problemas: Autonomia::Agents::Material::Problemas.new(@agent).lista }
  end
end
