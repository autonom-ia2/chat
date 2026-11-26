# O PEDIDO DE COTAÇÃO do Seguro Viagem (#3211): confere os dados da viagem que o modelo mandou e monta o corpo do
# `POST /v1/Cotacao` da Universal. Não chama nada e não grava nada.
#
# A Universal cota por data de nascimento; o cliente conta a idade. A data técnica de cada viajante é a saída menos a
# idade e mais seis meses de folga (`data_saida << (idade * 12 + 6)`): a idade na data da viagem fica a que o cliente
# disse, sem cair na borda do aniversário. O nome é "Viajante N": nenhum dado pessoal vai na cotação.
#
# O DESTINO é a sigla do país (ISO, "PT") ou o código da região da Universal ("X6", Europa), quando o cliente deu só a
# região (#3226). Os dois têm dois caracteres: letra e depois letra ou dígito. "X" sozinho e "4X" não passam (nenhum
# código da Universal começa por dígito); se a sigla existe, quem diz é a lista da Universal (`Destinos.validas_em?`).
#
# O BRASIL SAI quando há país de fora (#3226): a Universal não cota o Brasil junto (0 produtos em qualquer
# classificação), e o seguro internacional vale a partir da fronteira (condições gerais, 11.7 b). Viagem só no Brasil
# continua `["BR"]`. O nome do Brasil sai junto, da mesma posição em `nomes_dos_destinos`.
#
# Sem expressão regular: a sigla é conferida caractere a caractere, a data por `Date.iso8601`, a idade por `Integer`.
class Autonomia::Agents::Tools::Native::SeguroViagem::Pedido
  Falta = Data.define(:campo, :texto)

  IDADE_MAX = 120
  TIPO_VIAGEM_UNICA = 1
  TARIFA = { folheto: 1, acordo: 2 }.freeze
  CLASSIFICACAO = { nil => 1, 'lazer' => 4, 'estudo' => 5, 'negocios' => 6, 'gestante' => 7, 'cruzeiro' => 8 }.freeze
  MOTIVOS = %w[lazer estudo negocios gestante cruzeiro].freeze
  MESES_DE_FOLGA = 6
  TAMANHO_DA_SIGLA = 2
  LETRAS = ('A'..'Z')
  DIGITOS = ('0'..'9')
  BRASIL = 'BR'.freeze

  TEXTOS = {
    destinos: 'Informe cada país do roteiro pela sigla de duas letras (ISO 3166), por exemplo ["PT"], ou só a região ' \
              'pelo código da Universal, por exemplo ["X6"] para Europa. Viagem só no Brasil: ["BR"].',
    data_saida: 'A data de ida precisa vir no formato AAAA-MM-DD.',
    saida_passada: 'A data de ida já passou. Confirme a data com o cliente.',
    data_retorno: 'A data de volta precisa vir no formato AAAA-MM-DD.',
    retorno_antes: 'A data de volta é antes da data de ida. Confirme as datas com o cliente.',
    idades: "Informe a idade de cada viajante, um número inteiro de 0 a #{IDADE_MAX} por pessoa.".freeze,
    motivo: "O motivo só pode ser #{MOTIVOS.join(', ')} ou nulo.".freeze
  }.freeze

  def initialize(params, hoje:, tarifa_acordo:)
    @params = params.to_h.stringify_keys
    @hoje = hoje
    @tarifa_acordo = tarifa_acordo
  end

  # -> [pedido_da_universal, nil] ou [nil, Falta]
  def conferir
    falta = falta_nos_destinos || falta_nas_datas || falta_nas_idades || falta_no_motivo
    falta ? [nil, falta] : [montar, nil]
  end

  # As idades como o pedido as leu. Só valem depois de `conferir` sem falta (aí são inteiros de 0 a `IDADE_MAX`).
  # Base 10: "010" é dez, e "0x1A" não é idade.
  def idades
    @idades ||= lista('idades').map { |idade| idade.is_a?(Integer) ? idade : Integer(idade.to_s, 10, exception: false) }
  end

  # Os nomes que o modelo escreveu, sem o do Brasil quando o Brasil saiu (a mesma posição da sigla). Lista de outro
  # tamanho fica como veio: quem nomeia (`CotarSeguroViagem`) já a troca pelo nome da Universal.
  def nomes_dos_destinos
    nomes = @params['nomes_dos_destinos']
    return nomes unless brasil_fora? && nomes.is_a?(Array) && nomes.size == siglas_pedidas.size

    nomes.reject.with_index { |_nome, indice| siglas_pedidas[indice] == BRASIL }
  end

  # O Brasil veio junto de algum país de fora e saiu dos destinos.
  def brasil_fora?
    siglas = siglas_pedidas.uniq
    siglas.include?(BRASIL) && siglas.size > 1
  end

  private

  def montar
    {
      'destinos' => destinos, 'passageiros' => passageiros,
      'dataSaida' => saida.iso8601, 'dataRetorno' => retorno.iso8601,
      'tipoViagem' => TIPO_VIAGEM_UNICA, 'tipoTarifa' => @tarifa_acordo ? TARIFA[:acordo] : TARIFA[:folheto],
      'produtoAvulso' => false, 'cupom' => '', 'classificacoes' => [CLASSIFICACAO.fetch(motivo)]
    }
  end

  def passageiros
    idades.each_with_index.map do |idade, indice|
      { 'nome' => "Viajante #{indice + 1}", 'dataNascimento' => (saida << ((idade * 12) + MESES_DE_FOLGA)).iso8601 }
    end
  end

  def falta_nos_destinos
    return nil if destinos.present? && destinos.all? { |sigla| sigla?(sigla) }

    Falta.new('destinos', TEXTOS[:destinos])
  end

  def falta_nas_datas
    return Falta.new('data_saida', TEXTOS[:data_saida]) if saida.nil?
    return Falta.new('data_saida', TEXTOS[:saida_passada]) if saida < @hoje
    return Falta.new('data_retorno', TEXTOS[:data_retorno]) if retorno.nil?
    return Falta.new('data_retorno', TEXTOS[:retorno_antes]) if retorno < saida

    nil
  end

  def falta_nas_idades
    return nil if idades.present? && idades.all? { |idade| idade&.between?(0, IDADE_MAX) }

    Falta.new('idades', TEXTOS[:idades])
  end

  def falta_no_motivo
    return nil if motivo.nil? || MOTIVOS.include?(motivo)

    Falta.new('motivo', TEXTOS[:motivo])
  end

  def destinos
    @destinos ||= brasil_fora? ? siglas_pedidas.uniq - [BRASIL] : siglas_pedidas.uniq
  end

  def siglas_pedidas
    @siglas_pedidas ||= lista('destinos').map { |sigla| sigla.to_s.strip.upcase }
  end

  def sigla?(sigla)
    return false unless sigla.length == TAMANHO_DA_SIGLA

    primeiro, segundo = sigla.chars
    LETRAS.cover?(primeiro) && (LETRAS.cover?(segundo) || DIGITOS.cover?(segundo))
  end

  def saida
    return @saida if defined?(@saida)

    @saida = data(@params['data_saida'])
  end

  def retorno
    return @retorno if defined?(@retorno)

    @retorno = data(@params['data_retorno'])
  end

  def data(texto)
    texto.is_a?(String) ? Date.iso8601(texto.strip) : nil
  rescue Date::Error
    nil
  end

  def motivo
    @params['motivo'].presence
  end

  def lista(chave)
    valor = @params[chave]
    valor.is_a?(Array) ? valor : []
  end
end
