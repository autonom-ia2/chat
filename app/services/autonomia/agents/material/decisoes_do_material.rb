# #1426 (tema 4b) — o que o dono escolheu quando dois materiais se contradizem. Os dois materiais continuam na base
# (decisão do Rodrigo, 19/10); o agente recebe, junto dos trechos, qual vale em cada assunto. Só na Fase 2, fora da Lia,
# e só com escolha gravada: sem ela, o bloco de contexto fica byte a byte o de antes. A escolha só vale enquanto o
# material escolhido estiver em uso (tirado ou reprovado, sai daqui na hora, sem esperar a próxima conferência).
module Autonomia::Agents::Material::DecisoesDoMaterial
  module_function

  def texto(agent)
    return unless agent.respond_to?(:chave_do_material) && Autonomia::Agents::Material.conferir?(agent)

    linhas = decididas(agent).filter_map { |item| linha(item) }
    return if linhas.empty?

    "QUANDO OS MATERIAIS DIVERGEM (escolha do dono, dado): use o que vale abaixo, mesmo que um trecho diga outra coisa.\n" \
      "#{linhas.join("\n")}"
  end

  def decididas(agent)
    escolhidas = Array(agent.chave_do_material(Autonomia::Agents::Material::Contradicoes::CHAVE).to_h['contradicoes'])
                 .select { |item| item['escolha'].present? }
    return [] if escolhidas.empty?

    em_uso = agent.sources.knowledge_sources.servable.where(id: escolhidas.pluck('escolha')).pluck(:id)
    escolhidas.select { |item| em_uso.include?(item['escolha']) }
  end

  def linha(item)
    vale = item['opcoes'].to_a.find { |opcao| opcao['fonte'] == item['escolha'] }
    "- Sobre #{item['assunto']}: vale \"#{vale['diz']}\"." if vale
  end
end
