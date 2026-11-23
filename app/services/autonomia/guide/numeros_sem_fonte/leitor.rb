# Acha os números de um texto para a conferência de números do Guia (#3158), sem expressão regular.
#
# O `Captain::Copilot::NumberCheck` faz isto com regex. Aqui é um leitor de caracteres, pela regra do Rodrigo:
# fora de interpretação de linguagem, regex não é a escolha padrão quando há caminho legível. O comportamento é
# o do Copilot, com duas diferenças anotadas abaixo.
#
# Duas leituras:
#  - `da_ferramenta`: saída de ferramenta, que é JSON gerado por código. Número é dígitos com uma parte decimal
#    depois de ponto. Diferente do Copilot, vírgula nunca agrupa milhar: em JSON, `[100,200]` são dois números.
#  - `da_resposta`: o rascunho do modelo, no idioma da pessoa. Os grupos de milhar podem vir separados por ponto,
#    vírgula, apóstrofo ou espaço (1.899, 1 899,50, 1'899).
#
# Não são medida (não entram na conta): data e hora (dígitos ligados por `-`, `/` ou `:` — além do Copilot, que
# só pulava AAAA-MM-DD, pega o 23/11 do português), referência `#123`, o destino de um link `](...)` e o
# marcador de lista no começo da frase (`1. `, `2) `). Número colado em letra também não (5x, 14h30).
class Autonomia::Guide::NumerosSemFonte::Leitor
  Numero = Data.define(:texto, :medida)

  DATA = ['-', '/', ':'].freeze
  RESTO_DA_DATA = ['-', '/', ':', '.', 'T', 'Z', '+'].freeze
  ESPACOS = [' ', "\u00A0", "\u2009", "\u202F"].freeze
  BRANCOS = (ESPACOS + ["\t", "\n", "\r"]).freeze
  SEPARADORES_DA_RESPOSTA = ['.', ',', "'", '’'].freeze
  FIM_DE_FRASE = ['.', '!', '?', '。', '！', '？'].freeze
  PERGUNTA = ['?', '？', '؟'].freeze
  MARCA_DE_LISTA = ['.', ')'].freeze

  class << self
    # -> [Numero] de um texto de ferramenta: todos entram como conhecidos; só os `medida` entram nas contas.
    def da_ferramenta(texto)
      new(texto.to_s, separadores: ['.'], grupos: 1, espaco: false).numeros
    end

    # -> [String] dos números-medida de uma frase do rascunho, como foram escritos.
    def da_resposta(frase)
      new(frase.to_s, separadores: SEPARADORES_DA_RESPOSTA, grupos: nil, espaco: true).numeros.select(&:medida).map(&:texto)
    end

    # As frases do rascunho, sem as perguntas: pergunta de volta à pessoa não afirma número nenhum.
    def frases(texto)
      texto.to_s.split("\n").flat_map { |linha| dividir(linha) }.reject do |frase|
        frase.strip.empty? || PERGUNTA.include?(frase.rstrip[-1])
      end
    end

    def dividir(linha)
      frases = []
      atual = +''
      linha.each_char.with_index do |caractere, indice|
        atual << caractere
        next unless FIM_DE_FRASE.include?(caractere) && BRANCOS.include?(linha[indice + 1])

        frases << atual
        atual = +''
      end
      frases << atual
    end
  end

  def initialize(texto, separadores:, grupos:, espaco:)
    @texto = texto
    @separadores = separadores
    @grupos = grupos
    @espaco = espaco
    @posicao = 0
    @fim_do_link = nil
  end

  def numeros
    saida = []
    saida.concat(proximo) while @posicao < @texto.length
    saida
  end

  private

  def caractere(deslocamento = 0) = @texto[@posicao + deslocamento]

  def digito?(valor) = !valor.nil? && valor.between?('0', '9')

  # O `\w` do Ruby: letra ASCII, dígito ou sublinhado.
  def palavra?(valor)
    return false if valor.nil?

    digito?(valor) || valor == '_' || valor.between?('a', 'z') || valor.between?('A', 'Z')
  end

  def proximo
    entrar_no_link
    sair_do_link
    return referencia if caractere == '#' && digito?(caractere(1))
    return numero if digito?(caractere) && comeco_valido?

    @posicao += 1
    []
  end

  # O destino de um link (`](/app/accounts/7/conversations/4321)`): números conhecidos, nunca medida.
  def entrar_no_link
    return unless caractere == ']' && caractere(1) == '('

    @fim_do_link = @texto.index(')', @posicao) || @texto.length
  end

  def sair_do_link
    @fim_do_link = nil if @fim_do_link && @posicao > @fim_do_link
  end

  def dentro_do_link? = !@fim_do_link.nil?

  def referencia
    @posicao += 1
    inicio = @posicao
    pular_digitos
    [Numero.new(texto: @texto[inicio...@posicao], medida: false)]
  end

  # O número não pode começar colado em palavra nem logo depois de um separador (o ".5" de "1.5").
  def comeco_valido?
    anterior = @posicao.zero? ? nil : @texto[@posicao - 1]
    return true if anterior.nil?

    !palavra?(anterior) && anterior != '.' && !(@espaco && SEPARADORES_DA_RESPOSTA.include?(anterior))
  end

  def numero
    inicio = @posicao
    pular_digitos
    return data(inicio) if DATA.include?(caractere) && digito?(caractere(1))

    ler_grupos(inicio)
    texto = @texto[inicio...@posicao]
    return pular_palavra if palavra?(caractere)

    [Numero.new(texto: texto, medida: medida?(inicio, texto))]
  end

  def medida?(inicio, texto)
    !dentro_do_link? && !marca_de_lista?(inicio, texto)
  end

  # "1. " ou "2) " no começo da linha ou da frase.
  def marca_de_lista?(inicio, texto)
    return false unless texto.each_char.all? { |valor| digito?(valor) } && comeco_da_linha?(inicio)

    MARCA_DE_LISTA.include?(caractere) && (caractere(1).nil? || BRANCOS.include?(caractere(1)))
  end

  def comeco_da_linha?(inicio)
    antes = @texto[0...inicio]
    antes[(antes.rindex("\n") || -1) + 1..].each_char.all? { |valor| BRANCOS.include?(valor) }
  end

  # Data ou hora: cada grupo de dígitos entra como conhecido, nenhum como medida.
  def data(inicio)
    @posicao += 1 while digito?(caractere) || RESTO_DA_DATA.include?(caractere)
    @texto[inicio...@posicao].tr('-/:.TZ+', ' ').split.map { |grupo| Numero.new(texto: grupo, medida: false) }
  end

  def ler_grupos(inicio)
    return if @espaco && agrupado_por_espaco?(inicio)

    lidos = 0
    while @separadores.include?(caractere) && digito?(caractere(1)) && (@grupos.nil? || lidos < @grupos)
      @posicao += 1
      pular_digitos
      lidos += 1
    end
  end

  # "1 899" e "1 899,50": até três dígitos e depois grupos de exatamente três separados por espaço.
  def agrupado_por_espaco?(inicio)
    return false if @posicao - inicio > 3

    fim = @posicao
    fim += 4 while ESPACOS.include?(@texto[fim]) && tres_digitos?(fim + 1)
    return false if fim == @posicao

    @posicao = fim
    if [',', '.'].include?(caractere) && digito?(caractere(1))
      @posicao += 1
      pular_digitos
    end
    true
  end

  def tres_digitos?(posicao)
    (0..2).all? { |deslocamento| digito?(@texto[posicao + deslocamento]) } && !digito?(@texto[posicao + 3])
  end

  def pular_digitos
    @posicao += 1 while digito?(caractere)
  end

  # Colado em letra (5x, 14h30): não é número; o resto da palavra vai junto.
  def pular_palavra
    @posicao += 1 while palavra?(caractere)
    []
  end
end
