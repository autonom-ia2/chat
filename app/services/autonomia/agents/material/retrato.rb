# #1426 (tema 4b) — o que a gaveta "O que sabe" lê do material, além da lista de materiais (que segue na API de
# sources): os problemas, um por vez, e o resumo do autoteste. Nunca a instrução, o prompt nem o texto do material
# (só a primeira linha da tabela sem cabeçalho e o que o autoteste guardou). Fora do material da Fase 2: vazio.
class Autonomia::Agents::Material::Retrato
  def initialize(agent)
    @agent = agent
  end

  def to_h
    return { problemas: [], autoteste: nil } unless Autonomia::Agents::Material.conferir?(@agent)

    { problemas: Autonomia::Agents::Material::Problemas.new(@agent).lista, autoteste: autoteste }
  end

  private

  # estado: nunca (ainda não rodou) | rodando | pronto | parado (não terminou: teto, IA indisponível ou rodada que morreu).
  def autoteste
    salvo = @agent.chave_do_material(Autonomia::Agents::Material::Autoteste::CHAVE)
    return nunca if salvo.blank?

    itens = Array(salvo['itens'])
    { estado: estado(salvo), quando: salvo['quando'], feitas: salvo['feitas'].to_i, total: salvo['total'].to_i,
      do_material: da_origem(itens, 'material').size, de_fora: da_origem(itens, 'fora').size,
      certas_do_material: da_origem(itens, 'material').count { |item| ok?(item) },
      certas_de_fora: da_origem(itens, 'fora').count { |item| ok?(item) },
      resultados: itens.map { |item| { pergunta: item['pergunta'], origem: item['origem'], ok: ok?(item) } } }
  end

  def da_origem(itens, origem)
    itens.select { |item| item['origem'] == origem }
  end

  # Certa pelo juiz (certo, ou recusou na de fora) ou porque a pessoa disse que a resposta está certa.
  def ok?(item)
    %w[certo recusou].include?(item['veredito']) || item['confirmada'] == true
  end

  def estado(salvo)
    return 'parado' if salvo['estado'] == 'rodando' && Autonomia::Agents::Material::Autoteste.vencida?(salvo)

    salvo['estado']
  end

  # Sem rodada ainda: a caixa aparece só quando há material aprovado para testar.
  def nunca
    return unless @agent.sources.knowledge_sources.servable.exists?

    { estado: 'nunca', quando: nil, feitas: 0, total: 0, do_material: 0, de_fora: 0, certas_do_material: 0,
      certas_de_fora: 0, resultados: [] }
  end
end
