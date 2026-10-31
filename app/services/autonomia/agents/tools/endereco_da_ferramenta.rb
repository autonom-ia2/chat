# O endereço da chamada HTTP de uma ferramenta, com o valor do modelo de IA codificado pela POSIÇÃO da
# {{ }} (#1425, revisão 3). Antes, o valor entrava cru: `&admin=1` acrescentava campo na query, `#`
# cortava o endereço e `../` subia no caminho — com os cabeçalhos de autenticação indo junto.
#
# A posição sai do próprio texto do cadastro, com métodos de string: o fragmento começa no primeiro
# `#`, e a query no primeiro `?` antes dele. Cada parte é lida e renderizada à parte (`ModeloLiquid`):
# - esquema e host: variável recusada. Host vindo do modelo mandaria a chave para onde ele quisesse; o
#   cadastro já não aceita esse endereço (`Tool#validate_endpoint_url`), e aqui a recusa é explícita;
# - caminho: cada valor vira UM pedaço (`ERB::Util.url_encode`, que codifica também `/`, `?` e `#`).
#   Valor vazio ou só de espaços é recusado (cairia na coleção: `/clientes/`), e também valor que, partido em barra ou
#   barra invertida, tenha um pedaço "." ou ".." — um servidor que decodifica %2F antes de rotear
#   resolveria o `../`;
# - query: cada valor vira valor de campo (`URI.encode_www_form_component`);
# - fragmento: variável recusada (não vai ao servidor; só confundiria).
# Um `| url_encode` já escrito no fim da variável sai: codifica uma vez só. Endereço sem {{ }} sai
# exatamente como foi cadastrado. Tudo recusado aqui vira `endereco_invalido`.
class Autonomia::Agents::Tools::EnderecoDaFerramenta
  Recusa = Autonomia::Agents::Tools::HttpExecutor::ValorRecusado
  Modelo = Autonomia::Agents::Tools::ModeloLiquid
  RECUSA = 'endereco_invalido'.freeze
  BARRA_INVERTIDA = 92.chr.freeze
  # Espaços que o `String#strip` não tira (sem quebra, finos, ideográfico, sem largura): um valor só deles
  # também é um pedaço vazio disfarçado (#1444).
  ESPACOS_UNICODE = "\u00A0\u1680\u2000-\u200B\u202F\u205F\u3000\uFEFF".freeze
  NA_QUERY = ->(valor) { valor.nil? ? nil : URI.encode_www_form_component(Modelo.texto_de(valor)) }

  def initialize(tool:, params:)
    @cadastro = tool.endpoint_url.to_s
    @params = params
  end

  def texto
    return @cadastro unless Modelo.variavel?(@cadastro)

    base, fragmento = dividir(@cadastro, '#')
    caminho, query = dividir(base, '?')
    recusar if Modelo.variavel?(fragmento) || Modelo.variavel?(origem(caminho))

    url = renderizar(caminho, method(:no_caminho))
    recusar if @caminho_invalido
    url += "?#{renderizar(query, NA_QUERY)}" if query
    url += "##{fragmento}" if fragmento
    url
  end

  private

  # -> [antes, depois do separador] ou [texto, nil].
  def dividir(texto, separador)
    posicao = texto.index(separador)
    posicao ? [texto[0...posicao], texto[(posicao + 1)..]] : [texto, nil]
  end

  # Esquema e host (até a primeira "/" depois de "://"); sem "://", o texto todo.
  def origem(caminho)
    inicio = caminho.index('://')
    return caminho unless inicio

    barra = caminho.index('/', inicio + 3)
    barra ? caminho[0...barra] : caminho
  end

  # Roda DENTRO do render do Liquid, que troca qualquer exceção por um erro genérico: o valor inválido é
  # marcado aqui e recusado depois do render, com o código certo.
  def no_caminho(valor)
    texto = Modelo.texto_de(valor)
    @caminho_invalido ||= caminho_invalido?(texto)
    ERB::Util.url_encode(texto)
  end

  def caminho_invalido?(texto)
    pedacos = texto.split('/', -1).flat_map { |pedaco| pedaco.split(BARRA_INVERTIDA, -1) }
    texto.tr(ESPACOS_UNICODE, ' ').strip.empty? || pedacos.any? { |pedaco| ['.', '..'].include?(pedaco) }
  end

  def renderizar(texto, filtro)
    Modelo.renderizar(Modelo.ler(texto, recusa: RECUSA, sem_url_encode_final: true), @params, filtro)
  end

  def recusar
    raise Recusa, RECUSA
  end
end
