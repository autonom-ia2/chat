# #1431 (F1) — o corte por seção. Recebe os blocos que o processor leu da estrutura do próprio formato (título com nível,
# parágrafo, página) e devolve os trechos no formato do Chunker#chunks_with_metadata, mais as páginas.
#
# - Uma seção é tudo o que vem sob um título, até o próximo título do mesmo nível ou acima.
# - Seção até MAXIMO caracteres vira um trecho só; maior, divide por parágrafo, e o último parágrafo de um trecho abre o
#   seguinte (a resposta que cruza a divisa cabe inteira num dos dois).
# - Seção com corpo abaixo de PISO se junta à irmã seguinte (mesmo pai), com o título dela no texto: a definição de duas
#   linhas não vira trecho sozinha.
# - Cada trecho começa pelo caminho (Documento › Seção › Subseção), que vai ao embedding: é ele que faz "franquia" achar
#   o trecho da seção FRANQUIA. As páginas vão ao metadado, não ao texto.
# Nada aqui lê o texto da pessoa: a estrutura vem do formato.
class Autonomia::Agents::Knowledge::CortePorSecao
  # ~400 tokens em português (desenho da F1, docs/audit/2026-11-08-rag-v2-f1/desenho-f1.md).
  MAXIMO = 1600
  # ~60 tokens: abaixo disso a seção se junta à irmã seguinte.
  PISO = 240
  SEPARADOR = ' › '.freeze
  FIM_DE_FRASE = '. '.freeze

  Secao = Struct.new(:caminho, :paragrafos, :id, :pagina, keyword_init: true)

  def initialize(blocos, documento:, maximo: MAXIMO)
    @blocos = blocos
    @documento = documento
    @maximo = maximo
  end

  def trechos
    juntar_pequenas(secoes).flat_map { |secao| trechos_da(secao) }
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

  # Seção pequena entra no começo da irmã seguinte, com o próprio título como primeira linha.
  def juntar_pequenas(lista)
    lista.each_with_index.filter_map do |secao, indice|
      seguinte = lista[indice + 1]
      next secao unless pequena?(secao) && irmas?(secao, seguinte)

      seguinte.paragrafos.unshift(*como_paragrafos_da_irma(secao))
      nil
    end
  end

  def pequena?(secao)
    secao.paragrafos.sum { |paragrafo| paragrafo[:texto].length } < PISO
  end

  def irmas?(secao, seguinte)
    !seguinte.nil? && secao.caminho.any? && secao.caminho.size == seguinte.caminho.size &&
      secao.caminho[0...-1] == seguinte.caminho[0...-1]
  end

  def como_paragrafos_da_irma(secao)
    primeiro, *resto = secao.paragrafos
    [primeiro.merge(texto: "#{secao.caminho.last}\n#{primeiro[:texto]}"), *resto]
  end

  def trechos_da(secao)
    caminho = [@documento.presence, *secao.caminho].compact
    grupos(pedacos(secao.paragrafos)).map do |grupo|
      corpo = grupo.pluck(:texto).join("\n\n")
      { text: [caminho.join(SEPARADOR).presence, corpo].compact.join("\n\n"),
        paginas: grupo.pluck(:pagina).minmax,
        metadata: { section_heading: secao.caminho.last, material_type: 'secao', char_span: corpo.length,
                    keywords: Autonomia::Agents::Knowledge::Chunker.keywords_for("#{secao.caminho.last} #{corpo}"),
                    caminho: caminho, secao_id: secao.id } }
    end
  end

  # Parágrafo maior que o máximo vira vários, cortados no fim de frase (ou no espaço), nunca no meio da palavra.
  def pedacos(paragrafos)
    paragrafos.flat_map do |paragrafo|
      fatias(paragrafo[:texto]).map { |texto| paragrafo.merge(texto: texto) }
    end
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
