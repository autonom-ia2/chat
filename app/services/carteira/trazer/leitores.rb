# Como a célula de uma planilha vira data e valor de um seguro (E4, #2897). Só método de texto, sem regex, e com as
# mesmas convenções de quem já lê planilha aqui (ContactImports::AttributeValue): quem escreve é brasileiro.
#
# Data: "2027-03-10", "10/03/2027", "10-03-2027", "10.03.2027", "10/03/27" (ano de dois dígitos é deste século) e o
# número de dia do Excel, quando a célula de data chega sem formato. A hora que vier junto é ignorada. O ano tem de
# caber numa vigência (Carteira::LeituraDoPedido::ANOS).
#
# Valor: "R$ 3.410,00", "3410", "3410.5", "3.410" (ponto com três casas é milhar) e o número cru do XLSX. Lido com
# BigDecimal e arredondado ao centavo: o XLSX guarda 1234,56 como 1234.5600000000001.
#
# Célula vazia devolve nil. O que não dá para ler devolve INVALIDO: quem chama decide o que fazer, e nunca repete o texto.
module Carteira::Trazer::Leitores
  INVALIDO = :invalido
  ANOS = Carteira::LeituraDoPedido::ANOS
  SEPARADORES_DE_DATA = %w[/ - .].freeze
  PARTES_DA_DATA = 3
  ANO_INTEIRO = 4
  SECULO = 2000
  ANO_CURTO = 100
  EPOCA_DO_EXCEL = Date.new(1899, 12, 30)
  # De 1982 a 2201: número menor que isso numa coluna de data é outra coisa (um ano solto, um código).
  DIAS_DO_EXCEL = (30_000..110_000)
  MOEDA = 'R$'.freeze
  ESPACOS = "  \t".freeze
  MILHAR = 3
  SEM_INTEIRO = '0'.freeze

  module_function

  def data(texto)
    texto = texto.to_s.strip
    return if texto.empty?

    lida = dia_do_excel(texto) || do_calendario(texto.split.first)
    lida && ANOS.cover?(lida.year) ? lida : INVALIDO
  end

  def centavos(texto)
    limpo = texto.to_s.delete(ESPACOS).delete_prefix(MOEDA)
    return if limpo.empty?

    reais = BigDecimal(com_ponto_decimal(limpo), exception: false)
    return INVALIDO unless reais&.finite? && !reais.negative?

    centavos = (reais * Carteira::Campos::CENTAVOS_POR_REAL).round
    centavos <= Carteira::LeituraDoPedido::CENTAVOS_MAXIMOS ? centavos : INVALIDO
  end

  def dia_do_excel(texto)
    dias = Integer(texto, 10, exception: false)
    EPOCA_DO_EXCEL + dias if dias && DIAS_DO_EXCEL.cover?(dias)
  end

  def do_calendario(texto)
    ano, mes, dia = ano_mes_dia(texto)
    Date.new(ano, mes, dia) if ano && Date.valid_date?(ano, mes, dia)
  end

  # [ano, mês, dia], ou nil quando o texto não são três números separados. O ano vem na frente quando tem quatro dígitos
  # ("2027-03-10"); senão é dia, mês e ano.
  def ano_mes_dia(texto)
    escritas = partes_da_data(texto)
    numeros = escritas.filter_map { |parte| Integer(parte, 10, exception: false) }
    return unless [escritas.size, numeros.size] == [PARTES_DA_DATA, PARTES_DA_DATA] && numeros.none?(&:negative?)

    ano, mes, dia = escritas.first.length == ANO_INTEIRO ? numeros : numeros.reverse
    [ano < ANO_CURTO ? ano + SECULO : ano, mes, dia]
  end

  def partes_da_data(texto)
    separador = SEPARADORES_DE_DATA.find { |sinal| texto.include?(sinal) }
    separador ? texto.split(separador, -1) : []
  end

  # "1.234,56" vira "1234.56". Sem vírgula, o ponto é decimal ("3410.5"), menos quando separa grupos de três ("3.410").
  def com_ponto_decimal(texto)
    return texto.delete('.').tr(',', '.') if texto.include?(',')

    milhares?(texto) ? texto.delete('.') : texto
  end

  def milhares?(texto)
    inteiro, *grupos = texto.split('.', -1)
    grupos.any? && inteiro != SEM_INTEIRO && inteiro.length.between?(1, MILHAR) && grupos.all? { |grupo| grupo.length == MILHAR }
  end
end
