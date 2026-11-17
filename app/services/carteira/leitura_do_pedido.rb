# O que a tela manda para corrigir um seguro (E4, #2897), lido para as colunas da apólice: só os campos que vieram. Cada
# campo que não dá para gravar vira a recusa dele (CustomExceptions::CarteiraRecusa), que nunca repete o que foi mandado.
# A data vem como AAAA-MM-DD e o valor em reais, lido com BigDecimal: 0,1 + 0,2 em ponto flutuante não fecha os centavos.
# Seguradora e número levam junto a forma de comparação (Carteira::Chave), que é o que o índice único confere.
#
# Os dados do segurado da cotação (E8.1, #3043), cada um apagado quando vem em branco: o nascimento como AAAA-MM-DD (uma
# data que existe, de 1900 até hoje), o sexo F ou M, o CEP com 8 dígitos (o traço, o ponto e o espaço da máscara saem), a
# placa com 7 letras ou dígitos, as 3 primeiras letras (sai em maiúsculas, sem traço nem espaço), e a classe de bônus de
# 0 a 10. Tudo sem expressão regular: a forma é conferida tirando o que pode estar e vendo se sobrou algo.
class Carteira::LeituraDoPedido
  FORMATO_DA_DATA = '%Y-%m-%d'.freeze
  # Os anos em que uma vigência cabe. Fora disso é erro de digitação, e ano grande demais nem cabe na coluna de data.
  ANOS = (1900..2200)
  # O maior valor que a coluna (bigint) guarda.
  CENTAVOS_MAXIMOS = (2**63) - 1
  PRIMEIRO_ANO_DE_NASCIMENTO = 1900
  # O que a máscara do CEP e da placa põe entre os caracteres.
  DA_MASCARA = '-. '.freeze

  def initialize(dados)
    @dados = dados.to_h.stringify_keys
  end

  # Na ordem dos campos da tela. O nome do leitor sai da lista de campos (Carteira::Campos), nunca do que foi mandado.
  def atributos
    (Carteira::Campos::COLUNAS.keys & @dados.keys).reduce({}) { |lidos, campo| lidos.merge(send(campo, @dados[campo])) }
  end

  private

  def tipo(bruto)
    recusar('tipo_desconhecido') unless Carteira::Apolice::TIPOS.include?(bruto)
    { tipo: bruto }
  end

  def seguradora(bruto)
    texto = bruto.to_s.strip
    chave = Carteira::Chave.seguradora(texto)
    recusar('falta_seguradora') if chave.empty?
    { seguradora: texto, seguradora_chave: chave }
  end

  def numero(bruto)
    texto = bruto.to_s.strip
    chave = Carteira::Chave.numero(texto)
    recusar('falta_numero') if chave.empty?
    { numero: texto, numero_chave: chave }
  end

  def comeca(bruto)
    { inicio_vigencia: data(bruto) }
  end

  def termina(bruto)
    recusar('falta_termina') if bruto.blank?
    { fim_vigencia: data(bruto) }
  end

  def valor(bruto)
    { valor_centavos: centavos(bruto) }
  end

  def bem(bruto)
    { bem: bruto.to_s.strip.presence }
  end

  # Guardado como texto AAAA-MM-DD: a coluna é cifrada.
  def nascimento(bruto)
    return { segurado_nascimento: nil } if bruto.blank?

    lida = Date.strptime(bruto.to_s, FORMATO_DA_DATA)
    valida = lida.iso8601 == bruto.to_s && lida.year >= PRIMEIRO_ANO_DE_NASCIMENTO && lida <= Date.current
    recusar('nascimento_invalido') unless valida
    { segurado_nascimento: lida.iso8601 }
  rescue Date::Error
    recusar('nascimento_invalido')
  end

  def sexo(bruto)
    return { segurado_sexo: nil } if bruto.blank?

    recusar('sexo_invalido') unless Carteira::DadosDoSegurado::SEXOS.include?(bruto)
    { segurado_sexo: bruto }
  end

  def cep(bruto)
    texto = bruto.to_s.delete(DA_MASCARA)
    return { cep: nil } if texto.empty?

    recusar('cep_invalido') unless Carteira::DadosDoSegurado.cep?(texto)
    { cep: texto }
  end

  def placa(bruto)
    texto = bruto.to_s.upcase.delete(DA_MASCARA)
    return { placa: nil } if texto.empty?

    recusar('placa_invalida') unless Carteira::DadosDoSegurado.placa?(texto)
    { placa: texto }
  end

  def bonus(bruto)
    return { bonus_classe: nil } if bruto.nil? || bruto == ''

    classe = bruto.is_a?(Integer) ? bruto : Integer(bruto.to_s, 10, exception: false)
    recusar('bonus_invalido') unless classe && Carteira::DadosDoSegurado::BONUS.cover?(classe)
    { bonus_classe: classe }
  end

  # Só AAAA-MM-DD: a data lida, escrita de volta, tem de dar o mesmo texto ("2026-2-30" e "26-11-12" não dão).
  def data(bruto)
    return if bruto.blank?

    lida = Date.strptime(bruto.to_s, FORMATO_DA_DATA)
    recusar('data_invalida') unless lida.iso8601 == bruto.to_s && ANOS.cover?(lida.year)
    lida
  rescue Date::Error
    recusar('data_invalida')
  end

  def centavos(bruto)
    return if bruto.nil? || bruto == ''

    centavos = em_centavos(BigDecimal(bruto.to_s, exception: false))
    recusar('valor_invalido') unless centavos&.frac&.zero? && centavos.between?(0, CENTAVOS_MAXIMOS)
    centavos.to_i
  end

  # Nulo para o que não é número (texto, NaN, infinito).
  def em_centavos(reais)
    reais * Carteira::Campos::CENTAVOS_POR_REAL if reais&.finite?
  end

  def recusar(codigo)
    raise CustomExceptions::CarteiraRecusa, codigo
  end
end
