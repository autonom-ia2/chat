# Consulta basic_data da BigDataCorp por nome e telefone e lê os candidatos (porte de bigdatacorp-discovery.ts do Orth,
# #679). No máximo três candidatos. Envelope fora do formato oficial é erro; doc_finder sem documento é zero candidato.
#
# O nome entra sanitizado: `{`, `}` e `,` delimitam a sintaxe do q e viram espaço (vírgula é comum em nome fantasia).
# O telefone entra em E.164 pelo contrato de telefone da prospecção; telefone que não valida recusa a consulta.
class Autonomia::Prospecting::Research::BigDataCorpDiscovery
  LIMIT = 3
  DATASET = 'basic_data'.freeze
  MAX_NAME_LENGTH = 200
  MAX_PHONE_LENGTH = 64
  MAX_ID_LENGTH = 160
  QUERY_DELIMITERS = '{},'.freeze
  CONTROL_CHARACTERS = [(0..31), (127..159)].freeze

  Candidate = Struct.new(:cnpj, :name, :trade_name, :status, :is_headquarter, :headquarter_state, :match_keys,
                         :official_name_percentage, :trade_name_percentage, :provider_index, keyword_init: true)
  Result = Struct.new(:candidates, :provider_request_id, keyword_init: true)

  class Error < StandardError
    attr_reader :code, :provider_request_id

    def initialize(code, provider_request_id: nil)
      @code = code
      @provider_request_id = provider_request_id
      super(code)
    end
  end

  def initialize(client:)
    @client = client
  end

  # Levanta Error (entrada ou resposta) ou deixa passar o BigDataCorpClient::Error do transporte.
  def discover(name:, phone: nil, region: Autonomia::Prospecting::PhoneContract::DEFAULT_REGION)
    query = self.class.query(name: name, phone: phone, region: region)
    payload = @client.search_companies(query: query, limit: LIMIT, datasets: DATASET).payload
    Result.new(candidates: self.class.parse_candidates(payload), provider_request_id: self.class.query_id(payload))
  end

  def self.query(name:, phone:, region:)
    safe_name = sanitized_name(name)
    safe_phone = phone.nil? ? nil : e164(phone, region)
    raise Error, 'BIGDATACORP_INVALID_DISCOVERY_INPUT' if safe_name.nil? || (!phone.nil? && safe_phone.nil?)

    safe_phone ? "name{#{safe_name}},phone{#{safe_phone}}" : "name{#{safe_name}}"
  end

  def self.sanitized_name(value)
    sanitized = value.to_s.tr(QUERY_DELIMITERS, ' ').squish
    return if sanitized.empty? || sanitized.length > MAX_NAME_LENGTH || control_character?(sanitized)

    sanitized
  end

  def self.e164(value, region)
    raw = value.to_s.strip
    return if raw.empty? || raw.length > MAX_PHONE_LENGTH || control_character?(raw)

    Autonomia::Prospecting::PhoneContract.e164(raw, region: region)
  end

  def self.control_character?(value)
    value.each_char.any? { |char| CONTROL_CHARACTERS.any? { |range| range.cover?(char.ord) } }
  end

  def self.parse_candidates(payload)
    request_id = query_id(payload)
    rows = official_rows(payload, request_id)
    rows.first(LIMIT).each_with_index.map { |row, index| candidate(row, index, request_id) }
  end

  def self.query_id(payload)
    value = payload.is_a?(Hash) ? payload['QueryId'] : nil
    return unless value.is_a?(String)

    stripped = value.strip
    stripped.present? && stripped.length <= MAX_ID_LENGTH ? stripped : nil
  end

  def self.official_rows(payload, request_id)
    raise Error, 'BIGDATACORP_INVALID_PROVIDER_RESPONSE' unless payload.is_a?(Hash) && request_id

    status = payload['Status'].is_a?(Hash) ? payload['Status'] : {}
    basic = status['basic_data']
    return empty_doc_finder(status, payload, request_id) unless basic.is_a?(Array) && basic.any?

    basic.each { |entry| check_status_entry(entry, request_id) }
    result_rows(payload, request_id)
  end

  def self.result_rows(payload, request_id)
    return payload['Result'] if payload['Result'].is_a?(Array)

    raise Error.new('BIGDATACORP_INVALID_PROVIDER_RESPONSE', provider_request_id: request_id)
  end

  # Quando o doc finder não acha documento nenhum, o fornecedor nem roda o dataset: Status só com doc_finder e
  # Result vazio. É "não achou" (resposta legítima), não defeito de contrato.
  def self.empty_doc_finder(status, payload, request_id)
    return [] if status['doc_finder'].is_a?(Array) && payload['Result'] == []

    raise Error.new('BIGDATACORP_INVALID_PROVIDER_RESPONSE', provider_request_id: request_id)
  end

  def self.check_status_entry(entry, request_id)
    code = entry.is_a?(Hash) ? entry['Code'] : nil
    raise Error.new('BIGDATACORP_INVALID_PROVIDER_RESPONSE', provider_request_id: request_id) unless code.is_a?(Numeric) && code.finite?
    raise Error.new('BIGDATACORP_SEMANTIC_ERROR', provider_request_id: request_id) unless code.zero?
  end

  def self.candidate(row, index, request_id)
    data = row.is_a?(Hash) ? row['BasicData'] : nil
    invalid = Error.new('BIGDATACORP_INVALID_PROVIDER_RESPONSE', provider_request_id: request_id)
    raise invalid unless row.is_a?(Hash)
    raise Error.new('BIGDATACORP_SEMANTIC_ERROR', provider_request_id: request_id) if error_key?(row) || error_key?(data)
    raise invalid unless data.is_a?(Hash)

    build_candidate(row, data, index) || raise(invalid)
  end

  def self.error_key?(record)
    record.is_a?(Hash) && (record.key?('Error') || record.key?('error'))
  end

  def self.build_candidate(row, data, index)
    cnpj = Autonomia::Prospecting::Research::Cnpj.digits(string(data, 'TaxIdNumber'))
    name = string(data, 'OfficialName')
    status = string(data, 'TaxIdStatus')
    match_keys = string(row, 'MatchKeys')
    return unless cnpj.length == Autonomia::Prospecting::Research::Cnpj::LENGTH && name && status && match_keys

    Candidate.new(
      cnpj: cnpj, name: name, trade_name: string(data, 'TradeName'), status: status,
      is_headquarter: [true, false].include?(data['IsHeadquarter']) ? data['IsHeadquarter'] : nil,
      headquarter_state: string(data, 'HeadquarterState'), match_keys: [match_keys.first(MAX_ID_LENGTH)],
      official_name_percentage: percentage(data['OfficialNameInputNameMatchPercentage']),
      trade_name_percentage: percentage(data['TradeNameInputNameMatchPercentage']), provider_index: index
    )
  end

  def self.string(record, key)
    value = record[key]
    value.is_a?(String) && value.strip.present? ? value.strip : nil
  end

  def self.percentage(value)
    number = value.is_a?(String) ? Float(value.strip, exception: false) : value
    return unless number.is_a?(Numeric) && number.finite? && number.between?(0, 100)

    number.to_f
  end

  private_class_method :sanitized_name, :e164, :control_character?, :official_rows, :result_rows, :empty_doc_finder, :check_status_entry,
                       :candidate, :error_key?, :build_candidate, :string, :percentage
end
