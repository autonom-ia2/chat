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
#   linha e "001234" no começo da seguinte) confere emendado, mas só quando a quebra caiu num ponto, traço ou barra:
#   "12345" numa linha e "6789" na seguinte não são o número "123456789";
# - CPF e CNPJ: os 11 ou 14 dígitos são um bloco inteiro de número;
# - data: escrita com separador, como um bloco inteiro: 12/11/2026, 12-11-2026, 12.11.2026, 2026-11-12 ou 12/11/26.
#   O ano com dois dígitos só confere para este século: "12/11/27" é 2027, nunca 1927 nem 2127. Dígitos colados nunca
#   são data (o CEP "12112-027" não é 12/11/2027). Data escrita por extenso não se confirma e vira "não achei";
# - valor: é um dos valores em dinheiro escritos na página, por inteiro (R$ 2.254,98 é 225498; 2254 não é). Valor
#   escrito sem os centavos não se confirma, e o que está encostado em "%" é porcentagem. `centavos` diz que o valor
#   está escrito; `com_cifrao?` diz que ele vem logo depois de "R$". Sem o "R$" o bloco pode ser outra medida
#   ("1.250,50 kg"), e quem chama trata o valor como "a confirmar" (Carteira::Leitor::Resultado).
#
# Os dados do segurado da cotação (E8.1, #3043):
# - data de nascimento (`data_de_nascimento`): como a data, mas o ano com dois dígitos é do século passado quando passa
#   do ano de hoje ("15/03/85" é 1985; "15/03/05" é 2005), e a data do futuro não é nascimento;
# - CEP: os 8 dígitos são um bloco inteiro de número ("12345-678"), como o CPF; sai só com os dígitos;
# - placa: o bloco inteiro, como o número da apólice; sai em maiúsculas, sem traço nem espaço, e só quando tem a forma
#   de placa (7 letras ou dígitos, as 3 primeiras letras: um número de 7 dígitos não é placa);
# - sexo: quem decide F ou M é o modelo, mas a palavra em que ele se baseou ("Masculino") tem de estar escrita;
# - classe de bônus: o trecho em que ela está escrita ("Classe de bônus: 5") tem de estar escrito, e o número tem de ser
#   uma das palavras desse trecho. A âncora não sabe se o número é a classe ou um percentual ao lado: a bateria mede.
#
# O que a âncora NÃO faz: dizer qual dos valores escritos é o certo. A parcela e o IOF também são valores em dinheiro
# escritos na página, com "R$"; se o modelo trocar o prêmio total por um deles, a âncora deixa passar. Quem mede isso
# é a bateria com gabarito (lib/tasks/carteira_leitor.rake).
class Carteira::Leitor::Ancora
  include Carteira::Leitor::Reservado

  TAMANHOS_DE_DOCUMENTO = [11, 14].freeze
  DIGITOS_DO_CEP = 8
  ANOS_POR_SECULO = 100
  SEXOS = %w[F M].freeze
  BONUS = (0..10)
  # Na placa, o que a apólice escreve entre as letras e os números e o portal não lê.
  FORA_DA_PLACA = '- '.freeze
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

  # A data de nascimento como AAAA-MM-DD.
  def data_de_nascimento(valor)
    return unless valor.is_a?(String)

    data = Date.iso8601(valor)
    return if data > Date.current

    formas = formas_do_nascimento(data)
    data.iso8601 if @paginas.any? { |pagina| pagina.blocos.intersect?(formas) }
  rescue Date::Error
    nil
  end

  # Só os dígitos do CEP.
  def cep(valor)
    digitos = TOKENS.digitos(valor)
    digitos if digitos.length == DIGITOS_DO_CEP && @paginas.any? { |pagina| pagina.numeros.include?(digitos) }
  end

  # A placa na forma do portal.
  def placa(valor)
    escrita = codigo(valor)
    forma = escrita&.upcase&.delete(FORA_DA_PLACA)
    forma if Carteira::DadosDoSegurado.placa?(forma)
  end

  # F ou M, só quando a palavra de onde o modelo tirou o sexo está escrita.
  def sexo(valor, palavra)
    valor if SEXOS.include?(valor) && escrito(palavra)
  end

  # A classe de bônus, só quando o trecho dela está escrito e o número é uma das palavras do trecho.
  def bonus(classe, trecho)
    return unless classe.is_a?(Integer) && BONUS.cover?(classe)

    texto = escrito(trecho)
    classe if texto && TOKENS.new(texto).palavras.include?(classe.to_s)
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
  # linha que caiu num separador (Carteira::Leitor::Tokens#blocos_emendados_no_separador).
  def codigo_escrito?(pagina, blocos)
    TOKENS.sequencia?(pagina.blocos, blocos) || (blocos.one? && pagina.blocos_emendados_no_separador.include?(blocos.first))
  end

  # As formas em que o nascimento pode estar escrito na página: as da data e, quando o ano curto aponta para ele, aa.
  def formas_do_nascimento(data)
    formas = FORMAS_DA_DATA.map { |forma| data.strftime(forma) }
    ano_curto_de_nascimento?(data.year) ? formas + [data.strftime(ANO_CURTO)] : formas
  end

  # O ano com dois dígitos, no nascimento: do século passado quando passa do ano de hoje, deste quando não passa.
  def ano_curto_de_nascimento?(ano)
    hoje = Date.current.year
    curto = ano % ANOS_POR_SECULO
    seculo = curto > hoje % ANOS_POR_SECULO ? hoje - (hoje % ANOS_POR_SECULO) - ANOS_POR_SECULO : hoje - (hoje % ANOS_POR_SECULO)
    ano == seculo + curto
  end

  # As formas em que a data pode estar escrita na página.
  def escritas(data)
    formas = SECULO_DO_ANO_CURTO.cover?(data.year) ? FORMAS_DA_DATA + [ANO_CURTO] : FORMAS_DA_DATA
    formas.map { |forma| data.strftime(forma) }
  end
end
