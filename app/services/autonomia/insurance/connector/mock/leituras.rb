# AS LEITURAS DO MOCK (entrega 2): a consulta de placa e a leitura de volta da cotação — o que o
# adapter real responde com sessão e sem custo. Separadas do `Mock` por tamanho, e porque são
# dobles de teste: a placa vem de uma tabela, a leitura de volta devolve o que o `quote_start`
# recebeu, com nomes do portal em snake, para as provas conferirem.
module Autonomia::Insurance::Connector::Mock::Leituras
  # A CONSULTA DE PLACA do mock: as placas que os exemplos usam, com o tipo que decide as regras.
  # Placa desconhecida volta sem tipo — é o que o portal faz quando não acha.
  PLACAS = {
    'ABC1D23' => { 'model' => 'Gol 1.0', 'model_year' => 2016, 'vehicle_type' => 'v', 'fipe_code' => '0050001' },
    'HIK9383' => { 'model' => 'Vectra Elegance 2.0', 'model_year' => 2008, 'vehicle_type' => 'v', 'fipe_code' => '0043249' },
    'NCD3080' => { 'model' => 'CG 150 Titan', 'model_year' => 2004, 'vehicle_type' => 'm', 'fipe_code' => '8110101' },
    'IDX3056' => { 'model' => 'LS-1935', 'model_year' => 1995, 'vehicle_type' => 'c', 'fipe_code' => '0000005' },
    # Modelo do ano corrente: é a placa que deixa o zero-quilômetro ambíguo (entrega 3).
    'ZER0K26' => { 'model' => 'Onix 1.0', 'model_year' => Date.current.year, 'vehicle_type' => 'v', 'fipe_code' => '0040001' }
  }.freeze
  TAMANHO_DA_PLACA = 7

  def vehicle_lookup(provider:, session:, plate:)
    require_provider!(provider)
    require_session!(session)
    placa = plate.to_s.gsub(/[^A-Za-z0-9]/, '').upcase
    raise ::Autonomia::Insurance::Connector::Error.new(:validation, 'placa fora do formato') if placa.length != TAMANHO_DA_PLACA

    { 'plate' => placa }.merge(PLACAS.fetch(placa, {}))
  end

  # A LEITURA DE VOLTA do mock: devolve o que o `quote_start` recebeu, com os nomes do portal em
  # snake, para os campos que as provas conferem. Memória de processo: serve aos exemplos.
  def quote_read(provider:, session:, quote_id:)
    require_provider!(provider)
    require_session!(session)
    entrada = Leituras.entradas[quote_id.to_s] || {}
    veiculo = entrada['vehicle'].to_h
    cotacao = entrada['quotation'].to_h
    {
      'quote_id' => quote_id,
      'negocio' => { 'renovacao' => cotacao['isRenewal'] == true, 'bonus_anterior' => cotacao['bonusClass'],
                     'seguradora_anterior_id' => cotacao['previousInsurerCode'] }.compact,
      'veiculo' => { 'placa' => veiculo['plate'], 'garagem_residencia' => veiculo['garageAtHome'],
                     'jovem_condutor' => veiculo['youngDriver'], 'jovem_idade' => veiculo['youngDriverAge'],
                     'jovem_sexo' => veiculo['youngDriverGender'] }.compact,
      'condutor' => {},
      'cobertura' => { 'tipo_franquia' => entrada.dig('coverage', 'deductibleType') }.compact
    }
  end

  # Memória de processo das entradas por id de cotação: serve aos exemplos.
  def self.entradas
    @entradas ||= {}
  end
end
