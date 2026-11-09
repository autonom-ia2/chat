# #1431 (F1) — a junção de seções do CortePorSecao: a seção pequena entra na irmã seguinte, para a definição de duas
# linhas não virar trecho sozinha.
module Autonomia::Agents::Knowledge::CortePorSecao::Juncao
  private

  # Seção pequena entra no começo da irmã seguinte, com o próprio título como primeira linha. Uma vez só: a seção que
  # recebeu uma irmã não vai adiante, para o texto não acabar sob o caminho de uma seção duas casas à frente.
  # A que recebe também põe o próprio título antes do texto dela (#2786): no glossário, sem isso a definição dela ficava
  # sem o termo, e a da irmã, sob o caminho dela. Só no trecho da seção (`pedacos`): o trecho de item já começa por ele.
  def juntar_pequenas(lista)
    recebida = nil
    lista.each_with_index.filter_map do |secao, indice|
      secao = secao.class.new(**secao.to_h, paragrafos: como_paragrafos_da_irma(recebida) + com_titulo(secao)) if recebida
      juntar = recebida.nil? && pequena?(secao) && irmas?(secao, lista[indice + 1])
      recebida = juntar ? secao : nil
      secao unless juntar
    end
  end

  def pequena?(secao)
    secao.paragrafos.sum { |paragrafo| paragrafo[:texto].length } < self.class::PISO
  end

  def irmas?(secao, seguinte)
    !seguinte.nil? && secao.caminho.any? && secao.caminho.size == seguinte.caminho.size &&
      secao.caminho[0...-1] == seguinte.caminho[0...-1]
  end

  # O título da irmã entra no começo do texto dela e do primeiro item. O título solto já é o próprio texto: não se repete.
  def como_paragrafos_da_irma(secao)
    primeiro, *resto = secao.paragrafos
    return secao.paragrafos if primeiro[:titulo_solto]

    titulo = secao.caminho.last
    junto = primeiro.merge(texto: "#{titulo}\n#{primeiro[:texto]}")
    junto = junto.merge(itens: ["#{titulo}\n#{primeiro[:itens].first}", *primeiro[:itens].drop(1)]) if primeiro[:itens].present?
    [junto, *resto]
  end

  # A seção que recebe a irmã guarda o próprio título à parte, para o primeiro pedaço do trecho da seção (`pedacos`).
  def com_titulo(secao)
    primeiro, *resto = secao.paragrafos
    primeiro[:titulo_solto] ? secao.paragrafos : [primeiro.merge(titulo: secao.caminho.last), *resto]
  end
end
