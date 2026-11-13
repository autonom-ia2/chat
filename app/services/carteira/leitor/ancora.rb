# "O que o modelo devolveu está escrito nas páginas?" (E6, #2899). O leitor nunca confia num valor só porque o modelo o
# devolveu: cada campo precisa estar escrito, inteiro, numa das páginas que foram enviadas, senão vira "não achei". É
# comparação de valor, não interpretação de texto: quem entende a apólice é o modelo; aqui só se confere que ele não
# inventou.
#
# Sempre pedaço inteiro contra pedaço inteiro (Carteira::Leitor::Tokens), nunca um valor "dentro" de outro, e sempre
# na MESMA página:
# - texto (seguradora, ramo, bem, nome): as palavras do valor aparecem inteiras e seguidas, na ordem, sem contar
#   caixa, acento e pontuação. "Ana" não está em "Banana", e uma frase montada com pedaços de lugares diferentes não
#   passa;
# - número da apólice: o bloco inteiro, como está escrito, com a pontuação de dentro. "001234" não está em
#   "EX-001234", e "1234" não está em "12/34". O número que a quebra de linha partiu em dois ("EX-2026." no fim de uma
#   linha e "001234" no começo da seguinte) confere emendado, como o e-mail;
# - CPF e CNPJ: os 11 ou 14 dígitos são um bloco inteiro de número;
# - data: escrita com separador, como um bloco inteiro: 12/11/2026, 12-11-2026, 12.11.2026, 2026-11-12 ou 12/11/26.
#   O ano com dois dígitos só confere para este século: "12/11/27" é 2027, nunca 1927 nem 2127. Dígitos colados nunca
#   são data (o CEP "12112-027" não é 12/11/2027). Data escrita por extenso não se confirma e vira "não achei";
# - valor: é um dos valores em dinheiro escritos na página, por inteiro (R$ 2.254,98 é 225498; 2254 não é). Valor
#   escrito sem os centavos não se confirma, e o que está encostado em "%" é porcentagem. `centavos` diz que o valor
#   está escrito; `com_cifrao?` diz que ele vem logo depois de "R$". Sem o "R$" o bloco pode ser outra medida
#   ("1.250,50 kg"), e quem chama trata o valor como "a confirmar" (Carteira::Leitor::Resultado).
#
# O que a âncora NÃO faz: dizer qual dos valores escritos é o certo. A parcela e o IOF também são valores em dinheiro
# escritos na página, com "R$"; se o modelo trocar o prêmio total por um deles, a âncora deixa passar. Quem mede isso
# é a bateria com gabarito (lib/tasks/carteira_leitor.rake).
class Carteira::Leitor::Ancora
  include Carteira::Leitor::Reservado

  TAMANHOS_DE_DOCUMENTO = [11, 14].freeze
  MAXIMO_DO_TEXTO = 200
  FORMAS_DA_DATA = %w[%d/%m/%Y %d-%m-%Y %d.%m.%Y %Y-%m-%d].freeze
  # O ano escrito com dois dígitos joga o século fora: só confere quando o ano devolvido é 2000 + aa.
  ANO_CURTO = '%d/%m/%y'.freeze
  SECULO_DO_ANO_CURTO = (2000..2099)
  TOKENS = Carteira::Leitor::Tokens

  # paginas: as que foram ao modelo (Carteira::Leitor::Paginas::Pagina).
  def initialize(paginas)
    @paginas = paginas.map(&:tokens)
  end

  # O texto como veio, sem espaço sobrando; nil quando ele não está escrito assim em nenhuma página.
  def escrito(valor)
    return unless valor.is_a?(String)

    texto = valor.squish
    return if texto.length > MAXIMO_DO_TEXTO

    palavras = TOKENS.new(texto).palavras
    texto if @paginas.any? { |pagina| TOKENS.sequencia?(pagina.palavras, palavras) }
  end

  def codigo(valor)
    return unless valor.is_a?(String)

    do_valor = TOKENS.new(valor)
    valor.squish if do_valor.palavras.any? && @paginas.any? { |pagina| codigo_escrito?(pagina, do_valor.blocos) }
  end

  # Só os dígitos do CPF ou do CNPJ.
  def documento(valor)
    digitos = TOKENS.digitos(valor)
    digitos if TAMANHOS_DE_DOCUMENTO.include?(digitos.length) && @paginas.any? { |pagina| pagina.numeros.include?(digitos) }
  end

  # A data como AAAA-MM-DD.
  def data(valor)
    return unless valor.is_a?(String)

    data = Date.iso8601(valor)
    formas = escritas(data)
    data.iso8601 if @paginas.any? { |pagina| pagina.blocos.intersect?(formas) }
  rescue Date::Error
    nil
  end

  def centavos(valor)
    valor if valor.is_a?(Integer) && valor.positive? && @paginas.any? { |pagina| pagina.centavos.include?(valor) }
  end

  # O valor está escrito logo depois de "R$" em alguma página?
  def com_cifrao?(valor)
    @paginas.any? { |pagina| pagina.centavos_com_cifrao.include?(valor) }
  end

  private

  # Os blocos do número, seguidos e na ordem; ou, quando o número é um bloco só, esse bloco partido por uma quebra de
  # linha.
  def codigo_escrito?(pagina, blocos)
    TOKENS.sequencia?(pagina.blocos, blocos) || (blocos.one? && pagina.blocos_emendados.include?(blocos.first))
  end

  # As formas em que a data pode estar escrita na página.
  def escritas(data)
    formas = SECULO_DO_ANO_CURTO.cover?(data.year) ? FORMAS_DA_DATA + [ANO_CURTO] : FORMAS_DA_DATA
    formas.map { |forma| data.strftime(forma) }
  end
end
