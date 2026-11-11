# O QUE A BIGDATACORP RESPONDEU a uma consulta Premium (#2858, F7), já classificado para a cobrança:
#   - `encontrado`: veio o dado; conta (grátis ou cobrada);
#   - `sem_registro`: a BigDataCorp respondeu e não havia registro; conta, e o agente diz "não havia registro";
#   - `documento_invalido`: a BigDataCorp recebeu o pedido e recusou o documento (-114 "INVALID DOC PARAMETER", -155
#     "INVALID CAR NUMBER PARAMETER"); conta e é cobrado como o sem registro (decisão do Rodrigo), e o agente confere o
#     documento com o cliente. O documento com dígito errado que NÓS recusamos antes (`Premium::Parametros`) nem chega
#     aqui: não chama a BigDataCorp e não conta ("A, não conta", Rodrigo, 11/11);
#   - `falha`: não conta para o cliente. Inclui a fonte lenta (`DATASET IS TOO SLOW`, código -1201), o 504 e toda falha
#     de rede, token ou status da BigDataCorp. `custo_possivel?`: o pedido já tinha saído e a BigDataCorp pode ter
#     cobrado (a resposta 200 que não lemos, o tempo esgotado com o pedido no ar, a entrega incerta). A telemetria grava
#     o custo do dataset sem contar para o cliente, para bater com o painel da BigDataCorp (aceite 11). A fonte lenta e
#     o 504 continuam sem custo.
# O `Status` vem por dataset (`{"kyc": [{"Code": 0, "Message": "OK"}]}`): os códigos são os da documentação pública
# ("Códigos e descrições de status"). A comparação é com o código e a mensagem fixa da BigDataCorp, nunca com texto de
# pessoa.
class Autonomia::FerramentasProntas::Premium::Leitura
  LENTA = -1201
  MENSAGEM_DA_LENTA = 'DATASET IS TOO SLOW'.freeze
  # -204 "no results found", -1209 "could not find a name for this document", -2008 "not enough data to generate output".
  SEM_REGISTRO = [-204, -1209, -2008].freeze
  # "Códigos e descrições de status", grupo "Dados de entrada": -114 "INVALID DOC PARAMETER" (CPF, CNPJ) e -155 "INVALID
  # CAR NUMBER PARAMETER" (o código do imóvel no CAR, o documento do card de imóvel rural).
  DOCUMENTO_INVALIDO = [-114, -155].freeze
  OK = [0, 1].freeze

  attr_reader :situacao, :dados, :motivo, :id_na_fonte

  def initialize(situacao:, dados: nil, motivo: nil, id_na_fonte: nil, custo_possivel: false)
    @situacao = situacao
    @dados = dados
    @motivo = motivo
    @id_na_fonte = id_na_fonte
    @custo_possivel = custo_possivel
  end

  def custo_possivel?
    @custo_possivel
  end

  def self.falha(motivo, id_na_fonte: nil, custo_possivel: false)
    new(situacao: 'falha', motivo: motivo, id_na_fonte: id_na_fonte, custo_possivel: custo_possivel)
  end

  def self.de(dataset, payload, id_na_fonte: nil)
    pelo_status = pelo_status(status_do(dataset, payload), id_na_fonte)
    return pelo_status if pelo_status

    dados = extrair(dataset, payload)
    return falha('resposta_invalida', id_na_fonte: id_na_fonte, custo_possivel: true) if dados == :invalida

    dados.blank? ? new(situacao: 'sem_registro', id_na_fonte: id_na_fonte) : new(situacao: 'encontrado', dados: dados, id_na_fonte: id_na_fonte)
  end

  def self.status_do(dataset, payload)
    status = Array(payload.dig('Status', dataset.nome)).first
    status.is_a?(Hash) ? status : {}
  end

  # O desfecho que o `Status` já decide (lenta, sem registro, outro erro); nil quando o dado precisa ser lido.
  def self.pelo_status(status, id_na_fonte)
    return falha('fonte_lenta', id_na_fonte: id_na_fonte) if lenta?(status)
    return new(situacao: 'sem_registro', id_na_fonte: id_na_fonte) if SEM_REGISTRO.include?(status['Code'])
    return new(situacao: 'documento_invalido', id_na_fonte: id_na_fonte) if DOCUMENTO_INVALIDO.include?(status['Code'])
    return if status.empty? || OK.include?(status['Code'])

    falha("status_#{status['Code'].to_i.abs}", id_na_fonte: id_na_fonte)
  end

  def self.lenta?(status)
    status['Code'] == LENTA || status['Message'].to_s.upcase.start_with?(MENSAGEM_DA_LENTA)
  end

  def self.extrair(dataset, payload)
    resultado = Array(payload['Result']).first
    return nil unless resultado.is_a?(Hash)

    bruto = resultado[dataset.resposta]
    return nil if bruto.blank?
    raise TypeError, 'dado do dataset não é objeto nem lista' unless bruto.is_a?(Hash) || bruto.is_a?(Array)

    dataset.extrair.call(bruto)
  rescue NoMethodError, TypeError, ArgumentError => e
    # A BigDataCorp mudou o formato: não conta para o cliente, e o motivo fica no contador.
    avisar_formato(dataset, e)
    :invalida
  end

  # Ao rastreador e ao log: a classe do erro e o dataset. Nunca o valor consultado nem o dado de lá (a mensagem do erro
  # original pode citar o dado; ao rastreador vai um erro novo, só com a classe e o dataset).
  def self.avisar_formato(dataset, erro)
    Rails.logger.warn("[autonomia][premium] resposta_invalida dataset=#{dataset.nome} erro=#{erro.class}")
    ChatwootExceptionTracker.new(TypeError.new("premium resposta_invalida dataset=#{dataset.nome} erro=#{erro.class}")).capture_exception
  end
end
