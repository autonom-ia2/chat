# E-mail e telefone que aparecem no texto da conversa saem antes da IA ler (#3158, B8b). O motivo de uma nota baixa
# não depende deles, e a revisão não precisa levá-los ao provedor.
#
# Sem expressão regular: a mensagem é cortada em palavras pelos espaços, e cada palavra é julgada pelo formato.
# - e-mail: tem "@" com algo antes e um ponto depois;
# - telefone: depois de tirar a pontuação comum de número (+ ( ) - .), sobram 8 dígitos ou mais e nada além. Com
#   barra é data (17/11/2026), não telefone. Escrito em grupos separados por espaço, ver `juntar_telefones`.
# O ponto que fecha a frase não faz parte da palavra ("joao@empresa.com.br.").
# O e-mail e o telefone do próprio contato também saem quando aparecem colados em outra palavra.
class Autonomia::Guide::Revisoes::Mascara
  EMAIL = '[e-mail]'.freeze
  TELEFONE = '[telefone]'.freeze
  # O hífen no fim: no meio, `String#delete` o leria como intervalo (de ')' a '.', que inclui a vírgula).
  PONTUACAO_DE_NUMERO = '+().-'.freeze
  BORDA = ',;:!?"\'.'.freeze
  MIN_DIGITOS = 8
  GRUPOS = 4
  DIGITOS_EM_GRUPOS = (10..13)

  def initialize(literais: [])
    @literais = literais.map(&:to_s).map(&:strip).select { |literal| literal.size >= 6 }
  end

  def call(texto)
    # `scrub`: byte inválido (comum no WhatsApp) quebraria a montagem do JSON para a IA.
    # `gsub` com texto (não expressão regular) troca o literal exato.
    limpo = @literais.reduce(texto.to_s.scrub) { |atual, literal| atual.gsub(literal, marca(literal)) }
    juntar_telefones(limpo.split).map { |palavra| mascarar(palavra) }.join(' ')
  end

  private

  def marca(literal) = literal.include?('@') ? EMAIL : TELEFONE

  # Telefone escrito em grupos ("11 98765 4321", "+55 11 98765-4321", "(11) 98765-4321"): palavras vizinhas só de
  # número que, juntas, dão de 10 a 13 dígitos (DDD e número, com ou sem o 55) viram um telefone só. Um grupo precisa ter 4 dígitos ou
  # mais, para "1 2 3" de uma lista não virar telefone.
  def juntar_telefones(palavras)
    saida = []
    indice = 0
    while indice < palavras.size
      fim = fim_do_telefone(palavras, indice)
      saida << (fim ? TELEFONE : palavras[indice])
      indice = fim ? fim + 1 : indice + 1
    end
    saida
  end

  # -> o índice da última palavra do telefone que começa em `inicio`, ou nil.
  def fim_do_telefone(palavras, inicio)
    digitos = 0
    grupo_longo = false
    (inicio...[inicio + GRUPOS, palavras.size].min).each do |indice|
      numeros = so_numero(palavras[indice])
      return nil if numeros.nil?

      digitos += numeros.size
      grupo_longo ||= numeros.size >= 4
      return indice if indice > inicio && grupo_longo && DIGITOS_EM_GRUPOS.cover?(digitos)
    end
    nil
  end

  # -> os dígitos da palavra feita só de número e pontuação de número, ou nil.
  def so_numero(palavra)
    numeros = nucleo(palavra).delete(PONTUACAO_DE_NUMERO)
    numeros if numeros.present? && digitos?(numeros)
  end

  # A palavra sem a pontuação de frase das pontas. A de dentro fica: "1.500,00" é valor, não telefone.
  def nucleo(palavra)
    fim = palavra.size
    fim -= 1 while fim.positive? && BORDA.include?(palavra[fim - 1])
    inicio = 0
    inicio += 1 while inicio < fim && BORDA.include?(palavra[inicio])
    palavra[inicio...fim]
  end

  def digitos?(texto) = texto.each_char.all? { |caractere| caractere.between?('0', '9') }

  def mascarar(palavra)
    nucleo = nucleo(palavra)
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
    numeros.size >= MIN_DIGITOS && digitos?(numeros)
  end
end
