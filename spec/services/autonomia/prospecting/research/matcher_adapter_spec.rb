require 'rails_helper'

# Porte de lib/services/research/company-owner/bigdatacorp-matcher-adapter.test.ts do Orth (#679).
# O QSA e a proveniência campo a campo do cadastro são da frente B; aqui fica a identidade que o matcher usa.
RSpec.describe Autonomia::Prospecting::Research::MatcherAdapter do
  let(:cnpj) { '11222333000181' }

  def bdc_candidate(**overrides)
    Autonomia::Prospecting::Research::BigDataCorpDiscovery::Candidate.new(
      cnpj: cnpj, name: 'Razão BDC Ltda', trade_name: 'Marca BDC', status: 'ATIVA',
      official_name_percentage: 84, trade_name_percentage: 91, is_headquarter: false, headquarter_state: 'RJ',
      match_keys: ['name{Marca BDC},phone{********9999}'], provider_index: 0, **overrides
    )
  end

  def identity(**overrides)
    described_class::Identity.new(
      cnpj: cnpj, legal_name: 'Razão Registral Ltda', trade_name: 'Marca Registral', status: 'ATIVA',
      city: 'Campinas', uf: 'SP', domain: nil, **overrides
    )
  end

  def adapt(candidate = bdc_candidate, snapshot = identity)
    described_class.adapt(candidate, snapshot)
  end

  it 'congela a coorte máxima em três candidatos' do
    expect(described_class::MAX_IDENTITY_CANDIDATES).to eq(3)
  end

  it 'escolhe o nome fantasia do cadastro quando a porcentagem válida dele é maior' do
    result = adapt

    expect(result.kind).to eq(:matcher_candidate)
    expect(result.candidate.to_h).to include(cnpj: cnpj, name: 'Marca Registral', name_similarity: 0.91, match_score: 0.91)
    expect(result.audit[:selected_name_source]).to eq(:trade)
  end

  it 'usa a razão social do cadastro para desempatar porcentagens iguais' do
    result = adapt(bdc_candidate(official_name_percentage: 98, trade_name_percentage: 98))

    expect(result.candidate.to_h).to include(name: 'Razão Registral Ltda', name_similarity: 0.98, match_score: 0.98)
    expect(result.audit[:selected_name_source]).to eq(:official)
  end

  it 'usa a maior porcentagem válida e ignora a inválida' do
    result = adapt(bdc_candidate(official_name_percentage: 72, trade_name_percentage: 101))

    expect(result.candidate.to_h).to include(name: 'Razão Registral Ltda', name_similarity: 0.72, match_score: 0.72)
  end

  [[nil, nil], [-1, 101], [Float::NAN, Float::INFINITY]].each do |official, trade|
    it "devolve non_qualifiable quando nenhuma porcentagem é válida (#{official.inspect}, #{trade.inspect})" do
      result = adapt(bdc_candidate(official_name_percentage: official, trade_name_percentage: trade))

      expect(result.kind).to eq(:non_qualifiable)
      expect(result.reason).to eq('invalid_name_similarity_percentage')
      expect(result.audit).to include(is_headquarter: false, headquarter_state: 'RJ', match_keys: ['name{Marca BDC},phone{********9999}'])
    end
  end

  it 'usa cidade e UF do estabelecimento no cadastro, nunca a UF da matriz da BigDataCorp' do
    result = adapt(bdc_candidate(is_headquarter: false, headquarter_state: 'RJ'), identity(city: 'Cidade Registral', uf: 'SP'))

    expect(result.candidate.to_h).to include(city: 'Cidade Registral', uf: 'SP', phone: nil, domain: nil)
    expect(result.audit).to include(is_headquarter: false, headquarter_state: 'RJ')
  end

  it 'recusa CNPJ devolvido divergente sem montar entrada para o matcher' do
    result = adapt(bdc_candidate, identity(cnpj: '11444777000161'))

    expect(result.kind).to eq(:invalid_snapshot)
    expect(result.reason).to eq('snapshot_cnpj_mismatch')
    expect(result.candidate).to be_nil
  end

  {
    'sem razão social' => { legal_name: ' ' },
    'sem situação cadastral' => { status: nil },
    'sem cidade' => { city: nil },
    'UF inválida' => { uf: 'São Paulo' }
  }.each do |label, overrides|
    it "recusa identidade do cadastro incompleta: #{label}" do
      result = adapt(bdc_candidate, identity(**overrides))

      expect(result.kind).to eq(:invalid_snapshot)
      expect(result.reason).to eq('snapshot_identity_invalid')
    end
  end

  it 'recusa escolher o nome fantasia quando o cadastro não tem nome fantasia' do
    expect(adapt(bdc_candidate, identity(trade_name: nil)).reason).to eq('snapshot_identity_invalid')
  end

  it 'normaliza as situações de empresa fechada para INATIVA' do
    expect(described_class.normalize_status('BAIXADA')).to eq('INATIVA')
    expect(described_class.normalize_status(' INATIVA ')).to eq('INATIVA')
    expect(described_class.normalize_status('ATIVA')).to eq('ATIVA')
    expect(adapt(bdc_candidate, identity(status: 'BAIXADA')).candidate.status).to eq('INATIVA')
  end

  it 'aceita BAIXADA da BigDataCorp como rejeição antes do cadastro' do
    candidate = bdc_candidate(status: 'BAIXADA')

    expect(described_class.pre_hydration_hard_reject(candidate)).to eq(cnpj: cnpj, reason: 'company_inactive')
    expect(described_class.pre_hydration_matcher_candidate(candidate).to_h).to include(cnpj: cnpj, status: 'INATIVA')
  end

  it 'marca conflito quando o CNPJ do site é outro' do
    candidate = bdc_candidate

    expect(described_class.pre_hydration_hard_reject(candidate, site_cnpj: '11444777000161')).to eq(cnpj: cnpj, reason: 'cnpj_conflict')
    expect(described_class.pre_hydration_matcher_candidate(candidate, site_cnpj: '11444777000161').cnpj_conflict_with).to eq('11444777000161')
    expect(described_class.pre_hydration_hard_reject(candidate, site_cnpj: cnpj)).to be_nil
  end

  it 'não transforma candidato inválido da BigDataCorp em rejeição antes do cadastro' do
    expect(described_class.pre_hydration_hard_reject(bdc_candidate(name: ' ', trade_name: nil, status: 'BAIXADA'))).to be_nil
    expect(described_class.valid_candidate?(bdc_candidate(name: ' ', trade_name: nil))).to be(false)
  end

  it 'não deixa CNPJ com dígito inválido pular o cadastro porque a situação diz BAIXADA' do
    candidate = bdc_candidate(cnpj: '11222333000182', status: 'BAIXADA')

    expect(described_class.valid_candidate?(candidate)).to be(false)
    expect(described_class.pre_hydration_hard_reject(candidate)).to be_nil
  end
end
