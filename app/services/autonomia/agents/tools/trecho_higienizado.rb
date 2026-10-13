# O começo do corpo de uma resposta de erro, pronto para o modelo ler (#1425).
#
# O corpo vem de um sistema de fora e pode ecoar o que a ferramenta mandou — a chave de um cabeçalho,
# um token na query. Antes de chegar ao modelo (e à tela de teste):
#   1. cada valor que a ferramenta mandou (`segredos`) vira `[oculto]`, inteiro e por partes
#      ("Bearer abc…" ecoado só como "abc…" também some);
#   2. qualquer sequência longa com cara de token (letras, dígitos, `_` e `-`, a partir de
#      `MIN_TOKEN` caracteres) vira `[oculto]`;
#   3. espaços e quebras de linha viram um espaço só, e o texto é cortado em `limite` caracteres.
# Tudo com métodos de string, sem expressão regular.
class Autonomia::Agents::Tools::TrechoHigienizado
  OCULTO = '[oculto]'.freeze
  MIN_SEGREDO = 4
  MIN_TOKEN = 32
  CARACTERES_DE_TOKEN = [*'a'..'z', *'A'..'Z', *'0'..'9', '_', '-'].to_set.freeze

  def initialize(texto, segredos:, limite:)
    @texto = texto.to_s
    @segredos = partes_dos_segredos(segredos)
    @limite = limite
  end

  def to_s
    limpo = sem_tokens_longos(sem_segredos(@texto)).split.join(' ')
    limpo.truncate(@limite).presence
  end

  private

  # Do mais longo para o mais curto: um pedaço de um segredo não pode estragar a troca do inteiro.
  def partes_dos_segredos(segredos)
    Array(segredos).flat_map { |valor| [valor.to_s, *valor.to_s.split] }
                   .map(&:strip).select { |valor| valor.length >= MIN_SEGREDO }
                   .uniq.sort_by { |valor| -valor.length }
  end

  def sem_segredos(texto)
    @segredos.reduce(texto) { |saida, segredo| saida.gsub(segredo, OCULTO) }
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
