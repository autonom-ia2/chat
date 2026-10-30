# #1426 (t4d) — os trechos do material que o agente usou numa resposta do autoteste ("De onde {agente} tirou"). O
# autoteste guarda até 3 por pergunta: { fonte (id do material), paginas ([ini, fim] no material grande), texto }.
module Autonomia::Agents::Material::TrechosUsados
  # Para a tela: [{ onde, paginas, texto }]. O trecho de um material que saiu da base sai junto. nil numa rodada de
  # antes dos trechos, ou quando todos os trechos eram de material que saiu: a tela não mostra nada (o agente usou o
  # material, então "não usou nenhum trecho" seria falso).
  def self.da_tela(item, fontes_por_id)
    return unless item.key?('trechos')

    gravados = Array(item['trechos'])
    na_tela = gravados.filter_map do |trecho|
      fonte = fontes_por_id[trecho['fonte']]
      next unless fonte

      { 'onde' => Autonomia::Agents::Material.nome(fonte), 'paginas' => trecho['paginas'], 'texto' => trecho['texto'] }.compact
    end
    na_tela unless na_tela.empty? && gravados.any?
  end
end
