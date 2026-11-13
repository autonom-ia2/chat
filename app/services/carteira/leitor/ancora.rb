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
# - número da apólice: o bloco inteiro, sem contar a pontuação de dentro. "001234" não está em "EX-001234";
# - CPF e CNPJ: os 11 ou 14 dígitos são um bloco inteiro de número;
# - data: o dia, o mês e o ano são um bloco inteiro (12/11/2026, 2026-11-12 ou 12/11/26). Data escrita por extenso não
#   se confirma e vira "não achei";
# - valor: é um dos valores em dinheiro escritos na página, por inteiro (R$ 2.254,98 é 225498; 2254 não é). Valor
#   escrito sem os centavos não se confirma.
#
# O que a âncora NÃO faz: dizer qual dos valores escritos é o certo. A parcela e o IOF também são valores em dinheiro
# escritos na página; se o modelo trocar o prêmio total por um deles, a âncora deixa passar. Quem mede isso é a
# bateria com gabarito (lib/tasks/carteira_leitor.rake).
class Carteira::Leitor::Ancora
  TAMANHOS_DE_DOCUMENTO = [11, 14].freeze
  MAXIMO_DO_TEXTO = 200
  FORMAS_DA_DATA = %w[%d%m%Y %Y%m%d %d%m%y].freeze
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

    codigos = TOKENS.new(valor).codigos
    valor.squish if @paginas.any? { |pagina| TOKENS.sequencia?(pagina.codigos, codigos) }
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
    formas = FORMAS_DA_DATA.map { |forma| data.strftime(forma) }
    data.iso8601 if @paginas.any? { |pagina| pagina.numeros.intersect?(formas) }
  rescue Date::Error
    nil
  end

  def centavos(valor)
    valor if valor.is_a?(Integer) && valor.positive? && @paginas.any? { |pagina| pagina.centavos.include?(valor) }
  end
end
