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

  # A CONSULTA DE CEP do mock (autonomia-adapters#87), com as três saídas do adapter real: o endereço
  # inteiro, a cidade de CEP único (pergunta a rua e o bairro) e o CEP que o portal não conhece
  # (pergunta o CEP). As perguntas têm o formato e os motivos que o adapter devolve em `details`, que
  # o `Http` repassa sem traduzir.
  CEPS = {
    '01310100' => { 'logradouro' => 'Avenida Paulista - de 612 A 1510 - Lado Par', 'bairro' => 'Bela Vista',
                    'cidade' => 'São Paulo', 'uf' => 'SP' },
    '37757000' => { 'logradouro' => 'Estrada Municipal do Sertãozinho', 'bairro' => 'Zona Rural',
                    'cidade' => 'Bom Repouso', 'uf' => 'MG' }
  }.freeze
  CEPS_UNICOS = %w[12600000].freeze
  DIGITOS_DO_CEP = 8
  PERGUNTA_DO_CEP = { 'campo' => 'cep', 'motivo' => 'o portal não encontrou este CEP. Confirme o CEP com o cliente.' }.freeze
  PERGUNTA_DO_FORMATO = { 'campo' => 'cep',
                          'motivo' => 'o CEP tem 8 dígitos, e o informado não tem. Confirme o CEP com o cliente.' }.freeze
  PERGUNTAS_DO_CEP_UNICO = [
    { 'campo' => 'logradouro', 'motivo' => 'este CEP é de cidade de CEP único e não traz o nome da rua. ' \
                                           'Pergunte ao cliente o nome da rua do imóvel.' },
    { 'campo' => 'bairro', 'motivo' => 'este CEP é de cidade de CEP único e não traz o bairro. ' \
                                       'Pergunte ao cliente o bairro do imóvel.' }
  ].freeze

  def cep_lookup(provider:, session:, cep:)
    require_provider!(provider)
    require_session!(session)
    # `delete` com o conjunto de caracteres, e não regex: fica só o que é dígito.
    digitos = cep.to_s.delete('^0-9')
    perguntar_do_cep!([PERGUNTA_DO_FORMATO]) if digitos.length != DIGITOS_DO_CEP
    perguntar_do_cep!(PERGUNTAS_DO_CEP_UNICO) if CEPS_UNICOS.include?(digitos)
    perguntar_do_cep!([PERGUNTA_DO_CEP]) unless CEPS.key?(digitos)

    { 'cep' => digitos }.merge(CEPS.fetch(digitos))
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

  private

  # A recusa do adapter real para o que a consulta de CEP não respondeu: 422 com `issues` e `perguntas`.
  def perguntar_do_cep!(perguntas)
    detalhes = { 'issues' => perguntas.map { |p| "#{p['campo']}: #{p['motivo']}" }, 'perguntas' => perguntas }
    raise ::Autonomia::Insurance::Connector::Error.new(:validation, 'endereco do CEP incompleto', detalhes)
  end
end
