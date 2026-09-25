require 'rails_helper'

# Porte de identity-hydration-cohort.test.ts do Orth. A coorte busca no cadastro público até 3 CNPJs candidatos, só
# chama o matcher com a coorte inteira, e devolve apenas a empresa aceita. Os casos de getter hostil e de handle opaco
# do Orth não existem em Ruby (não há snapshot guardado para descartar por referência): o que não foi aceito
# simplesmente não sai daqui.
RSpec.describe Autonomia::Prospecting::Research::Registry::IdentityCohort do
  let(:registry) { Autonomia::Prospecting::Research::Registry }
  let(:hydrated) { [] }
  let(:three) { [{ cnpj: '11111111000191' }, { cnpj: '22222222000191' }, { cnpj: '33333333000191' }] }

  def company(cnpj, legal_name: "Empresa #{cnpj} Ltda")
    registry::Company.new(
      cnpj: cnpj, legal_name: legal_name, trade_name: nil, registration_status: 'ATIVA', registration_state: 'SP',
      city: 'Campinas', legal_nature_code: 2062, legal_nature_text: nil, opened_on: nil, cnae: nil, provider: 'OpenCNPJ',
      sources: [], qsa: [registry::Partner.build(name: "Sócia #{cnpj}", qualification: 'SÓCIO-ADMINISTRADOR', person_type: 'PF')]
    )
  end

  def success(cnpj, company_cnpj = cnpj)
    registry::Hydration.new(cnpj: cnpj, company: company(company_cnpj), failure_reason: nil, attempts: [])
  end

  def failure(cnpj)
    registry::Hydration.new(cnpj: cnpj, company: nil, failure_reason: :providers_exhausted, attempts: [])
  end

  # O bloco recebe o CNPJ e devolve a Hydration daquele CNPJ.
  def hydrator(&block)
    block ||= ->(cnpj) { success(cnpj) }
    calls = hydrated
    Class.new do
      define_method(:hydrate) do |cnpjs|
        calls.concat(cnpjs)
        cnpjs.map(&block)
      end
    end.new
  end

  def accept(cnpj)
    { decision: 'accept', accepted_cnpj: cnpj, reason: 'exact_name_plus_city_uf', top_score: 0.95, second_score: nil, name_similarity: 1.0 }
  end

  def run(candidates:, matcher:, hydrator: self.hydrator)
    described_class.new(hydrator: hydrator).run(candidates: candidates, matcher: matcher)
  end

  it 'busca todo candidato elegível e chama o matcher uma vez com a coorte completa' do
    seen = []
    matcher = lambda do |companies|
      seen << companies.keys
      accept('11111111000191')
    end
    result = run(candidates: three, matcher: matcher)

    expect(hydrated).to eq(%w[11111111000191 22222222000191 33333333000191])
    expect(seen).to eq([%w[11111111000191 22222222000191 33333333000191]])
    expect(result).to have_attributes(status: :complete, reason: nil)
  end

  it 'devolve provider_error e não chama o matcher quando 1 de 3 falha' do
    matcher = ->(_companies) { raise 'não devia ser chamado' }
    result = run(candidates: three, matcher: matcher,
                 hydrator: hydrator { |cnpj| cnpj == '22222222000191' ? failure(cnpj) : success(cnpj) })

    expect(result).to have_attributes(status: :provider_error, reason: 'hydration_incomplete', match: nil, accepted: nil)
  end

  it 'devolve provider_error quando todas falham' do
    result = run(candidates: three.first(1), matcher: ->(_c) { raise 'não' }, hydrator: hydrator { |cnpj| failure(cnpj) })

    expect(result.status).to eq(:provider_error)
  end

  it 'devolve invalid_hydration_snapshot quando o cadastro volta com outro CNPJ' do
    result = run(candidates: three.first(1), matcher: ->(_c) { raise 'não' },
                 hydrator: hydrator { |cnpj| success(cnpj, '98765432000198') })

    expect(result).to have_attributes(status: :provider_error, reason: 'invalid_hydration_snapshot')
  end

  it 'pula a busca só do candidato já recusado antes (inativo na descoberta), e o matcher ainda o vê' do
    seen = nil
    result = run(candidates: [{ cnpj: '11111111000191', skip_hydration: true }, { cnpj: '22222222000191' }],
                 matcher: ->(companies) { (seen = companies) && accept('22222222000191') })

    expect(hydrated).to eq(['22222222000191'])
    expect(seen.keys).to eq(%w[11111111000191 22222222000191])
    expect(seen['11111111000191']).to be_nil
    expect(result.accepted.cnpj).to eq('22222222000191')
  end

  it 'recusa candidato malformado sem buscar nada' do
    result = run(candidates: [{ cnpj: '123' }], matcher: ->(_c) { raise 'não' })

    expect(result).to have_attributes(status: :provider_error, reason: 'invalid_discovery_candidate')
    expect(hydrated).to eq([])
  end

  it 'recusa mais de três candidatos sem truncar, e CNPJ repetido' do
    four = three + [{ cnpj: '44444444000191' }]

    expect(run(candidates: four, matcher: ->(_c) { raise 'não' }).reason).to eq('invalid_discovery_cohort')
    expect(run(candidates: [three[0], three[0]], matcher: ->(_c) { raise 'não' }).reason).to eq('invalid_discovery_cohort')
    expect(run(candidates: 'x', matcher: ->(_c) { raise 'não' }).reason).to eq('invalid_discovery_cohort')
    expect(hydrated).to eq([])
  end

  it 'devolve só a empresa aceita, com o próprio quadro' do
    result = run(candidates: three.first(2), matcher: ->(_c) { accept('11111111000191') })

    expect(result.status).to eq(:complete)
    expect(result.match).to include(decision: 'accept', accepted_cnpj: '11111111000191')
    expect(result.accepted.cnpj).to eq('11111111000191')
    expect(result.accepted.qsa.map(&:name)).to eq(['Sócia 11111111000191'])
    expect(result.to_h.to_s).not_to include('22222222000191')
  end

  {
    'ambiguous' => { reason: 'top_two_difference_lt_010', top_score: 0.9, second_score: 0.85 },
    'not_found' => { reason: 'no_qualified_candidate' },
    'rejected' => { reason: 'company_inactive' }
  }.each do |decision, extra|
    it "não entrega empresa nem quadro na decisão #{decision}" do
      result = run(candidates: three.first(1), matcher: ->(_c) { { decision: decision, accepted_cnpj: nil }.merge(extra) })

      expect(result).to have_attributes(status: :complete, accepted: nil)
      expect(result.match[:decision]).to eq(decision)
    end
  end

  it 'não expõe empresa quando o matcher aponta para fora da coorte' do
    result = run(candidates: three.first(1), matcher: ->(_c) { accept('99999999000199') })

    expect(result).to have_attributes(status: :provider_error, reason: 'invalid_matcher_result', match: nil, accepted: nil)
  end

  it 'não aceita o candidato que foi pulado, porque ele não tem cadastro' do
    result = run(candidates: [{ cnpj: '11111111000191', skip_hydration: true }], matcher: ->(_c) { accept('11111111000191') })

    expect(result.reason).to eq('invalid_matcher_result')
  end

  {
    'nil' => nil,
    'faltando campos' => { decision: 'accept' },
    'nota fora de 0..1' => { decision: 'accept', accepted_cnpj: '11111111000191', top_score: 2 },
    'decisão desconhecida' => { decision: 'maybe', accepted_cnpj: nil },
    'recusa com CNPJ aceito' => { decision: 'not_found', accepted_cnpj: '11111111000191' }
  }.each do |label, malformed|
    it "trata resultado malformado do matcher como provider_error: #{label}" do
      result = run(candidates: three.first(1), matcher: ->(_c) { malformed })

      expect(result).to have_attributes(status: :provider_error, reason: 'invalid_matcher_result', match: nil, accepted: nil)
    end
  end

  it 'trata matcher que levanta como matcher_failed' do
    result = run(candidates: three.first(1), matcher: ->(_c) { raise ArgumentError, 'detalhe privado' })

    expect(result).to have_attributes(status: :provider_error, reason: 'matcher_failed')
    expect(result.to_h.to_s).not_to include('detalhe privado')
  end

  it 'congela a decisão e a empresa aceita, para ninguém mudar depois' do
    raw = accept('11111111000191')
    result = run(candidates: three.first(1), matcher: ->(_c) { raw })
    raw[:accepted_cnpj] = '99999999000199'

    expect(result.match[:accepted_cnpj]).to eq('11111111000191')
    expect(result.match).to be_frozen
    expect(result.accepted).to be_frozen
    expect(result.accepted.qsa).to be_frozen
  end
end
