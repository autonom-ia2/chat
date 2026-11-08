# #1431 (F1) — o corte por seção. Recebe os blocos que o processor leu da estrutura do próprio formato (título com nível,
# parágrafo, página) e devolve os trechos no formato do Chunker#chunks_with_metadata, mais as páginas.
#
# - Uma seção é tudo o que vem sob um título, até o próximo título do mesmo nível ou acima.
# - Seção até MAXIMO caracteres vira um trecho só; maior, divide por parágrafo, e o último parágrafo de um trecho abre o
#   seguinte (a resposta que cruza a divisa cabe inteira num dos dois).
# - Seção com corpo abaixo de PISO se junta à irmã seguinte (mesmo pai), com o título dela no texto: a definição de duas
#   linhas não vira trecho sozinha.
# - Cada trecho começa pelo caminho (Documento › Seção › Subseção), que vai ao embedding: é ele que faz "franquia" achar
#   o trecho da seção FRANQUIA. As páginas do trecho vão ao metadado (`paginas_do_trecho`), não ao texto. A chave
#   `paginas` é outra coisa: a seção de 25 páginas do material grande, que o Ingestor põe (ResumoPorSecao e Revisor
#   leem por ela).
# - PR 1b: na seção longa (acima de ITENS_ACIMA), cada item (o item de lista, o verbete do glossário, que o processor
#   marca em `itens`) também vira trecho, com o mesmo caminho; a fileira da tabela, sempre. Na medida da F1 eles ficavam
#   diluídos no trecho da seção inteira e a busca não os achava (docs/audit/2026-11-08-rag-v2-f1/medida-f1.md). O trecho
#   de item serve só para achar: leva em `trecho_da_secao` o índice do trecho da seção que o contém, e é este que a busca
#   devolve (Retriever); quem lê o material inteiro o ignora (KnowledgeEntry.do_material). O item curto (o termo antes da
#   definição) entra no seguinte, e a abertura mais recente da seção, a linha que termina em dois-pontos ("estarão
#   excluídas da cobertura:"), vai junto de cada item seguinte, para o item não perder o sentido. A tabela entra no trecho
#   da seção com as fileiras já com o cabeçalho de cada coluna, e a maior que o máximo divide entre fileiras.
# Nada aqui lê o texto da pessoa: a estrutura vem do formato.
class Autonomia::Agents::Knowledge::CortePorSecao
  # ~400 tokens em português (desenho da F1, docs/audit/2026-11-08-rag-v2-f1/desenho-f1.md).
  MAXIMO = 1600
  # ~60 tokens: abaixo disso a seção se junta à irmã seguinte.
  PISO = 240
  SEPARADOR = ' › '.freeze
  FIM_DE_FRASE = '. '.freeze
  # Seção com corpo acima disto dá também um trecho por item.
  ITENS_ACIMA = 600
  # Item abaixo disto (o termo do glossário) entra no começo do seguinte.
  MINIMO_DO_ITEM = 60
  # A abertura da lista vai junto de cada item até este tamanho.
  MAXIMO_DA_ABERTURA = 400
  ABRE_LISTA = ':'.freeze

  Secao = Struct.new(:caminho, :paragrafos, :id, :pagina, keyword_init: true)

  def initialize(blocos, documento:, maximo: MAXIMO)
    @blocos = blocos
    @documento = documento
    @maximo = maximo
  end

  def trechos
    juntar_pequenas(secoes).each_with_object([]) do |secao, lista|
      da_secao = trechos_da(secao)
      inicio = lista.size
      lista.concat(da_secao)
      lista.concat(trechos_dos_itens(secao).map { |item| com_trecho_da_secao(item, da_secao, inicio) })
    end
  end

  private

  # As seções na ordem do documento. O texto antes do primeiro título fica sob o nome do documento.
  def secoes
    titulos = []
    lista = [Secao.new(caminho: [], paragrafos: [], id: 's0')]
    @blocos.each do |bloco|
      next lista.last.paragrafos << bloco unless bloco[:tipo] == :titulo

      titulos.pop while titulos.any? && titulos.last[:nivel] >= bloco[:nivel]
      titulos << bloco
      lista << Secao.new(caminho: titulos.pluck(:texto), paragrafos: [], id: "s#{lista.size}", pagina: bloco[:pagina])
    end
    com_titulos_soltos(lista).reject { |secao| secao.paragrafos.empty? }
  end

  # Título sem nada embaixo e que não abre subseção (o seguinte não é mais fundo) é conteúdo lido como título — o item
  # de lista curto em negrito, por exemplo. O texto dele vira o corpo da própria seção, para não sumir.
  def com_titulos_soltos(lista)
    lista.each_with_index.map do |secao, indice|
      seguinte = lista[indice + 1]
      next secao unless secao.paragrafos.empty? && secao.caminho.any?
      next secao if seguinte && seguinte.caminho.size > secao.caminho.size

      secao.class.new(**secao.to_h, paragrafos: [{ tipo: :paragrafo, texto: secao.caminho.last, pagina: secao.pagina }])
    end
  end

  # Seção pequena entra no começo da irmã seguinte, com o próprio título como primeira linha. Uma vez só: a seção que
  # recebeu uma irmã não vai adiante, para o texto não acabar sob o caminho de uma seção duas casas à frente.
  def juntar_pequenas(lista)
    recebida = nil
    lista.each_with_index.filter_map do |secao, indice|
      secao = secao.class.new(**secao.to_h, paragrafos: como_paragrafos_da_irma(recebida) + secao.paragrafos) if recebida
      juntar = recebida.nil? && pequena?(secao) && irmas?(secao, lista[indice + 1])
      recebida = juntar ? secao : nil
      secao unless juntar
    end
  end

  def pequena?(secao)
    secao.paragrafos.sum { |paragrafo| paragrafo[:texto].length } < PISO
  end

  def irmas?(secao, seguinte)
    !seguinte.nil? && secao.caminho.any? && secao.caminho.size == seguinte.caminho.size &&
      secao.caminho[0...-1] == seguinte.caminho[0...-1]
  end

  # O título da irmã entra no começo do texto dela e do primeiro item.
  def como_paragrafos_da_irma(secao)
    primeiro, *resto = secao.paragrafos
    titulo = secao.caminho.last
    junto = primeiro.merge(texto: "#{titulo}\n#{primeiro[:texto]}")
    junto = junto.merge(itens: ["#{titulo}\n#{primeiro[:itens].first}", *primeiro[:itens].drop(1)]) if primeiro[:itens].present?
    [junto, *resto]
  end

  def trechos_da(secao)
    grupos(pedacos(secao.paragrafos)).map do |grupo|
      paginas = grupo.flat_map { |paragrafo| [paragrafo[:pagina], paragrafo[:pagina_fim]] }.compact.minmax
      trecho(secao, grupo.pluck(:texto).join("\n\n"), paginas, 'secao')
    end
  end

  # O trecho de item começa só pelo título da seção dele: o caminho inteiro, igual em todos os itens, pesava mais que o
  # item curto na busca. O metadado leva o caminho inteiro nos dois.
  def trecho(secao, corpo, paginas, tipo)
    caminho = [@documento.presence, *secao.caminho].compact
    rotulo = tipo == 'item' ? secao.caminho.last : caminho.join(SEPARADOR)
    { text: [rotulo.presence, corpo].compact.join("\n\n"), paginas: paginas,
      metadata: { section_heading: secao.caminho.last, material_type: tipo, char_span: corpo.length,
                  keywords: Autonomia::Agents::Knowledge::Chunker.keywords_for("#{secao.caminho.last} #{corpo}"),
                  caminho: caminho, secao_id: secao.id } }
  end

  def trechos_dos_itens(secao)
    itens = com_aberturas(juntar_curtos(unidades(secao)))
    return [] if itens.size < 2

    itens.flat_map do |abertura, item|
      fatias(item[:texto]).map do |texto|
        trecho(secao, [abertura, texto].compact.join("\n"), [item[:pagina], item[:pagina]], 'item').merge(nucleo: texto)
      end
    end
  end

  # O índice (na lista final) do trecho da seção que contém o item inteiro. O item que atravessa a divisa entre dois
  # trechos da seção fica sem ele: a busca devolve o próprio item, que tem o texto inteiro.
  def com_trecho_da_secao(item, da_secao, inicio)
    pai = da_secao.index { |trecho| trecho[:text].include?(item[:nucleo]) }
    metadata = pai ? item[:metadata].merge(trecho_da_secao: inicio + pai) : item[:metadata]
    item.except(:nucleo).merge(metadata: metadata)
  end

  # [abertura, item]: cada item com a abertura mais recente da seção. A abertura não vira item (está no trecho da seção), e
  # a fileira da tabela vai sem ela (tem o cabeçalho).
  def com_aberturas(itens)
    abertura = nil
    itens.each_with_object([]) do |item, lista|
      next abertura = item[:texto] if item[:abertura]

      lista << [item[:fileira] ? nil : abertura, item]
    end
  end

  # Os itens da seção, na ordem: a fileira da tabela sempre; o item do parágrafo só na seção longa. Parágrafo sem itens
  # marcados é um item só.
  def unidades(secao)
    longa = tamanho(secao.paragrafos) > ITENS_ACIMA
    secao.paragrafos.flat_map do |paragrafo|
      next paragrafo[:itens].map { |texto| { texto: texto, pagina: paragrafo[:pagina], fileira: true } } if paragrafo[:tipo] == :tabela
      next [] unless longa

      (paragrafo[:itens] || [paragrafo[:texto]]).map { |texto| { texto: texto, pagina: paragrafo[:pagina], abertura: abertura?(texto) } }
    end
  end

  def abertura?(texto)
    texto.end_with?(ABRE_LISTA) && texto.length <= MAXIMO_DA_ABERTURA
  end

  # O item curto entra no começo do seguinte, uma vez só; o último fica, mesmo curto. A fileira de tabela e a abertura
  # não se juntam.
  def juntar_curtos(unidades)
    guardado = nil
    unidades.each_with_index.filter_map do |unidade, indice|
      unidade = unidade.merge(texto: "#{guardado[:texto]}\n#{unidade[:texto]}") if guardado
      juntar = guardado.nil? && curto?(unidade) && indice < unidades.size - 1
      guardado = juntar ? unidade : nil
      unidade unless juntar
    end
  end

  def curto?(unidade)
    !unidade[:fileira] && !unidade[:abertura] && unidade[:texto].length < MINIMO_DO_ITEM
  end

  # Parágrafo maior que o máximo vira vários, cortados no fim de frase (ou no espaço), nunca no meio da palavra. A tabela
  # divide entre fileiras.
  def pedacos(paragrafos)
    paragrafos.flat_map do |paragrafo|
      textos = paragrafo[:tipo] == :tabela ? partes_da_tabela(paragrafo) : fatias(paragrafo[:texto])
      textos.map { |texto| paragrafo.merge(texto: texto) }
    end
  end

  # A tabela maior que o máximo vira partes de fileiras inteiras (cada fileira já traz o cabeçalho das colunas).
  def partes_da_tabela(tabela)
    return [tabela[:texto]] if tabela[:texto].length <= @maximo

    partes = tabela[:itens].each_with_object([[]]) do |fileira, grupos|
      grupos << [] if grupos.last.any? && grupos.last.sum(&:length) + grupos.last.size + fileira.length > @maximo
      grupos.last << fileira
    end
    partes.map { |fileiras| fileiras.join("\n") }
  end

  def fatias(texto)
    resto = texto.strip
    partes = []
    while resto.length > @maximo
      corte = ponto_de_corte(resto)
      partes << resto[0...corte].strip
      resto = resto[corte..].strip
    end
    partes << resto
  end

  def ponto_de_corte(texto)
    janela = texto[0...@maximo]
    fim_de_frase = janela.rindex(FIM_DE_FRASE)
    return fim_de_frase + 1 if fim_de_frase&.positive?

    janela.rindex(' ') || @maximo
  end

  # Grupos de parágrafos até o máximo; o último parágrafo de um grupo abre o seguinte.
  def grupos(paragrafos)
    lista = [[]]
    paragrafos.each do |paragrafo|
      atual = lista.last
      if atual.any? && tamanho(atual + [paragrafo]) > @maximo
        anterior = atual.last
        lista << (tamanho([anterior, paragrafo]) <= @maximo ? [anterior] : [])
      end
      lista.last << paragrafo
    end
    lista
  end

  def tamanho(grupo)
    grupo.sum { |paragrafo| paragrafo[:texto].length } + ((grupo.size - 1) * 2)
  end
end
