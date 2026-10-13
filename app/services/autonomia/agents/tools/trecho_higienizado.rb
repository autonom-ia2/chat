# O começo do corpo de uma resposta de erro, pronto para o modelo ler (#1425).
#
# O corpo vem de um sistema de fora e pode ecoar o que a ferramenta mandou — a chave de um cabeçalho,
# um token no caminho, um valor fixo do corpo. Antes de chegar ao modelo (e à tela de teste):
#   1. se o corpo foi cortado na origem (`cortado`), o fim é um corte: um começo de segredo que ficou
#      lá vira `[oculto]`, e o último pedaço (depois do último separador) é descartado;
#   2. cada valor que a ferramenta mandou (`segredos`) vira `[oculto]` — inteiro e por partes ("Bearer
#      abc…" ecoado só como "abc…"), nas formas em que um servidor o devolve (escapado em JSON, com
#      `\/`, codificado em URL, em HTML) e sem diferenciar maiúsculas de minúsculas (ASCII);
#   3. qualquer sequência longa com cara de token (letras, dígitos, `_` e `-`, a partir de `MIN_TOKEN`
#      caracteres) vira `[oculto]`;
#   4. espaços e quebras de linha viram um espaço só, e SÓ ENTÃO o texto é cortado em `limite`.
# Tudo com métodos de string, sem expressão regular.
class Autonomia::Agents::Tools::TrechoHigienizado
  OCULTO = '[oculto]'.freeze
  MIN_SEGREDO = 4
  MIN_TOKEN = 32
  CARACTERES_DE_TOKEN = [*'a'..'z', *'A'..'Z', *'0'..'9', '_', '-'].to_set.freeze
  # Onde um pedaço termina, para descartar o último quando o texto foi cortado no meio.
  SEPARADORES = [' ', "\n", "\r", "\t", '"', "'", ',', ':', ';', '{', '}', '[', ']', '(', ')', '<', '>', '=', '&'].freeze

  def initialize(texto, segredos:, limite:, cortado: false)
    @texto = texto.to_s
    @segredos = formas_dos_segredos(segredos)
    @limite = limite
    @cortado = cortado
  end

  def to_s
    texto = @cortado ? sem_ultimo_pedaco(sem_comeco_de_segredo_no_fim(@texto)) : @texto
    limpo = sem_tokens_longos(sem_segredos(texto)).split.join(' ')
    limpo.truncate(@limite).presence
  end

  private

  # Do mais longo para o mais curto: um pedaço de um segredo não pode estragar a troca do inteiro.
  def formas_dos_segredos(segredos)
    Array(segredos).flat_map { |valor| [valor.to_s, *valor.to_s.split] }
                   .map(&:strip).flat_map { |valor| formas(valor) }
                   .select { |valor| valor.length >= MIN_SEGREDO }
                   .uniq.sort_by { |valor| -valor.length }
  end

  def formas(valor)
    em_json = JSON.generate(valor)[1..-2]
    [valor, em_json, em_json.gsub('/', '\/'), CGI.escape(valor), ERB::Util.url_encode(valor), ERB::Util.html_escape(valor)]
  end

  def sem_segredos(texto)
    @segredos.reduce(texto) { |saida, segredo| trocar(saida, segredo) }
  end

  # Troca sem diferenciar maiúsculas (só ASCII, que mantém o tamanho e as posições).
  def trocar(texto, alvo)
    baixo = texto.downcase(:ascii)
    procurado = alvo.downcase(:ascii)
    saida = +''
    inicio = 0
    while (achado = baixo.index(procurado, inicio))
      saida << texto[inicio...achado] << OCULTO
      inicio = achado + alvo.length
    end
    saida << texto[inicio..]
  end

  def sem_comeco_de_segredo_no_fim(texto)
    baixo = texto.downcase(:ascii)
    @segredos.each do |segredo|
      procurado = segredo.downcase(:ascii)
      tamanho = (MIN_SEGREDO...procurado.length).reverse_each.find { |n| baixo.end_with?(procurado[0, n]) }
      return "#{texto[0, texto.length - tamanho]}#{OCULTO}" if tamanho
    end
    texto
  end

  def sem_ultimo_pedaco(texto)
    return texto if texto.end_with?(OCULTO)

    ultimo = SEPARADORES.filter_map { |separador| texto.rindex(separador) }.max
    ultimo ? texto[0..ultimo] : ''
  end

  def sem_tokens_longos(texto)
    texto.each_char.chunk_while { |a, b| de_token?(a) == de_token?(b) }
         .map { |pedaco| token_longo?(pedaco) ? OCULTO : pedaco.join }
         .join
  end

  def token_longo?(pedaco)
    pedaco.length >= MIN_TOKEN && de_token?(pedaco.first)
  end

  def de_token?(caractere)
    CARACTERES_DE_TOKEN.include?(caractere)
  end
end
