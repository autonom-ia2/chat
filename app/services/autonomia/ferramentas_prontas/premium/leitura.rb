# O QUE A BIGDATACORP RESPONDEU a uma consulta Premium (#2858, F7), já classificado para a cobrança:
#   - `encontrado`: veio o dado; conta (grátis ou cobrada);
#   - `sem_registro`: a BigDataCorp respondeu e não havia registro; conta, e o agente diz "não havia registro";
#   - `falha`: não conta para o cliente. Inclui a fonte lenta (`DATASET IS TOO SLOW`, código -1201), o 504 e toda falha
#     de rede, token ou status da BigDataCorp.
# O `Status` vem por dataset (`{"kyc": [{"Code": 0, "Message": "OK"}]}`): os códigos são os da documentação pública
# ("Códigos e descrições de status"). A comparação é com o código e a mensagem fixa da BigDataCorp, nunca com texto de
# pessoa.
class Autonomia::FerramentasProntas::Premium::Leitura
  LENTA = -1201
  MENSAGEM_DA_LENTA = 'DATASET IS TOO SLOW'.freeze
  # -204 "no results found", -1209 "could not find a name for this document", -2008 "not enough data to generate output".
  SEM_REGISTRO = [-204, -1209, -2008].freeze
  OK = [0, 1].freeze

  attr_reader :situacao, :dados, :motivo, :id_na_fonte

  def initialize(situacao:, dados: nil, motivo: nil, id_na_fonte: nil)
    @situacao = situacao
    @dados = dados
    @motivo = motivo
    @id_na_fonte = id_na_fonte
  end

  def self.falha(motivo, id_na_fonte: nil)
    new(situacao: 'falha', motivo: motivo, id_na_fonte: id_na_fonte)
  end

  def self.de(dataset, payload, id_na_fonte: nil)
    pelo_status = pelo_status(status_do(dataset, payload), id_na_fonte)
    return pelo_status if pelo_status

    dados = extrair(dataset, payload)
    return falha('resposta_invalida', id_na_fonte: id_na_fonte) if dados == :invalida

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
    return :invalida unless bruto.is_a?(Hash) || bruto.is_a?(Array)

    dataset.extrair.call(bruto)
  rescue NoMethodError, TypeError, ArgumentError
    # A BigDataCorp mudou o formato: não conta para o cliente, e o motivo fica no contador.
    :invalida
  end
end
