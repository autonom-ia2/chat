# Os pedaços do texto de uma página, para comparar valor com valor (E6, #2899). A conferência do leitor nunca procura um
# valor "em algum lugar do texto": "001234" dentro de "EX-001234", "Ana" dentro de "Banana" e "2254" dentro de
# "2.254,98" não são o valor escrito. Aqui o texto vira pedaços inteiros, e só pedaço inteiro se compara.
#
# - `palavras`: letras e dígitos seguidos, sem acento e em minúsculas; todo o resto separa. Serve ao texto corrido
#   (nome, seguradora, bem).
# - `blocos`: o que está escrito junto, com a pontuação de dentro ("ex-001234", "1.234,56", "12/11/2026",
#   "nome@exemplo.com"). Espaço, quebra de linha e a pontuação de fora (dois-pontos, parênteses, cifrão) separam; a
#   pontuação das pontas sai (o ponto do fim da frase). Deles saem `codigos` (cada bloco só com letra e dígito),
#   `numeros` (os dígitos do bloco que só tem número) e `centavos` (os valores em dinheiro).
#
# Não interpreta nada: separa por caractere, com método de texto, sem regex. Quem entende o texto é o modelo.
class Carteira::Leitor::Tokens
  FORA_DA_PALAVRA = '^a-z0-9'.freeze
  FORA_DO_BLOCO = '^a-z0-9.,/@_+-'.freeze
  PONTAS = '.,/@_+-'.freeze
  SO_DIGITOS = '^0-9'.freeze
  DE_NUMERO = '0-9./-'.freeze
  DE_DINHEIRO = '0-9.,'.freeze
  PONTO = '.'.freeze
  VIRGULA = ','.freeze
  CASAS_DOS_CENTAVOS = 2
  CENTAVOS_POR_REAL = 100

  def self.digitos(texto)
    texto.to_s.delete(SO_DIGITOS)
  end

  # O trecho aparece inteiro e seguido dentro da lista? Lista vazia nunca aparece.
  def self.sequencia?(lista, trecho)
    return false if trecho.empty?

    (0..lista.size - trecho.size).any? { |inicio| lista[inicio] == trecho.first && lista[inicio, trecho.size] == trecho }
  end

  def initialize(texto)
    @texto = ActiveSupport::Inflector.transliterate(texto.to_s, locale: :en).downcase
  end

  def palavras
    @palavras ||= @texto.tr(FORA_DA_PALAVRA, ' ').split
  end

  def blocos
    @blocos ||= em_blocos(@texto)
  end

  # O fim de cada linha emendado no começo da linha seguinte: o e-mail que a quebra de linha partiu em dois volta a ser
  # um bloco. Só a quebra de linha é emendada, nunca o espaço.
  def blocos_emendados
    @blocos_emendados ||= @texto.lines.map(&:split).reject(&:empty?).each_cons(2).flat_map do |de_cima, de_baixo|
      em_blocos(de_cima.last + de_baixo.first)
    end
  end

  # A forma de comparação de cada bloco: só letra e dígito ("ex-2026.001234" é "ex2026001234").
  def codigos
    @codigos ||= blocos.map { |bloco| bloco.delete(FORA_DA_PALAVRA) }
  end

  # Para cada bloco, os dígitos dele quando só tem número ("123.456.789-00", "99999-0001", "12/11/2026"); nil no bloco
  # que tem letra ou vírgula. Na mesma ordem dos blocos, para saber o que está escrito em seguida do quê.
  def numeros
    @numeros ||= blocos.map { |bloco| bloco.delete(SO_DIGITOS) if bloco.delete(DE_NUMERO).empty? }
  end

  # Os dígitos estão escritos em blocos de número seguidos, sem nada no meio? "(11) 99999-0001" são dois blocos.
  def numeros_seguidos?(digitos)
    digitos.present? && numeros.each_index.any? { |inicio| seguidos_desde?(inicio, digitos) }
  end

  # Os valores em dinheiro escritos, em centavos: o bloco só de dígitos, ponto e vírgula, com dois dígitos depois da
  # vírgula ("1.234,56" é 123456). Valor escrito sem os centavos não entra.
  def centavos
    @centavos ||= blocos.filter_map { |bloco| em_centavos(bloco) }
  end

  private

  def em_blocos(texto)
    texto.tr(FORA_DO_BLOCO, ' ').split.filter_map { |bloco| sem_pontas(bloco) }
  end

  def sem_pontas(bloco)
    letras = bloco.chars
    inicio = letras.index { |letra| PONTAS.exclude?(letra) }
    return if inicio.nil?

    fim = letras.rindex { |letra| PONTAS.exclude?(letra) }
    bloco[inicio..fim]
  end

  def seguidos_desde?(inicio, digitos)
    resto = digitos
    (inicio...numeros.size).each do |indice|
      numero = numeros[indice]
      return false if numero.nil? || !resto.start_with?(numero)

      resto = resto.delete_prefix(numero)
      return true if resto.empty?
    end
    false
  end

  def em_centavos(bloco)
    return unless bloco.delete(DE_DINHEIRO).empty?

    reais, centavos, sobra = bloco.split(VIRGULA, 3)
    reais = reais.to_s.delete(PONTO)
    return if sobra || reais.empty? || centavos.to_s.length != CASAS_DOS_CENTAVOS || centavos.include?(PONTO)

    (reais.to_i * CENTAVOS_POR_REAL) + centavos.to_i
  end
end
