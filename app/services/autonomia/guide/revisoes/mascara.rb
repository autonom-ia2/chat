# E-mail e telefone que aparecem no texto da conversa saem antes da IA ler (#3158, B8b). O motivo de uma nota baixa
# não depende deles, e a revisão não precisa levá-los ao provedor.
#
# Sem expressão regular: a mensagem é cortada em palavras pelos espaços, e cada palavra é julgada pelo formato.
# - e-mail: tem "@" com algo antes e um ponto depois;
# - telefone: depois de tirar a pontuação comum de número (+ ( ) - .), sobram 8 dígitos ou mais e nada além. Com
#   barra é data (17/11/2026), não telefone.
# O e-mail e o telefone do próprio contato também saem quando aparecem colados em outra palavra.
class Autonomia::Guide::Revisoes::Mascara
  EMAIL = '[e-mail]'.freeze
  TELEFONE = '[telefone]'.freeze
  PONTUACAO_DE_NUMERO = '+()-.'.freeze
  PONTUACAO_DE_FRASE = ',;:!?"\''.freeze
  MIN_DIGITOS = 8

  def initialize(literais: [])
    @literais = literais.map(&:to_s).map(&:strip).select { |literal| literal.size >= 6 }
  end

  def call(texto)
    # `gsub` com texto (não expressão regular) troca o literal exato.
    limpo = @literais.reduce(texto.to_s) { |atual, literal| atual.gsub(literal, marca(literal)) }
    limpo.split.map { |palavra| mascarar(palavra) }.join(' ')
  end

  private

  def marca(literal) = literal.include?('@') ? EMAIL : TELEFONE

  def mascarar(palavra)
    nucleo = palavra.delete(PONTUACAO_DE_FRASE)
    return palavra if nucleo.empty?
    return EMAIL if email?(nucleo)
    return TELEFONE if telefone?(nucleo)

    palavra
  end

  def email?(palavra)
    antes, depois = palavra.split('@', 2)
    antes.present? && depois.to_s.include?('.') && !depois.start_with?('.') && !depois.end_with?('.')
  end

  def telefone?(palavra)
    return false if palavra.include?('/')

    numeros = palavra.delete(PONTUACAO_DE_NUMERO)
    numeros.size >= MIN_DIGITOS && numeros.each_char.all? { |caractere| caractere.between?('0', '9') }
  end
end
