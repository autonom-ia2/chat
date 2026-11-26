# #3237: a busca na web da OpenAI devolve links com `utm_source=openai` e, às vezes, em markdown `[texto](url)`. Isso
# chegava ao cliente no WhatsApp. Aqui sai só essa marca (os outros parâmetros ficam, na mesma ordem) e o link em markdown
# vira o endereço puro. Sem regex novo: o ReplyChunker já sabe achar a URL no texto, e a URL é lida com o parser do Ruby.
module Autonomia::Agents::Answerer::LinkSemMarca
  PARAMETRO = 'utm_source'.freeze
  VALOR = 'openai'.freeze
  # Pontuação do texto que a URL achada pode ter engolido no fim.
  PONTUACAO_FINAL = ').,;!?'.freeze

  module_function

  def limpar(texto)
    return texto unless texto.is_a?(String) && texto.include?('http')

    sem_markdown(texto).gsub(Autonomia::Agents::Operate::ReplyChunker::URL_REGEX) { |achado| limpar_url(achado) }
  end

  # `[texto](https://...)` -> `https://...`. O `[texto]` some; o `(` e o `)` que embrulham o endereço também.
  def sem_markdown(texto)
    saida = texto.dup
    desde = 0
    while (meio = saida.index('](http', desde))
      abre, fecha = link_em(saida, meio)
      unless abre
        desde = meio + 1
        next
      end

      url = saida[(meio + 2)...fecha]
      saida[abre..fecha] = url
      desde = abre + url.length
    end
    saida
  end

  # Onde começa (`[`) e termina (`)`) o link em markdown cujo `](` está em `meio`, ou nil. O `[` fica na mesma linha e
  # o endereço não tem espaço nem quebra: um `[` solto lá atrás não engole o texto até o link.
  def link_em(saida, meio)
    abre = saida.rindex('[', meio)
    fecha = saida.index(')', meio)
    return unless abre && fecha
    return if saida[abre...meio].include?("\n") || saida[(meio + 2)...fecha].split.size != 1

    [abre, fecha]
  end

  def limpar_url(achado)
    url = achado.dup
    cola = +''
    cola.prepend(url.slice!(-1)) until url.empty? || PONTUACAO_FINAL.exclude?(url[-1])
    "#{sem_a_marca(url)}#{cola}"
  rescue URI::InvalidURIError
    achado
  end

  def sem_a_marca(url)
    uri = URI.parse(url)
    pares = uri.query.to_s.split('&')
    restante = pares.reject { |par| marca?(par) }
    return url if restante.size == pares.size

    uri.query = restante.empty? ? nil : restante.join('&')
    uri.to_s
  end

  def marca?(par)
    chave, valor = par.split('=', 2)
    chave == PARAMETRO && valor == VALOR
  end
end
