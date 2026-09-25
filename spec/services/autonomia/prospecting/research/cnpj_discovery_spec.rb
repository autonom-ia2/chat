require 'rails_helper'

# Descoberta do CNPJ do lead (#679, frente A): BigDataCorp acha os candidatos, o cadastro público (frente B,
# injetado aqui) dá cidade e UF de cada um, o matcher do Orth decide e o CNPJ do site do lead corrobora.
RSpec.describe Autonomia::Prospecting::Research::CnpjDiscovery do
  let(:token_url) { 'https://plataforma.bigdatacorp.com.br/tokens/gerar' }
  let(:companies_url) { 'https://plataforma.bigdatacorp.com.br/empresas' }
  let(:env) { { BIGDATACORP_USER: 'fixture-user-secret', BIGDATACORP_PASSWORD: 'fixture-password-secret' } }
  let(:account) { create(:account) }
  let(:lead_attributes) { {} }
  # O que o site do lead mostra, lido pela pesquisa (Research::SiteCnpj, com spec próprio).
  let(:site_cnpj) { nil }
  let(:site_reader) { ->(_lead) { site_cnpj } }
  let(:lead) do
    Autonomia::Prospecting::Lead.create!(
      account: account, provider: 'mock', provider_place_id: 'places/alfa', name: 'Alfa Oficina',
      phone: '(11) 99900-0001', city: 'Campinas', state: 'SP', website: 'https://www.alfa-oficina.com.br', **lead_attributes
    )
  end
  let(:company_class) { Struct.new(:cnpj, :legal_name, :trade_name, :registration_status, :registration_state, :city, keyword_init: true) }
  let(:registry) do
    {
      '11222333000181' => company_class.new(cnpj: '11222333000181', legal_name: 'Alfa Oficina Mecanica Ltda', trade_name: 'Alfa Oficina',
                                            registration_status: 'ATIVA', registration_state: 'SP', city: 'Campinas'),
      '11444777000161' => company_class.new(cnpj: '11444777000161', legal_name: 'Alfa Oficina Centro Ltda', trade_name: 'Alfa Oficina Centro',
                                            registration_status: 'ATIVA', registration_state: 'SP', city: 'Campinas')
    }
  end
  let(:hydrated) { [] }
  let(:hydrator) do
    table = registry
    calls = hydrated
    lambda { |cnpj|
      calls << cnpj
      table[cnpj]
    }
  end

  def row(cnpj, official:, trade:, status: 'ATIVA', name: 'Alfa Oficina Ltda')
    { 'MatchKeys' => 'name{Alf*******na}',
      'BasicData' => { 'TaxIdNumber' => cnpj, 'OfficialName' => name, 'TradeName' => 'Alfa Oficina', 'TaxIdStatus' => status,
                       'OfficialNameInputNameMatchPercentage' => official, 'TradeNameInputNameMatchPercentage' => trade } }
  end

  def stub_bigdatacorp(rows)
    stub_request(:post, token_url).to_return(status: 200, body: { token: 'fixture-access-secret', tokenID: 'fixture-token-id-secret' }.to_json)
    stub_request(:post, companies_url).to_return(
      status: 200,
      body: { QueryId: 'query-1', Status: { basic_data: [{ Code: 0, Message: 'OK' }] }, Result: rows }.to_json
    )
  end

  def perform
    with_modified_env(**env) { described_class.new(lead: lead, hydrator: hydrator, site_reader: site_reader).perform }
  end

  it 'sem credencial devolve not_configured sem nenhuma chamada HTTP' do
    result = with_modified_env(BIGDATACORP_USER: nil, BIGDATACORP_PASSWORD: '') { described_class.new(lead: lead, hydrator: hydrator).perform }

    expect(result.to_h).to include(status: :not_configured, cnpj: nil, confidence: 0.0, candidates: [], error_code: 'BIGDATACORP_NOT_CONFIGURED')
    expect(a_request(:any, /bigdatacorp/)).not_to have_been_made
    expect(hydrated).to be_empty
  end

  it 'acha o CNPJ quando o cadastro confirma cidade e UF e o nome passa do limite' do
    stub_bigdatacorp([row('11222333000181', official: 70, trade: 95)])

    result = perform

    expect(result.to_h).to include(status: :found, cnpj: '11222333000181', confidence: 0.95, candidates: ['11222333000181'], error_code: nil)
    expect(result.evidence).to include({ source: 'matcher', signal: 'exact_name_plus_city_uf' },
                                       { source: 'bigdatacorp', signal: 'name_similarity', value: 0.95 })
    expect(result.company).to eq(registry['11222333000181'])
  end

  it 'manda nome e telefone normalizado em E.164 pela região da conta' do
    stub_bigdatacorp([])

    perform

    expect(a_request(:post, companies_url).with(body: { Datasets: 'basic_data', q: 'name{Alfa Oficina},phone{+5511999000001}', Limit: 3 }.to_json))
      .to have_been_made.once
  end

  it 'sem candidato devolve not_found sem consultar o cadastro' do
    stub_bigdatacorp([])

    result = perform

    expect(result.to_h).to include(status: :not_found, cnpj: nil, confidence: 0.0, candidates: [], error_code: nil)
    expect(result.evidence).to include({ source: 'bigdatacorp', signal: 'no_candidates' })
    expect(hydrated).to be_empty
  end

  it 'dois candidatos sem desempate viram ambiguous' do
    stub_bigdatacorp([row('11222333000181', official: 70, trade: 88), row('11444777000161', official: 70, trade: 84)])

    result = perform

    expect(result.to_h).to include(status: :ambiguous, cnpj: nil, candidates: %w[11222333000181 11444777000161], error_code: nil)
    expect(result.confidence).to eq(0.88)
    expect(result.evidence).to include({ source: 'matcher', signal: 'top_two_difference_lt_010' })
  end

  context 'when o site do lead mostra o CNPJ de um candidato' do
    let(:site_cnpj) { '11.222.333/0001-81' }

    it 'corrobora o candidato igual, desfaz a ambiguidade e sobe a confiança' do
      stub_bigdatacorp([row('11222333000181', official: 70, trade: 85), row('11444777000161', official: 70, trade: 84)])

      result = perform

      expect(result.to_h).to include(status: :found, cnpj: '11222333000181', confidence: 0.95)
      expect(result.evidence).to include({ source: 'official_site', signal: 'cnpj_corroborated' },
                                         { source: 'matcher', signal: 'exact_name_plus_domain' })
      expect(hydrated).to eq(['11222333000181'])
    end

    it 'com o domínio do site o limite de nome cai para 0,65' do
      stub_bigdatacorp([row('11222333000181', official: 60, trade: 66)])

      expect(perform.to_h).to include(status: :found, cnpj: '11222333000181', confidence: 0.76)
    end
  end

  context 'when o site do lead mostra um CNPJ diferente de todos os candidatos' do
    let(:site_cnpj) { '11.444.777/0001-61' }

    it 'rejeita por conflito e devolve not_found' do
      stub_bigdatacorp([row('11222333000181', official: 70, trade: 95)])

      result = perform

      expect(result.to_h).to include(status: :not_found, cnpj: nil)
      expect(result.evidence).to include({ source: 'official_site', signal: 'cnpj_conflict' }, { source: 'matcher', signal: 'cnpj_conflict' })
      expect(hydrated).to be_empty
    end
  end

  context 'when o lead já tem enriched_cnpj, gravado por uma pesquisa anterior, e o site não mostra CNPJ' do
    let(:lead_attributes) { { enriched_cnpj: '11.222.333/0001-81' } }

    it 'não trata a coluna como sinal do site: o outro candidato continua podendo ser aceito' do
      stub_bigdatacorp([row('11444777000161', official: 70, trade: 100), row('11222333000181', official: 70, trade: 85)])

      result = perform

      expect(result.to_h).to include(status: :found, cnpj: '11444777000161')
      expect(result.evidence).not_to include(hash_including(source: 'official_site'))
      expect(hydrated).to contain_exactly('11444777000161', '11222333000181')
    end
  end

  it 'lê o site só quando há candidato, e uma vez' do
    reads = []
    reader = lambda { |target|
      reads << target.id
      nil
    }
    stub_bigdatacorp([])
    with_modified_env(**env) { described_class.new(lead: lead, hydrator: hydrator, site_reader: reader).perform }
    expect(reads).to be_empty

    stub_bigdatacorp([row('11222333000181', official: 70, trade: 95), row('11444777000161', official: 70, trade: 60)])
    with_modified_env(**env) { described_class.new(lead: lead, hydrator: hydrator, site_reader: reader).perform }
    expect(reads).to eq([lead.id])
  end

  context 'when o site mostra um CNPJ com dígito inválido' do
    let(:site_cnpj) { '11.222.333/0001-80' }

    it 'ignora o CNPJ do site' do
      stub_bigdatacorp([row('11222333000181', official: 70, trade: 95)])

      result = perform

      expect(result.to_h).to include(status: :found, confidence: 0.95)
      expect(result.evidence).not_to include(hash_including(source: 'official_site'))
    end
  end

  it 'candidato BAIXADA na BigDataCorp não vai ao cadastro e não é aceito' do
    stub_bigdatacorp([row('11222333000181', official: 70, trade: 95, status: 'BAIXADA')])

    result = perform

    expect(result.to_h).to include(status: :not_found, cnpj: nil)
    expect(result.evidence).to include({ source: 'matcher', signal: 'company_inactive' })
    expect(hydrated).to be_empty
  end

  it 'UF do cadastro diferente da do lead rejeita o candidato' do
    registry['11222333000181'].registration_state = 'RJ'
    stub_bigdatacorp([row('11222333000181', official: 70, trade: 95)])

    expect(perform.evidence).to include({ source: 'matcher', signal: 'uf_incompatible' })
  end

  it 'timeout da BigDataCorp vira failed com error_code' do
    stub_request(:post, token_url).to_return(status: 200, body: { token: 'a', tokenID: 'b' }.to_json)
    stub_request(:post, companies_url).to_timeout

    expect(perform.to_h).to include(status: :failed, cnpj: nil, confidence: 0.0, error_code: 'BIGDATACORP_TIMEOUT')
  end

  it 'erro HTTP da BigDataCorp vira failed com error_code' do
    stub_request(:post, token_url).to_return(status: 200, body: { token: 'a', tokenID: 'b' }.to_json)
    stub_request(:post, companies_url).to_return(status: 400, body: '{}')

    expect(perform.to_h).to include(status: :failed, error_code: 'BIGDATACORP_HTTP_ERROR')
  end

  it 'resposta fora do formato oficial vira failed com error_code' do
    stub_request(:post, token_url).to_return(status: 200, body: { token: 'a', tokenID: 'b' }.to_json)
    stub_request(:post, companies_url).to_return(status: 200, body: { Result: [] }.to_json)

    expect(perform.to_h).to include(status: :failed, error_code: 'BIGDATACORP_INVALID_PROVIDER_RESPONSE')
  end

  it 'candidato com CNPJ de dígito inválido derruba a coorte' do
    stub_bigdatacorp([row('11222333000182', official: 70, trade: 95)])

    expect(perform.to_h).to include(status: :failed, error_code: 'BIGDATACORP_INVALID_DISCOVERY_COHORT')
  end

  it 'cadastro que não responde vira failed' do
    registry.delete('11222333000181')
    stub_bigdatacorp([row('11222333000181', official: 70, trade: 95)])

    expect(perform.to_h).to include(status: :failed, error_code: 'REGISTRY_HYDRATION_INCOMPLETE')
  end

  it 'cadastro que levanta erro vira failed' do
    stub_bigdatacorp([row('11222333000181', official: 70, trade: 95)])
    failing = ->(_cnpj) { raise Net::ReadTimeout }

    result = with_modified_env(**env) { described_class.new(lead: lead, hydrator: failing, site_reader: site_reader).perform }

    expect(result.to_h).to include(status: :failed, error_code: 'REGISTRY_HYDRATION_INCOMPLETE')
  end

  it 'cadastro sem cidade vira failed, porque sem cidade o matcher não qualifica ninguém' do
    registry['11222333000181'].city = nil
    stub_bigdatacorp([row('11222333000181', official: 70, trade: 95)])

    expect(perform.to_h).to include(status: :failed, error_code: 'REGISTRY_IDENTITY_INVALID')
  end

  it 'nome inválido falha antes de chamar a BigDataCorp' do
    lead.update_columns(name: ' ') # rubocop:disable Rails/SkipsModelValidations

    expect(perform.to_h).to include(status: :failed, error_code: 'BIGDATACORP_INVALID_DISCOVERY_INPUT')
    expect(a_request(:any, /bigdatacorp/)).not_to have_been_made
  end

  it 'não grava nada no lead' do
    stub_bigdatacorp([row('11222333000181', official: 70, trade: 95)])
    before = lead.reload.attributes

    perform

    expect(lead.reload.attributes).to eq(before)
  end

  it 'não põe credencial, token nem nome de pessoa no resultado nem no log' do
    output = StringIO.new
    allow(Rails).to receive(:logger).and_return(ActiveSupport::Logger.new(output))
    stub_request(:post, token_url).to_return(status: 503, body: { token: 'fixture-access-secret', tokenID: 'fixture-token-id-secret' }.to_json)

    result = perform
    evidence = [result.inspect, result.to_h.to_json, output.string].join("\n")

    expect(result.to_h).to include(status: :failed, error_code: 'BIGDATACORP_TOKEN_UNAVAILABLE')
    expect(evidence).not_to include('fixture-user-secret', 'fixture-password-secret', 'fixture-access-secret', 'fixture-token-id-secret')
    expect(output.string).to include('BIGDATACORP_TOKEN_UNAVAILABLE')
  end

  it 'a evidência só leva fonte, sinal e número, nunca nome' do
    stub_bigdatacorp([row('11222333000181', official: 70, trade: 95)])

    result = perform

    expect(result.evidence.flat_map(&:keys).uniq - %i[source signal value]).to be_empty
    expect(result.evidence.to_json).not_to include('Alfa')
  end

  # Nota de nome da BigDataCorp também sem empresa achada (#681, frente B): a maior nota vai na evidência e cada candidato
  # leva só CNPJ, nota de nome, telefone e cidade/UF, para calibrar a descoberta. Nome de empresa ou pessoa não entra.
  describe 'notas dos candidatos' do
    let(:company_class) do
      Struct.new(:cnpj, :legal_name, :trade_name, :registration_status, :registration_state, :city, :phones, keyword_init: true)
    end
    let(:registry) do
      {
        '11222333000181' => company_class.new(cnpj: '11222333000181', legal_name: 'Alfa Oficina Mecanica Ltda', trade_name: 'Alfa Oficina',
                                              registration_status: 'ATIVA', registration_state: 'SP', city: 'Campinas',
                                              phones: ['(11) 99900-0001']),
        '11444777000161' => company_class.new(cnpj: '11444777000161', legal_name: 'Alfa Oficina Centro Ltda', trade_name: 'Alfa Centro',
                                              registration_status: 'ATIVA', registration_state: 'SP', city: 'Sumare', phones: [])
      }
    end

    it 'grava a maior nota de nome e a nota de cada candidato quando nenhum é aceito' do
      stub_bigdatacorp([row('11222333000181', official: 40, trade: 52), row('11444777000161', official: 61, trade: 30)])

      result = perform

      expect(result.status).to eq(:not_found)
      expect(result.evidence).to include({ source: 'bigdatacorp', signal: 'top_name_similarity', value: 0.61 })
      expect(result.candidate_scores).to eq(
        [{ cnpj: '11222333000181', name_similarity: 0.52, phone_match: true, city_uf_match: true },
         { cnpj: '11444777000161', name_similarity: 0.61, phone_match: false, city_uf_match: false }]
      )
    end

    it 'grava as notas no desfecho ambíguo' do
      registry['11444777000161'].city = 'Campinas'
      stub_bigdatacorp([row('11222333000181', official: 70, trade: 88), row('11444777000161', official: 70, trade: 84)])

      result = perform

      expect(result.status).to eq(:ambiguous)
      expect(result.evidence).to include({ source: 'bigdatacorp', signal: 'top_name_similarity', value: 0.88 })
      expect(result.candidate_scores.pluck(:name_similarity)).to eq([0.88, 0.84])
    end

    it 'o candidato rejeitado antes do cadastro entra com a nota da BigDataCorp, sem cidade' do
      stub_bigdatacorp([row('11222333000181', official: 90, trade: 20, status: 'BAIXADA')])

      result = perform

      expect(result.candidate_scores).to eq([{ cnpj: '11222333000181', name_similarity: 0.9, phone_match: false, city_uf_match: false }])
      expect(result.evidence).to include({ source: 'bigdatacorp', signal: 'top_name_similarity', value: 0.9 })
    end

    it 'sem candidato não inventa nota' do
      stub_bigdatacorp([])

      result = perform

      expect(result.candidate_scores).to eq([])
      expect(result.evidence.pluck(:signal)).not_to include('top_name_similarity')
    end

    it 'as notas não levam nome de empresa nem de pessoa' do
      stub_bigdatacorp([row('11222333000181', official: 40, trade: 52, name: 'Maria da Silva')])

      result = perform

      expect(result.candidate_scores.flat_map(&:keys).uniq).to match_array(%i[cnpj name_similarity phone_match city_uf_match])
      expect(result.candidate_scores.to_json).not_to include('Maria', 'Alfa')
    end
  end
end
