# #1426 (tema 4b) — o que o dono escolheu quando dois materiais se contradizem. Os dois materiais continuam na base
# (decisão do Rodrigo, 19/10); o agente recebe, junto dos trechos, QUAL MATERIAL vale em cada assunto. Só na Fase 2,
# fora da Lia, e só com escolha gravada: sem ela, o bloco de contexto fica byte a byte o de antes. A escolha só vale
# enquanto o material escolhido estiver em uso (tirado ou reprovado, sai daqui na hora, sem esperar a próxima conferência).
#
# Ao prompt vai só a preferência por material: o assunto e o nome do material (o mesmo rótulo `fonte:` dos trechos),
# cada linha em JSON. O trecho que o modelo apontou fica só na tela: texto livre do modelo nunca entra aqui com
# prioridade, e o agente lê o que vale nos trechos do próprio material.
module Autonomia::Agents::Material::DecisoesDoMaterial
  module_function

  CABECALHO = 'QUANDO OS MATERIAIS DIVERGEM (escolha do dono, dado): em cada assunto abaixo, use o que diz o material ' \
              'indicado em "vale_o_material" (o mesmo nome do "fonte:" dos trechos), mesmo que outro material diga outra coisa.'.freeze

  def texto(agent)
    return unless agent.respond_to?(:chave_do_material) && Autonomia::Agents::Material.conferir?(agent)

    linhas = decididas(agent)
    return if linhas.empty?

    "#{CABECALHO}\n#{linhas.join("\n")}"
  end

  # Uma linha JSON por escolha cujo material ainda está em uso.
  def decididas(agent)
    escolhidas = Array(agent.chave_do_material(Autonomia::Agents::Material::Contradicoes::CHAVE).to_h['contradicoes'])
                 .select { |item| item['escolha'].present? }
    return [] if escolhidas.empty?

    em_uso = agent.sources.knowledge_sources.servable.where(id: escolhidas.pluck('escolha')).index_by(&:id)
    escolhidas.filter_map do |item|
      fonte = em_uso[item['escolha']]
      { assunto: item['assunto'].to_s.squish, vale_o_material: Autonomia::Agents::Material.nome(fonte) }.to_json if fonte
    end
  end
end
